//
//  NotificationCenterReader.swift
//  Gourd 内置模块 · 通知中心数据库的**只读**读取器与可行性探针（P2c）
//
//  设计依据：docs/09-features-and-mechanisms.md §5.5（通知上岛）与 docs/12-p1-batches.md P2c
//  「先做探针（0.5 天）验证 macOS 27 上数据库可读；通过则完整实现」。
//
//  **三条硬性规则**（09 §5.5）：
//  1. **只读**：一律 `SQLITE_OPEN_READONLY` 打开，绝不写该库（连 VACUUM / WAL 都不碰）；
//     也不写任何临时文件到该目录；
//  2. **增量**：按 `record` 表的单调自增 id 取新增 + **文件事件触发**（`startWatching`，2026-09-28
//     把 30s 轮询换成了事件驱动——`db`/`db-wal` 一有写入就取数，浮层因此是实时的；mtime 只作
//     兜底轮询的廉价闸门），不做 1s 全表扫（该库可能很大）；
//  3. **防御式解码**：`record.data` 是二进制 plist，键名与 schema 都是私有的——
//     逐键 try，取不到给空并记录缺失键名，**任何 schema 差异都不得崩或抛错**。
//
//  读取被 TCC 拒绝是**预期路径**（本机实测：`sqlite3 -readonly` 报 `authorization denied`、
//  POSIX `open(2)` 报 `errno 1 EPERM`）：应用必须由用户手动授予**完全磁盘访问**。
//  完全磁盘访问**无法程序化申请**，因此这里只做「判定 + 报告原因」，不做任何授权弹窗。
//
//  SQLite 走 `import SQLite3`（工程已有同款先例：`managers/LLMUsage/Quota/CursorTokenStore.swift`
//  用 `sqlite3_open_v2` + `SQLITE_OPEN_READONLY` 读 Cursor 的 state.vscdb）。TCC 归属按**进程**判定，
//  所以从本进程（而不是 `/usr/bin/sqlite3` 子进程）读才可能命中我们自己的授权。
//

import Foundation
import OSLog
import SQLite3

// MARK: - 数据形状

/// 一条通知（模块呈现所需的最小字段集）。
///
/// 字段来源：`record` 表的 `rec_id`（记录 id）/ `data`（二进制 plist：标题、副标题、正文、App id）
/// + `app` 表的 bundle id ↔ 显示名映射；`deliveredDate` 优先取记录行的投递时间列。
struct NotificationItem: Identifiable, Equatable, Sendable {
    /// `record.rec_id`（单调自增，增量基线的唯一依据）。
    let id: Int64
    let bundleIdentifier: String
    let appName: String
    let title: String
    let subtitle: String?
    let body: String
    let deliveredDate: Date?

    /// 点击行为用的 App 名兜底：拿不到显示名时用 bundle id（再拿不到就用占位符）。
    var displayName: String {
        if !appName.isEmpty { return appName }
        return bundleIdentifier.isEmpty ? "?" : bundleIdentifier
    }
}

extension NotificationItem {
    /// **纯函数**（生产路径与单测共用）：`record` 行（id + `data` 列）→ 条目。
    ///
    /// `appName` 由调用方按 `app` 表补（拿不到给空串，呈现层退回 `displayName`）；
    /// `deliveredDate` 优先取记录行的时间列，缺省回落到 plist 里的时间。
    static func make(
        recordID: Int64,
        payload: NotificationPayload,
        appName: String = "",
        deliveredDate: Date? = nil
    ) -> NotificationItem {
        NotificationItem(
            id: recordID,
            bundleIdentifier: payload.bundleIdentifier ?? "",
            appName: appName,
            title: payload.title,
            subtitle: payload.subtitle,
            body: payload.body,
            deliveredDate: deliveredDate ?? payload.date
        )
    }

    /// 便捷形态：直接吃 `record.data` 的原始字节（单测喂构造的二进制 plist 走这条）。
    static func make(recordID: Int64, data: Data, appName: String = "", deliveredDate: Date? = nil) -> NotificationItem {
        make(
            recordID: recordID,
            payload: NotificationCenterReader.payload(fromRecord: data),
            appName: appName,
            deliveredDate: deliveredDate
        )
    }

    /// 换一个 App 显示名（其余字段不变）。**探针实测校准用**：`app` 表没有显示名列时，
    /// 显示名由模块侧走 `NSWorkspace` 解析后回填。
    func withAppName(_ name: String) -> NotificationItem {
        NotificationItem(
            id: id,
            bundleIdentifier: bundleIdentifier,
            appName: name,
            title: title,
            subtitle: subtitle,
            body: body,
            deliveredDate: deliveredDate
        )
    }
}

/// `record.data` 二进制 plist 的防御式解码结果。
///
/// `missingKeys` 是**校准用的唯一依据**（探针把它写进报告）：schema 变了以后，看缺哪些键就知道
/// 新键名该往 `NotificationItem.keyPaths` 里加什么。
struct NotificationPayload: Equatable, Sendable {
    var title = ""
    var subtitle: String?
    var body = ""
    var category: String?
    var bundleIdentifier: String?
    var date: Date?
    /// 没取到的键名（canonical 名，逐键记录，**不是**错误）。
    var missingKeys: [String] = []
    /// 解码失败的原因（plist 损坏 / 根不是字典）——有值时上面各字段一律为空/缺省。
    var decodeError: String?
}

/// 最近一次读取的可读性判定（模块据此决定面板显示「最近 N 条 / 需要完全磁盘访问 / 错误」）。
enum NotificationReadState: Equatable, Sendable {
    /// 库读到了（**空库也算**）。
    case ok
    /// `open(2)` 被 TCC 拒绝（EPERM/EACCES）——需要用户在系统设置里授予完全磁盘访问。
    case needsFullDiskAccess
    /// 其它失败（库不存在、schema 变了、SQLite 打开失败…），带可读原因（UI 截断显示）。
    case failure(String)
}

/// 探针报告：可行性的**唯一证据**，落盘到 `~/Library/Logs/Gourd/notifications-probe.log`。
struct ProbeReport: Sendable {
    var timestamp = Date()
    var path = ""
    var hostDescription = ""
    /// 文件元数据（`stat` 在 TCC 下通常仍可读，本机实测 size / mtime 都拿得到）。
    var exists = false
    var sizeBytes: Int64?
    var modificationDate: Date?
    var metadataError: String?
    /// POSIX `open(2)` 的结果：nil = 打开成功（可读）。
    var posixOpenError: String?
    /// `sqlite3_open_v2`（只读）的结果：nil = 打开成功。
    var sqliteOpenError: String?
    /// 可读性判定（与 `NotificationReadState` 同口径）。
    var readState: NotificationReadState = .failure("未执行")
    var tables: [String] = []
    var recordColumns: [String] = []
    var appColumns: [String] = []
    var recentRecords: [ProbeRecord] = []
    /// 最近 5 条记录都取不到时的原因（例如 TCC 拒绝）。
    var recordsError: String?
    /// 列表查询自检：`SELECT *` 跑通不等于「最近 N 条」那条 SQL 跑通，这里跑一遍**生产路径**的
    /// `fetchRecent(limit:)`，把结果摘要写进报告（探针的价值就在于提前发现读不出来）。
    var listCheck: String?

    /// 一行摘要（给 `Logger.log(category: .debug)` 用）。
    var summary: String {
        switch readState {
        case .ok:
            return "探针：可读；表 \(tables.joined(separator: ","))；record 列 \(recordColumns.count) 个、"
                + "app 列 \(appColumns.count) 个；最近记录 \(recentRecords.count) 条"
        case .needsFullDiskAccess:
            return "探针：读取被拒绝，需要完全磁盘访问（\(posixOpenError ?? sqliteOpenError ?? "未知原因")）"
        case .failure(let reason):
            return "探针：不可读 — \(reason)"
        }
    }
}

/// 探针里的一条原始记录（能解出多少算多少）。
struct ProbeRecord: Sendable {
    /// 记录 id（`rec_id` / `id`，取不到记 nil）。
    var recordID: Int64?
    /// 行内所有列的原始值（BLOB 只留字节数与前 16 字节十六进制）。
    var rawColumns: [(name: String, value: String)] = []
    /// plist 解码结果（仅在能拿到 `data` 列时有值）。
    var payload: NotificationPayload?
}

// MARK: - 读取器

/// 通知中心库的只读读取器。**实例无共享可变状态**（`lastState` 等只由本实例的 `fetch` 写，
/// 调用方串行使用即可），因此可从后台任务安全使用（不阻塞主线程）。
final class NotificationCenterReader: @unchecked Sendable {
    /// 通知中心数据库（macOS 27 已实测存在；**读取需完全磁盘访问**）。
    static let defaultDatabasePath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
        .path

    /// 探针日志（追加写）。落盘是刻意的：schema 是私有的，报告是后续校准的唯一依据。
    static let probeLogPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Gourd/notifications-probe.log")
        .path

    /// `record` / `app` 两张表在私有 schema 里的**候选列名**——都按顺序 try，命中即用。
    private enum ColumnCandidates {
        static let recordID = ["rec_id", "id", "record_id"]
        static let data = ["data", "data1", "blob"]
        static let appIdentifier = ["identifier", "bundle_id", "bundleIdentifier"]
        static let appName = ["display_name", "name", "displayName"]
        static let appID = ["app_id", "id"]
        static let deliveredDate = ["delivered_date", "request_date", "date", "timestamp"]
    }

    /// plist 里各字段的候选键名（顺序即优先级；`req` 是通知请求字典，实测口径见 09 §5.5）。
    private enum KeyCandidates {
        static let title = ["titl", "title"]
        static let subtitle = ["subt", "subtitle"]
        static let body = ["body"]
        static let category = ["cate", "category"]
        static let bundleIdentifier = ["app", "bundleIdentifier", "bundleId"]
        static let date = ["date", "requestDate"]
    }

    let databasePath: String

    private(set) var lastState: NotificationReadState = .ok
    /// 最近一次成功取的全局 `MAX(rec_id)`（增量基线；取不到时保持上一次的值）。
    private(set) var lastMaxRecordID: Int64?

    init(databasePath: String = NotificationCenterReader.defaultDatabasePath) {
        self.databasePath = databasePath
    }

    // MARK: 元数据

    /// 库文件（含 WAL 旁文件）的修改时间。**TCC 通常不拦 `stat`**（本机实测可读），
    /// 因此 mtime 可以当「库有没有变」的第一道廉价闸门（09 §5.5 的增量策略）。
    ///
    /// **必须把 `-wal` 一起看（2026-09-28 实测校正）**：该库是 **WAL 模式**——新通知只写进
    /// `db-wal`，主库文件 `db` 的 mtime **纹丝不动**（本机实测：`db` 停在 9-26 21:17，
    /// 而 `db-wal` 每次通知都变）。只看主库会让 30s 轮询**永远早退**，增量与浮层都再不会触发
    ///（直到某次 checkpoint 偶然改写主库）。取两者里较晚的那个：checkpoint 前的写入靠 `-wal`，
    /// checkpoint 后靠主库，两种情形都能感知。
    ///
    /// `-wal` 不存在（已 checkpoint 清理）时自然退化成「只看主库」。
    var modificationDate: Date? {
        [databasePath, databasePath + "-wal"]
            .compactMap { (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }
            .max()
    }

    // MARK: 文件事件监听（实时化的主路径）

    /// 监听 `db` 与 `db-wal` 的**写入事件**；事件到来后**去抖 ~0.3s** 再回调
    /// （一条通知会写多行 / 两个文件，事件成串到来，不去抖会把同一批取好几遍）。
    ///
    /// 返回值是**取消闭包**，同时也是监听器的生命周期持有者——闭包被调用一次或释放后，监听即停
    /// （`deactivate()` 侧只需要把它存下来、必要时调一次）。
    ///
    /// 监听**不读库内容、不申请任何权限**：`open(path, O_EVTONLY)` 只订阅 vnode 事件。
    /// 该 `open` 被 TCC 拒绝时只是「这个文件挂不上 source」——调用方仍有兜底轮询，
    /// 事件驱动是**加速**而不是唯一取数路径，因此这里不抛错、也不改判定。
    func startWatching(onChange: @escaping () -> Void) -> () -> Void {
        let watcher = NotificationDatabaseWatcher(databasePath: databasePath, onChange: onChange)
        watcher.start()
        return { watcher.stop() }
    }

    // MARK: 读取列表

    /// 最新 `limit` 条通知（按 id 降序取、返回时仍是降序 = 新的在前）。
    ///
    /// **任何失败都返回空数组**，原因记进 `lastState`（UI 显示、不抛错）。
    func fetchRecent(limit: Int) -> [NotificationItem] {
        fetch(after: nil, limit: limit)
    }

    /// 增量：`rec_id > recordID` 的通知，按 id **升序**（调用方按到达顺序累加计数）。
    func fetchNew(after recordID: Int64, limit: Int) -> [NotificationItem] {
        fetch(after: recordID, limit: limit)
    }

    // MARK: 探针

    /// 可行性探针：文件元数据 → POSIX 可读性（带 errno）→ SQLite 只读打开 →
    /// 表清单 / 两张表的列名 / 最近 5 条记录的原始字段与解码结果。
    ///
    /// **副作用有两处且此处有意为之**：追加一次报告到 `probeLogPath`、并打一条 `.debug` 摘要。
    func probe() -> ProbeReport {
        var report = ProbeReport()
        report.timestamp = Date()
        report.path = databasePath
        report.hostDescription = Self.hostDescription

        // ① 文件元数据（存在性 / 大小 / mtime）
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: databasePath)
            report.exists = true
            report.sizeBytes = (attributes[.size] as? NSNumber)?.int64Value
            report.modificationDate = attributes[.modificationDate] as? Date
        } catch {
            report.metadataError = Self.describe(error)
        }

        // ② POSIX 只读 open：TCC 拒绝在这里给出**精确 errno**（EPERM/EACCES = 需要完全磁盘访问）
        let descriptor = open(databasePath, O_RDONLY)
        if descriptor < 0 {
            let code = errno
            report.posixOpenError = "errno \(code): \(String(cString: strerror(code)))"
            report.readState = Self.state(forErrno: code)
        } else {
            close(descriptor)
        }

        // ③ SQLite 只读打开 + 结构与样本
        var db: OpaquePointer?
        if sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db {
            report.tables = Self.queryStrings(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            report.recordColumns = Self.columnDescriptions(db, table: "record")
            report.appColumns = Self.columnDescriptions(db, table: "app")
            do {
                report.recentRecords = try recentRecords(db, limit: 5)
            } catch {
                report.recordsError = Self.describe(error)
            }
            sqlite3_close(db)
            if report.posixOpenError == nil {
                report.readState = .ok
                report.listCheck = listQueryCheck()
            }
        } else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 失败且无错误信息"
            if let db { sqlite3_close(db) }
            report.sqliteOpenError = message
            if report.posixOpenError == nil {
                // POSIX open 成功但 SQLite 打不开：不是权限问题，按普通失败报。
                report.readState = .failure("sqlite3 只读打开失败：\(message)")
            }
        }

        appendProbeLog(report)
        Logger.log("通知库探针 — \(report.summary)", category: .debug)
        return report
    }

    /// 追加一份带时间戳的报告（先确保目录存在；写失败只记日志，不影响探针结果）。
    private func appendProbeLog(_ report: ProbeReport) {
        let directory = (Self.probeLogPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let text = Self.render(report) + "\n"
            guard let data = text.data(using: .utf8) else { return }
            if !FileManager.default.fileExists(atPath: Self.probeLogPath) {
                FileManager.default.createFile(atPath: Self.probeLogPath, contents: data)
                return
            }
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: Self.probeLogPath))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            Logger.log("探针日志写入失败：\(Self.describe(error))", category: .warning)
        }
    }

    /// 生产路径的列表查询自检（探针的收尾一步）。
    private func listQueryCheck() -> String {
        let sample = fetchRecent(limit: 5)
        guard !sample.isEmpty else { return "返回 0 条（判定 \(Self.describe(lastState))）" }
        let detail = sample.prefix(3).map { item in
            "rec_id=\(item.id) app=\(item.bundleIdentifier.isEmpty ? "<空>" : item.bundleIdentifier) "
                + "nameFallback=\(Self.quoted(item.displayName)) title=\(Self.quoted(item.title)) "
                + "body=\(Self.quoted(String(item.body.prefix(40)))) "
                + "date=\(item.deliveredDate.map(Self.timestamp) ?? "<无>")"
        }.joined(separator: " | ")
        // nameFallback 是 reader 的兜底链（app 表显示名列 → bundle id 末段；实测 `app` 表没有显示名列，
        // 所以一直是末段）；UI 侧另经 NSWorkspace 解析真实显示名，见 `NotificationStore.resolveAppNames`。
        return "返回 \(sample.count) 条；样例：\(detail)"
    }

    // MARK: 增量读取的实现

    private func fetch(after recordID: Int64?, limit: Int) -> [NotificationItem] {
        guard limit > 0 else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 失败"
            if let db { sqlite3_close(db) }
            lastState = Self.state(forOpenMessage: message, path: databasePath)
            return []
        }
        defer { sqlite3_close(db) }

        let recordColumns = Self.columnNames(db, table: "record")
        guard let idColumn = Self.pick(ColumnCandidates.recordID, from: recordColumns),
              let dataColumn = Self.pick(ColumnCandidates.data, from: recordColumns)
        else {
            lastState = .failure("record 表缺少 id/data 列（私有 schema 变更？实际列：\(recordColumns.joined(separator: ","))）")
            return []
        }

        lastMaxRecordID = Self.scalarInt64(db, sql: "SELECT MAX(\(idColumn)) FROM record") ?? lastMaxRecordID

        let appMap = Self.appDisplayNames(db)
        let dateColumn = Self.pick(ColumnCandidates.deliveredDate, from: recordColumns)
        let direction = recordID == nil ? "DESC" : "ASC"
        let predicate = recordID == nil ? "" : "WHERE \(idColumn) > ? "
        let sql = "SELECT \(idColumn), \(dataColumn)"
            + (dateColumn.map { ", \($0)" } ?? "")
            + " FROM record \(predicate)ORDER BY \(idColumn) \(direction) LIMIT ?"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            lastState = .failure("SQL 准备失败：\(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(statement) }

        var index: Int32 = 1
        if let recordID {
            sqlite3_bind_int64(statement, index, recordID)
            index += 1
        }
        sqlite3_bind_int(statement, index, Int32(min(limit, 200)))

        var items: [NotificationItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let identifier = sqlite3_column_int64(statement, 0)
            let payload = Self.payload(statement, column: 1) ?? NotificationPayload()
            let bundleIdentifier = payload.bundleIdentifier ?? ""
            // 记录行的时间列只在存在时读（列序随 schema 变，不能写死索引语义之外的假设）。
            let delivered = dateColumn.flatMap { _ in Self.date(fromAppleEpoch: sqlite3_column_double(statement, 2)) }
            items.append(
                NotificationItem.make(
                    recordID: identifier,
                    payload: payload,
                    appName: Self.appDisplayName(bundleIdentifier: bundleIdentifier, appMap: appMap),
                    deliveredDate: delivered
                )
            )
        }

        lastState = .ok
        return items
    }

    /// `app` 表 → bundle id 到显示名的映射。表 / 列名都是私有的，全部按候选名 try；
    /// 没有可用的显示名列就返回空表（调用方退回 bundle id 最后一段）。
    ///
    /// **探针实测（2026-09-28，macOS 27）**：`app` 表只有 `app_id` / `identifier` / `badge`——
    /// **没有显示名列**，所以这里在当前系统上恒返回空表；显示名由模块侧走 `NSWorkspace` 解析
    /// （见 `NotificationStore.resolveAppNames`）。保留本方法是为了 schema 若加回显示名列时可直接生效。
    private static func appDisplayNames(_ db: OpaquePointer) -> [String: String] {
        let columns = columnNames(db, table: "app")
        guard let identifierColumn = pick(ColumnCandidates.appIdentifier, from: columns) else { return [:] }
        let nameColumn = pick(ColumnCandidates.appName, from: columns)
        let sql = "SELECT \(identifierColumn)" + (nameColumn.map { ", \($0)" } ?? "") + " FROM app"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [:] }
        defer { sqlite3_finalize(statement) }

        var map: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let identifierText = sqlite3_column_text(statement, 0) else { continue }
            let identifier = String(cString: identifierText)
            let name = nameColumn != nil ? sqlite3_column_text(statement, 1).map { String(cString: $0) } : nil
            map[identifier] = name ?? ""
        }
        return map
    }

    /// App 显示名的兜底链：`app` 表的显示名 → bundle id 的最后一段（`com.apple.Mail` → `Mail`）
    /// → 空串（`NotificationItem.displayName` 再兜一层 `?`）。
    static func appDisplayName(bundleIdentifier: String, appMap: [String: String]) -> String {
        if let name = appMap[bundleIdentifier], !name.isEmpty { return name }
        guard let last = bundleIdentifier.split(separator: ".").last, !last.isEmpty else { return "" }
        return String(last)
    }

    // MARK: 防御式 plist 解码

    /// 把某一列当 BLOB 读出来解 plist（列不是 BLOB / 为空 → nil，调用方给空字段）。
    private static func payload(_ statement: OpaquePointer, column: Int32) -> NotificationPayload? {
        guard sqlite3_column_type(statement, column) == SQLITE_BLOB,
              let pointer = sqlite3_column_blob(statement, column) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, column))
        guard length > 0 else { return nil }
        return payload(fromRecord: Data(bytes: pointer, count: length))
    }

    /// `record.data` → 字段。**逐键 try**：单个键取不到不影响其它键，缺键记进 `missingKeys`；
    /// 数据为空 / 非 plist / 根不是字典都返回空字段 + `decodeError`，**不抛错**。
    static func payload(fromRecord data: Data) -> NotificationPayload {
        var payload = NotificationPayload()
        guard !data.isEmpty else {
            payload.decodeError = "data 列为空"
            payload.missingKeys = canonicalKeys
            return payload
        }

        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            payload.decodeError = "plist 解析失败：\(describe(error))"
            payload.missingKeys = canonicalKeys
            return payload
        }
        guard let root = object as? [String: Any] else {
            payload.decodeError = "plist 根不是字典（\(type(of: object))）"
            payload.missingKeys = canonicalKeys
            return payload
        }

        // 候选字典按优先级排：`req`（新通知请求）→ 根自身 → `$objects` 里第一个含目标键的字典
        // （老版本用 NSKeyedArchiver 包装，字段散在归档数组里）。
        var candidates: [[String: Any]] = []
        if let request = root["req"] as? [String: Any] { candidates.append(request) }
        candidates.append(root)
        if let objects = root["$objects"] as? [Any] {
            candidates.append(contentsOf: objects.compactMap { $0 as? [String: Any] })
        }

        if let value = firstString(KeyCandidates.title, in: candidates) {
            payload.title = value
        } else {
            payload.missingKeys.append("titl")
        }
        if let value = firstString(KeyCandidates.subtitle, in: candidates) {
            payload.subtitle = value
        } else {
            payload.missingKeys.append("subt")
        }
        if let value = firstString(KeyCandidates.body, in: candidates) {
            payload.body = value
        } else {
            payload.missingKeys.append("body")
        }
        if let value = firstString(KeyCandidates.category, in: candidates) {
            payload.category = value
        } else {
            payload.missingKeys.append("cate")
        }
        if let value = firstString(KeyCandidates.bundleIdentifier, in: candidates) {
            payload.bundleIdentifier = value
        } else {
            payload.missingKeys.append("app")
        }
        if let value = firstValue(KeyCandidates.date, in: candidates) {
            payload.date = date(fromPlistValue: value)
        } else {
            payload.missingKeys.append("date")
        }
        return payload
    }

    /// 与 `payload(fromRecord:)` 的缺键记录口径一致的全量键名清单（解码完全失败时用）。
    private static let canonicalKeys = ["titl", "subt", "body", "cate", "app", "date"]

    /// 按候选键名逐个在候选字典里找字符串值。**空串算命中**（键在、值为空与键缺失是两回事：
    /// 前者说明 schema 没变、只是这条通知没有该字段）。
    private static func firstString(_ keys: [String], in candidates: [[String: Any]]) -> String? {
        for key in keys {
            for candidate in candidates {
                if let value = candidate[key] as? String { return value }
            }
        }
        return nil
    }

    private static func firstValue(_ keys: [String], in candidates: [[String: Any]]) -> Any? {
        for key in keys {
            for candidate in candidates {
                if let value = candidate[key] { return value }
            }
        }
        return nil
    }

    /// plist 里的时间形态：`Date` 直接用；数值按「< 1e9 视为 Apple 纪元（2001）秒数」解释
    /// （通知库里两种都存在，这是防御式启发，不影响其它字段）。
    static func date(fromPlistValue value: Any) -> Date? {
        if let date = value as? Date { return date }
        if let number = value as? NSNumber { return date(fromAppleEpoch: number.doubleValue) }
        if let text = value as? String, let raw = Double(text) { return date(fromAppleEpoch: raw) }
        return nil
    }

    /// 数值 → 时间：Apple 纪元（2001-01-01）与 Unix 纪元（1970-01-01）都用同一启发式区分。
    static func date(fromAppleEpoch value: Double) -> Date? {
        guard value > 0, value.isFinite else { return nil }
        // 1e9 秒：Apple 纪元的 1e9 ≈ 2032 年，Unix 纪元的 1e9 ≈ 2001 年——两侧都不误判。
        return value < 1_000_000_000 ? Date(timeIntervalSinceReferenceDate: value) : Date(timeIntervalSince1970: value)
    }

    // MARK: 探针的报告渲染

    static func render(_ report: ProbeReport) -> String {
        var lines: [String] = []
        lines.append("===== Gourd 通知库可行性探针（P2c / 09 §5.5）=====")
        lines.append("时间: \(timestamp(report.timestamp))")
        if !report.hostDescription.isEmpty { lines.append("宿主: \(report.hostDescription)") }
        lines.append("库路径: \(report.path)")
        lines.append("文件存在: \(report.exists ? "是" : "否")")
        if let size = report.sizeBytes { lines.append("文件大小: \(size) 字节") }
        if let date = report.modificationDate { lines.append("修改时间: \(timestamp(date))") }
        if let error = report.metadataError { lines.append("元数据读取错误: \(error)") }
        lines.append("POSIX 只读 open: \(report.posixOpenError ?? "成功")")
        lines.append("sqlite3 只读打开: \(report.sqliteOpenError ?? "成功")")
        lines.append("判定: \(describe(report.readState))")
        lines.append("表清单(sqlite_master): \(report.tables.isEmpty ? "(取不到)" : report.tables.joined(separator: ", "))")
        lines.append("record 列(PRAGMA table_info): \(report.recordColumns.isEmpty ? "(取不到)" : report.recordColumns.joined(separator: ", "))")
        lines.append("app 列(PRAGMA table_info): \(report.appColumns.isEmpty ? "(取不到)" : report.appColumns.joined(separator: ", "))")
        if let error = report.recordsError { lines.append("最近记录读取错误: \(error)") }
        if let listCheck = report.listCheck { lines.append("列表查询自检(fetchRecent): \(listCheck)") }
        lines.append("最近 5 条记录: \(report.recentRecords.isEmpty ? "(取不到)" : "")")
        for (offset, record) in report.recentRecords.enumerated() {
            lines.append("  [\(offset + 1)] rec_id=\(record.recordID.map(String.init) ?? "?")")
            for column in record.rawColumns {
                lines.append("      \(column.name) = \(column.value)")
            }
            if let payload = record.payload {
                let subtitle = payload.subtitle.map { "\($0)" } ?? "<无>"
                lines.append("      解码: title=\(quoted(payload.title)) subtitle=\(quoted(subtitle)) "
                    + "body=\(quoted(payload.body)) cate=\(quoted(payload.category ?? "<无>")) "
                    + "app=\(quoted(payload.bundleIdentifier ?? "<无>")) date=\(payload.date.map(timestamp) ?? "<无>")")
                lines.append("      缺失键: \(payload.missingKeys.isEmpty ? "无" : payload.missingKeys.joined(separator: ", "))")
                if let error = payload.decodeError { lines.append("      解码错误: \(error)") }
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func describe(_ state: NotificationReadState) -> String {
        switch state {
        case .ok: return "可读"
        case .needsFullDiskAccess: return "需要完全磁盘访问（读取被 TCC 拒绝）"
        case .failure(let reason): return "不可读 — \(reason)"
        }
    }

    private static func quoted(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static var hostDescription: String {
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "Gourd \(app) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    // MARK: 错误归类与 SQLite 小工具

    /// errno → 判定：`EPERM` / `EACCES` 是 TCC 拒绝（= 需要完全磁盘访问），其余是普通失败。
    private static func state(forErrno code: Int32) -> NotificationReadState {
        if code == EPERM || code == EACCES {
            return .needsFullDiskAccess
        }
        return .failure("open(2) 失败 errno \(code): \(String(cString: strerror(code)))")
    }

    /// SQLite 打开失败的文案里出现 `authorization denied`（本机实测）时也归到「需要完全磁盘访问」——
    /// 与 POSIX errno 两条路互为兜底。
    private static func state(forOpenMessage message: String, path: String) -> NotificationReadState {
        if message.contains("authorization denied") || message.contains("not authorized") {
            return .needsFullDiskAccess
        }
        if !FileManager.default.fileExists(atPath: path) {
            return .failure("库不存在：\(path)")
        }
        if message.contains("unable to open") {
            return .needsFullDiskAccess
        }
        return .failure("sqlite3 只读打开失败：\(message)")
    }

    private static func queryStrings(_ db: OpaquePointer, sql: String) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { values.append(String(cString: text)) }
        }
        return values
    }

    private static func scalarInt64(_ db: OpaquePointer, sql: String) -> Int64? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    /// `PRAGMA table_info(<table>)` → `"name(type)"` 形态的列描述（report 用）。
    private static func columnDescriptions(_ db: OpaquePointer, table: String) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let name = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "?"
            let type = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            values.append(type.isEmpty ? name : "\(name)(\(type))")
        }
        return values
    }

    private static func columnNames(_ db: OpaquePointer, table: String) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 1) { names.append(String(cString: text)) }
        }
        return names
    }

    private static func pick(_ candidates: [String], from columns: [String]) -> String? {
        candidates.first { columns.contains($0) }
    }

    /// 最近 `limit` 条记录的原始字段。用 `SELECT *` 是为了把**所有**列都写进报告——
    /// 私有 schema 校准靠的就是这份原始快照。
    private func recentRecords(_ db: OpaquePointer, limit: Int) throws -> [ProbeRecord] {
        let columns = Self.columnNames(db, table: "record")
        guard !columns.isEmpty else { return [] }
        let idColumn = Self.pick(ColumnCandidates.recordID, from: columns) ?? "rowid"
        let order = Self.pick(ColumnCandidates.recordID, from: columns) ?? "rowid"
        var statement: OpaquePointer?
        let sql = "SELECT * FROM record ORDER BY \(order) DESC LIMIT \(max(0, limit))"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        let dataIndex = columns.firstIndex(of: Self.pick(ColumnCandidates.data, from: columns) ?? "data")
        var records: [ProbeRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var record = ProbeRecord()
            for (index, name) in columns.enumerated() {
                record.rawColumns.append((name: name, value: Self.rawValue(statement, index: Int32(index))))
            }
            if columns.contains(idColumn),
               let idIndex = columns.firstIndex(of: idColumn),
               sqlite3_column_type(statement, Int32(idIndex)) != SQLITE_NULL {
                record.recordID = sqlite3_column_int64(statement, Int32(idIndex))
            }
            if let dataIndex {
                record.payload = Self.payload(statement, column: Int32(dataIndex))
            }
            records.append(record)
        }
        return records
    }

    /// 列值的可读快照：BLOB 只留字节数 + 前 16 字节十六进制（报告不该塞几百 KB 的 plist）。
    private static func rawValue(_ statement: OpaquePointer, index: Int32) -> String {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return "\(sqlite3_column_int64(statement, index))"
        case SQLITE_FLOAT:
            return "\(sqlite3_column_double(statement, index))"
        case SQLITE_NULL:
            return "NULL"
        case SQLITE_BLOB:
            let length = Int(sqlite3_column_bytes(statement, index))
            guard let pointer = sqlite3_column_blob(statement, index) else { return "<blob \(length) 字节>" }
            let head = Data(bytes: pointer, count: min(length, 16)).map { String(format: "%02x", $0) }.joined()
            return "<blob \(length) 字节: \(head)\(length > 16 ? "…" : "")>"
        default:
            return sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "NULL"
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
    }
}

// MARK: - 文件事件监听器

/// 通知库文件的事件监听器：**`db` 与 `db-wal` 各一个 `DispatchSource`**。
///
/// 为什么必须两个都挂（2026-09-28 实测）：该库是 **WAL 模式**——新通知只写 `db-wal`，
/// 主库 `db` 的 mtime 纹丝不动（同 `modificationDate` 的校正口径）。只挂主库 = 等于没挂。
///
/// 三条实现约束：
/// 1. **每个事件后重新对账**（`reconcileNow`）：`db-wal` 会被 checkpoint 清掉、被 rename 换掉，
///    那时旧 fd 已经失效（新文件写它收不到事件），必须摘掉；文件重新出现时再补挂。
///    只在启动时挂一次会永久丢掉 `db-wal`；
/// 2. **去抖**（不去抖就是「一次通知触发一串取数」）：事件里记一个 pending 令牌，
///    `Task.sleep(300ms)` 醒来后比对令牌——期间来过新事件就让这次回调作废。
///    刻意不用 `Timer`：堆叠的 Timer 会在密集写入下同时点火，正是要避免的情形；
/// 3. **回调在 watcher 自己的串行队列上**：调用方负责跳回自己的 actor（模块侧跳主 actor）。
///
/// `O_EVTONLY` 的 `open` 被 TCC 拒绝时（`EPERM`）不致命：该文件挂不上 source，兜底轮询仍在跑。
final class NotificationDatabaseWatcher: @unchecked Sendable {
    /// 去抖窗口：0.3s 够让「一次通知写多行 + 写两个文件」的成串事件收成一次回调，
    /// 又远小于人眼能察觉的延迟（用户的验收口径是 < 3s，实测 < 1s）。
    static let debounceInterval: Duration = .milliseconds(300)

    /// 监听的文件（顺序固定：主库在前、WAL 在后，日志口径稳定）。
    private let paths: [String]
    /// 事件处理与 source 管理都在这一条串行队列上（不占主线程）。
    private let queue = DispatchQueue(label: "com.cmeng.gourd.notifications.db-watcher")
    /// 保护 `sources` / `pendingToken` / `isStopped`（跨队列访问：stop 可能在任意线程被调）。
    private let lock = NSLock()
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    /// 去抖令牌：每次事件自增，睡醒后令牌不等 = 期间又有事件，本次回调作废。
    private var pendingToken = 0
    private var isStopped = false
    private let onChange: () -> Void

    /// 监听器的诊断日志。**刻意不走宿主 `Logger`**：那条路径受设置里的 `logLevel` 闸门控制
    ///（默认 `.none` = 全静默），而「source 挂上没有、事件来没来」是实时性唯一的现场证据——
    /// 一律直出到统一日志（`log stream --info --predicate 'subsystem BEGINSWITH "com.cmeng.gourd"'`）。
    private static let logger = os.Logger(
        subsystem: "com.cmeng.gourd.module.notifications",
        category: "watcher"
    )

    init(databasePath: String, onChange: @escaping () -> Void) {
        self.paths = [databasePath, databasePath + "-wal"]
        self.onChange = onChange
    }

    deinit { stop() }

    /// 起监听（异步对账一次：只为**已存在**的文件挂 source）。
    func start() {
        queue.async { [self] in
            Self.logger.info("监听开始，目标 \(self.paths.map { ($0 as NSString).lastPathComponent }.joined(separator: " + "), privacy: .public)")
            reconcileNow()
        }
    }

    /// 停监听并取消全部 source（幂等；`cancel` 的清理闭包负责关掉 fd）。
    func stop() {
        lock.lock()
        isStopped = true
        pendingToken += 1  // 让在飞的去抖任务失效
        let live = Array(sources.values)
        sources.removeAll()
        lock.unlock()
        live.forEach { $0.cancel() }
    }

    /// 与文件系统对账：给新出现的文件补挂 source，把已消失的文件摘掉。
    ///
    /// 公开给「兜底轮询」顺带调用是可选的（模块当前不调）：事件路径自己每次都会对账。
    func reconcile() {
        queue.async { [self] in reconcileNow() }
    }

    // MARK: 内部（全部在 `queue` 上）

    private func reconcileNow() {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        for path in existing where currentSource(for: path) == nil {
            attach(path)
        }
        for (path, source) in currentSources() where !existing.contains(path) {
            // delete / rename 之后旧 fd 只对已被 unlink 的 inode 有效：留着只会空转，
            // 等文件重新出现（下一次 reconcileNow）再补挂。
            removeSource(for: path)
            source.cancel()
            Self.logger.info("摘掉 source（文件已消失）：\((path as NSString).lastPathComponent, privacy: .public)")
        }
    }

    private func attach(_ path: String) {
        let name = (path as NSString).lastPathComponent
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            // TCC 拒绝（EPERM）或其它 open 失败：不致命，兜底轮询仍在（见类型注释）。
            Self.logger.warning(
                "open(O_EVTONLY) 失败，\(name, privacy: .public) 没有 source，errno \(errno, privacy: .public)"
            )
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.handleEvent(name) }
        source.setCancelHandler { close(descriptor) }

        lock.lock()
        if isStopped {
            lock.unlock()
            source.cancel()
            source.resume()  // 已挂起的 source 要 resume 才会派发 cancel 事件（= 关掉 fd）
            return
        }
        sources[path] = source
        lock.unlock()
        source.resume()
        Self.logger.info("已挂 source：\(name, privacy: .public)（fd \(descriptor, privacy: .public)）")
    }

    private func handleEvent(_ name: String) {
        Self.logger.debug("文件事件：\(name, privacy: .public)")
        // ① 先对账：`.delete` / `.rename` 之后文件可能已经换了一个（checkpoint 清 db-wal、
        //    库被原子替换），同一批事件里就要把旧的摘掉、新的补上。
        reconcileNow()
        // ② 再去抖回调：一次写入会来一串事件，只让最后那次回调生效。
        scheduleCallback()
    }

    private func scheduleCallback() {
        lock.lock()
        guard !isStopped else {
            lock.unlock()
            return
        }
        pendingToken += 1
        let token = pendingToken
        lock.unlock()

        Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard let self else { return }
            guard self.consumeDebounceToken(token) else { return }  // 期间又有事件：交给那一次
            Self.logger.info("去抖窗口结束，回调取数")
            self.onChange()
        }
    }

    /// 去抖令牌是否仍是「最后那一个」（同步方法：`NSLock` 不能在 async 上下文里直接 lock/unlock——
    /// 那是 Swift 6 的编译错误，这里包一层同步壳子）。
    private func consumeDebounceToken(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isStopped && pendingToken == token
    }

    private func currentSource(for path: String) -> DispatchSourceFileSystemObject? {
        lock.lock()
        defer { lock.unlock() }
        return sources[path]
    }

    private func currentSources() -> [String: DispatchSourceFileSystemObject] {
        lock.lock()
        defer { lock.unlock() }
        return sources
    }

    private func removeSource(for path: String) {
        lock.lock()
        defer { lock.unlock() }
        sources[path] = nil
    }
}
