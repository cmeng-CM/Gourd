// Modified for Gourd (2026-09-30)
// Copyright (C) 2026 Gourd Contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//

//
//  ModuleKernelTests.swift
//  Gourd 模块内核 · 类型层单测（P1 批次 / T1）
//
//  覆盖 docs/13-runtime-kernel.md §接口与数据形状：
//  T1 类型层——manifest 校验（每个 ModuleManifestError 分支至少一例）、取值词汇表、
//  权限白名单常量表、config 子集解析、协议可一致性；构造一律走 `ModuleManifest.decode(from:)`
//  （JSON 路径），与宿主读 descriptor 同一条路。
//  T2 注册表与组合根——注册幂等、activate 抛错隔离、启用门、tab 投影、content 降级、
//  `ModuleContextFactory` 的默认值读取、首启默认值幂等、**折叠态中央槽位投影**
//  （`compactEntries` 过滤与排序、`compactSlotContent()` 的转发与无候选回退）。
//  T3 接缝——S2 的 tab 计数（刘海最小宽度的输入）把注册表条目计入总数；S4 的
//  `selectModule(_:)` 同时设 `selectedModuleID` 与 `currentView`。
//  T4 试点模块 progress——进度计算（闰年 2 月 / 季度边界 / 年初年末 / 周起止随日历）、
//  剩余量分档（`remaining`：跨天向上取整 / 跨小时 / 最后一分钟 / 刚过整点）、
//  `visibleScopes` 解析（缺省=今天+本周+本月 / 非法值忽略 / 顺序按输入，两条入口同口径）、
//  manifest 与 config 契约、真组合根注册后的 tab 投影与展开内容。
//  T5 待办模块 todos——分类与计数（今日 / 本周 / 所有三档的成员与 `(已办, 总量)`、
//  「无到期时间只进所有」、今日与本周的刻意重叠、本周随 `firstWeekday`）、清单排序、
//  manifest 契约、中央槽位的候选顺序（todos 的 order 20 排在 progress 的 30 之前）。
//  T6 笔记同步过滤——`AppleNotesTrashFilter.isTrashed` 的语言表命中、表外与空串不命中、
//  大小写与首尾空白无关（「最近删除」条目按语言名判定，表外语言保持旧行为）。
//  P2c 通知上岛——相对时间分档边界（<1 分钟 / 59 分钟 / 1 小时 / 23 小时 / 1 天 与时钟回拨）、
//  二进制 plist 的防御式解码（键齐解出 / 缺键给空并记缺失键名 / 垃圾字节与空 data 只记错不崩）、
//  manifest 契约与本地化 key 可解析、组合根的模块投影（三模块 tab 与槽位候选顺序）。
//  **单测不读系统通知库**（构造的二进制 plist 夹具），真实可读性由运行期探针报告判定。
//  P2d 瞬时浮层——`presentHUD` 的覆盖语义与身份更替、`ttl` 夹取到 1…15s、
//  到期**只清自己那一条**（被后来者替换后旧任务让路）与无人接替时自动清除、
//  `UIHandle.presentTransient` 转发到注册表（唯一实现落点）、
//  **主动撤浮层**（`dismissHUD(id:)` 的 id 判据与 `UIHandle.dismissTransient()` 的归属判定）、
//  **收起刘海请求**（D-28：`UIHandle.requestCollapse()` 由工厂原样转发到应用侧注入的闭包、
//  未接线时是空操作、组合根 → 注册表 → 工厂 → 句柄的透传链）、
//  **浮层窗口宿主的放置几何与尺寸消毒**（D-23：刘海 / 菜单栏内边、居中贴顶、0×0 与非有限值兜底）、
//  **可见性状态机的幂等性**（2026-09-28：首次上台 / 淡出中被接手 / 淡出结束无接手 / 同尺寸重弹 /
//  有接手时不 orderOut——「内置屏偶发只显示第一条」的根因判据）。
//  **浮层的多屏显示**（D-25：`targetScreenNames` 的三种输入口径——全屏模式取全集 /
//  单屏模式「指定屏 → 主屏 → 第一块」三档兜底 / 空屏集合给空集合）。
//  P2d 通知浮层——基线过滤（只有 `rec_id > 基线` 才弹、多条只弹最新一条）、
//  `showBodyInHUD` 的呈现口径（默认 true 显示正文，关掉只剩「新通知」）与键的声明默认值、
//  **卡片尺寸口径**（`notificationHUDScale` 的边界与钳位）、
//  **显示时长口径**（`notificationHUDDurationSeconds` 默认 8s + 设置值 → ttl 的映射与夹取边界）、
//  **配置区口径**（`enableNotificationHUD` 总开关关掉 → 不弹浮层的纯判据、`notificationHUDBackgroundStyle`
//  的默认档与写盘往返）。
//  **主面板背景可配**（D-26：`notchPanelBackgroundStyle` 的默认纯黑 / 三档词汇表 / 写盘往返、
//  `panelBackgroundUsesStyle` 的「玻璃只在展开态与浮动药丸上生效、刘海屏折叠态保持纯黑」四条组合、
//  以及玻璃底顶部的**不透明黑带高度** `panelTopOpaqueBandHeight`：取「刘海高度 / 菜单栏高度」里
//  更高的那个再 +1、异常输入夹到 0——2026-09-28「菜单栏图标被玻璃糊变形」与
//  2026-09-29「顶部比系统黑区窄」的判据）。
//  P2 启动台——扫描（`LauncherAppScanner`：只扫一层、按 url 去重、跳过 `.app` 内的嵌套包、
//  非 `.app` 与非目录跳过、名称三级回落、根目录可注入且单根失败不空表）与
//  排序 / 过滤（`LauncherRanking`：固定优先 → 最近使用 → 使用次数 → 名称、无使用数据回落名称、
//  未知固定 id 忽略、大小写不敏感地匹配显示名或文件名）。
//  **扫描用例一律用临时目录树 fixture**——不扫真实 `/Applications`（机器状态会让断言抖动）。
//  p7 / T2 工作日统计——`WorkdayCalendar` 的 2026 国务院节假日与调休表逐日期抽查（放假日恒休息、
//  调休日恒上班、表外年份退化纯星期）、今天行四态与 `todayFraction` 边界、
//  周 / 月 `spanStats` 的**手算值**（工作日占比 + 剩余工作日数，含「区间内一个工作日都没有」的
//  除零边界）、坏配置回落默认（工作星期集合与上下班小时）。
//  p7 / T3 工作日统计模块化——`WorkdayRowText` 的行文案矩阵（四态 → key 映射、`compactDuration`
//  边界、`leftDays` 的 0 与正数两档、10/1 当天的现状核对）、progress manifest 的三键契约
//  （类型 / 默认值与 `WorkdayCalendar` 常量同源）、模块三个新键的真句柄读侧（覆盖值优先 / 坏值归一）。
//  p7 / T5 启动台两区——`LauncherStore.pin` / `.unpin` 驱动 `quickApps` / `gridApps` 的分区
//  （上区 = **固定先后**、下区 = 剔除固定项保序）、**先落盘再刷新**、pin / unpin 的幂等
//  （固定表走内存假体 `LauncherPins`，不碰开发机真实 `Defaults` 域）。
//  p9 / T5 隔空投送字形几何——`AirDropGlyphMetrics` 的四个**量取值**逐字钉死（圆心点 0.13R、
//  三段弧环心 0.33 / 0.65 / 0.90R、线宽 0.113R、底部开口 70°；从用户给的控制中心参考图量出，
//  见 docs/34 §做法 机制二）；视图侧的渲染像素判据（圆心点 + 三段同心环 + 缺口在视觉正下方）
//  在 `.workflow/p9-calendar-week-icon/evidence/glyph-structure.py`（脚本，退出码 0）。
//  P11 / T2 首页行滚动卡片列——`CalendarEventCardList.ordered` 的展示顺序（全天在前、各自按
//  `start` 升序、提醒与日程混排同一把尺子、空数组返回空；口径逐字沿用旧紧凑行的
//  `orderedEvents`）。
//  P11 / T5 快速新增口径——`CalendarQuickAdd` 六条纯函数（宽松时间解析 D-11 的收/拒全表、
//  日程默认时段 D-08 的整点取当前与 23 点回退、起止同自然日校验、全天区间、提醒到期组件的
//  年月日归一化）。**不碰真 EventKit**（无 TCC 依赖）；服务层真写入归 T8 上屏复核。
//

import AppKit
import ApplicationServices
import Combine
import Defaults
import EventKit
import SQLite3
import SwiftUI
import XCTest

@testable import Gourd

@MainActor
final class ModuleKernelTests: XCTestCase {

    /// 注册表是 `shared` 单例：用例之间必须清空，否则前一个用例注册的模块会污染后一个的
    /// `manifests` / `states`（`deactivateAll()` 停用实例并清空 instances / states / manifests / moduleTypes）。
    override func setUp() async throws {
        try await super.setUp()
        await ModuleRegistry.shared.deactivateAll()
    }

    override func tearDown() async throws {
        await ModuleRegistry.shared.deactivateAll()
        try await super.tearDown()
    }

    // MARK: - 夹具

    /// 合法内置 manifest 的基线：字段与取值对齐 docs/13 §接口与数据形状 + 06 §2.2。
    private enum Fixture {
        static let baseline: [String: Any] = [
            "manifestVersion": 1,
            "id": "com.cmeng.gourd.progress",
            "name": ["key": "module.progress.name"] as [String: Any],
            "summary": ["key": "module.progress.summary"] as [String: Any],
            "icon": ["type": "symbol", "name": "chart.pie"] as [String: Any],
            "version": "1.0.0",
            "apiVersion": "1.0",
            "kind": "builtin",
            "surfaces": ["expanded"],
            "defaultPlacement": ["slot": "center", "order": 30] as [String: Any],
            "defaultEnabled": true,
            "permissions": ["notifications", "network:api.example.com"],
            "config": [
                "type": "object",
                "properties": [
                    "visibleScopes": ["type": "list", "itemType": "string", "default": ["day", "week"]] as [String: Any],
                    "style": ["type": "enum", "default": "ring", "values": ["ring", "bar", "text"]] as [String: Any],
                    "showSeconds": ["type": "boolean", "default": false] as [String: Any],
                    "refreshMinutes": ["type": "integer", "default": 1] as [String: Any],
                    "scale": ["type": "number", "default": 1.5] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]

        static func data(_ overrides: [String: Any] = [:], removing: [String] = []) throws -> Data {
            var object = baseline
            for key in removing { object.removeValue(forKey: key) }
            for (key, value) in overrides { object[key] = value }
            return try JSONSerialization.data(withJSONObject: object)
        }

        static func decode(_ overrides: [String: Any] = [:], removing: [String] = []) throws -> ModuleManifest {
            try ModuleManifest.decode(from: data(overrides, removing: removing))
        }
    }

    /// 断言 manifest 解码失败且错误是某个具体分支（`ModuleManifestError` 九个分支各有其证）。
    private func assertRejects(
        _ overrides: [String: Any] = [:],
        removing: [String] = [],
        equals expected: ModuleManifestError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try Fixture.decode(overrides, removing: removing), file: file, line: line) { error in
            XCTAssertEqual(error as? ModuleManifestError, expected, file: file, line: line)
        }
    }

    private func decodeConfigNode(_ json: String) throws -> ConfigNode {
        try JSONDecoder().decode(ConfigNode.self, from: Data(json.utf8))
    }

    /// `badLocalizedText` 的载荷是给人看的中文描述，断言分支而不是逐个字符串。
    private func assertBadLocalizedText(
        _ overrides: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try Fixture.decode(overrides), file: file, line: line) { error in
            guard let manifestError = error as? ModuleManifestError,
                  case .badLocalizedText = manifestError
            else {
                return XCTFail("期望 badLocalizedText，实到 \(error)", file: file, line: line)
            }
        }
    }

    // MARK: - 合法路径

    func testValidManifestDecodes() throws {
        let manifest = try Fixture.decode()

        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.progress")
        XCTAssertEqual(manifest.name.key, "module.progress.name")
        XCTAssertNil(manifest.name.table)
        XCTAssertEqual(manifest.summary?.key, "module.progress.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "chart.pie"))
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.apiVersion, "1.0")
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.expanded])
        XCTAssertEqual(manifest.defaultPlacement?.slot, .center)
        XCTAssertEqual(manifest.defaultPlacement?.order, 30)
        XCTAssertEqual(manifest.defaultEnabled, true)
        XCTAssertEqual(manifest.permissions, ["notifications", "network:api.example.com"])
        XCTAssertEqual(manifest.config?.type, "object")
        XCTAssertEqual(manifest.config?.properties.count, 5)
        XCTAssertNoThrow(try manifest.validate())
    }

    /// `surfaces` 可以只声明 `expanded`（D-12：本批不声明 `lockscreen`）；
    /// 内置模块必须用 `symbol` 图标；`permissions` 可省略（06 §2.2 缺省 `[]`）。
    func testManifestAcceptsMinimalBuiltinShape() throws {
        let manifest = try Fixture.decode(removing: ["summary", "defaultPlacement", "defaultEnabled", "permissions", "config"])
        XCTAssertNil(manifest.summary)
        XCTAssertNil(manifest.defaultPlacement)
        XCTAssertNil(manifest.defaultEnabled)
        XCTAssertTrue(manifest.permissions.isEmpty)
        // `config` 缺省即无 schema——06 §2.2 的默认 `{object, properties:{}}` 对读取侧等价于空表。
        XCTAssertNil(manifest.config)
        XCTAssertEqual(manifest.surfaces, [.expanded])
    }

    /// 插件形态的 locale 表（含 `en`）合法；本批只解析、不渲染。
    func testManifestAcceptsPluginStyleLocalizedText() throws {
        let manifest = try Fixture.decode([
            "name": ["en": "Progress", "zh-Hans": "进度"] as [String: Any],
            "summary": ["en": "Day/week/month/quarter/year progress"] as [String: Any],
        ])
        XCTAssertNil(manifest.name.key)
        XCTAssertEqual(manifest.name.table, ["en": "Progress", "zh-Hans": "进度"])
        XCTAssertEqual(manifest.summary?.table, ["en": "Day/week/month/quarter/year progress"])
    }

    /// D-11：`shortID` 由保留前缀派生；前缀是内置专属，插件不得占用（06 §2.2）。
    func testManifestShortIDAndIDPrefix() throws {
        XCTAssertEqual(try Fixture.decode().shortID, "progress")
        XCTAssertEqual(try Fixture.decode(["id": "com.cmeng.gourd.nowplaying"]).shortID, "nowplaying")

        // 内置缺保留前缀 → badID
        assertRejects(["id": "com.example.pomodoro"], equals: .badID("com.example.pomodoro"))

        // 非内置不得使用保留前缀 → badID（先于 unsupportedKind 报出，见 validate() 顺序）
        assertRejects(["id": "com.cmeng.gourd.fake", "kind": "js"], equals: .badID("com.cmeng.gourd.fake"))

        // 非内置 id 无 shortID 概念：原样返回（绕过 validate 直接解码，隔离该断言）
        let raw = try JSONDecoder().decode(ModuleManifest.self, from: Fixture.data(["id": "com.example.pomodoro"]))
        XCTAssertEqual(raw.shortID, "com.example.pomodoro")
    }

    // MARK: - manifest 校验（每个错误分支至少一例）

    func testManifestRejectsBadManifestVersion() throws {
        assertRejects(["manifestVersion": 2], equals: .badVersion(2))
        assertRejects(["manifestVersion": 0], equals: .badVersion(0))
    }

    func testManifestRejectsBadID() throws {
        // 大写不在 `^[a-z0-9]+(\.[a-z0-9-]+)+$` 内（06 §2.2）
        assertRejects(["id": "com.cmeng.Gourd"], equals: .badID("com.cmeng.Gourd"))
        // 单段（无点）
        assertRejects(["id": "progress"], equals: .badID("progress"))
        // 长度 > 128
        let tooLong = "com.cmeng.gourd." + String(repeating: "a", count: 129)
        assertRejects(["id": tooLong], equals: .badID(tooLong))
    }

    func testManifestRejectsBadAPIVersion() throws {
        // 必须 `^\d+\.\d+$`（不含 patch，06 §8.1）
        assertRejects(["apiVersion": "1"], equals: .badAPIVersion("1"))
        assertRejects(["apiVersion": "1.0.0"], equals: .badAPIVersion("1.0.0"))
        assertRejects(["apiVersion": "v1.0"], equals: .badAPIVersion("v1.0"))
        // major 不符
        assertRejects(["apiVersion": "2.0"], equals: .badAPIVersion("2.0"))
        // minor 超出宿主实现的最高 minor（本批 = 0）
        assertRejects(["apiVersion": "1.1"], equals: .badAPIVersion("1.1"))
    }

    func testManifestRejectsEmptySurfaces() throws {
        assertRejects(["surfaces": [String]()], equals: .emptySurfaces)
    }

    /// surface 取值是封闭词汇表：未知值在解码层就失败，不可能进入 validate（06 §6.1 不新增 `hud`）。
    func testManifestRejectsUnknownSurface() throws {
        let data = try Fixture.data(["surfaces": ["expanded", "hud"]])
        XCTAssertThrowsError(try ModuleManifest.decode(from: data)) { error in
            XCTAssertTrue(error is DecodingError, "期望解码失败，实到 \(error)")
        }
    }

    func testManifestRejectsBadIcon() throws {
        // 内置必须 `symbol`（06 §2.2）
        assertRejects(["icon": ["type": "image"] as [String: Any]], equals: .badIcon("image"))
        assertRejects(["icon": ["type": "appIcon"] as [String: Any]], equals: .badIcon("appIcon"))
        // `symbol` 必须给 name
        assertRejects(["icon": ["type": "symbol"] as [String: Any]], equals: .badIcon("symbol 缺少 name"))
        // `name` 必须能被系统符号表解析（06 §2.4 实测一次）
        let bogus = "gourd.definitely.not.a.symbol"
        assertRejects(["icon": ["type": "symbol", "name": bogus] as [String: Any]], equals: .badIcon(bogus))
    }

    func testManifestRejectsMixedLocalizedText() throws {
        // key 与 locale 表混用（06 §2.3）
        let mixed: [String: Any] = ["key": "module.progress.name", "en": "Progress"]
        assertBadLocalizedText(["name": mixed])

        // locale 表缺 `en`
        let noEnglish: [String: Any] = ["zh-Hans": "进度"]
        assertBadLocalizedText(["name": noEnglish])

        // 空文本（既无 key 也无 locale 表）
        assertBadLocalizedText(["name": [String: Any]()])

        // 长度上限（06 §2.2：name ≤ 40）
        let tooLong: [String: Any] = ["en": String(repeating: "x", count: 41)]
        assertBadLocalizedText(["name": tooLong])

        // 上限内的文本照常通过（约束不是「一律拒绝」）
        XCTAssertNoThrow(try Fixture.decode(["summary": ["en": String(repeating: "y", count: 120)] as [String: Any]]))
    }

    func testManifestRejectsUnknownPermission() throws {
        // 不在 06 §7.1 白名单内
        assertRejects(["permissions": ["clipboard"]], equals: .unknownPermission("clipboard"))
        // 裸 `network` 不合法（06 §7 硬性规则 1：必须 `network:<host>`）
        assertRejects(["permissions": ["network"]], equals: .unknownPermission("network"))
        // 参数为空
        assertRejects(["permissions": ["network:"]], equals: .unknownPermission("network:"))
        assertRejects(["permissions": ["events:subscribe:"]], equals: .unknownPermission("events:subscribe:"))
    }

    /// `kind == builtin` 不得声明 `entry`（06 §2.2 → `E_UNEXPECTED_FIELD`）
    func testManifestRejectsUnexpectedEntry() throws {
        let entry: [String: Any] = ["runtime": "js", "main": "main.js"]
        assertRejects(["entry": entry], equals: .unexpectedEntry)
    }

    /// 本批只允许 `builtin`（插件运行时属 P4）；非内置 id 用合法反域名以免与前缀规则混淆。
    func testManifestRejectsUnsupportedKind() throws {
        assertRejects(["id": "com.example.pomodoro", "kind": "js"], equals: .unsupportedKind("js"))
        assertRejects(["id": "com.example.pomodoro", "kind": "xpc"], equals: .unsupportedKind("xpc"))
    }

    // MARK: - config 子集

    func testManifestParsesConfigSubset() throws {
        let properties = try XCTUnwrap(try Fixture.decode().config?.properties)

        XCTAssertEqual(properties["visibleScopes"]?.type, "list")
        XCTAssertEqual(properties["visibleScopes"]?.itemType, "string")
        XCTAssertEqual(properties["visibleScopes"]?.default, ConfigValue.strings(["day", "week"]))

        XCTAssertEqual(properties["style"]?.type, "enum")
        XCTAssertEqual(properties["style"]?.values, ["ring", "bar", "text"])
        XCTAssertEqual(properties["style"]?.default, ConfigValue.string("ring"))

        XCTAssertEqual(properties["showSeconds"]?.default, ConfigValue.bool(false))
        XCTAssertEqual(properties["refreshMinutes"]?.default, ConfigValue.int(1))
        XCTAssertEqual(properties["scale"]?.default, ConfigValue.double(1.5))
        XCTAssertEqual(properties["scale"]?.type, "number")
    }

    /// 06 §5.3：`default` 在 manifest JSON 里是**裸值**——不是一个带类型标签的对象。
    /// 这条是 `ConfigValue` 必须自定义 `Codable` 的理由，也是它最容易写错的地方。
    func testConfigValueDefaultIsBareJSON() throws {
        XCTAssertEqual(try decodeConfigNode(#"{"type":"string","default":"ring"}"#).default, ConfigValue.string("ring"))
        XCTAssertEqual(try decodeConfigNode(#"{"type":"boolean","default":true}"#).default, ConfigValue.bool(true))
        XCTAssertEqual(try decodeConfigNode(#"{"type":"integer","default":1}"#).default, ConfigValue.int(1))
        XCTAssertEqual(try decodeConfigNode(#"{"type":"number","default":1.5}"#).default, ConfigValue.double(1.5))
        XCTAssertEqual(try decodeConfigNode(#"{"type":"list","default":["a","b"]}"#).default, ConfigValue.strings(["a", "b"]))

        // 整数不得被写成浮点（裸值 `1` 解成 `.int(1)`），否则 `get(_:as:Int.self)` 会静默失败
        XCTAssertNotEqual(try decodeConfigNode(#"{"type":"integer","default":1}"#).default, ConfigValue.double(1))

        // 编码回写同样是裸值（合成编码会产出 {"string":"ring"}）
        let encoded = try JSONEncoder().encode(ConfigValue.string("ring"))
        XCTAssertEqual(String(data: encoded, encoding: .utf8), #""ring""#)

        // 来回一趟不丢形态（同时验证 `default` 的 CodingKey 双向可用）
        let node = try decodeConfigNode(#"{"type":"enum","default":"ring","values":["ring","bar"]}"#)
        XCTAssertEqual(try JSONDecoder().decode(ConfigNode.self, from: JSONEncoder().encode(node)), node)
    }

    // MARK: - 取值词汇表与权限白名单

    /// 06 §3.1 / §6.1 / §6.2 的取值词汇表是本批对外契约（D-02 / D-11：逐字沿用、不得漂移）。
    /// `Surface` 的第四个取值 `home`（首页 strip 的一块）是 P2 批次的增量
    ///（docs/17-nookx-adoption.md §接口与数据形状 1），排在既有三个取值**之后**——
    /// 既有取值的语义与顺序不变。
    func testProtocolVocabularyMatchesProtocolDoc() {
        XCTAssertEqual(Surface.allCases.map(\.rawValue), ["compact", "expanded", "lockscreen", "home"])
        XCTAssertEqual(Slot.allCases.map(\.rawValue), ["left", "right", "center"])
        // 四态定死；本批只有 collapsed / expanded 可达（D-04 包装路线，hoverPreview / dragging 属 P1-2）
        XCTAssertEqual(NotchPhase.allCases.map(\.rawValue), ["collapsed", "hoverPreview", "expanded", "dragging"])
        XCTAssertEqual(
            [ContentRequestReason.initial, .event, .configChanged, .tick, .redraw].map(\.rawValue),
            ["initial", "event", "configChanged", "tick", "redraw"]
        )
    }

    /// 06 §7.1 全表 15 行抄成常量：无参数 13 项 + 带参数 2 项。
    func testPermissionCatalogMatchesProtocolDoc() {
        let table = [
            "notifications", "timers", "storage",
            "clipboard:read", "clipboard:write",
            "files:picker", "files:shelf",
            "media:control", "media:read",
            "system:metrics", "power:control",
            "shortcuts:run", "ai:complete",
            "network:<host>", "events:subscribe:<eventName>",
        ]
        XCTAssertEqual(table.count, 15)
        XCTAssertEqual(ModulePermissionCatalog.allCapabilities.count, 15)
        for capability in table {
            XCTAssertTrue(ModulePermissionCatalog.allCapabilities.contains(capability), capability)
        }

        XCTAssertTrue(ModulePermissionCatalog.isKnown("network:api.example.com"))
        XCTAssertTrue(ModulePermissionCatalog.isKnown("events:subscribe:notch.phaseChanged"))
        XCTAssertFalse(ModulePermissionCatalog.isKnown("network"))
        XCTAssertFalse(ModulePermissionCatalog.isKnown("network:"))
        XCTAssertFalse(ModulePermissionCatalog.isKnown("events:subscribe:"))
        XCTAssertFalse(ModulePermissionCatalog.isKnown(""))
    }

    // MARK: - 协议可一致性（GourdModule / ModuleContent / ModuleContext）

    func testModuleProtocolIsUsableWithInjectedContext() throws {
        let stub = StubModule.manifest
        XCTAssertNoThrow(try stub.validate())
        XCTAssertEqual(stub.shortID, "stub")
        XCTAssertEqual(stub.surfaces, [.expanded])

        let ui = StubUIHandle()
        let context = ModuleContext(
            moduleID: stub.id,
            host: HostInfo(appVersion: "0.1.0", apiVersion: HostInfo.currentAPIVersion, macOSVersion: "15.0"),
            config: StubConfigHandle(),
            logger: ModuleLogger(moduleID: stub.id, shortID: stub.shortID),
            ui: ui
        )

        let module = StubModule(context: context)
        XCTAssertEqual(module.context.moduleID, "com.cmeng.gourd.stub")
        XCTAssertEqual(context.host.apiVersion, "1.0")

        let request = ContentRequest(surface: .expanded, phase: .expanded, reason: .initial)
        guard case .unavailable(let reason) = module.content(for: request) else {
            return XCTFail("期望 .unavailable")
        }
        XCTAssertEqual(reason, "stub 未实现内容")

        XCTAssertFalse(context.ui.isLowPower)
        context.ui.requestRedraw()
        XCTAssertEqual(ui.redrawCount, 1)
    }

    // MARK: - 注册表与组合根（T2）

    /// 组合根的启用门**逐字复刻**：`manifests[id]?.defaultEnabled ?? false`（06 §2.2 缺省 false）。
    private func registerProbes(_ types: [any GourdModule.Type]) {
        ModuleRegistry.shared.register(types, enabled: { ModuleRegistry.shared.manifests[$0]?.defaultEnabled ?? false })
    }

    private func request(_ surface: Surface = .expanded) -> ContentRequest {
        ContentRequest(surface: surface, phase: .expanded, reason: .initial)
    }

    private func assertUnavailable(
        _ content: ModuleContent,
        contains id: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unavailable(let reason) = content else {
            return XCTFail("期望 .unavailable，实到 \(content)", file: file, line: line)
        }
        XCTAssertTrue(reason.contains(id), "降级原因应带上模块 id，实到 \(reason)", file: file, line: line)
    }

    /// 同 id 重复注册被忽略：manifest 只留一份，bootstrap 后实例是**先注册**的那个类型（不被覆盖）。
    func testRegisterIgnoresDuplicateID() async {
        let registry = ModuleRegistry.shared
        registerProbes([AlphaProbeModule.self, AlphaImpostorModule.self])

        XCTAssertEqual(registry.manifests.count, 1, "同 id 重复注册应被忽略")
        XCTAssertNotNil(registry.manifests["com.cmeng.gourd.probe-alpha"])

        await registry.bootstrap()
        XCTAssertEqual(registry.states.count, 1)
        XCTAssertTrue(
            registry.instance(for: "com.cmeng.gourd.probe-alpha") is AlphaProbeModule,
            "后注册的同 id 模块不得覆盖先注册者"
        )
    }

    /// 一个模块 `activate()` 抛错只禁用它自己：其余模块照常激活——含 id 排在它**之后**的模块，
    /// 证明 `bootstrap()` 没有提前返回；`.failed` 是终态，不重试。
    func testRegistryIsolatesFailingModule() async {
        let registry = ModuleRegistry.shared
        registerProbes([AlphaProbeModule.self, BetaProbeModule.self, GammaProbeModule.self])

        await registry.bootstrap()

        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-alpha"], .active)
        // beta 的 id 在 gamma 之前：它抛错后 gamma 仍 active = 循环走完了
        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-gamma"], .active)
        XCTAssertNil(registry.instance(for: "com.cmeng.gourd.probe-beta"), "失败的模块不留实例")

        guard case .failed(let reason)? = registry.states["com.cmeng.gourd.probe-beta"] else {
            return XCTFail("期望 .failed，实到 \(String(describing: registry.states["com.cmeng.gourd.probe-beta"]))")
        }
        XCTAssertFalse(reason.isEmpty)

        // 再 bootstrap 一次：失败的模块不重试、已激活的模块不重复激活
        await registry.bootstrap()
        guard case .failed? = registry.states["com.cmeng.gourd.probe-beta"] else {
            return XCTFail("失败的模块不得被重试")
        }
        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-gamma"], .active)
    }

    /// `defaultEnabled = false` 的模块：不实例化、状态为 `.disabled`、不进 `tabEntries`。
    func testDisabledModuleIsNotActivated() async {
        let registry = ModuleRegistry.shared
        registerProbes([AlphaProbeModule.self, OptInProbeModule.self])

        await registry.bootstrap()

        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-alpha"], .active)
        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-optin"], .disabled)
        XCTAssertNil(registry.instance(for: "com.cmeng.gourd.probe-optin"), "未启用的模块不实例化")
        XCTAssertEqual(registry.tabEntries.map(\.id), ["com.cmeng.gourd.probe-alpha"])
    }

    /// tab 投影 = 只含 `active` 且声明 `.expanded` 的模块，按 `order` 升序、同 `order` 按 id 字典序；
    /// `label` 走 key → `en` 表 → `shortID` 的解析顺序。
    func testTabEntriesReflectRegistryProjection() async {
        let registry = ModuleRegistry.shared
        // 注册顺序与 tab 顺序**故意不一致**：排序不能是注册顺序
        registerProbes([
            DeltaProbeModule.self,
            GammaProbeModule.self,
            OptInProbeModule.self,
            CompactProbeModule.self,
            BetaProbeModule.self,
            AlphaProbeModule.self,
        ])

        await registry.bootstrap()

        XCTAssertEqual(registry.tabEntries.map(\.id), [
            "com.cmeng.gourd.probe-alpha",   // order 10，与 gamma 同序 → id 字典序在前
            "com.cmeng.gourd.probe-gamma",   // order 10
            "com.cmeng.gourd.probe-delta",   // 无 defaultPlacement → Int.max
        ])
        XCTAssertEqual(registry.tabEntries.map(\.order), [10, 10, Int.max])
        XCTAssertEqual(registry.tabEntries.map(\.symbolName), Array(repeating: "square", count: 3))
        // key 形态在 Localizable 里查不到 → 回退 shortID；locale 表形态 → 取 en 文案
        XCTAssertEqual(registry.tabEntries.map(\.label), ["probe-alpha", "Gamma Probe", "probe-delta"])

        // 被过滤的三类：failed（beta）/ disabled（optin）/ 只声明 .compact（compact）
        for id in ["com.cmeng.gourd.probe-beta", "com.cmeng.gourd.probe-optin", "com.cmeng.gourd.probe-compact"] {
            XCTAssertFalse(registry.tabEntries.contains { $0.id == id }, "\(id) 不应进 tab 列表")
        }
        XCTAssertEqual(registry.states.count, 6, "六个模块都被判定过（active / failed / disabled）")
    }

    /// `content(for:request:)` 转发已激活模块；未知 id 与未激活模块（disabled / failed / 未 bootstrap）
    /// 一律 `.unavailable`（不崩、不返回空内容）。
    func testContentUnavailableForInactiveModule() async {
        let registry = ModuleRegistry.shared
        registerProbes([AlphaProbeModule.self, BetaProbeModule.self, OptInProbeModule.self])

        // 已注册但尚未 bootstrap（无状态、无实例）→ unavailable
        assertUnavailable(registry.content(for: "com.cmeng.gourd.probe-alpha", request: request()), contains: "com.cmeng.gourd.probe-alpha")

        await registry.bootstrap()

        // 已激活：转发到实例（夹具返回 `.none`，与注册表的降级 `.unavailable` 可区分）
        guard case .none = registry.content(for: "com.cmeng.gourd.probe-alpha", request: request()) else {
            return XCTFail("期望转发给实例并返回 .none")
        }
        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-alpha"], .active)

        assertUnavailable(registry.content(for: "com.cmeng.gourd.probe-optin", request: request()), contains: "com.cmeng.gourd.probe-optin")
        assertUnavailable(registry.content(for: "com.cmeng.gourd.probe-beta", request: request()), contains: "com.cmeng.gourd.probe-beta")
        // 未知 id：返回 unavailable 而不是崩溃
        assertUnavailable(registry.content(for: "com.cmeng.gourd.probe-ghost", request: request()), contains: "com.cmeng.gourd.probe-ghost")
    }

    /// `ModuleContextFactory`：host 从宿主取、config 读 manifest 默认值（含 `number` 节点整数默认值的
    /// int→Double 互认）、覆盖值落模块专属 suite、`requestRedraw` 转发注入闭包。
    func testModuleContextConfigReadsManifestDefault() throws {
        let suiteName = "com.cmeng.gourd.module.probe-config"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)      // 前置：清掉上次运行留下的覆盖值
        defer { suite.removePersistentDomain(forName: suiteName) }

        let manifest = try ModuleManifest.decode(from: Data(#"""
        {
          "manifestVersion": 1,
          "id": "com.cmeng.gourd.probe-config",
          "name": {"key": "module.probe-config.name"},
          "icon": {"type": "symbol", "name": "square"},
          "version": "1.0.0",
          "apiVersion": "1.0",
          "kind": "builtin",
          "surfaces": ["expanded"],
          "config": {
            "type": "object",
            "properties": {
              "scale": {"type": "number", "default": 2},
              "ratio": {"type": "number", "default": 1.5},
              "refreshMinutes": {"type": "integer", "default": 1},
              "style": {"type": "enum", "default": "ring", "values": ["ring", "bar"]},
              "showSeconds": {"type": "boolean", "default": false},
              "visibleScopes": {"type": "list", "itemType": "string", "default": ["day", "week"]}
            }
          }
        }
        """#.utf8))

        let probe = RedrawProbe()
        let context = ModuleContextFactory.make(manifest: manifest, redraw: { probe.count += 1 })

        XCTAssertEqual(context.moduleID, "com.cmeng.gourd.probe-config")
        XCTAssertEqual(context.host.apiVersion, "1.0")
        XCTAssertEqual(context.host.appVersion, Bundle.main.releaseVersionNumber ?? "0")
        XCTAssertEqual(context.host.macOSVersion, ModuleContextFactory.macOSVersion)

        // manifest 默认值（本批唯一默认值来源）
        XCTAssertEqual(context.config.get("refreshMinutes", as: Int.self), 1)
        XCTAssertEqual(context.config.get("style", as: String.self), "ring")
        XCTAssertEqual(context.config.get("showSeconds", as: Bool.self), false)
        XCTAssertEqual(context.config.get("visibleScopes", as: [String].self), ["day", "week"])
        XCTAssertEqual(context.config.get("ratio", as: Double.self), 1.5)
        // `{"type":"number","default":2}` 的裸值落成 `.int(2)`：`get(_:as: Double.self)` 必须互认，
        // 否则 `number` 型的整数默认值会静默返回 nil
        XCTAssertEqual(context.config.get("scale", as: Double.self), 2.0)
        // schema 之外的键读不到（不崩）
        XCTAssertNil(context.config.get("undeclared", as: String.self))

        // 覆盖值：落模块专属 suite、优先于默认值；未声明的键不落盘
        XCTAssertTrue(context.config.set("refreshMinutes", to: 30))
        XCTAssertEqual(context.config.get("refreshMinutes", as: Int.self), 30)
        let readBack = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertNotNil(readBack.data(forKey: "refreshMinutes"), "覆盖值应落在 com.cmeng.gourd.module.<shortID>")
        XCTAssertFalse(context.config.set("undeclared", to: 1))
        XCTAssertNil(readBack.object(forKey: "undeclared"))

        // 覆盖值清掉后回到 manifest 默认值
        readBack.removeObject(forKey: "refreshMinutes")
        XCTAssertEqual(context.config.get("refreshMinutes", as: Int.self), 1)

        // UIHandle：转发注入闭包、isLowPower 恒 false
        XCTAssertFalse(context.ui.isLowPower)
        context.ui.requestRedraw()
        context.ui.requestRedraw()
        XCTAssertEqual(probe.count, 2)
    }

    /// 首启默认值**一次性、幂等**：闸门键为真后不再覆盖用户手动改回的值。
    func testFirstLaunchDefaultsIdempotent() {
        let defaults = UserDefaults.standard
        // 闸门键（接缝 S7）定义在 `Constants.swift` 的 `Defaults.Keys` 里：用例取 Key 名做
        // `UserDefaults` 原值快照/还原，不再有第二处字面量。
        let flagKey = Defaults.Keys.gourdFirstLaunchDefaultsApplied.name
        // TEST_HOST = Gourd.app：这里改的是开发者机器上真实的 app defaults，用例改过的键全部还原
        let originalFlag = defaults.object(forKey: flagKey)
        let originalScreenAssistant = defaults.object(forKey: "enableScreenAssistant")
        defer {
            if let originalFlag {
                defaults.set(originalFlag, forKey: flagKey)
            } else {
                defaults.removeObject(forKey: flagKey)
            }
            if let originalScreenAssistant {
                defaults.set(originalScreenAssistant, forKey: "enableScreenAssistant")
            } else {
                defaults.removeObject(forKey: "enableScreenAssistant")
            }
        }

        // 前置：模拟「从未首启」+ 上游默认值 true
        defaults.removeObject(forKey: flagKey)
        defaults.set(true, forKey: "enableScreenAssistant")

        KernelBootstrap.applyFirstLaunchDefaults()
        XCTAssertFalse(defaults.bool(forKey: "enableScreenAssistant"), "首启应关掉 enableScreenAssistant")
        XCTAssertTrue(defaults.bool(forKey: flagKey), "首启应落闸门键")

        // 用户随后手动打开 → 第二次调用不得再覆盖（幂等）
        defaults.set(true, forKey: "enableScreenAssistant")
        KernelBootstrap.applyFirstLaunchDefaults()
        XCTAssertTrue(defaults.bool(forKey: "enableScreenAssistant"), "已应用过 → 第二次调用必须原样返回")
    }

    // MARK: - 接缝（T3）

    /// 接缝 S2：`enabledStandardTabCount()`（刘海最小宽度的输入）必须把注册表 tab 计入总数。
    ///
    /// 断言用**增量**而非绝对值：上游那 6 个标准 tab 由开发机上的真实 Defaults 决定，
    /// 只有增量能把「注册表条目被计入」与「Default 开关恰好这样」分开。注册表为空时该数
    /// 必须回到基线——否则 S2 读的就不是 `tabEntries`（清空后应当归零）。
    func testEnabledStandardTabCountIncludesActiveModuleEntries() async {
        let baseline = enabledStandardTabCount()

        registerProbes([
            AlphaProbeModule.self,     // active + 声明 .expanded → 计入
            GammaProbeModule.self,     // active + 声明 .expanded → 计入
            DeltaProbeModule.self,     // active + 声明 .expanded → 计入
            BetaProbeModule.self,      // activate 抛错 → failed，不计入
            CompactProbeModule.self,   // 只声明 .compact，不计入
            OptInProbeModule.self,     // defaultEnabled=false → disabled，不计入
        ])
        await ModuleRegistry.shared.bootstrap()

        let entries = ModuleRegistry.shared.tabEntries
        XCTAssertEqual(entries.count, 3, "投影只含 active 且声明 .expanded 的模块")
        XCTAssertEqual(
            enabledStandardTabCount(),
            baseline + entries.count,
            "S2 必须把注册表条目计入总数（恰好多 N，而不是只多了一个词）"
        )

        // 反向：注册表清空 → 回到基线（S2 的增量只来自 tabEntries）
        await ModuleRegistry.shared.deactivateAll()
        XCTAssertEqual(enabledStandardTabCount(), baseline, "注册表清空后必须回到基线")
    }

    /// 接缝 S4：`selectModule(_:)` 必须**同时**设 `selectedModuleID` 与 `currentView = .module`。
    ///
    /// 两个都要：只设 `currentView` 会让内容区拿不到模块 id 而渲染 EmptyView（S1 ④ 的失败模式）；
    /// 只设 id 则 tab 选中态（`isSelected` 比 id）与内容区不同步。
    func testSelectModuleSetsSelectedIDAndView() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let originalID = coordinator.selectedModuleID
        let originalView = coordinator.currentView
        // 上游 `currentView.didSet` 在极简模式下会把非 `.home` 的选中强制回 `.home`；
        // 用例把该开关压到 false 再断言，结束还原原值（只影响本用例窗口期）。
        let originalMinimalistic = Defaults[.enableMinimalisticUI]
        defer {
            Defaults[.enableMinimalisticUI] = originalMinimalistic
            coordinator.selectedModuleID = originalID
            coordinator.currentView = originalView
        }
        Defaults[.enableMinimalisticUI] = false

        coordinator.selectModule("com.cmeng.gourd.probe-alpha")

        XCTAssertEqual(coordinator.selectedModuleID, "com.cmeng.gourd.probe-alpha")
        XCTAssertEqual(coordinator.currentView, .module, "selectModule 必须把 currentView 切到 .module")
    }

    // MARK: - 试点模块 progress（T4）

    /// 固定日历：不读开发机的时区 / 语言 / 周起始日，断言才可复现。
    private func fixedGregorian(timeZone: String = "Asia/Shanghai", firstWeekday: Int = 2) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZone))
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// 构造注入用的固定「现在」（按给定日历的时区解释）。
    private func instant(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        calendar: Calendar
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = calendar.timeZone
        return try XCTUnwrap(calendar.date(from: components), "构造日期失败：\(year)-\(month)-\(day)")
    }

    /// D-07 的进度计算：断言覆盖闰年 2 月、季度边界（3/31、4/1、12/31）、年初年末、
    /// 周进度在周一 / 周日两侧——一律「注入固定 now + 固定时区日历」，结论只依赖 `Calendar` 语义。
    func testProgressCalculation() throws {
        let calendar = try fixedGregorian()

        // 日：正午恰好一半；00:00 归零
        XCTAssertEqual(
            ProgressCalculator.progress(for: .day, now: try instant(2026, 3, 31, 12, calendar: calendar), calendar: calendar),
            0.5, accuracy: 1e-9
        )
        XCTAssertEqual(
            ProgressCalculator.progress(for: .day, now: try instant(2026, 3, 31, calendar: calendar), calendar: calendar),
            0, accuracy: 1e-9
        )

        // 闰年 2 月：区间总长由 `Calendar` 定（2024 = 29 天、2023 = 28 天），不手算天数
        let leapDayNoon = try instant(2024, 2, 29, 12, calendar: calendar)
        XCTAssertEqual(
            try XCTUnwrap(ProgressCalculator.interval(for: .month, now: leapDayNoon, calendar: calendar)).duration,
            29.0 * 86_400, accuracy: 1
        )
        XCTAssertEqual(ProgressCalculator.progress(for: .month, now: leapDayNoon, calendar: calendar), 28.5 / 29, accuracy: 1e-9)
        XCTAssertEqual(
            try XCTUnwrap(ProgressCalculator.interval(for: .month, now: try instant(2023, 2, 28, 12, calendar: calendar), calendar: calendar)).duration,
            28.0 * 86_400, accuracy: 1
        )
        // 跨月边界：闰日多出来的那天在 3/1 00:00 之后才计入
        XCTAssertEqual(
            ProgressCalculator.progress(for: .month, now: try instant(2024, 3, 1, calendar: calendar), calendar: calendar),
            0, accuracy: 1e-9
        )
        // 年尺度也跟着 `Calendar` 走：闰年 366 天
        XCTAssertEqual(
            try XCTUnwrap(ProgressCalculator.interval(for: .year, now: try instant(2024, 6, 1, calendar: calendar), calendar: calendar)).duration,
            366.0 * 86_400, accuracy: 1
        )

        // 季度边界 3/31：Q1 = [1/1, 4/1)，1–3 月 = 90 天；3/31 00:00 = 89/90，最后一分钟仍 < 1
        let q1 = try XCTUnwrap(ProgressCalculator.interval(for: .quarter, now: try instant(2026, 3, 31, calendar: calendar), calendar: calendar))
        XCTAssertEqual(q1.start, try instant(2026, 1, 1, calendar: calendar))
        XCTAssertEqual(q1.end, try instant(2026, 4, 1, calendar: calendar))
        XCTAssertEqual(
            ProgressCalculator.progress(for: .quarter, now: try instant(2026, 3, 31, calendar: calendar), calendar: calendar),
            89.0 / 90.0, accuracy: 1e-9
        )
        let q1LastMinute = ProgressCalculator.progress(for: .quarter, now: try instant(2026, 3, 31, 23, 59, calendar: calendar), calendar: calendar)
        XCTAssertGreaterThan(q1LastMinute, 89.0 / 90.0)
        XCTAssertLessThan(q1LastMinute, 1)

        // 季度边界 4/1：落到 Q2 的起点（0）
        let q2Start = try instant(2026, 4, 1, calendar: calendar)
        let q2 = try XCTUnwrap(ProgressCalculator.interval(for: .quarter, now: q2Start, calendar: calendar))
        XCTAssertEqual(q2.start, q2Start)
        XCTAssertEqual(q2.end, try instant(2026, 7, 1, calendar: calendar))
        XCTAssertEqual(ProgressCalculator.progress(for: .quarter, now: q2Start, calendar: calendar), 0, accuracy: 1e-9)

        // 季度边界 12/31：Q4 = [10/1, **次年** 1/1)，跨年边界仍由 `Calendar` 给；10–12 月 = 92 天
        let q4Mid = try instant(2026, 12, 31, 12, calendar: calendar)
        let q4 = try XCTUnwrap(ProgressCalculator.interval(for: .quarter, now: q4Mid, calendar: calendar))
        XCTAssertEqual(q4.start, try instant(2026, 10, 1, calendar: calendar))
        XCTAssertEqual(q4.end, try instant(2027, 1, 1, calendar: calendar))
        XCTAssertEqual(ProgressCalculator.progress(for: .quarter, now: q4Mid, calendar: calendar), 91.5 / 92, accuracy: 1e-9)

        // 年初 / 年末：1/1 00:00 归零、12/31 23:59:59 尚未到 1、次日 00:00 已是新年
        XCTAssertEqual(
            ProgressCalculator.progress(for: .year, now: try instant(2026, 1, 1, calendar: calendar), calendar: calendar),
            0, accuracy: 1e-9
        )
        let yearEnd = try instant(2026, 12, 31, 23, 59, 59, calendar: calendar)
        let yearProgress = ProgressCalculator.progress(for: .year, now: yearEnd, calendar: calendar)
        XCTAssertGreaterThan(yearProgress, 0.9999)
        XCTAssertLessThan(yearProgress, 1)
        XCTAssertEqual(
            try XCTUnwrap(ProgressCalculator.interval(for: .year, now: yearEnd, calendar: calendar)).duration,
            365.0 * 86_400, accuracy: 1
        )
        XCTAssertEqual(
            ProgressCalculator.progress(for: .year, now: try instant(2027, 1, 1, calendar: calendar), calendar: calendar),
            0, accuracy: 1e-9
        )

        // 周（周一为首日）：2026-03-29 是周日，落在 [3/23, 3/30) 的第 6.5 天
        let mondayFirst = try fixedGregorian(firstWeekday: 2)
        let sundayNoon = try instant(2026, 3, 29, 12, calendar: mondayFirst)
        let mondayFirstWeek = try XCTUnwrap(ProgressCalculator.interval(for: .week, now: sundayNoon, calendar: mondayFirst))
        XCTAssertEqual(mondayFirstWeek.start, try instant(2026, 3, 23, calendar: mondayFirst))
        XCTAssertEqual(mondayFirstWeek.end, try instant(2026, 3, 30, calendar: mondayFirst))
        XCTAssertEqual(ProgressCalculator.progress(for: .week, now: sundayNoon, calendar: mondayFirst), 6.5 / 7, accuracy: 1e-9)
        // 周一 00:00 是新的周起点 → 归零，一小时后重新推进
        XCTAssertEqual(
            ProgressCalculator.progress(for: .week, now: try instant(2026, 3, 30, calendar: mondayFirst), calendar: mondayFirst),
            0, accuracy: 1e-9
        )
        XCTAssertEqual(
            ProgressCalculator.progress(for: .week, now: try instant(2026, 3, 30, 1, calendar: mondayFirst), calendar: mondayFirst),
            1.0 / (7 * 24), accuracy: 1e-9
        )

        // 周（**周日**为首日）：起止随日历走，不假定周一——同一个周日（3/29）成了新周的第 0.5 天，
        // 而在周一为首日时它已是那一周的第 6.5 天（同刻不同位，两个日历各自成立）
        let sundayFirst = try fixedGregorian(firstWeekday: 1)
        let sundayFirstWeek = try XCTUnwrap(
            ProgressCalculator.interval(for: .week, now: try instant(2026, 3, 29, 12, calendar: sundayFirst), calendar: sundayFirst)
        )
        XCTAssertEqual(sundayFirstWeek.start, try instant(2026, 3, 29, calendar: sundayFirst))
        XCTAssertEqual(sundayFirstWeek.end, try instant(2026, 4, 5, calendar: sundayFirst))
        XCTAssertEqual(
            ProgressCalculator.progress(for: .week, now: try instant(2026, 3, 29, 12, calendar: sundayFirst), calendar: sundayFirst),
            0.5 / 7, accuracy: 1e-9
        )
        // 同一时刻（2026-03-30 周一 12:00）在两种日历下落在不同的周内位置：
        // 周日起首 = 第 1.5 天，周一为首日 = 第 0.5 天
        XCTAssertEqual(
            ProgressCalculator.progress(for: .week, now: try instant(2026, 3, 30, 12, calendar: sundayFirst), calendar: sundayFirst),
            1.5 / 7, accuracy: 1e-9
        )
        XCTAssertEqual(
            ProgressCalculator.progress(for: .week, now: try instant(2026, 3, 30, 12, calendar: mondayFirst), calendar: mondayFirst),
            0.5 / 7, accuracy: 1e-9
        )
    }

    /// `remaining` 的分档边界（09 §5.3 剩余量）：跨天（≥ 1 天，**向上取整**）、
    /// 跨小时（1 小时 ≤ r < 1 天，整点截断）、最后一分钟（截断且至少 1）、刚过整点（区间起点重新计数）。
    /// 回归测试（2026-09-28）：小时档必须**成对**取值。
    ///
    /// 修复前的显示是「剩 13 小时 826 分钟」——`remaining()` 给整点小时、另一个函数给**总分钟**，
    /// 两者口径不一致（826 = 13×60 + 46）。这条用例把"余分钟必须落在 0…59 且与整点小时同源"钉住。
    func testProgressRemainingHoursAndMinutesArePaired() throws {
        let calendar = try fixedGregorian()

        // 10:14 → 当天 24:00 剩 13 小时 46 分（修复前分钟位会显示 826）
        let pair = ProgressCalculator.remainingHoursAndMinutes(
            for: .day, now: try instant(2026, 9, 28, 10, 14, calendar: calendar), calendar: calendar
        )
        XCTAssertEqual(pair.hours, 13)
        XCTAssertEqual(pair.minutes, 46)

        // 余分钟永不越界：全天逐刻扫一遍，分钟位必须恒在 0…59
        for minute in stride(from: 0, to: 24 * 60, by: 7) {
            let now = try instant(2026, 9, 28, minute / 60, minute % 60, calendar: calendar)
            let p = ProgressCalculator.remainingHoursAndMinutes(for: .day, now: now, calendar: calendar)
            XCTAssertTrue((0...59).contains(p.minutes), "分钟位越界：\(p)")
            XCTAssertEqual(p.hours * 60 + p.minutes, 24 * 60 - minute, "小时/分钟不同源：\(p)")
        }
    }

    func testProgressRemainingBoundaries() throws {
        let calendar = try fixedGregorian()

        // 跨天：年尺度剩 95 整日；同一天的正午「余量算一天」仍是 95（向上取整）
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 9, 28, calendar: calendar), calendar: calendar).value,
            95
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 9, 28, 12, calendar: calendar), calendar: calendar).value,
            95
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 9, 28, calendar: calendar), calendar: calendar).unit,
            .day
        )
        // 刚过整点：区间起点（元旦 00:00）剩满一年 365 天；日尺度 00:00 剩满 24 小时 = 1 天
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 1, 1, calendar: calendar), calendar: calendar).value,
            365
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, calendar: calendar), calendar: calendar).value,
            1
        )
        // 刚过整点 + 30 秒：不足 1 整日 → 落到小时档（23 小时 59 分）
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 0, 0, 30, calendar: calendar), calendar: calendar).value,
            23
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 0, 0, 30, calendar: calendar), calendar: calendar).unit,
            .hour
        )

        // 跨小时：2 小时 / 1 小时 30 分都落小时档（整点截断，分钟余量由视图从同一区间拼）
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 22, calendar: calendar), calendar: calendar).value,
            2
        )
        let hourAndHalf = ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 22, 30, calendar: calendar), calendar: calendar)
        XCTAssertEqual(hourAndHalf.value, 1)
        XCTAssertEqual(hourAndHalf.unit, .hour)
        // 恰好 1 小时：整点边界仍算小时档
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 23, calendar: calendar), calendar: calendar).unit,
            .hour
        )
        // 月末最后半天 / 周日的最后半天：同一条规则（12 小时、18 小时）
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .month, now: try instant(2026, 9, 30, 12, calendar: calendar), calendar: calendar).value,
            12
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .week, now: try instant(2026, 3, 29, 12, calendar: calendar), calendar: calendar).value,
            12
        )

        // 最后一分钟：不足 1 分钟时截断为 0，**至少给 1**；59 分 30 秒仍是 59（不越到小时档）
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 23, 59, 30, calendar: calendar), calendar: calendar).value,
            1
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 23, 59, 30, calendar: calendar), calendar: calendar).unit,
            .minute
        )
        let almostAnHour = ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 23, 0, 30, calendar: calendar), calendar: calendar)
        XCTAssertEqual(almostAnHour.value, 59)
        XCTAssertEqual(almostAnHour.unit, .minute)

        // 年末最后一天：00:00 剩 1 整天（天档），正午只剩 12 小时（小时档）——分档按剩余量而非日期
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 12, 31, calendar: calendar), calendar: calendar).unit,
            .day
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 12, 31, 12, calendar: calendar), calendar: calendar).unit,
            .hour
        )
    }

    /// `visibleScopes` 解析（纯函数）：缺省 / 非 list / 空 / 全非法 → **今天 + 本周 + 本月**；
    /// 非法值逐项忽略；顺序按输入；重复项去重。manifest 的默认值本身也是这三档。
    ///
    /// **两条入口**（docs/29 §做法 机制二 / D-05）：`ConfigValue?`（manifest 的默认值）与
    /// `[String]`（`ConfigHandle.get("visibleScopes", as: [String].self)` 的往返类型，模块侧走它）。
    /// 第二条是本批新增的重载，判定本体在它里面、第一条只做「拆出 `.strings`」——因此这里把
    /// 两条入口逐档对一遍（任何一条漂回「日 + 年」都会红）。
    func testProgressVisibleScopesResolution() {
        XCTAssertEqual(ProgressCalculator.defaultVisibleScopes, [.day, .week, .month], "出厂三档（D-04）")
        XCTAssertEqual(ProgressCalculator.resolveScopes(from: nil), [.day, .week, .month], "缺省 → 三档")
        XCTAssertEqual(ProgressCalculator.resolveScopes(from: .string("day")), [.day, .week, .month], "不是 list → 回落默认")
        XCTAssertEqual(ProgressCalculator.resolveScopes(from: .strings([])), [.day, .week, .month], "空列表 → 回落默认")
        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: .strings(["bogus", "Week"])),
            [.day, .week, .month],
            "全非法（含大小写不符的取值）→ 回落默认"
        )

        XCTAssertEqual(ProgressCalculator.resolveScopes(from: .strings(["year", "month"])), [.year, .month], "顺序按输入")
        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: .strings(["day", "bogus", "year"])),
            [.day, .year],
            "非法值逐项忽略，剩下的按输入顺序"
        )
        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: .strings(["week", "week", "day"])),
            [.week, .day],
            "重复项去重且保留首次出现的位置"
        )

        // ② `[String]` 重载（`ConfigHandle` 的往返类型）：逐档与上面同口径
        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: []),
            [.day, .week, .month],
            "空表 → 回落默认（`get` 拿不到键时的退化形态）"
        )
        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: ["quarter", "bogus", "quarter"]),
            [.quarter],
            "坏值逐项忽略 + 重复项去重（剩下的唯一一项就是 quarter）"
        )
        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: ["year", "month", "day"]),
            [.year, .month, .day],
            "顺序按输入（用户给的先后即展示先后）"
        )
        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: ["Day", "", "week"]),
            [.week],
            "大小写不符与空串都是坏值：忽略后只剩 week（不回落到默认）"
        )
        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: ["nope"]),
            [.day, .week, .month],
            "全坏值 → 回落默认（不是空表）"
        )
        // 两条入口对同一份输入必须给同一个答案（判定本体只有一处）
        for raw in [["day"], ["year", "month"], ["bogus"], [], ["quarter", "quarter", "week"]] {
            XCTAssertEqual(
                ProgressCalculator.resolveScopes(from: .strings(raw)),
                ProgressCalculator.resolveScopes(from: raw),
                "两条入口同口径（\(raw)）"
            )
        }

        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: ProgressModule.manifest.config?.properties["visibleScopes"]?.default),
            [.day, .week, .month],
            "manifest 的 visibleScopes 默认值即出厂展示尺度"
        )
    }

    /// **渲染行数裁剪**：`listedScopes(_:forWidth:height:)` = 宽度档与高度档**取小者**，
    /// 再按 `visibleScopes` 的声明顺序取前 N 个——docs/29 §验收标准 A3 / A4 与 §已知限制 3 的
    /// 「不缩字、不滚动、按声明顺序截断」。
    func testProgressHomeBlockLayoutListedScopesTrimsByBothTiers() {
        let five: [ProgressCalculator.Scope] = [.day, .week, .month, .quarter, .year]

        // 默认三档：在任何块尺寸下都该三行都在（96 高 / 180 宽起）
        XCTAssertEqual(
            ProgressHomeBlockLayout.listedScopes(ProgressCalculator.defaultVisibleScopes, forWidth: 180, height: 96),
            [.day, .week, .month],
            "默认就是屏上那三行（今天是 今天 / 本周 / 本月）"
        )
        XCTAssertEqual(
            ProgressHomeBlockLayout.listedScopes(ProgressCalculator.defaultVisibleScopes, forWidth: 240, height: 96),
            [.day, .week, .month],
            "宽块不会因为宽度档多画/少画"
        )

        // 五档：96 高的紧凑块放得下全部五个 → 勾满就是五行（不是「勾了第五个没反应」）
        XCTAssertEqual(
            ProgressHomeBlockLayout.listedScopes(five, forWidth: 240, height: 96),
            five,
            "96 高的块里五档全画（5×14 + 4×5 = 90，配内容顶部内缩 5 仍 ≤ 96，D-23）"
        )
        // 高度档更小 → 按声明顺序只画前 N 个
        XCTAssertEqual(
            ProgressHomeBlockLayout.listedScopes(five, forWidth: 240, height: 54),
            [.day, .week, .month],
            "高度档 3 行：勾满五档也只画前三个（A4）"
        )
        XCTAssertEqual(
            ProgressHomeBlockLayout.listedScopes(five, forWidth: 240, height: 34),
            [.day, .week],
            "高度档 2 行：只画前两个"
        )
        XCTAssertEqual(
            ProgressHomeBlockLayout.listedScopes(five, forWidth: 240, height: 0),
            [],
            "块高 0（或被丢掉）→ 一行都不画"
        )
        // 宽度档更小（退化窄块）→ 只画出厂三档
        XCTAssertEqual(
            ProgressHomeBlockLayout.listedScopes(five, forWidth: 179.5, height: 96),
            [.day, .week, .month],
            "退化窄块：宽度档 3 行先截断（与高度档取小者）"
        )
        // 宽度取不到 → 1 行（最保守的那一档）
        XCTAssertEqual(
            ProgressHomeBlockLayout.listedScopes(five, forWidth: .nan, height: 96),
            [.day],
            "宽度取不到 → 1 行"
        )

        // **顺序恒按输入**（模块侧 `resolveScopes` 已按用户勾选先后给出顺序）：
        // 截断取的是**前缀**，不是「前三种尺度」——本季排第二时它该在，今年排第一时它该在最上面
        XCTAssertEqual(
            ProgressHomeBlockLayout.listedScopes([.quarter, .year], forWidth: 240, height: 96),
            [.quarter, .year],
            "声明顺序即展示顺序（不是按 Scope 的原始顺序重排）"
        )
        XCTAssertEqual(
            ProgressHomeBlockLayout.listedScopes([.year, .week, .day], forWidth: 240, height: 54),
            [.year, .week, .day],
            "声明顺序即展示顺序（三行都在）"
        )
        XCTAssertEqual(
            ProgressHomeBlockLayout.listedScopes([.year, .week, .day, .month], forWidth: 240, height: 34),
            [.year, .week],
            "截断取前缀：前两个是今年的在前（顺序按输入）"
        )

        // 空表 / 少于档位：不崩、不补
        XCTAssertEqual(ProgressHomeBlockLayout.listedScopes([], forWidth: 240, height: 96), [])
        XCTAssertEqual(ProgressHomeBlockLayout.listedScopes([.month], forWidth: 240, height: 96), [.month])
    }

    /// **覆盖值优先**（docs/29 §验收标准 A3 的取证项「覆盖值优先 + 坏值回落」）：模块侧 `scopes`
    /// 读的是 `context.config.get("visibleScopes", as: [String].self)`——组件卡写进去的覆盖值压过
    /// manifest 的默认值，坏值 / 空值回落出厂三档。
    ///
    /// 走的是**真句柄**（`ModuleContextFactory.configHandle(for:)` → `ManifestConfigHandle`），
    /// 只是换一个 probe manifest（短名 `probe-scopes`）把域隔开：manifest 的默认值特意写成
    /// `["month"]`（与出厂三档不同）——「覆盖值优先」与「回落 manifest 默认」两档因此各有一个
    /// 可区分的取值（若读取侧还是旧实现「直接读 manifest 默认值」，第一条断言之后的每一条都会红）。
    /// probe 域用完即删，**不碰**开发机真实的 `com.cmeng.gourd.module.progress`。
    func testProgressModuleScopesReadConfigOverrideThroughTheRealHandle() throws {
        let suiteName = "com.cmeng.gourd.module.probe-scopes"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)          // 前置：清掉上次运行留下的覆盖值
        defer { suite.removePersistentDomain(forName: suiteName) }

        let manifest = try ModuleManifest.decode(from: Data(#"""
        {
          "manifestVersion": 1,
          "id": "com.cmeng.gourd.probe-scopes",
          "name": {"key": "module.probe-scopes.name"},
          "icon": {"type": "symbol", "name": "square"},
          "version": "1.0.0",
          "apiVersion": "1.0",
          "kind": "builtin",
          "surfaces": ["home"],
          "config": {
            "type": "object",
            "properties": {
              "visibleScopes": {"type": "list", "itemType": "string", "default": ["month"]}
            }
          }
        }
        """#.utf8))

        let config = ModuleContextFactory.configHandle(for: manifest)
        let context = ModuleContext(
            moduleID: manifest.id,
            host: HostInfo(appVersion: "0", apiVersion: HostInfo.currentAPIVersion, macOSVersion: "15.0"),
            config: config,
            logger: ModuleLogger(moduleID: manifest.id, shortID: manifest.shortID),
            ui: StubUIHandle()
        )
        let module = ProgressModule(context: context)

        // ① 没有覆盖值 → 真句柄回落到 manifest 的默认值（这也就是「组件页没勾过」的形态）
        XCTAssertEqual(module.scopes, [.month], "缺覆盖值 → 回落 manifest 的 visibleScopes 默认值")

        // ② 覆盖值优先：写入一条与默认不同的（含默认里没有的取值）
        XCTAssertTrue(config.set("visibleScopes", to: ["day", "week", "month", "quarter", "year"]))
        XCTAssertEqual(
            module.scopes,
            [.day, .week, .month, .quarter, .year],
            "覆盖值压过 manifest 默认值——这就是「勾满五档」那一档"
        )

        // ③ 覆盖值只有一项：也照它来（不是「并上默认」）
        XCTAssertTrue(config.set("visibleScopes", to: ["quarter"]))
        XCTAssertEqual(module.scopes, [.quarter], "覆盖值就是全部：不并上 manifest 默认的那一项")

        // ④ 坏值 / 空值：**回落出厂三档**（`resolveScopes` 的既有口径，一字不改）——
        //    注意不是回落 manifest 的 ["month"]：判定只认 `defaultVisibleScopes` 这一个兜底
        XCTAssertTrue(config.set("visibleScopes", to: ["bogus", "Month"]))
        XCTAssertEqual(module.scopes, [.day, .week, .month], "覆盖值全坏 → 回落出厂三档")
        XCTAssertTrue(config.set("visibleScopes", to: [String]()))
        XCTAssertEqual(module.scopes, [.day, .week, .month], "空覆盖值 → 回落出厂三档（不留空块）")

        // ⑤ 落盘的字节就是 `[String]`（与模块侧 `get(as: [String].self)` 同一类型：
        //    写成别的类型就是「勾得动、模块读不到」的静默故障）
        XCTAssertTrue(config.set("visibleScopes", to: ["week", "year"]))
        XCTAssertEqual(
            try JSONDecoder().decode([String].self, from: try XCTUnwrap(suite.data(forKey: "visibleScopes"))),
            ["week", "year"],
            "覆盖值按 JSON 字节存（`[String]`）"
        )
    }

    /// 行首图标的符号名必须能被系统符号表解析（否则面板上那一行只剩空白）。
    func testProgressScopeSymbolsResolve() {
        for scope in ProgressCalculator.Scope.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: scope.symbolName, accessibilityDescription: nil),
                "\(scope.rawValue) 的图标 \(scope.symbolName) 不是可解析的 SF Symbol"
            )
        }
    }

    /// `ProgressModule.manifest` 的契约：id / surfaces / icon / defaultEnabled / 六项 config
    /// 的类型、取值与默认值；并回走一次 JSON 路径（与宿主读 descriptor 同一条路）。
    func testProgressModuleManifestMatchesContract() throws {
        let manifest = ProgressModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, "com.cmeng.gourd.progress")
        XCTAssertEqual(manifest.shortID, "progress")
        XCTAssertEqual(manifest.name.key, "module.progress.name")
        XCTAssertEqual(manifest.summary?.key, "module.progress.summary")
        // p7 / T3：显示名换「工作日统计」（值在 catalog；key 不变），图标 chart.pie → briefcase
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "briefcase"))
        XCTAssertEqual(manifest.kind, "builtin")
        // 2026-09-30（p3-widgets / T1，D-01）：纯展示改**首页块**——展开 tab 不再由本模块承担
        XCTAssertEqual(manifest.surfaces, [.home], "只声明首页块（26 §做法 机制一）")
        XCTAssertFalse(manifest.surfaces.contains(.expanded), "展开 tab 已撤销（首页块与 tab 互不蕴含）")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "折叠槽位 2026-09-30 已撤销（那枚 pill 与亮度 HUD 同形）")
        // 2026-09-28 用户判定「时间进度」无行动价值 → 默认关（代码保留，组件页可开回）
        XCTAssertEqual(manifest.defaultEnabled, false, "progress 默认关（13 号文档 D-20）")
        XCTAssertEqual(manifest.defaultPlacement?.order, 30, "order 今天是首页块顺序（13 §已知限制 25 的双语义）")
        XCTAssertNil(manifest.defaultPlacement?.slot, "不声明 compact → slot 记 nil（06 §6.2）")
        XCTAssertTrue(manifest.permissions.isEmpty, "09 §5.3：progress 无权限")

        // 两条取值型钩子：不是接管模块（没有上游总开关，启用在组件页写 moduleEnableOverrides）、
        // 宽度声明 = 26 §做法 机制一 给进度的定值 180 / 240
        XCTAssertNil(ProgressModule.takeoverEnableKey, "进度没有上游键 → 不是接管模块（启用走 moduleEnableOverrides）")
        XCTAssertEqual(
            ProgressModule.homeBlockWidth,
            ModuleHomeBlockWidth(min: 180, ideal: 240),
            "首页块宽度由宿主声明（26 §做法 机制一）"
        )

        let properties = try XCTUnwrap(manifest.config?.properties)
        XCTAssertEqual(properties["visibleScopes"]?.type, "list")
        XCTAssertEqual(properties["visibleScopes"]?.itemType, "string")
        XCTAssertEqual(
            properties["visibleScopes"]?.default,
            ConfigValue.strings(["day", "week", "month"]),
            "docs/29 §做法 机制二 / D-04：出厂显示 今天 + 本周 + 本月"
        )
        XCTAssertEqual(properties["style"]?.type, "enum")
        XCTAssertEqual(properties["style"]?.values, ["ring", "bar", "text"])
        XCTAssertEqual(properties["style"]?.default, ConfigValue.string("ring"))
        XCTAssertEqual(properties["baseCalendar"]?.type, "enum")
        XCTAssertEqual(properties["baseCalendar"]?.values, ["gregorian", "chinese"])
        XCTAssertEqual(properties["baseCalendar"]?.default, ConfigValue.string("gregorian"))

        // p7 / T3 的三键（docs/31 §接口 4 / D-08）：类型、默认值与 `WorkdayCalendar` 的常量同源
        XCTAssertEqual(properties["workStart"]?.type, "integer")
        XCTAssertEqual(properties["workStart"]?.default, ConfigValue.int(9), "默认上班 9 点（= defaultWorkStartHour）")
        XCTAssertEqual(properties["workEnd"]?.type, "integer")
        XCTAssertEqual(properties["workEnd"]?.default, ConfigValue.int(18), "默认下班 18 点（= defaultWorkEndHour）")
        XCTAssertEqual(properties["workdays"]?.type, "list")
        XCTAssertEqual(properties["workdays"]?.itemType, "string")
        XCTAssertEqual(
            properties["workdays"]?.default,
            ConfigValue.strings(["1", "2", "3", "4", "5"]),
            "默认工作日一~五（ISO 编号；= defaultWorkdays）"
        )
        // 默认值直接取模块侧常量，不在 manifest 里写第二份字面量（两处必须同源）
        XCTAssertEqual(WorkdayCalendar.defaultWorkStartHour, 9)
        XCTAssertEqual(WorkdayCalendar.defaultWorkEndHour, 18)
        XCTAssertEqual(WorkdayCalendar.defaultWorkdays, [1, 2, 3, 4, 5])

        // 字面量 manifest 也能走 JSON：编码 → `decode(from:)`（含 validate）→ 相等
        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// 首页块的行数分档（`ProgressHomeBlockLayout`）：**宽度档与高度档取小者**
    /// （docs/29 §做法 机制二 / §已知限制 3、A4）。
    ///
    /// 宽度档：到声明最小宽（180）就够画全部五档（宽度不是行数的真实约束），更窄是退化态、
    /// 非有限数退到 1；高度档：`floor((高 + 行距) / (行高 + 行距))`，钳 `0…5`。
    ///
    /// **96 高的紧凑块要放得下五档 + 内容顶部内缩**（5×14 + 4×5 + 5 = 95，D-23 起行距 6 → 5）——
    /// 这是「勾满五档在屏上是五行都在」的算术前提（D-04 的「三行填满 96」是旧版口径，本批改判，
    /// 见 T2 报告 §候选决策；顶部留白见 `HomeBlockChrome.contentInsetTopText`）。
    func testProgressHomeBlockLayoutRowTiers() {
        // 行高 / 行距 / 条高：三个数一起决定高度档与画出来的东西
        XCTAssertEqual(ProgressHomeBlockLayout.rowHeight, 14, "11pt 文字的自然行高（实测 14pt）")
        XCTAssertEqual(
            ProgressHomeBlockLayout.rowSpacing, 5,
            "取 5 的唯一理由：96 高的块里五行 + 内容顶部内缩放得下（5×14 + 4×5 + 5 = 95，D-23）"
        )
        XCTAssertEqual(ProgressHomeBlockLayout.barHeight, 6, "进度条钉在 6pt（`.linear` 默认 20pt，不钉住行高就不是 14）")
        XCTAssertEqual(
            ProgressHomeBlockLayout.allScopesWidth,
            ProgressModule.homeBlockWidth?.min,
            "宽度档门槛 = 模块声明的最小宽（两处必须是同一个数）"
        )

        // ① 宽度档：声明值域（180 / 240）内一律答「全部五档」——行数交给高度档
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forWidth: 180), 5, "最小块（180）够画五档")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forWidth: 219.5), 5, "旧版分档线 220 不再是上限")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forWidth: 240), 5, "ideal 块（240）同样是五档")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forWidth: 408.5), 5, "再宽也只有五档（尺度总数）")
        // 退化窄块（低于声明最小宽）：只画出厂三档
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forWidth: 179.5), 3, "低于声明最小宽 → 出厂三档")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forWidth: 0), 3, "宽度 0 也是退化态（不是「非有限数」）")
        // 宽度取不到：最保守的一档（与旧版同口径）
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forWidth: .nan), 1, "非有限数（NaN）→ 1 行")
        XCTAssertEqual(
            ProgressHomeBlockLayout.rowLimit(forWidth: .infinity),
            1,
            "非有限数一律不当宽度用（±∞ 同 NaN）"
        )

        // ② 高度档：边界逐个钉（pitch = 14 + 5 = 19；N 行占 19N − 5）
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: 96), 5, "紧凑块（96）放得下五档（95 ≤ 96）")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: 90), 5, "恰好放得下五行（90）→ 仍是五行")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: 89.9), 4, "差一点就是四行（不赌半个字）")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: 74), 4, "四行及以上 → 四行")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: 54), 3, "恰好三行 → 三行（A4 的那一档）")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: 34), 2, "恰好两行 → 两行")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: 14), 1, "恰好一行 → 一行")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: 13.9), 0, "一行都放不下 → 0（不画）")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: 0), 0, "块高 0 → 0")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: -40), 0, "负高度 → 0（不崩、不为负）")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: 152), 5, "大块档（152）也只画五档（上限 = 尺度总数）")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: .nan), 0, "非有限高度 → 0（高度取不到时不画）")
        XCTAssertEqual(ProgressHomeBlockLayout.rowLimit(forHeight: .infinity), 0, "±∞ 同 NaN")

        // ③ 不变量：行高之和永不越界（每个高度上都要成立——块壳 `.clipped()` 会把越界裁成
        //    「半个字」，这正是 T2 的失败信号之一）
        for height in stride(from: 0.0, through: 260.0, by: 0.5) {
            let rows = CGFloat(ProgressHomeBlockLayout.rowLimit(forHeight: height))
            let used = rows * ProgressHomeBlockLayout.rowHeight + max(0, rows - 1) * ProgressHomeBlockLayout.rowSpacing
            XCTAssertLessThanOrEqual(used, height, "块高 \(height) 下画了 \(Int(rows)) 行：内容高 \(used) 越界")
        }
    }

    /// T4/T5 的端到端：`KernelBootstrap.builtinModules` 里的**真模块**经真组合根注册 → 过启用门 →
    /// 激活 → 进 tab 投影 → 内容请求拿到 `.view`。
    ///
    /// 两段：① 走**真启用门**（`defaultEnabled`）——todos 默认开、progress 默认关（D-20）；
    /// ② 手动全放行重注册一次，保住 progress 的内容路径覆盖（它是「两条 surface + lockscreen 降级」
    /// 的样本）。`module.progress.name` / `module.todos.name` 必须能从宿主 bundle 解析出文案
    /// （06 §3.3 R5 的 key 形态）。
    /// （激活失败隔离等机制由假模块覆盖，见 T2 的用例；`register` 本身不校验 manifest，
    /// 所以这里显式对真模块的 manifest 跑一次 `validate()`。）
    ///
    /// **这条用例的 `count == 10` 与逐项 `ObjectIdentifier` 断言是批内契约**（13 号文档已知限制 22）：
    /// 加第十二个内置模块时会红，按该条的口径一并放宽（T4 加 progress 时从 1 放宽到 3、
    /// P2 启动台批次从 3 放宽到 4、P2 接管批次 / T2 从 4 放宽到 5、T4 从 5 放宽到 6、
    /// T5 落 `MusicModule` 时从 6 放宽到 7、P2 快捷指令与前台应用批次 / T2 落 `ShortcutsModule`
    /// 时从 7 放宽到 8、T4 落 `FrontAppModule` 时从 8 放宽到 9，P3 冻结批次 / T6 落 `CalendarModule`
    /// 时从 9 放宽到 10，p3-widgets / T2 落 `StatsModule` 时从 10 放宽到 11，都是这一条）。
    func testKernelBootstrapRegistersBuiltinModulesAndServesExpandedContent() async throws {
        // `bootstrap()` 会落首启默认值：把闸门先置真让它提前返回（用例结束还原原值），
        // 避免改开发机上真实的 `enableScreenAssistant`。
        let defaults = UserDefaults.standard
        let flagKey = Defaults.Keys.gourdFirstLaunchDefaultsApplied.name
        let originalFlag = defaults.object(forKey: flagKey)
        defer {
            if let originalFlag {
                defaults.set(originalFlag, forKey: flagKey)
            } else {
                defaults.removeObject(forKey: flagKey)
            }
        }
        defaults.set(true, forKey: flagKey)

        // 计时器接管（T2）后，本条用例的期望**不再能由开发机偏好决定**：启用门读上游总开关
        // （`enableTimerFeature`）、tab 可见性读显示方式（`timerDisplayMode`）——这两个键读的是
        // **测试域**（Debug 域 `com.cmeng.gourd.dev`，不是 Release 域 `com.cmeng.gourd`）盘上的值：
        // 该域此刻是 `enableTimerFeature = 0`、`timerDisplayMode` **缺键**（缺键走 `Defaults` 默认
        // `.tab`），驱动量是前者——不置夹具的话计时器不过门、不进 tab 投影，「计时器进 tab」必红
        // （`defaults read com.cmeng.gourd.dev <键>` 可复核；Release 域里的 `popover` 与本条无关）。
        // 镜子接管（T4）同理：`showMirror` 也是**测试域**盘上的值（本机曾读到 `0`；上游默认 `false`），
        // 而「进 homeEntries」要求模块 `.active`——不置夹具的话镜子不激活、块名单里没有它，断言必红。
        // 音乐接管（T5）同理：真源是 `showStandardMediaControls`（上游默认 `true`，但本机**测试域缺键**，
        // 缺键走默认 true；缺键的机器与显式写过 false 的机器必须走同一条断言，故同样置定值）。
        // 日历（P3 冻结批次 / T6；**docs/37 D-06 改判为非接管**）：改前真源是 `showCalendar`，
        // 与首页日历行共用一个键；解耦后它走 `moduleEnableOverrides` 缺省 → `defaultEnabled: true`
        // ——**不需要任何夹具键**（p13 / docs/38 D-13 起 `showCalendar` 本人也随月历退出首页删掉了）。
        // 统计接管（p3-widgets / T2）同理：真源是 `enableStatsFeature`（上游默认 `false`，本机测试域
        // 可能是任意值）——同样置定值（true：让它走完整条链，进首页块投影并取到 .view），
        // 让「统计的启用门读上游键」这件事在本条真组合根路径上也有覆盖。
        // 夹具写法与首启闸门键同款：先读持久域现值（nil = 盘上原本没有这个键）→ 置定值 → `defer` 逐字还原
        // （原本有键写回原值、原本没键删键，不把 Defaults 注册域里的默认值写进持久域）。
        let takeoverKeyNames = [
            Defaults.Keys.enableTimerFeature.name,
            Defaults.Keys.timerDisplayMode.name,
            Defaults.Keys.showMirror.name,
            Defaults.Keys.showStandardMediaControls.name,
            Defaults.Keys.enableStatsFeature.name,
        ]
        let domain = Bundle.main.bundleIdentifier
        let originalTakeoverValues = takeoverKeyNames.reduce(into: [String: Any]()) { table, key in
            table[key] = domain.flatMap { defaults.persistentDomain(forName: $0)?[key] }
        }
        defer {
            for key in takeoverKeyNames {
                if let value = originalTakeoverValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            // 注：本条用例的 `bootstrap()` 起的重同步桥（三个接管模块各订阅一个上游键）在用例结束后
            // 仍然挂着——与真实应用一致（桥的生命周期 = 应用生命周期）。后续用例若写这三个键，回调只会
            // 对着当时（多半已清空的）注册表调一次 `setEnabled`：未注册 → 记一条 warning、不写状态；
            // 接管用例自己的 `setUp` 会以空注册表重建订阅表，把它清掉。
        }
        Defaults[.enableTimerFeature] = true
        Defaults[.timerDisplayMode] = .tab
        Defaults[.showMirror] = true
        Defaults[.showStandardMediaControls] = true
        Defaults[.enableStatsFeature] = true

        XCTAssertEqual(
            KernelBootstrap.builtinModules.count,
            9,
            "A3：内置模块清单 = 九行（todos + notifications + launcher + timer + music + shortcuts + frontapp + calendar + stats）——p13 / docs/38 起 progress（工作日统计）与 mirror（镜子）退场（读数搬进今天带 / 改由顶栏浮动预览），文件与用例仍在、只是不再注册"
        )
        XCTAssertEqual(
            KernelBootstrap.builtinModules.map { ObjectIdentifier($0) },
            [
                ObjectIdentifier(TodosModule.self),
                ObjectIdentifier(NotificationsModule.self),
                ObjectIdentifier(LauncherModule.self),
                ObjectIdentifier(TimerModule.self),
                ObjectIdentifier(MusicModule.self),
                ObjectIdentifier(ShortcutsModule.self),
                ObjectIdentifier(FrontAppModule.self),
                ObjectIdentifier(CalendarModule.self),
                ObjectIdentifier(StatsModule.self),
            ],
            "builtinModules 里应是 TodosModule、NotificationsModule、LauncherModule、TimerModule、MusicModule、ShortcutsModule、FrontAppModule、CalendarModule 与 StatsModule（p13 起没有 ProgressModule / MirrorModule）"
        )
        for type in KernelBootstrap.builtinModules {
            XCTAssertNoThrow(try type.manifest.validate(), "真模块的 manifest 必须过校验")
        }

        await KernelBootstrap.bootstrap()

        let registry = ModuleRegistry.shared
        let id = "com.cmeng.gourd.progress"
        let todosID = "com.cmeng.gourd.todos"
        let notificationsID = "com.cmeng.gourd.notifications"
        let launcherID = "com.cmeng.gourd.launcher"
        let shortcutsID = ShortcutsModule.moduleID
        let frontAppID = FrontAppModule.moduleID
        let timerID = TimerModule.moduleID
        let mirrorID = MirrorModule.moduleID
        let musicID = MusicModule.moduleID
        let calendarID = CalendarModule.moduleID
        let statsID = StatsModule.moduleID

        // ① 真启用门：非接管模块逐字取 `defaultEnabled`（todos 与 notifications 默认开、
        // progress 与 launcher 默认关，D-20 / T-12）；**接管模块取上游键**——
        // 计时器的真源是 `enableTimerFeature`、镜子的真源是 `showMirror`、音乐的真源是
        // `showStandardMediaControls`（三个夹具都置 true），因此它们过门、进各自的投影。
        XCTAssertEqual(registry.states[todosID], .active)
        XCTAssertEqual(registry.states[notificationsID], .active)
        XCTAssertEqual(registry.states[launcherID], .disabled, "launcher 默认关（docs/14 T-12 / D-04）")
        XCTAssertNil(registry.instance(for: launcherID), "默认关的模块不实例化，也不占任何 surface")
        XCTAssertEqual(registry.states[shortcutsID], .disabled, "快捷指令默认关（docs/22 D-06：新增模块一律默认关）")
        XCTAssertNil(registry.instance(for: shortcutsID), "默认关的模块不实例化，也不占任何 surface")
        XCTAssertEqual(registry.states[frontAppID], .disabled, "前台应用默认关（docs/22 D-06：新增模块一律默认关）")
        XCTAssertNil(registry.instance(for: frontAppID), "默认关的模块不实例化，也不占任何 surface")
        XCTAssertEqual(registry.states[timerID], .active, "接管模块的启用门读上游键（夹具 true），不看 defaultEnabled")
        XCTAssertNotNil(registry.instance(for: timerID) as? TimerModule, "过门的计时器照常实例化")
        XCTAssertEqual(
            registry.states[musicID],
            .active,
            "音乐的真源是 `showStandardMediaControls`（夹具 true）——不看 `defaultEnabled` 的登记值"
        )
        XCTAssertNotNil(registry.instance(for: musicID) as? MusicModule, "过门的音乐照常实例化")
        XCTAssertEqual(
            registry.states[calendarID],
            .active,
            "日历自 docs/37 D-06 起**非接管**（面板日历页与首页日历行解耦）：启用门走 `moduleEnableOverrides` 缺省 → `defaultEnabled: true`"
        )
        XCTAssertNotNil(registry.instance(for: calendarID) as? CalendarModule, "过门的日历照常实例化")
        XCTAssertEqual(registry.states[statsID], .active, "统计的真源是 `enableStatsFeature`（夹具 true）——不看 `defaultEnabled` 的登记值")
        XCTAssertNotNil(registry.instance(for: statsID) as? StatsModule, "过门的统计照常实例化")
        XCTAssertNotNil(registry.instance(for: todosID) as? TodosModule)
        XCTAssertNotNil(registry.instance(for: notificationsID) as? NotificationsModule)

        // 投影里只剩已激活的那几个（未激活的 progress 与 launcher 不进 tab、不进槽位候选），
        // 槽位内容 = todos 的视图；对 progress 的内容请求按 06 §3.2 降级为 `.unavailable`。
        // tab 顺序按 `(order, id)`：todos（20）→ notifications（40）→ 日历与计时器（**都无 placement
        // → `Int.max`**，排在所有给了 order 的模块之后；同 order 按 id 字典序，故 calendar → timer）；
        // **镜子、音乐与统计都不进 tab**（三者都只声明 `.home`，不声明 `expanded`——这一条同时是
        // 「接管不会凭空多出 tab」的判据；统计的 tab 是本批（p3-widgets / T2）从上游删掉的那一条）
        XCTAssertEqual(registry.tabEntries.map(\.id), [todosID, notificationsID, calendarID, timerID])
        XCTAssertFalse(registry.tabEntries.contains { $0.id == musicID }, "音乐只声明 home → 不进 tab 投影")
        XCTAssertFalse(registry.tabEntries.contains { $0.id == statsID }, "统计只声明 home → 不进 tab 投影（上游那条 Stats 分支已删）")
        // 快捷指令默认关（docs/22 D-06）：**不进任何投影**——这条是"新增模块默认关"的判据，
        // 与下面「全部放行」那一段的 `tabEntries` 期望互为反面。
        XCTAssertFalse(
            registry.tabEntries.contains { $0.id == shortcutsID },
            "默认关的快捷指令不得进 tab 投影（门不放行）"
        )
        // 前台应用默认关（docs/22 D-06）同样**不进任何投影**——**首页块名单也不加它**：
        // 「默认关」的判据是"门不放行 ⟹ 声明了 home 也一块都不占"（下面对照段是它的反面）。
        XCTAssertFalse(
            registry.homeEntries.contains { $0.id == frontAppID },
            "默认关的前台应用不得进首页块投影（门不放行；它声明了 home，所以这一条不是白捡的）"
        )
        XCTAssertFalse(
            registry.tabEntries.contains { $0.id == frontAppID },
            "前台应用不声明 expanded → 不进 tab 投影"
        )
        XCTAssertEqual(registry.compactEntries.map(\.id), [todosID, notificationsID])
        XCTAssertFalse(registry.compactEntries.contains { $0.id == musicID }, "音乐不声明 compact（D-09：本批不占折叠槽位）")
        XCTAssertFalse(registry.compactEntries.contains { $0.id == statsID }, "统计不声明 compact（D-09：本批不占折叠槽位）")
        // 首页块投影（P2 / T4 起，T1 加通知块、T4 加镜子块、T5 加音乐块；p3-widgets / T2 加统计块）：
        // 声明 `.home` 的已激活模块都进块名单——**音乐（`order` 0）在最前**（= 被它取代的内置音乐块的
        // 默认序号）、镜子（2）其次（同理）、todos（20）在中、notifications（40）在后、统计（50）在最后；
        // 各块的首页请求都拿到 `.view` 或按判据答 `.none`（不是「投影里没有」）。
        // progress 在本段是 disabled（默认关）→ **不进块名单**；它的首页块在下面「全部放行」那一段验。
        // 音乐与镜子的**内容**另有运行期判据（docs/20 §做法 机制一末段 /
        // `MusicModule.isVisible` / `MirrorModule.isVisible`）：摄像头可不可用、此刻有没有播放会话
        // 随机器而变，因此这里按同一个纯函数分档断言，而不是写死 `.view`。
        XCTAssertEqual(
            registry.homeEntries.map(\.id),
            [musicID, todosID, notificationsID, statsID],
            "首页块名单 = 声明 .home 的已激活模块（音乐 order 0 → todos 20 → notifications 40 → 统计 50）——p13 起镜子块退场（顶栏浮动预览）"
        )
        XCTAssertEqual(registry.homeEntries.map(\.order), [0, 20, 40, 50], "块顺序与 tab / 槽位同一比较器")
        let musicEntry = try XCTUnwrap(registry.homeEntries.first { $0.id == musicID }, "音乐应进首页块投影")
        XCTAssertEqual(musicEntry.symbolName, "music.note")
        XCTAssertTrue(
            ["Music", "音乐"].contains(musicEntry.label),
            "块文案应已本地化（module.music.name），实到 \(musicEntry.label)"
        )
        let musicHome = registry.content(for: musicID, request: ModuleRegistry.home)
        if MusicModule.isVisible(
            showStandardMediaControls: Defaults[.showStandardMediaControls],
            autoHideInactive: Defaults[.autoHideInactiveNotchMediaPlayer],
            hasActiveSession: MusicManager.shared.hasActiveSession
        ) {
            guard case .view = musicHome else {
                return XCTFail("判据成立时音乐的首页请求应是 .view（判据：总开关 &&（非「无会话即隐藏」|| 有会话））")
            }
        } else {
            guard case .none = musicHome else {
                return XCTFail("判据不成立时音乐的首页请求应是 .none（不占位），而是 \(musicHome)")
            }
        }
        // p13 / docs/38 D-08：**镜子不再是模块块**（渲染点改为顶栏那枚按钮的浮动预览），
        // 因此它既不在 `homeEntries` 里、也没有首页内容可问。
        XCTAssertNil(registry.manifests[mirrorID], "镜子模块已退场（不再注册）")
        XCTAssertFalse(registry.homeEntries.contains { $0.id == mirrorID }, "首页块名单里不得有镜子")
        guard case .view = registry.content(for: notificationsID, request: ModuleRegistry.home) else {
            return XCTFail("notifications 声明了 home，首页块内容应是 .view")
        }
        // 统计块（p3-widgets / T2）：首页请求 = 迷你条 `.view`；展开请求按「不声明 expanded」答 `.none`
        //（上游那条 Stats tab 分支已删——这条同时钉住「统计不再有面板」）。
        let statsEntry = try XCTUnwrap(registry.homeEntries.first { $0.id == statsID }, "统计应进首页块投影")
        XCTAssertEqual(statsEntry.symbolName, "chart.xyaxis.line")
        XCTAssertTrue(
            ["Stats", "统计"].contains(statsEntry.label),
            "块文案应已本地化（module.stats.name），实到 \(statsEntry.label)"
        )
        guard case .view = registry.content(for: statsID, request: ModuleRegistry.home) else {
            return XCTFail("统计声明了 home，首页请求应是迷你条（.view）")
        }
        guard case .none = registry.content(for: statsID, request: request(.expanded)) else {
            return XCTFail("统计不声明 expanded（D-02：不需要单独面板）→ 展开请求必须答 .none")
        }
        guard case .view = registry.content(for: todosID, request: ModuleRegistry.home) else {
            return XCTFail("todos 声明了 home，首页块内容应是 .view")
        }
        guard case .view = registry.compactSlotContent() else {
            return XCTFail("折叠态中央槽位应拿到 todos 的 .view 内容")
        }
        guard case .view = registry.content(for: todosID, request: request(.expanded)) else {
            return XCTFail("todos 的展开请求应拿到 .view")
        }
        guard case .view = registry.content(for: todosID, request: request(.compact)) else {
            return XCTFail("todos 声明了 compact，应返回 .view")
        }
        guard case .none = registry.content(for: todosID, request: request(.lockscreen)) else {
            return XCTFail("todos 未声明 lockscreen，应返回 .none")
        }
        // 通知上岛：expanded（列表）/ compact（未读数）各一份内容，lockscreen 不占位
        guard case .view = registry.content(for: notificationsID, request: request(.expanded)) else {
            return XCTFail("notifications 的展开请求应拿到 .view")
        }
        guard case .view = registry.content(for: notificationsID, request: request(.compact)) else {
            return XCTFail("notifications 声明了 compact，应返回 .view")
        }
        guard case .none = registry.content(for: notificationsID, request: request(.lockscreen)) else {
            return XCTFail("notifications 未声明 lockscreen，应返回 .none")
        }

        // ② 手动全放行（模拟用户显式开启 launcher 等默认关的模块）后重注册：全部模块都 active
        await registry.deactivateAll()
        registry.register(KernelBootstrap.builtinModules, enabled: { _ in true })
        await registry.bootstrap()

        XCTAssertEqual(registry.states[launcherID], .active, "launcher 声明了 expanded，放行后进 tab 投影")
        XCTAssertEqual(registry.states[shortcutsID], .active, "快捷指令声明了 expanded，放行后进 tab 投影")
        XCTAssertEqual(registry.states[frontAppID], .active, "前台应用声明了 home，放行后进首页块投影")
        XCTAssertNotNil(registry.instance(for: frontAppID) as? FrontAppModule, "过门的前台应用照常实例化")
        XCTAssertEqual(registry.states[statsID], .active, "统计声明了 home，放行后进首页块投影")

        // tab 候选按 `order` 升序：todos（20）→ notifications（40）→
        // 日历、launcher、快捷指令与计时器（**都无 placement → `Int.max`**，排在所有给了 order 的
        // 模块之后；同 order 按 id 字典序，故 calendar → launcher → shortcuts → timer）。
        XCTAssertEqual(
            registry.tabEntries.map(\.id),
            [todosID, notificationsID, calendarID, launcherID, shortcutsID, timerID]
        )
        let launcherEntry = try XCTUnwrap(registry.tabEntries.first { $0.id == launcherID }, "launcher 应进展开面板的 tab 投影")
        XCTAssertEqual(launcherEntry.symbolName, "square.grid.2x2")
        XCTAssertTrue(
            ["Launcher", "启动台"].contains(launcherEntry.label),
            "tab 文案应已本地化（module.launcher.name），实到 \(launcherEntry.label)"
        )
        let shortcutsEntry = try XCTUnwrap(
            registry.tabEntries.first { $0.id == shortcutsID },
            "快捷指令应进展开面板的 tab 投影（无 placement → `Int.max` 段内按 id 字典序排在 launcher 之后）"
        )
        XCTAssertEqual(shortcutsEntry.symbolName, "bolt.square")
        XCTAssertTrue(
            ["Shortcuts", "快捷指令"].contains(shortcutsEntry.label),
            "tab 文案应已本地化（module.shortcuts.name），实到 \(shortcutsEntry.label)"
        )
        guard case .view = registry.content(for: shortcutsID, request: request(.expanded)) else {
            return XCTFail("快捷指令声明了 expanded，展开请求应拿到 .view")
        }
        for surface in [Surface.compact, .lockscreen, .home] {
            guard case .none = registry.content(for: shortcutsID, request: request(surface)) else {
                return XCTFail("快捷指令未声明 \(surface.rawValue) → 必须答 .none（不占位）")
            }
        }
        XCTAssertFalse(
            registry.compactEntries.contains { $0.id == shortcutsID },
            "快捷指令不声明 compact → 不得进折叠槽位候选"
        )
        XCTAssertFalse(
            registry.homeEntries.contains { $0.id == shortcutsID },
            "快捷指令不声明 home → 首页块名单里不得出现它"
        )
        // 前台应用是**反向的那一档**（只声明 `home`，docs/22 机制四）：全部放行下它**必须**在首页块
        // 名单里，且按 `order 30` 落在 todos（20）之后；而 tab 条与折叠槽位里都不该出现它
        //（不声明 `expanded` / `compact`）——`order` 只对声明了 `expanded` 的模块是 tab 顺序，
        // 所以"给了 order 却不进 tab"是预期行为，不是漏接线。进度（p3-widgets / T1）现在与它同档。
        let frontAppEntry = try XCTUnwrap(
            registry.homeEntries.first { $0.id == frontAppID },
            "前台应用声明了 home 且已放行 → 首页块名单里必须有它（order 30）"
        )
        XCTAssertEqual(frontAppEntry.symbolName, "app.badge")
        XCTAssertTrue(
            ["Front App", "前台应用"].contains(frontAppEntry.label),
            "块文案应已本地化（module.frontapp.name），实到 \(frontAppEntry.label)"
        )
        XCTAssertEqual(
            registry.homeEntries.map(\.id),
            [musicID, todosID, frontAppID, notificationsID, statsID],
            "全部放行下的首页块名单：音乐（0）→ todos（20）→ 前台应用（30）→ notifications（40）→ 统计（50）"
        )
        XCTAssertEqual(
            registry.homeEntries.map(\.order),
            [0, 20, 30, 40, 50],
            "音乐 0 → todos 20 → 前台应用 30 → notifications 40 → 统计 50（p13 起没有镜子 2 与进度 30）"
        )
        guard case .view = registry.content(for: frontAppID, request: ModuleRegistry.home) else {
            return XCTFail("前台应用声明了 home，首页请求应拿到 .view（当前应用 + 最近切换）")
        }
        for surface in [Surface.expanded, .compact, .lockscreen] {
            guard case .none = registry.content(for: frontAppID, request: request(surface)) else {
                return XCTFail("前台应用未声明 \(surface.rawValue) → 必须答 .none（不占位）")
            }
        }
        XCTAssertFalse(
            registry.tabEntries.contains { $0.id == frontAppID },
            "前台应用不声明 expanded → 即使全部放行也不得进 tab 投影（order 不蕴含 tab）"
        )
        XCTAssertFalse(
            registry.compactEntries.contains { $0.id == frontAppID },
            "前台应用不声明 compact → 不得进折叠槽位候选"
        )
        let timerEntry = try XCTUnwrap(registry.tabEntries.first { $0.id == timerID }, "计时器应进展开面板的 tab 投影")
        XCTAssertEqual(timerEntry.symbolName, "timer")
        XCTAssertTrue(
            ["Timer", "计时器"].contains(timerEntry.label),
            "tab 文案应已本地化（module.timer.name），实到 \(timerEntry.label)"
        )
        guard case .view = registry.content(for: timerID, request: request(.expanded)) else {
            return XCTFail("计时器的展开请求应拿到上游那个 NotchTimerView（.view）")
        }
        // **日历是「只声明 expanded 的孤儿视图接线」那一档**（P3 冻结批次 / T6，docs/24 §做法 机制三）：
        // 展开 tab 存在且文案 / 图标对得上，内容 = 那个孤儿视图（`StandaloneCalendarView`）；
        // 不声明 compact / home / lockscreen（D-09 口径：不占折叠槽位与首页块）。
        let calendarEntry = try XCTUnwrap(
            registry.tabEntries.first { $0.id == calendarID },
            "日历应进展开面板的 tab 投影（声明了 expanded 且模块开着）"
        )
        XCTAssertEqual(calendarEntry.symbolName, "calendar")
        XCTAssertTrue(
            ["Calendar", "日历"].contains(calendarEntry.label),
            "tab 文案应已本地化（module.calendar.name），实到 \(calendarEntry.label)"
        )
        guard case .view = registry.content(for: calendarID, request: request(.expanded)) else {
            return XCTFail("日历的展开请求应拿到那个孤儿视图 StandaloneCalendarView（.view）")
        }
        for surface in [Surface.compact, .lockscreen, .home] {
            guard case .none = registry.content(for: calendarID, request: request(surface)) else {
                return XCTFail("日历未声明 \(surface.rawValue) → 必须答 .none（不占位）")
            }
        }
        XCTAssertFalse(
            registry.compactEntries.contains { $0.id == calendarID },
            "日历不声明 compact → 不得进折叠槽位候选"
        )
        XCTAssertFalse(
            registry.homeEntries.contains { $0.id == calendarID },
            "日历不声明 home → 首页块名单里不得出现它（首页那条全宽日历行仍由上游 NotchHomeView 渲染）"
        )
        // **进度与镜子已退场**（p13 / docs/38 D-06 / D-08）：两条都不再注册，因此在任何投影里
        // 都不该出现——它们的文件与用例仍在（可逆），只是 `builtinModules` 里没有它们。
        XCTAssertNil(registry.manifests[id], "progress 已退场（不再注册）：读数搬进首页今天带")
        // 折叠态中央槽位投影：候选只剩 **order 20 的 todos** 与 order 40 的 notifications
        // ——`compactSlotContent()` 只转发第一个。
        XCTAssertEqual(registry.compactEntries.map(\.id), [todosID, notificationsID])
        XCTAssertEqual(registry.compactEntries.map(\.order), [20, 40])
        guard case .view = registry.compactSlotContent() else {
            return XCTFail("折叠态中央槽位应拿到 todos 的 .view 内容")
        }

        // **launcher 即使被放行也不占折叠态与首页**（P2 启动台批次的核心契约 / docs/19 D-02）：
        // 它只声明 `expanded`，两条投影里都不该出现——"首页与折叠态没有多出东西"就是这一条。
        XCTAssertFalse(
            registry.compactEntries.contains { $0.id == launcherID },
            "launcher 不声明 compact → 不得进折叠槽位候选（否则会与待办抢中央槽位）"
        )
        XCTAssertFalse(
            registry.homeEntries.contains { $0.id == launcherID },
            "launcher 不声明 home → 首页块名单里不得出现它（本批不占首页块）"
        )

        // **计时器同样只声明 `expanded`**（P2 接管批次 / T2，docs/20 D-09：折叠槽位已降级、
        // 计时器不占首页块）——两条投影里都不该出现。
        XCTAssertFalse(
            registry.compactEntries.contains { $0.id == timerID },
            "计时器不声明 compact → 不得进折叠槽位候选（D-09：本批不声明任何 compact）"
        )
        XCTAssertFalse(
            registry.homeEntries.contains { $0.id == timerID },
            "计时器不声明 home → 首页块名单里不得出现它"
        )

        // **音乐是「只声明 home」的那一档**（P2 接管批次 / T5）：全部放行下它**必须**在首页块名单里
        // （门放行 + 声明 home），而 tab 条与折叠槽位里都不该出现它（不声明 `expanded` / `compact`，
        // D-09）——这正是「接管不会让音乐凭空多出一个 tab 或一个折叠槽位」的判据。
        // 同一档今天还有**前台应用**（docs/22 T4，order 30）与**统计**（p3-widgets / T2，order 50）：
        // 这份名单是两段合起来的结论——本段上方逐条钉过它们的位置与内容，这里再按整份名单钉一次
        //（两处同源、互为复核）。**p13 起没有镜子（2）与进度（30）**：两条模块已退场。
        XCTAssertEqual(
            registry.homeEntries.map(\.id),
            [musicID, todosID, frontAppID, notificationsID, statsID],
            "全部放行下的首页块名单：音乐（0）→ todos（20）→ 前台应用（30）→ notifications（40）→ 统计（50）"
        )
        XCTAssertFalse(
            registry.tabEntries.contains { $0.id == musicID },
            "音乐不声明 expanded → 即使全部放行也不得进 tab 投影"
        )
        XCTAssertFalse(
            registry.compactEntries.contains { $0.id == musicID },
            "音乐不声明 compact → 不得进折叠槽位候选"
        )
    }

    /// 折叠态中央槽位的投影：只含 `active` 且声明 `.compact` 的模块（**只有 `expanded` 的不得入选**，
    /// failed / disabled 同样不入选），按 `order` 升序、同 `order` 按 id 字典序；
    /// `compactSlotContent()` 转发候选里的第一个，无候选（未 bootstrap / 未激活）时返回 `.none`。
    func testCompactEntriesProjectionAndSlotContent() async {
        let registry = ModuleRegistry.shared
        // 三个声明 compact 的：order 1 的 compact（只有 compact）、order 1 的 dual（compact + expanded，
        // 同 order 按 id 字典序）、order 40 的 compact-late；加上只有 expanded 的 alpha（不得入选）、
        // 抛错的 beta 与被禁用的 optin（不得入选）
        registerProbes([
            CompactProbeModule.self,
            DualSurfaceProbeModule.self,
            CompactLateProbeModule.self,
            AlphaProbeModule.self,
            BetaProbeModule.self,
            OptInProbeModule.self,
        ])

        // 注册了但尚未 bootstrap：没有 active 的候选 → 槽位内容 `.none`（不占位）
        XCTAssertTrue(registry.compactEntries.isEmpty, "未 bootstrap 时不应有候选")
        guard case .none = registry.compactSlotContent() else {
            return XCTFail("无候选时槽位内容应为 .none")
        }

        await registry.bootstrap()

        XCTAssertEqual(registry.compactEntries.map(\.id), [
            "com.cmeng.gourd.probe-compact",       // order 1，与 dual 同序 → id 字典序在前
            "com.cmeng.gourd.probe-dual",          // order 1
            "com.cmeng.gourd.probe-compact-late",  // order 40
        ])
        XCTAssertEqual(registry.compactEntries.map(\.order), [1, 1, 40])
        // 只有 expanded 的模块（alpha）不得入选；failed（beta）/ disabled（optin）也不得入选
        for id in ["com.cmeng.gourd.probe-alpha", "com.cmeng.gourd.probe-beta", "com.cmeng.gourd.probe-optin"] {
            XCTAssertFalse(registry.compactEntries.contains { $0.id == id }, "\(id) 不应进折叠态槽位候选")
        }

        // 转发**第一个**候选：`compact` / `compact-late` 的内容都是 `.none`（与「无候选」同形），
        // 所以换一组夹具——只注册 dual（compact 请求答一个可辨认的 `.unavailable`）
        await registry.deactivateAll()
        registerProbes([DualSurfaceProbeModule.self, AlphaProbeModule.self])
        await registry.bootstrap()
        XCTAssertEqual(registry.compactEntries.map(\.id), ["com.cmeng.gourd.probe-dual"])
        guard case .unavailable(let reason) = registry.compactSlotContent() else {
            return XCTFail("槽位内容应转发给第一个候选模块")
        }
        XCTAssertTrue(reason.contains("probe-dual"), "转发到的应是 compactEntries 的第一个，实到 \(reason)")
    }

    // MARK: - 工作日统计（p7）

    /// 2026 年表逐日期抽查（国办发明电〔2025〕7号，docs/31 §接口与数据形状 3）：
    /// 放假日**恒休息**（哪怕落在周一至周五）、调休上班日**恒上班**（哪怕落在周六周日）、
    /// 查不到才按 ISO 星期判定（`Calendar.component(.weekday)` 1=周日 与 ISO 1=周一 的换算
    /// 若错一天，下面 9/20（周日）与 10/10（周六）两族的调休断言会立刻红）。
    ///
    /// 期望值只来自「表 + 星期」两条规则，日历自 2026 年真实历推演：10/1 周四、10/8 周四、
    /// 10/10 周六、10/11 周日、2/14 周六、2/23 周一、2/24 周二、5/4 周一、9/20 周日。
    func testWorkdayCalendarMatchesThe2026StateCouncilTable() throws {
        let calendar = try fixedGregorian()
        let workdays = WorkdayCalendar.defaultWorkdays

        func isWorkday(_ year: Int, _ month: Int, _ day: Int) throws -> Bool {
            WorkdayCalendar.isWorkday(
                try instant(year, month, day, 12, calendar: calendar),
                workdays: workdays,
                calendar: calendar
            )
        }

        // 国庆：10/1（周四，放假）休息；10/8（周四）上班；10/10（周六，调休）上班；10/11（周日）休息
        XCTAssertFalse(try isWorkday(2026, 10, 1), "10/1 放假日（周四）→ 休息：星期判定不得盖过表")
        XCTAssertTrue(try isWorkday(2026, 10, 8), "10/8 普通工作日（周四）→ 上班")
        XCTAssertTrue(try isWorkday(2026, 10, 10), "10/10 调休上班（周六）→ 上班：周末不得盖过调休")
        XCTAssertFalse(try isWorkday(2026, 10, 11), "10/11 周末（周日）→ 休息")

        // 春节：2/14（周六，调休）上班；2/23（周一，放假）休息；2/24（周二）上班
        XCTAssertTrue(try isWorkday(2026, 2, 14), "2/14 调休上班（周六）→ 上班")
        XCTAssertFalse(try isWorkday(2026, 2, 23), "2/23 春节放假日（周一）→ 休息：星期判定不得盖过表")
        XCTAssertTrue(try isWorkday(2026, 2, 24), "2/24 普通工作日（周二）→ 上班")

        // 劳动节 5/4（周一，放假）休息；中秋调休 9/20（周日）上班
        XCTAssertFalse(try isWorkday(2026, 5, 4), "5/4 劳动节放假日（周一）→ 休息")
        XCTAssertTrue(try isWorkday(2026, 9, 20), "9/20 中秋调休上班（周日）→ 上班")

        // 表外年份（2027 无表）：退化纯星期且不崩——2027-01-04 是周一 → 上班
        XCTAssertNil(WorkdayCalendar.holidayTables[2027], "2027 没有表（退化口径的前提）")
        XCTAssertTrue(try isWorkday(2027, 1, 4), "表外年份按星期判定（周一 → 上班）")
    }

    /// 今天行四态（`todayState`）与 `todayFraction` 的边界：8:59 上班前（差 1 分钟）/
    /// 9:00 与 12:00 班中（距下班 540 / 360 分）/ 18:00 与 18:01 已下班；休息日恒 `restDay`。
    /// 比例：休息日 = 0、上班前 = 0、正午 = (12−9)/(18−9) = 1/3、下班及以后 = 1。
    ///
    /// 样例日 2026-10-12 是周一（普通工作日，不在 2026 表的两张名单里）；
    /// 2026-10-11 是周日（休息日）。当班 9:00–18:00 = 540 分钟。
    func testWorkdayTodayStateBoundaries() throws {
        let calendar = try fixedGregorian()
        let workdays = WorkdayCalendar.defaultWorkdays

        func state(_ hour: Int, _ minute: Int, day: Int) throws -> WorkdayCalendar.TodayState {
            WorkdayCalendar.todayState(
                now: try instant(2026, 10, day, hour, minute, calendar: calendar),
                workdays: workdays, workStartHour: 9, workEndHour: 18, calendar: calendar
            )
        }
        func fraction(_ hour: Int, _ minute: Int, day: Int) throws -> Double {
            WorkdayCalendar.todayFraction(
                now: try instant(2026, 10, day, hour, minute, calendar: calendar),
                workdays: workdays, workStartHour: 9, workEndHour: 18, calendar: calendar
            )
        }

        // 10/12（周一，工作日）
        XCTAssertEqual(try state(8, 59, day: 12), .beforeStart(minutes: 1), "8:59 → 距上班 1 分钟")
        XCTAssertEqual(try state(9, 0, day: 12), .working(minutesToEnd: 540), "9:00 → 上班，距下班 540 分")
        XCTAssertEqual(try state(12, 0, day: 12), .working(minutesToEnd: 360), "12:00 → 距下班 360 分")
        XCTAssertEqual(try state(18, 0, day: 12), .afterEnd, "18:00 → 恰在下班点，已下班")
        XCTAssertEqual(try state(18, 1, day: 12), .afterEnd, "18:01 → 已下班")

        // 10/11（周日）：休息日
        XCTAssertEqual(try state(12, 0, day: 11), .restDay)
        XCTAssertEqual(try fraction(12, 0, day: 11), 0, accuracy: 1e-9, "休息日 → 比例 0")

        // todayFraction：上班前 0、班内按整分钟推进（正午 180/540 = 1/3）、下班及以后 1
        XCTAssertEqual(try fraction(8, 59, day: 12), 0, accuracy: 1e-9, "上班前 → 0")
        XCTAssertEqual(try fraction(9, 0, day: 12), 0, accuracy: 1e-9, "恰在上班点 → 0（尚未开始）")
        XCTAssertEqual(try fraction(12, 0, day: 12), 1.0 / 3, accuracy: 1e-9, "正午 = 3 小时 / 9 小时")
        XCTAssertEqual(try fraction(18, 0, day: 12), 1, accuracy: 1e-9, "下班点 → 1")
        XCTAssertEqual(try fraction(18, 1, day: 12), 1, accuracy: 1e-9, "下班以后 → 1")
    }

    /// `spanStats` 的手算值（docs/31 §验收标准 A3）：2026-10-12 12:00（周一，普通工作日）。
    ///
    /// **手算过程**（10 月表 + 星期）：10 月区间 [10/1, 11/1) 的 18 个工作日 =
    /// 10/8、10/9、10/10（调休）＋ 10/12–10/16 ＋ 10/19–10/23 ＋ 10/26–10/30
    /// （10/1–10/7 全部放假日；10/11、10/17、10/18、10/24、10/25、10/31 周末）。
    /// - 月：今天之前 = 8、9、10 号共 3 个；今天按工作时长比例 180/540 = 1/3；
    ///   progress = (3 + 1/3) / 18 = 5/27；今天之后 = 4 + 5 + 5 = 14。
    /// - 周（周一为首日 = [10/12, 10/19)）：工作日 = 10/12–10/16 共 5 个；今天之前 0；
    ///   progress = (1/3) / 5 = 1/15；今天之后 = 4。
    func testWorkdaySpanStatsCountCompletedAndRemaining() throws {
        let calendar = try fixedGregorian()   // firstWeekday = 2（周一为首日）
        let workdays = WorkdayCalendar.defaultWorkdays
        let noon = try instant(2026, 10, 12, 12, calendar: calendar)

        let month = WorkdayCalendar.spanStats(
            scope: .month, now: noon, workdays: workdays,
            workStartHour: 9, workEndHour: 18, calendar: calendar
        )
        XCTAssertEqual(month.progress, (3 + 1.0 / 3) / 18, accuracy: 1e-9, "月 = (3 + 1/3)/18 = 5/27")
        XCTAssertEqual(month.remainingWorkdays, 14, "10/13–10/16、10/19–10/23、10/26–10/30")

        let week = WorkdayCalendar.spanStats(
            scope: .week, now: noon, workdays: workdays,
            workStartHour: 9, workEndHour: 18, calendar: calendar
        )
        XCTAssertEqual(week.progress, (1.0 / 3) / 5, accuracy: 1e-9, "周 = (1/3)/5 = 1/15")
        XCTAssertEqual(week.remainingWorkdays, 4, "今天之后 10/13–10/16 四天")

        // 今天非工作日（10/11 周日）的月统计：分子只剩「今天之前」的 3 个（8、9、10 号），
        // 今天不折算任何比例；remaining 从 10/12 起算 = 5 + 5 + 5 = 15
        let restDayMonth = WorkdayCalendar.spanStats(
            scope: .month, now: try instant(2026, 10, 11, 12, calendar: calendar), workdays: workdays,
            workStartHour: 9, workEndHour: 18, calendar: calendar
        )
        XCTAssertEqual(restDayMonth.progress, 3.0 / 18, accuracy: 1e-9, "今天休息 → 分子 = 3 个整天")
        XCTAssertEqual(restDayMonth.remainingWorkdays, 15)

        // **区间内一个工作日都没有**：2026-02-18（周三）所在周 [2/16, 2/23) —— 2/15–2/23 九天
        // 全部放假日，整周 0 个工作日 → progress 0（不除零、不 NaN）、remaining 0
        let holidayWeek = WorkdayCalendar.spanStats(
            scope: .week, now: try instant(2026, 2, 18, 12, calendar: calendar), workdays: workdays,
            workStartHour: 9, workEndHour: 18, calendar: calendar
        )
        XCTAssertEqual(holidayWeek.progress, 0, accuracy: 1e-9, "0 个工作日 → 0（不是 NaN）")
        XCTAssertEqual(holidayWeek.remainingWorkdays, 0)
    }

    /// 坏配置回落（docs/31 §接口 3 的 `resolveWorkdays` / `resolveWorkHours` 口径）：
    /// 空表 / 全坏值 → 默认工作日一~五；workdays 坏值逐项忽略；上下班小时**任一项越界即整体
    /// 回落 (9, 18)、不夹取**（2026-10-01 T2 审查裁定），两值都在区间内但 `end ≤ start` 同样回落。
    func testWorkdayResolveFallsBackOnInvalidConfig() throws {
        let calendar = try fixedGregorian()

        // workdays：空 / 全坏（非整数、空串、越界 0 与 8、小数）→ 默认一~五；坏值逐项忽略
        XCTAssertEqual(WorkdayCalendar.defaultWorkdays, [1, 2, 3, 4, 5])
        XCTAssertEqual(WorkdayCalendar.resolveWorkdays(from: []), [1, 2, 3, 4, 5], "空表 → 默认")
        XCTAssertEqual(
            WorkdayCalendar.resolveWorkdays(from: ["bogus", "", "0", "8", "1.5"]),
            [1, 2, 3, 4, 5],
            "全坏值 → 默认（0 / 8 越界，1.5 不是整数）"
        )
        XCTAssertEqual(WorkdayCalendar.resolveWorkdays(from: ["6", "7"]), [6, 7], "合法子集原样（周末班）")
        XCTAssertEqual(WorkdayCalendar.resolveWorkdays(from: ["1", "bogus", "5", "5"]), [1, 5], "坏值逐项忽略、重复合并")

        // workHourRange：0...23 的单一来源（T3 的整数滑块与读侧越界回落共用这一个常量；读侧不夹取）
        XCTAssertEqual(WorkdayCalendar.workHourRange, 0...23)

        // workStart 30（越界）→ 整体回落默认（不夹到 23）
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 30, end: nil).start, 9)
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 30, end: nil).end, 18)
        // workEnd 0（早于默认上班 9）→ 默认
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: nil, end: 0).start, 9)
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: nil, end: 0).end, 18)
        // end ≤ start（18 → 9 倒挂；12 = 12 相等）→ 默认
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 18, end: 9).start, 9)
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 12, end: 12).end, 18)
        // nil / nil → 默认；区间内的合法值原样
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: nil, end: nil).start, 9)
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: nil, end: nil).end, 18)
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 8, end: 17).start, 8)
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 8, end: 17).end, 17)
        // 端点 0 与 23 是**有效**配置（0–23 班、0–5 班）：只在越界时回落，边界值不回落也不夹取
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 0, end: 23).start, 0, "0 是区间内有效值")
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 0, end: 23).end, 23, "23 是区间内有效值")
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 0, end: 5).end, 5)
        // 越界值**一律**整体回落默认（不夹到端点）：−5 / 24 / 99 三档
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: -5, end: nil).start, 9, "−5 越界 → 9")
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: -5, end: nil).end, 18, "−5 越界 → 18（同一份配置整体回落）")
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 22, end: 24).start, 9, "24 越界 → 整体回落（不夹到 23）")
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 22, end: 24).end, 18)
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 9, end: 99).end, 18, "99 越界 → 整体回落")
        XCTAssertEqual(WorkdayCalendar.resolveWorkHours(start: 9, end: 99).start, 9)

        // 读侧归一：判定入口对坏配置也回落默认——9–18 的班，10/12 正午 → 距下班 360 分
        XCTAssertEqual(
            WorkdayCalendar.todayState(
                now: try instant(2026, 10, 12, 12, calendar: calendar),
                workdays: WorkdayCalendar.defaultWorkdays,
                workStartHour: 30, workEndHour: 0, calendar: calendar
            ),
            .working(minutesToEnd: 360),
            "坏配置在 todayState 里也回落 (9, 18)"
        )
    }

    /// 首页块行动文案（`WorkdayRowText`，p7 / T3，docs/31 §接口与数据形状 4 / D-09）：
    /// **四态矩阵 + 「剩 N 天」的 0 与正数两档 + `compactDuration` 边界**。
    ///
    /// 语言无关（本用例钉的是**结构**与**数字格式**，不钉具体译文）：四态 → 文案 key 的映射由
    /// `todayKey` 逐条断言（最终字符串只再经一次 catalog 查表）；`compactDuration` 是纯数字格式；
    /// `leftDays` 与 `todayTrailing` 的最终字符串只断言**实参已就位**（`contains` / 与 key 不同源）。
    /// catalog 的**值**由 `TakeoverEnablementTests` 的解析断言与跨 catalog 一致性兜底。
    func testWorkdayRowTrailingTextMatrix() throws {
        // ① compactDuration 边界：整点不带 0m（`3h`）、不足小时只给分（`45m`）、0 与负数 → `0m`
        XCTAssertEqual(WorkdayRowText.compactDuration(minutes: 0), "0m", "0 分钟 → 0m（T2 报告的备忘）")
        XCTAssertEqual(WorkdayRowText.compactDuration(minutes: -5), "0m", "负数按 0 处理（不上负号）")
        XCTAssertEqual(WorkdayRowText.compactDuration(minutes: 1), "1m")
        XCTAssertEqual(WorkdayRowText.compactDuration(minutes: 45), "45m")
        XCTAssertEqual(WorkdayRowText.compactDuration(minutes: 59), "59m", "不足 60 只给分钟")
        XCTAssertEqual(WorkdayRowText.compactDuration(minutes: 60), "1h", "整点不带 0m")
        XCTAssertEqual(WorkdayRowText.compactDuration(minutes: 61), "1h1m")
        XCTAssertEqual(WorkdayRowText.compactDuration(minutes: 140), "2h20m", "docs/31 的样例：2 小时 20 分")
        XCTAssertEqual(WorkdayRowText.compactDuration(minutes: 180), "3h", "整点 3 小时")
        XCTAssertEqual(WorkdayRowText.compactDuration(minutes: 360), "6h", "9–18 班正午的距下班")
        XCTAssertEqual(WorkdayRowText.compactDuration(minutes: 540), "9h", "整班时长")

        // ② 四态 → （key, 实参）：key 形态逐条钉死（写错 key / 换错分支这里立刻红）
        let rest = WorkdayRowText.todayKey(.restDay)
        XCTAssertEqual(rest.key, "module.progress.workday.rest")
        XCTAssertNil(rest.argument, "休息日没有插值")
        let beforeStart = WorkdayRowText.todayKey(.beforeStart(minutes: 80))
        XCTAssertEqual(beforeStart.key, "module.progress.workday.toStart")
        XCTAssertEqual(beforeStart.argument, "1h20m", "实参必须已过 compactDuration")
        let working = WorkdayRowText.todayKey(.working(minutesToEnd: 140))
        XCTAssertEqual(working.key, "module.progress.workday.toEnd")
        XCTAssertEqual(working.argument, "2h20m")
        let afterEnd = WorkdayRowText.todayKey(.afterEnd)
        XCTAssertEqual(afterEnd.key, "module.progress.workday.clockedOut")
        XCTAssertNil(afterEnd.argument, "已下班没有插值")

        // ③ 最终字符串：插值已就位、且不是 key 原样（catalog 没编进宿主 bundle 时会退化成 key）
        let workingText = WorkdayRowText.todayTrailing(state: .working(minutesToEnd: 140))
        XCTAssertTrue(workingText.contains("2h20m"), "距下班文案里必须有格式化后的时长，实到 \(workingText)")
        XCTAssertNotEqual(workingText, "module.progress.workday.toEnd", "查不到 catalog 时会原样返回 key——这里必须已解析")
        let restText = WorkdayRowText.todayTrailing(state: .restDay)
        XCTAssertNotEqual(restText, "module.progress.workday.rest", "休息日文案必须已解析")
        XCTAssertFalse(restText.contains("%@"), "无插值的形态不得留下格式符，实到 \(restText)")

        // ④ 「剩 N 天」的 0 与正数两档：0 照写（「今天之后没有工作日了」是事实，不隐藏）
        let leftZero = WorkdayRowText.leftDays(0)
        XCTAssertTrue(leftZero.contains("0"), "0 天照写，实到 \(leftZero)")
        XCTAssertNotEqual(leftZero, "module.progress.workday.leftDays", "必须已解析出 catalog 文案")
        let leftDays = WorkdayRowText.leftDays(18)
        XCTAssertTrue(leftDays.contains("18"), "正数档实参已就位，实到 \(leftDays)")
        XCTAssertNotEqual(leftDays, "module.progress.workday.leftDays")
        XCTAssertTrue(WorkdayRowText.leftDays(-3).contains("0"), "负数按 0 处理（同 compactDuration 的容错口径）")

        // ⑤ 现状核对（控制器说明）：2026-10-01 是国庆放假第一天——今天行是「休息日」，
        //    本周（周一起始 [9/28, 10/5)）剩余 = 0，本月剩余 = 18。这三条把「块上真会画什么」
        //    与 `WorkdayCalendar` 的判定对起来（文案与判定之间不再有第二套口径）。
        let calendar = try fixedGregorian()
        let today = try instant(2026, 10, 1, 12, calendar: calendar)
        XCTAssertEqual(
            WorkdayCalendar.todayState(
                now: today, workdays: WorkdayCalendar.defaultWorkdays,
                workStartHour: 9, workEndHour: 18, calendar: calendar
            ),
            .restDay,
            "10/1 是 2026 国庆放假日 → 今天行画「休息日」（不是倒计时）"
        )
        XCTAssertEqual(
            WorkdayRowText.todayTrailing(state: .restDay),
            WorkdayRowText.todayTrailing(state: WorkdayCalendar.todayState(
                now: today, workdays: WorkdayCalendar.defaultWorkdays,
                workStartHour: 9, workEndHour: 18, calendar: calendar
            )),
            "今天行文案由判定直出——休息日不再显示倒计时"
        )
        XCTAssertEqual(
            WorkdayCalendar.spanStats(
                scope: .week, now: today, workdays: WorkdayCalendar.defaultWorkdays,
                workStartHour: 9, workEndHour: 18, calendar: calendar
            ).remainingWorkdays,
            0,
            "国庆周的剩余工作日 = 0"
        )
        XCTAssertEqual(
            WorkdayCalendar.spanStats(
                scope: .month, now: today, workdays: WorkdayCalendar.defaultWorkdays,
                workStartHour: 9, workEndHour: 18, calendar: calendar
            ).remainingWorkdays,
            18,
            "10 月 18 个工作日全在今天之后"
        )
    }

    /// 模块读侧的三个新键（`workdays` / `workStart` / `workEnd`，p7 / T3）：**覆盖值优先、
    /// 取不到回落 manifest 默认**——走**真句柄**（`ModuleContextFactory.configHandle`），
    /// probe 域用完即删，**不碰**开发机真实的 `com.cmeng.gourd.module.progress`。
    ///
    /// 与 `testProgressModuleScopesReadConfigOverrideThroughTheRealHandle` 同款：manifest 是
    /// probe 自己的（键名 / 类型 / 默认值与真 manifest 逐字同形），模块是**真 `ProgressModule`**
    /// ——读侧归一（`resolveWorkdays` / `resolveWorkHours`）因此被端到端钉住。
    func testProgressModuleWorkdayConfigReadsThroughTheRealHandle() throws {
        let suiteName = "com.cmeng.gourd.module.probe-workday"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)          // 前置：清掉上次运行留下的覆盖值
        defer { suite.removePersistentDomain(forName: suiteName) }

        let manifest = try ModuleManifest.decode(from: Data(#"""
        {
          "manifestVersion": 1,
          "id": "com.cmeng.gourd.probe-workday",
          "name": {"key": "module.progress.name"},
          "icon": {"type": "symbol", "name": "briefcase"},
          "version": "1.0.0",
          "apiVersion": "1.0",
          "kind": "builtin",
          "surfaces": ["home"],
          "config": {
            "type": "object",
            "properties": {
              "workStart": {"type": "integer", "default": 9},
              "workEnd": {"type": "integer", "default": 18},
              "workdays": {"type": "list", "itemType": "string", "default": ["1", "2", "3", "4", "5"]}
            }
          }
        }
        """#.utf8))

        let config = ModuleContextFactory.configHandle(for: manifest)
        let context = ModuleContext(
            moduleID: manifest.id,
            host: HostInfo(appVersion: "0", apiVersion: HostInfo.currentAPIVersion, macOSVersion: "15.0"),
            config: config,
            logger: ModuleLogger(moduleID: manifest.id, shortID: manifest.shortID),
            ui: StubUIHandle()
        )
        let module = ProgressModule(context: context)

        // ① 缺覆盖值 → 真句柄回落 manifest 默认（= 出厂档）
        XCTAssertEqual(module.workdays, [1, 2, 3, 4, 5], "缺键 → 一~五")
        XCTAssertEqual(module.workHours.start, 9)
        XCTAssertEqual(module.workHours.end, 18)

        // ② 覆盖值优先（含默认里没有的取值）
        XCTAssertTrue(config.set("workdays", to: ["1", "2", "3", "4", "5", "6"]))
        XCTAssertTrue(config.set("workStart", to: 10))
        XCTAssertTrue(config.set("workEnd", to: 19))
        XCTAssertEqual(module.workdays, [1, 2, 3, 4, 5, 6], "覆盖值压过默认（周六上班）")
        XCTAssertEqual(module.workHours.start, 10)
        XCTAssertEqual(module.workHours.end, 19)
        // 落盘类型是 `[String]` / `Int`（写错类型模块 `get` 就是 nil / 回落，这里钉住 JSON 形态）
        XCTAssertEqual(
            try JSONDecoder().decode([String].self, from: try XCTUnwrap(suite.data(forKey: "workdays"))),
            ["1", "2", "3", "4", "5", "6"]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(Int.self, from: try XCTUnwrap(suite.data(forKey: "workStart"))),
            10
        )

        // ③ 坏值归一在模块读侧也成立：空表 / 全坏值 → 一~五；越界 / 倒挂 → (9, 18)
        XCTAssertTrue(config.set("workdays", to: [String]()))
        XCTAssertEqual(module.workdays, [1, 2, 3, 4, 5], "空表 → 一~五（不留空块）")
        XCTAssertTrue(config.set("workdays", to: ["bogus", "0", "8"]))
        XCTAssertEqual(module.workdays, [1, 2, 3, 4, 5], "全坏值 → 一~五")
        XCTAssertTrue(config.set("workStart", to: 30))
        XCTAssertEqual(module.workHours.start, 9, "越界 → 回落 9（不夹到 23）")
        XCTAssertTrue(config.set("workStart", to: 18))
        XCTAssertTrue(config.set("workEnd", to: 9))
        XCTAssertEqual(module.workHours.end, 18, "倒挂 → 回落 18")
    }

    // MARK: - 瞬时浮层 HUD（D-22）

    /// 覆盖语义：第二条浮层**替换**第一条（不排队、不叠加），`id` 换成新的（到期任务的判据）；
    /// `clearHUD()` 幂等；`deactivateAll()` 也把浮层撤掉（注册表清空后它没有归属）。
    func testPresentHUDOverridesPreviousHUD() async {
        let registry = ModuleRegistry.shared

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 4)
        let firstID = registry.activeHUD?.id
        XCTAssertNotNil(firstID)
        XCTAssertEqual(registry.activeHUD?.moduleID, "com.cmeng.gourd.probe-alpha")

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-beta", view: AnyView(Text("B")), ttl: 4)
        XCTAssertNotEqual(registry.activeHUD?.id, firstID, "第二条浮层必须是新身份（旧到期任务据此让路）")
        XCTAssertEqual(registry.activeHUD?.moduleID, "com.cmeng.gourd.probe-beta", "后到者覆盖先到者")

        registry.clearHUD()
        XCTAssertNil(registry.activeHUD)
        registry.clearHUD()
        XCTAssertNil(registry.activeHUD, "clearHUD 必须幂等")

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 4)
        await registry.deactivateAll()
        XCTAssertNil(registry.activeHUD, "注册表清空时浮层必须一并撤掉")
    }

    /// `ttl` 夹取到 1…15s：给 0.05s（等于没弹）与 600s（等于常驻）都落回区间端点，
    /// `expiresAt` 按夹取后的值算（模块给什么值都不会让浮层常驻）。
    func testPresentHUDClampsTTLToRange() {
        let registry = ModuleRegistry.shared
        XCTAssertEqual(ModuleRegistry.hudTTLRange.lowerBound, 1)
        XCTAssertEqual(ModuleRegistry.hudTTLRange.upperBound, 15)

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 0.05)
        XCTAssertEqual(
            registry.activeHUD?.expiresAt.timeIntervalSinceNow ?? -1,
            ModuleRegistry.hudTTLRange.lowerBound,
            accuracy: 0.5,
            "过短的 ttl 应被抬到下界 1s"
        )

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: -10)
        XCTAssertEqual(
            registry.activeHUD?.expiresAt.timeIntervalSinceNow ?? -1,
            ModuleRegistry.hudTTLRange.lowerBound,
            accuracy: 0.5,
            "负数 ttl 同样夹到下界"
        )

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 600)
        XCTAssertEqual(
            registry.activeHUD?.expiresAt.timeIntervalSinceNow ?? -1,
            ModuleRegistry.hudTTLRange.upperBound,
            accuracy: 0.5,
            "过长的 ttl 应被压到上界 15s"
        )

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 4)
        XCTAssertEqual(registry.activeHUD?.expiresAt.timeIntervalSinceNow ?? -1, 4, accuracy: 0.5, "区间内的 ttl 原样使用")

        registry.clearHUD()
    }

    /// 到期清除**只清自己那一条**：先弹一条短 ttl、立即被长 ttl 的后来者替换，
    /// 旧任务的到期时刻醒来后不得把新浮层清掉（否则「两条通知先后到达」会闪断）。
    func testHUDExpiryDoesNotClearNewerEntry() async throws {
        let registry = ModuleRegistry.shared

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("short")), ttl: 1)
        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-beta", view: AnyView(Text("long")), ttl: 15)
        let newerID = registry.activeHUD?.id

        try await Task.sleep(for: .seconds(1.3))  // 跨过第一条的到期点

        XCTAssertEqual(registry.activeHUD?.id, newerID, "旧浮层的到期任务不得清掉后来者")
        XCTAssertEqual(registry.activeHUD?.moduleID, "com.cmeng.gourd.probe-beta")
        registry.clearHUD()
    }

    /// 没有人接替时，到期**自动清除**（浮层是瞬时的：不需要模块自己收尾）。
    func testHUDExpiresAndClearsItself() async throws {
        let registry = ModuleRegistry.shared

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 1)
        XCTAssertNotNil(registry.activeHUD)

        try await Task.sleep(for: .seconds(1.3))

        XCTAssertNil(registry.activeHUD, "ttl 到点后应自动清除")
    }

    /// `UIHandle.presentTransient` 的实现落点是注册表（同一份浮层状态，不是第二处副本）：
    /// 模块 id 由工厂补上，视图原样送达。
    func testPresentTransientRoutesToRegistry() throws {
        let manifest = RegistryFixture.manifest(shortID: "hud-probe")
        let context = ModuleContextFactory.make(manifest: manifest, redraw: {})

        context.ui.presentTransient(view: AnyView(Text("hi")), ttl: 4)

        XCTAssertEqual(ModuleRegistry.shared.activeHUD?.moduleID, "com.cmeng.gourd.hud-probe")
        XCTAssertNotNil(ModuleRegistry.shared.activeHUD?.view)
        ModuleRegistry.shared.clearHUD()
    }

    /// `dismissHUD(id:)` **只撤匹配 id 的那条**：`id` 是「这一次弹出」的身份，不是模块 id——
    /// 模块点掉自己那条 × 时台前可能已被后来者替换（通知连发 / 别的模块抢先），
    /// 那种情况必须让后来者继续显示。不匹配 = 空操作（幂等）。
    func testDismissHUDOnlyClearsMatchingID() throws {
        let registry = ModuleRegistry.shared

        // 第一条（极短 ttl → 夹到 1s 下界，代表「已经被顶掉的旧身份」）
        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 0.05)
        let staleID = try XCTUnwrap(registry.activeHUD?.id)

        // 第二条把它顶掉（覆盖语义）——台前那次弹出的身份已经换人
        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-beta", view: AnyView(Text("B")), ttl: 15)
        let liveID = try XCTUnwrap(registry.activeHUD?.id)
        XCTAssertNotEqual(staleID, liveID, "覆盖后是新身份")

        // 拿旧身份 / 无关身份去撤：一条都不许动
        registry.dismissHUD(id: staleID)
        XCTAssertEqual(registry.activeHUD?.id, liveID, "旧身份的撤请求不得清掉台前的后来者")
        registry.dismissHUD(id: UUID())
        XCTAssertEqual(registry.activeHUD?.id, liveID, "无关 id 同样是空操作")

        // 拿当前身份去撤：这一条消失；重复撤仍幂等
        registry.dismissHUD(id: liveID)
        XCTAssertNil(registry.activeHUD)
        registry.dismissHUD(id: liveID)
        XCTAssertNil(registry.activeHUD, "dismissHUD 必须幂等")
        registry.dismissHUD(id: UUID())
        XCTAssertNil(registry.activeHUD, "本来就没有浮层时也不崩")
    }

    /// `UIHandle.dismissTransient()`（工厂实现）→ 注册表 `dismissHUD(id:)`，且**先判归属**：
    /// 只撤本模块弹的那一条；台前是别的模块的浮层时什么都不做。
    func testDismissTransientDismissesOwnHUDOnly() throws {
        let registry = ModuleRegistry.shared
        let manifest = RegistryFixture.manifest(shortID: "hud-probe")
        let context = ModuleContextFactory.make(manifest: manifest, redraw: {})

        // 本模块弹的那条：撤得掉
        context.ui.presentTransient(view: AnyView(Text("mine")), ttl: 4)
        XCTAssertEqual(registry.activeHUD?.moduleID, "com.cmeng.gourd.hud-probe")
        context.ui.dismissTransient()
        XCTAssertNil(registry.activeHUD, "本模块的浮层应被主动撤掉")

        // 别的模块弹的那条：撤不动（归属判定，不是「无条件清台前」）
        registry.presentHUD(moduleID: "com.cmeng.gourd.someone-else", view: AnyView(Text("other")), ttl: 4)
        context.ui.dismissTransient()
        XCTAssertEqual(
            registry.activeHUD?.moduleID,
            "com.cmeng.gourd.someone-else",
            "别的模块的浮层不在本模块的处置范围内"
        )
        registry.clearHUD()
    }

    // MARK: - 收起刘海请求（docs/13 D-28）

    /// `UIHandle.requestCollapse()` 的实现落点 = **应用侧注入的闭包**：工厂原样转发，模块一调就算数。
    /// 内核这一层不认识窗口、也不做裁决（「哪块屏、能不能收」由应用侧定），因此这里只钉转发本身。
    func testRequestCollapseForwardsInjectedClosure() throws {
        let manifest = RegistryFixture.manifest(shortID: "collapse-probe")
        let probe = RedrawProbe()
        let context = ModuleContextFactory.make(manifest: manifest, redraw: {}, collapse: { probe.count += 1 })

        XCTAssertEqual(probe.count, 0, "前置：没请求就不该有转发")
        context.ui.requestCollapse()
        XCTAssertEqual(probe.count, 1, "requestCollapse 必须转发到注入的闭包")
        context.ui.requestCollapse()
        XCTAssertEqual(probe.count, 2, "逐次转发、不做去重（合并与裁决都在应用侧）")
    }

    /// 未接线时（`make` 的 `collapse` 默认 `{}`）**不崩、也不静默改变语义**：收起请求是空操作。
    /// 这条是「单测与注释掉一行的启动路径都不必传闭包」的判据。
    func testRequestCollapseWithoutInjectedClosureIsNoOp() throws {
        let context = ModuleContextFactory.make(
            manifest: RegistryFixture.manifest(shortID: "collapse-probe"),
            redraw: {}
        )
        XCTAssertNoThrow(context.ui.requestCollapse())
    }

    /// **透传链**（组合根 → 注册表 → 工厂 → 句柄）：`bootstrap(collapse:)` 注入的闭包必须真的落进
    /// `activate()` 之后那个模块的 `context.ui`——注册表只是转发者，中间任何一环改写闭包都会断链。
    func testBootstrapPassesCollapseClosureIntoModuleContext() async throws {
        let registry = ModuleRegistry.shared
        let probe = RedrawProbe()
        registry.register([StubModule.self], enabled: { _ in true })

        await registry.bootstrap(collapse: { probe.count += 1 })
        let instance = try XCTUnwrap(registry.instance(for: "com.cmeng.gourd.stub") as? StubModule)
        XCTAssertEqual(registry.states["com.cmeng.gourd.stub"], .active, "前置：模块应已激活")

        instance.context.ui.requestCollapse()
        XCTAssertEqual(probe.count, 1, "bootstrap 注入的闭包应直达模块的 UIHandle")
    }

    // MARK: - 浮层期间的悬浮展开抑制

    /// **有浮层 → 抑制**：浮层在台前时，两条抢跑路径（`startHoverClickMonitor` 的 `mouseDown`
    /// 回调、`handleHover` 的延时展开任务）都必须在 `openNotch()` 前被这条判据挡住——
    /// 否则点浮层上 × / 打开 App 的那一下会被 mouseDown 先吃走，面板被打开、浮层被盖掉。
    func testHoverOpenSuppressedWhileHUDIsPresent() {
        let registry = ModuleRegistry.shared
        XCTAssertNil(registry.activeHUD, "前置：setUp 的 deactivateAll 应已清掉浮层")

        registry.presentHUD(moduleID: "com.cmeng.gourd.hud-probe", view: AnyView(Text("HUD")), ttl: 4)
        XCTAssertNotNil(registry.activeHUD)
        XCTAssertTrue(
            shouldSuppressHoverOpen(activeHUD: registry.activeHUD),
            "浮层存活的 ttl 内必须抑制悬浮展开"
        )

        registry.clearHUD()
    }

    /// **无浮层 → 放行**：判据是「当前有没有浮层」而不是「曾经弹过浮层」——
    /// ttl 到期（内核清）或 × 主动撤（`dismissHUD`）后 `activeHUD` 回到 nil，悬浮展开照旧。
    func testHoverOpenAllowedWithoutHUD() {
        XCTAssertNil(ModuleRegistry.shared.activeHUD)
        XCTAssertFalse(
            shouldSuppressHoverOpen(activeHUD: ModuleRegistry.shared.activeHUD),
            "无浮层时必须放行悬浮展开"
        )
        XCTAssertFalse(shouldSuppressHoverOpen(activeHUD: nil), "显式 nil 同样放行（判据形状）")
    }

    // MARK: - 非刘海屏 hide-until-hover

    /// **基础为真**：非刘海屏 + 关闭态 + 设置开启 + 没有上游瞬时提示 → 隐藏（挪出屏幕）。
    /// 这条是 hide-until-hover 的原有语义，改判据不得把它改掉。
    func testHideClosedContentUntilHoverBaseline() {
        XCTAssertTrue(
            shouldHideClosedContentUntilHover(
                hideSetting: true,
                isNonNotch: true,
                isClosed: true,
                hasSneakPeek: false
            ),
            "非刘海屏关闭态且无瞬时提示时必须隐藏"
        )
    }

    /// **上游 sneak 在场 → 不隐藏**：sneakPeek（音量 / 亮度 / 音乐…）是上游既有的豁免项，
    /// 与改造前同口径（音量键按下时非刘海屏必须露出来）。
    func testHideClosedContentUntilHoverRevealedBySneakPeek() {
        XCTAssertFalse(
            shouldHideClosedContentUntilHover(
                hideSetting: true,
                isNonNotch: true,
                isClosed: true,
                hasSneakPeek: true
            ),
            "上游瞬时提示在场时必须强制显示"
        )
    }

    /// **模块浮层不再是豁免项**（2026-09-28，D-23）：浮层改由内核的独立窗口渲染
    ///（`Kernel/ModuleHUDWindow.swift`），不再占用关闭态那一格——判据回到「只认上游 sneakPeek」，
    /// 并且**即使注册表里有浮层也照常隐藏关闭态内容**（两条路径互不干扰：浮层窗口自己会出现在
    /// 鼠标所在屏，关不关关闭态内容都不影响它）。
    /// 判据同时**读真值**（注册表 `activeHUD`）验证接缝：注册表状态不再影响本判据的取值。
    func testHideClosedContentUntilHoverIgnoresModuleHUD() {
        let registry = ModuleRegistry.shared
        XCTAssertNil(registry.activeHUD, "前置：setUp 的 deactivateAll 应已清掉浮层")

        registry.presentHUD(moduleID: "com.cmeng.gourd.hud-probe", view: AnyView(Text("HUD")), ttl: 4)
        defer { registry.clearHUD() }
        XCTAssertNotNil(registry.activeHUD, "前置：浮层确实在台前")

        XCTAssertTrue(
            shouldHideClosedContentUntilHover(
                hideSetting: true,
                isNonNotch: true,
                isClosed: true,
                hasSneakPeek: false
            ),
            "浮层在台前时关闭态内容照常隐藏（浮层走独立窗口，不再需要豁免）"
        )
    }

    // MARK: - 浮层窗口宿主的放置几何（D-23）

    /// **内置屏（有刘海）**：顶部内边取刘海高度（实测 32pt），窗口顶端贴在其下方 `topGap`，
    /// 水平居中于该屏。这条钉住「浮层不再压在刘海底下、下半截被裁」。
    func testHUDWindowPlacementOnNotchedScreen() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let inset = ModuleHUDWindowHost.topInset(
            safeAreaTop: 32,          // 刘海高度优先于菜单栏高度
            frameMaxY: screenFrame.maxY,
            visibleFrameMaxY: screenFrame.maxY - 24
        )
        XCTAssertEqual(inset, 32, "有刘海时必须避让刘海高度")

        let origin = ModuleHUDWindowHost.origin(
            windowSize: CGSize(width: 400, height: 66),
            screenFrame: screenFrame,
            topInset: inset,
            topGap: ModuleHUDWindowHost.topGap
        )
        XCTAssertEqual(origin.y, screenFrame.maxY - 32 - ModuleHUDWindowHost.topGap - 66, "顶端贴齐可用顶边下方")
        XCTAssertEqual(origin.x, screenFrame.midX - 200, "水平居中于该屏")
    }

    /// **外接屏（无刘海）**：顶部内边取菜单栏高度（屏顶与 `visibleFrame` 顶之差，实测 24pt）——
    /// 不避开会被菜单栏盖住上半行。
    func testHUDWindowPlacementOnNonNotchScreen() {
        let screenFrame = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let inset = ModuleHUDWindowHost.topInset(
            safeAreaTop: 0,
            frameMaxY: screenFrame.maxY,
            visibleFrameMaxY: screenFrame.maxY - 25
        )
        XCTAssertEqual(inset, 25, "无刘海时必须避让菜单栏高度")

        let origin = ModuleHUDWindowHost.origin(
            windowSize: CGSize(width: 400, height: 66),
            screenFrame: screenFrame,
            topInset: inset,
            topGap: ModuleHUDWindowHost.topGap
        )
        XCTAssertEqual(origin.y, screenFrame.maxY - 25 - ModuleHUDWindowHost.topGap - 66)
        XCTAssertEqual(origin.x, screenFrame.midX - 200, "居中按该屏而不是主屏")
    }

    /// **菜单栏高度缺失时不产生负内边**（`visibleFrame` 与屏顶一样高的极端值）：内边兜底 0，
    /// 窗口仍然贴顶。（`sanitizedContentSize` / 0×0 兜底那条链在改固定尺寸时已删除——
    /// 固定尺寸永远是有限的正数，不需要消毒；尺寸口径见
    /// `testHUDWindowFixedContentSizeScalesAndClamps`。）
    func testHUDWindowPlacementAndSizeGuards() {
        XCTAssertEqual(
            ModuleHUDWindowHost.topInset(safeAreaTop: 0, frameMaxY: 1000, visibleFrameMaxY: 1000),
            0,
            "量不出菜单栏高度时兜底 0（不能是负数）"
        )
    }

    // MARK: - 浮动镜子的避让几何（p17 / docs/38 D-08）

    /// **浮动镜子的上内缩必须让开顶栏那排图标**（p17 回归）：浮层挂在面板内容之上且可命中测试，
    /// 若它的上沿压在顶栏那排图标（`headerPadding + iconSide` = 8 + 30 = 38）上，鼠标点在镜子按钮的
    /// 位置命中的就是浮层——「开着镜子再点同一枚按钮收起」永远点不动（本 bug；上一轮 AXPress 验收
    /// 不经命中测试，因此漏掉）。第二条断言是钉住本 bug 的那条：上内缩 **≥ 顶栏下沿**；
    /// 第一条钉住默认几何下它就是 46。
    func testMirrorFloatingPreviewTopInsetClearsHeaderIconRow() {
        XCTAssertEqual(
            MirrorFloatingPreview.topInset(),
            46,
            "默认几何：8（顶栏内边距）+ 30（按钮边长）+ 8（缝）= 46"
        )
        XCTAssertGreaterThanOrEqual(
            MirrorFloatingPreview.topInset(),
            8 + 30,
            "上内缩必须 ≥ 顶栏那排图标的下沿（headerPadding + iconSide），否则浮层盖住镜子按钮、点击被吞"
        )
    }

    // MARK: - 浮层的多屏显示（D-25：所有屏同时显示）

    /// **全屏模式**（用户当前设置 `showOnAllDisplays = 1`）：所有屏都该显示浮层——
    /// 这条钉住 2026-09-28 的用户反馈「应该是所有屏幕都显示才对」（旧口径是跟随鼠标屏，
    /// 于是只有一块屏看得见）。
    func testHUDScreensAllDisplaysModeShowsEveryScreen() {
        let names = ["Built-in Retina Display", "VA2478-H-2", "DELL U2720Q"]
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: true,
                screenNames: names,
                mainScreenName: names[0],
                preferredScreenName: names[2]
            ),
            Set(names),
            "全屏模式下三层输入都无关：所有屏都在集合里（鼠标 / 主屏 / 指定屏都不该收窄它）"
        )
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: true,
                screenNames: ["Only One"],
                mainScreenName: "Only One",
                preferredScreenName: nil
            ),
            ["Only One"],
            "单屏机器同样成立"
        )
    }

    /// **单屏模式**（`showOnAllDisplays = false`）：只在该设置指定的那块屏；
    /// 指定屏不在场时退到主屏；主屏也取不到时退到列表第一块（三档兜底，见纯函数文档）。
    func testHUDScreensSingleDisplayModePrefersSettingThenMainThenFirst() {
        let names = ["Built-in Retina Display", "VA2478-H-2"]

        // ① 指定屏在场 → 只它
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: false,
                screenNames: names,
                mainScreenName: names[0],
                preferredScreenName: names[1]
            ),
            [names[1]],
            "单屏模式：只显示在设置指定的那块屏上（与岛同源：preferred_screen_name）"
        )

        // ② 指定屏不在场（拔掉 / 改名 / 尚未写入键）→ 主屏
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: false,
                screenNames: names,
                mainScreenName: names[0],
                preferredScreenName: "已拔掉的外接屏"
            ),
            [names[0]],
            "指定屏不在场时退到主屏（不能让浮层彻底消失）"
        )
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: false,
                screenNames: names,
                mainScreenName: names[0],
                preferredScreenName: nil
            ),
            [names[0]],
            "键没写过（nil）同口径 → 主屏"
        )

        // ③ 连主屏都取不到 → 列表第一块（仍然要有一块屏显示）
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: false,
                screenNames: names,
                mainScreenName: nil,
                preferredScreenName: nil
            ),
            [names[0]],
            "主屏也取不到时退到列表第一块"
        )
    }

    /// **空屏集合兜底**：没有屏可显示 → 空集合（调用方（`present`）据此什么都不做，
    /// 不会去创建 0 个窗口或崩在取下标上）。两种模式都要成立。
    func testHUDScreensEmptyFallbackYieldsNoScreen() {
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: true,
                screenNames: [],
                mainScreenName: "Main",
                preferredScreenName: "Main"
            ),
            [],
            "全屏模式 + 空屏集合 → 空集合"
        )
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: false,
                screenNames: [],
                mainScreenName: nil,
                preferredScreenName: nil
            ),
            [],
            "单屏模式 + 空屏集合 → 空集合（不越界取 screenNames[0]）"
        )
    }

    // MARK: - 浮层窗口的可见性状态机（2026-09-28：「内置屏偶发只显示第一条」）

    /// ① **首次 present**：窗口还不在台上（刚创建时 `alphaValue` 是 1，所以这里是 `alpha = 1` +
    /// `isVisible = false`）→ 必须「先归零 + 摆位 + 上台 + 淡入」，四步一个都不能少。
    func testHUDVisibilityFirstPresentOrdersFrontAndFadesIn() {
        let actions = HUDVisibilityStateMachine.presentActions(isVisible: false, alpha: 1)
        XCTAssertEqual(actions, [.setAlpha(0), .reposition, .orderFront, .fadeIn])
        XCTAssertTrue(actions.contains(.orderFront), "首次 present 必须让窗口上台")
        XCTAssertEqual(actions.last, .fadeIn, "淡入在三步之后（先归零，淡入才看得见）")
    }

    /// ② **淡出中被接手**（坏状态 ①）：窗口还在台上但 alpha 停在 0 / 半透明 →
    /// 必须**直接给 alpha 终态 1**（不赌动画），且不许出现 `orderOut`。
    ///
    /// 这条正是「内置屏偶发看不到」的修复判据：旧实现只剩 `fadeIn` 的 `guard alphaValue < 1`
    /// 一条恢复路径，且 present 因 `isVisible == true` 跳过 `orderFrontRegardless`。
    func testHUDVisibilityPresentRecoversWindowStuckTransparent() {
        let actions = HUDVisibilityStateMachine.presentActions(isVisible: true, alpha: 0)
        XCTAssertEqual(actions, [.setAlpha(1), .reposition])
        XCTAssertFalse(actions.contains(.orderOut), "在台的窗口不许被收起")
        XCTAssertFalse(actions.contains(.fadeIn), "停在 0 的窗口要给终态，不靠动画恢复")

        // 半透明（淡出进行到一半）同样直接补到 1
        XCTAssertEqual(
            HUDVisibilityStateMachine.presentActions(isVisible: true, alpha: 0.4),
            [.setAlpha(1), .reposition]
        )
        // 已经 1：只剩「重新贴顶居中」一条（幂等；不做无意义的 alpha 写入）
        XCTAssertEqual(HUDVisibilityStateMachine.presentActions(isVisible: true, alpha: 1), [.reposition])
    }

    /// ③ **淡出结束、无人接手**：这才是真正该下台的时刻（`orderOut` + 归零，下次上台重新淡入）。
    func testHUDVisibilityDismissCompletionOrdersOutWhenNobodyTookOver() {
        XCTAssertEqual(
            HUDVisibilityStateMachine.dismissCompletionActions(generationMatches: true, hasActiveHUD: false),
            [.orderOut, .setAlpha(0)]
        )
    }

    /// ④ **同尺寸重弹**：尺寸回调的早退只该省掉 `setContentSize`，不该省掉显隐纠正——
    /// 窗口已被收起（`isVisible == false`）时，即使内容尺寸与缓存一模一样，也必须重新露出。
    ///
    /// 状态机因此**不看尺寸**（尺寸是另一条正交的输入）：动作只由「窗口在不在台上 / 透明不透明」
    /// 决定，所以「同尺寸重弹」得到的动作与首次 present 完全一致。
    func testHUDVisibilitySameSizeRePresentStillBringsWindowBack() {
        let first = HUDVisibilityStateMachine.presentActions(isVisible: false, alpha: 1)
        let sameSizeAgain = HUDVisibilityStateMachine.presentActions(isVisible: false, alpha: 0)
        XCTAssertEqual(first, sameSizeAgain, "同尺寸重弹的动作必须与首次一致（不因尺寸相同而空转）")
        XCTAssertTrue(sameSizeAgain.contains(.orderFront), "窗口已被收起时重新露出它")
        XCTAssertTrue(
            HUDVisibilityStateMachine.presentActions(isVisible: true, alpha: 1).contains(.reposition),
            "尺寸没变也要重新贴顶居中（鼠标可能换到了另一块屏）"
        )
    }

    /// ⑤ **有接手时不 orderOut**：新浮层已经在台前 / 已有更新的淡出在途时，
    /// 旧淡出的完成回调不得把窗口收起来、也不得把 alpha 留在 0（否则新浮层跟着一起消失）。
    func testHUDVisibilityDismissCompletionNeverHidesAHandedOverWindow() {
        let takenOver = HUDVisibilityStateMachine.dismissCompletionActions(
            generationMatches: true,
            hasActiveHUD: true
        )
        XCTAssertFalse(takenOver.contains(.orderOut), "新浮层在台前：不许收起窗口")
        XCTAssertFalse(takenOver.contains(.setAlpha(0)), "更不许把 alpha 留在 0（那就是「看不到」）")
        XCTAssertEqual(takenOver, [.setAlpha(1), .reposition], "撤销这次淡出并重新贴顶居中")

        XCTAssertEqual(
            HUDVisibilityStateMachine.dismissCompletionActions(generationMatches: false, hasActiveHUD: false),
            [],
            "代数不匹配 = 早有更新的浮层/淡出接手，旧回调什么都不做"
        )
        XCTAssertEqual(
            HUDVisibilityStateMachine.dismissCompletionActions(generationMatches: false, hasActiveHUD: true),
            [],
            "代数不匹配优先：接手方自己保证可见，旧回调不得插手"
        )
    }

    // MARK: - 待办模块 todos（T5）

    /// 构造一条待办（id 兼作标题，便于按 id 断言顺序）。
    private func todo(
        _ id: String,
        due: Date? = nil,
        completed: Bool = false,
        completedAt: Date? = nil,
        list: String = "提醒"
    ) -> TodoBucketing.Item {
        TodoBucketing.Item(
            id: id,
            title: id,
            dueDate: due,
            isCompleted: completed,
            completionDate: completedAt,
            listName: list
        )
    }

    private func todoIDs(_ result: TodoBucketing.BucketResult) -> [String] { result.items.map(\.id) }

    /// 分类与计数（2026-09-28 用户定稿的口径）：
    /// 今日 = ① 到期在今天 ∪ ② 已过期且未完成 ∪ ③ 今天完成；本周 = 到期落在一周区间内 **∪ 今日**（刻意重叠）；
    /// 所有 = 全集。**无到期时间只进「所有」**（含「无到期时间 + 今天完成」这种两条规则相抵的条目）。
    func testTodoBucketingMembershipAndCounts() throws {
        let calendar = try fixedGregorian()  // Asia/Shanghai，周一为首日
        let now = try instant(2026, 9, 28, 10, calendar: calendar)  // 2026-09-28 是周一

        let summary = TodoBucketing.classify([
            todo("due-today", due: try instant(2026, 9, 28, 9, calendar: calendar)),
            todo(
                "done-today",
                due: try instant(2026, 9, 28, 8, calendar: calendar),
                completed: true,
                completedAt: try instant(2026, 9, 28, 9, 30, calendar: calendar)
            ),
            todo("overdue-open", due: try instant(2026, 9, 25, 9, calendar: calendar)),
            todo(
                "overdue-done-last-week",
                due: try instant(2026, 9, 25, 9, calendar: calendar),
                completed: true,
                completedAt: try instant(2026, 9, 26, 9, calendar: calendar)
            ),
            todo("later-this-week", due: try instant(2026, 10, 1, 9, calendar: calendar)),
            todo("next-month", due: try instant(2026, 10, 20, 9, calendar: calendar)),
            todo("no-due", list: "收集箱"),
            todo(
                "no-due-done-today",
                completed: true,
                completedAt: try instant(2026, 9, 28, 9, calendar: calendar),
                list: "收集箱"
            ),
        ], now: now, calendar: calendar)

        // 今日：未完成在前（到期升序）、已完成排最后 → 逾期 > 今天到期 > 今天完成
        XCTAssertEqual(todoIDs(summary.today), ["overdue-open", "due-today", "done-today"])
        // 本周：今日的三条**重复出现**（刻意重叠），再加本周内到期的 later-this-week
        XCTAssertEqual(todoIDs(summary.week), ["overdue-open", "due-today", "later-this-week", "done-today"])
        XCTAssertEqual(summary.week.total, summary.today.total + 1, "本周 ⊇ 今日：本周是更大窗口，重叠计数是刻意的")
        // 本周之后 / 上周完成的 / 无到期时间的：都不进今日、本周（later-this-week 则只在本周、不在今日）
        for id in ["next-month", "overdue-done-last-week", "no-due", "no-due-done-today"] {
            XCTAssertFalse(todoIDs(summary.week).contains(id), "\(id) 不应在本周")
            XCTAssertFalse(todoIDs(summary.today).contains(id), "\(id) 不应在今日")
        }
        XCTAssertFalse(todoIDs(summary.today).contains("later-this-week"), "本周内但非今天到期的，不进今日")

        // 所有：全集（含无到期时间与下月的）；未完成按到期升序、无到期时间排最后，已完成按完成时刻倒序
        XCTAssertEqual(summary.all.total, 8)
        XCTAssertEqual(todoIDs(summary.all), [
            "overdue-open", "due-today", "later-this-week", "next-month", "no-due",
            "done-today", "no-due-done-today", "overdue-done-last-week",
        ])

        // (已办, 总量) 与环心文案
        XCTAssertEqual(summary.today.completed, 1)
        XCTAssertEqual(summary.today.total, 3)
        XCTAssertEqual(summary.today.counterText, "1/3")
        XCTAssertEqual(summary.week.completed, 1)
        XCTAssertEqual(summary.week.total, 4)
        XCTAssertEqual(summary.week.counterText, "1/4")
        XCTAssertEqual(summary.all.completed, 3)
        XCTAssertEqual(summary.all.total, 8)
        XCTAssertEqual(summary.all.counterText, "3/8")
        XCTAssertEqual(summary.all.progress, 3.0 / 8.0, accuracy: 1e-9)
    }

    /// 今日的第 ③ 条「今天完成的也归今日」：把被第 ② 条（已过期**且未完成**）挡掉的
    /// 「已过期但今天完成」接回来；未来到期但今天完成的同样归今日。
    /// 而「无到期时间 + 今天完成」按单列的硬规则**只进「所有」**（两条规则相抵时以前者为准）。
    func testTodoBucketingCompletedTodayEntersToday() throws {
        let calendar = try fixedGregorian()
        let now = try instant(2026, 9, 28, 10, calendar: calendar)
        let completedAt = try instant(2026, 9, 28, 9, calendar: calendar)

        let summary = TodoBucketing.classify([
            todo(
                "overdue-done-today",
                due: try instant(2026, 9, 25, 9, calendar: calendar),
                completed: true,
                completedAt: completedAt
            ),
            todo(
                "future-done-today",
                due: try instant(2026, 10, 20, 9, calendar: calendar),
                completed: true,
                completedAt: completedAt
            ),
            todo("no-due-done-today", completed: true, completedAt: completedAt),
        ], now: now, calendar: calendar)

        XCTAssertEqual(todoIDs(summary.today), ["overdue-done-today", "future-done-today"], "今天完成的都归今日（有到期时间的）")
        XCTAssertEqual(todoIDs(summary.all), ["overdue-done-today", "future-done-today", "no-due-done-today"])
        XCTAssertFalse(todoIDs(summary.today).contains("no-due-done-today"), "无到期时间只进「所有」")
        XCTAssertFalse(todoIDs(summary.week).contains("no-due-done-today"), "无到期时间不进「本周」")
    }

    /// 总量为 0 的边界：三个类别都是 `0/0`、进度 0（环为空）；并钉住环的展示顺序。
    func testTodoBucketingEmptyBoundary() throws {
        let calendar = try fixedGregorian()
        let summary = TodoBucketing.classify(
            [],
            now: try instant(2026, 9, 28, 10, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(summary.ordered.map(\.bucket), [.today, .week, .all], "环的展示顺序：今日 → 本周 → 所有")
        for result in summary.ordered {
            XCTAssertEqual(result.completed, 0)
            XCTAssertEqual(result.total, 0)
            XCTAssertEqual(result.counterText, "0/0")
            XCTAssertEqual(result.progress, 0)
        }
    }

    /// 周区间的起止随日历的 `firstWeekday`（不假定周一）：2026-10-04（周日）在「周一为首日」的
    /// 周 `[09-28, 10-05)` 内，在「周日为首日」的周 `[09-27, 10-04)` 之外（它是下一周的第一天）——
    /// 两种日历下都不进今日、都进所有。
    ///
    /// 用未来到期（而非昨天）的条目，是为了不撞上「已过期 → 进今日」那条规则：
    /// 2026-09-27（周日）虽然也随 `firstWeekday` 在两周之间挪动，但它已过期，两种日历下都进今日。
    func testTodoBucketingWeekFollowsFirstWeekday() throws {
        let mondayFirst = try fixedGregorian(firstWeekday: 2)
        let sundayFirst = try fixedGregorian(firstWeekday: 1)
        let now = try instant(2026, 9, 28, 10, calendar: mondayFirst)
        let item = todo("sunday-due", due: try instant(2026, 10, 4, 9, calendar: mondayFirst))

        let mondaySummary = TodoBucketing.classify([item], now: now, calendar: mondayFirst)
        let sundaySummary = TodoBucketing.classify([item], now: now, calendar: sundayFirst)

        XCTAssertEqual(todoIDs(mondaySummary.week), ["sunday-due"], "周一为首日：本周 = [09-28, 10-05)")
        XCTAssertTrue(todoIDs(sundaySummary.week).isEmpty, "周日为首日：本周 = [09-27, 10-04)，10-04 已是下一周")
        XCTAssertEqual(mondaySummary.today.total, 0, "日后到期且未完成 → 不进今日")
        XCTAssertEqual(sundaySummary.today.total, 0)
        XCTAssertEqual(mondaySummary.all.total, 1)
        XCTAssertEqual(sundaySummary.all.total, 1)
    }

    /// 到期时间恰好是**明天 00:00** 时不算今天（自然日的半开区间边界）。
    /// `DateInterval.contains(_:)` 的实现含 end 端点，用它会把这条算进今天——本模块因此自写半开判定。
    func testTodoBucketingMidnightBoundary() throws {
        let calendar = try fixedGregorian()
        let summary = TodoBucketing.classify([
            todo("tomorrow-midnight", due: try instant(2026, 9, 29, calendar: calendar)),
            todo("today-last-minute", due: try instant(2026, 9, 28, 23, 59, calendar: calendar)),
        ], now: try instant(2026, 9, 28, 23, 59, calendar: calendar), calendar: calendar)

        XCTAssertEqual(todoIDs(summary.today), ["today-last-minute"])
    }

    // MARK: - 待办四视图过滤（P1 / T1，docs/18 §接口与数据形状 3）

    /// 视图枚举的词汇表：`rawValue` 是稳定标识（左导航按声明顺序展示），**只加不改**。
    func testTodoViewKindVocabulary() throws {
        XCTAssertEqual(TodoBucketing.TodoViewKind.allCases.map(\.rawValue), ["today", "next7Days", "all", "completed"])
        XCTAssertEqual(TodoBucketing.TodoViewKind.allCases.map(\.id), TodoBucketing.TodoViewKind.allCases.map(\.rawValue))
    }

    /// 四个视图各自的取数口径：`today` / `next7Days` 只收**未完成**且到期落在各自的半开区间；
    /// `all` = 全部未完成（含无到期时间）；`completed` = 全部已完成（不论日期）。
    ///
    /// 固定 `now = 2026-09-28 10:00`（周一，Asia/Shanghai）+ 固定日历，结论只依赖 `Calendar` 语义。
    func testTodoViewKindMembership() throws {
        let calendar = try fixedGregorian()
        let now = try instant(2026, 9, 28, 10, calendar: calendar)

        let items = [
            todo("today-open", due: try instant(2026, 9, 28, 9, calendar: calendar)),
            todo(
                "today-done",
                due: try instant(2026, 9, 28, 8, calendar: calendar),
                completed: true,
                completedAt: try instant(2026, 9, 28, 9, 30, calendar: calendar)
            ),
            todo("tomorrow-open", due: try instant(2026, 9, 29, 9, calendar: calendar)),
            todo("day6-open", due: try instant(2026, 10, 4, 9, calendar: calendar)),   // 今天 + 6 天：窗内
            todo("day7-open", due: try instant(2026, 10, 5, 9, calendar: calendar)),   // 今天 + 7 天：窗外
            todo("last-minute-open", due: try instant(2026, 9, 28, 23, 59, calendar: calendar)),
            todo("no-due-open", list: "收集箱"),
            todo(
                "overdue-done",
                due: try instant(2026, 9, 20, 9, calendar: calendar),
                completed: true,
                completedAt: try instant(2026, 9, 20, 10, calendar: calendar)
            ),
        ]

        // 今天：到期落在 [09-28 00:00, 09-29 00:00) 且未完成
        XCTAssertEqual(
            viewed(.today, items, now: now, calendar: calendar),
            ["today-open", "last-minute-open"],
            "今天只收今天到期且未完成的（today-done 已完成 → 只在 completed）"
        )
        // 最近 7 天：到期落在 [09-28 00:00, 10-05 00:00) 且未完成（含今天，随 `sorted` 按到期升序）
        XCTAssertEqual(
            viewed(.next7Days, items, now: now, calendar: calendar),
            ["today-open", "last-minute-open", "tomorrow-open", "day6-open"],
            "7 天窗含今天；第 7 天（10-05）在窗外；已完成 / 无到期日的都不进"
        )
        // 全部未完成：含无到期时间（排在最后）、含窗外与过期未完成的
        XCTAssertEqual(
            viewed(.all, items, now: now, calendar: calendar),
            ["today-open", "last-minute-open", "tomorrow-open", "day6-open", "day7-open", "no-due-open"],
            "清单 = 未完成全集：无到期日的算、第 7 天与更远的算"
        )
        // 已完成：不论日期（今天完成的排在更早完成的之前）
        XCTAssertEqual(
            viewed(.completed, items, now: now, calendar: calendar),
            ["today-done", "overdue-done"],
            "已完成档按完成时刻倒序：刚完成的在前"
        )
    }

    /// 边界逐条钉死：今天 23:59 算今天（半开区间上界仍是今天）；**恰好第 7 天要排除**；
    /// 无到期日只进 `all`；已完成 + 已过期只进 `completed`（不进任何时间窗）。
    func testTodoViewKindBoundaries() throws {
        let calendar = try fixedGregorian()
        // now 取当天最后一刻，最大化「同一条目是否算今天」的判定压力
        let now = try instant(2026, 9, 28, 23, 59, calendar: calendar)
        let items = [
            todo("today-last-minute", due: try instant(2026, 9, 28, 23, 59, calendar: calendar)),
            todo("tomorrow-midnight", due: try instant(2026, 9, 29, calendar: calendar)),
            todo("day6-midnight", due: try instant(2026, 10, 4, calendar: calendar)),
            todo("day7-midnight", due: try instant(2026, 10, 5, calendar: calendar)),
            todo("no-due", list: "收集箱"),
            todo(
                "done-overdue",
                due: try instant(2026, 9, 15, 9, calendar: calendar),
                completed: true,
                completedAt: try instant(2026, 9, 16, 9, calendar: calendar)
            ),
        ]

        XCTAssertEqual(viewed(.today, items, now: now, calendar: calendar), ["today-last-minute"], "今天 23:59 算今天")
        XCTAssertEqual(
            viewed(.next7Days, items, now: now, calendar: calendar),
            ["today-last-minute", "tomorrow-midnight", "day6-midnight"],
            "半开区间：明天 00:00 在窗内，第 7 天 00:00 恰好出窗"
        )
        XCTAssertEqual(
            viewed(.all, items, now: now, calendar: calendar),
            ["today-last-minute", "tomorrow-midnight", "day6-midnight", "day7-midnight", "no-due"],
            "无到期日的进清单（排最后）；已完成的进不来"
        )
        XCTAssertEqual(viewed(.completed, items, now: now, calendar: calendar), ["done-overdue"], "过期但已完成 → 只在已完成档")
        for view in [TodoBucketing.TodoViewKind.today, .next7Days, .all] {
            XCTAssertFalse(viewed(view, items, now: now, calendar: calendar).contains("done-overdue"), "\(view) 不出现已完成条目")
        }
    }

    /// 空表：四个视图都空（`sorted` / 过滤都不崩）。
    func testTodoViewKindEmptyInput() throws {
        let calendar = try fixedGregorian()
        let now = try instant(2026, 9, 28, 10, calendar: calendar)
        for view in TodoBucketing.TodoViewKind.allCases {
            XCTAssertTrue(viewed(view, [], now: now, calendar: calendar).isEmpty, "\(view) 空表为空")
        }
    }

    /// 视图过滤的调用壳（把 `TodoBucketing.items(in:from:now:calendar:)` 收敛成 id 列表）。
    private func viewed(
        _ view: TodoBucketing.TodoViewKind,
        _ items: [TodoBucketing.Item],
        now: Date,
        calendar: Calendar
    ) -> [String] {
        TodoBucketing.items(in: view, from: items, now: now, calendar: calendar).map(\.id)
    }

    /// `TodosModule.manifest` 的契约：id / surfaces / icon / defaultEnabled / placement / 空权限 / 无配置；
    /// 并回走一次 JSON 路径（与宿主读 descriptor 同一条路）。
    func testTodosModuleManifestMatchesContract() throws {
        let manifest = TodosModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, "com.cmeng.gourd.todos")
        XCTAssertEqual(manifest.shortID, "todos")
        XCTAssertEqual(manifest.name.key, "module.todos.name")
        XCTAssertEqual(manifest.summary?.key, "module.todos.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "checklist"))
        XCTAssertEqual(manifest.kind, "builtin")
        // 顺序 + 内容都钉住：P2（T4）起多一个 `.home`（首页 strip 的一块），值的顺序即声明顺序
        XCTAssertEqual(manifest.surfaces, [.expanded, .compact, .home], "展开面板 + 折叠态中央槽位 + 首页块")
        XCTAssertTrue(manifest.surfaces.contains(.home), "首页块是 manifest 驱动的：todos 必须声明 .home")
        XCTAssertEqual(manifest.defaultEnabled, true)
        XCTAssertEqual(manifest.defaultPlacement, Placement(slot: .center, order: 20))
        XCTAssertTrue(manifest.permissions.isEmpty, "06 §7.1 无「提醒」词条：提醒走系统 TCC，不声明 capability")
        XCTAssertNil(manifest.config, "第一版不做配置")

        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    // MARK: - 待办的新增 / 删除（2026-09-28 用户反馈「待办里面要可以增删待办内容」）

    /// 新增的校验与构造是纯函数：**标题去首尾空白**后写库，日期三选一给「当天 00:00 的年月日」。
    ///
    /// 「今天」给的是**年月日组件、不带时分**——与系统「提醒」App 的全天条目同形，读回时
    /// `TodoDueLabel` 按自然日判定（到期落在今天 → 「今天」，其余 `M/D`，见 P1 / T2 的用例）。
    func testTodoComposerTrimsTitleAndBuildsTodayDue() throws {
        let calendar = try fixedGregorian()
        let now = try instant(2026, 9, 28, 14, 30, calendar: calendar)

        let draft = TodoComposer.draft(title: "  买牛奶\n ", due: .today, now: now, calendar: calendar)
        guard case let .create(title, components) = draft else {
            return XCTFail("非空标题必须能建：\(draft)")
        }
        XCTAssertEqual(title, "买牛奶", "首尾空白与换行都去掉，内部文字不动")
        XCTAssertEqual(components?.year, 2026)
        XCTAssertEqual(components?.month, 9)
        XCTAssertEqual(components?.day, 28)
        XCTAssertNil(components?.hour, "只给年月日：不带时分才是全天口径（14:30 的现在也不写 14:30）")
        XCTAssertNil(components?.minute)
        XCTAssertNil(components?.second)
        XCTAssertEqual(
            calendar.date(from: try XCTUnwrap(components)),
            calendar.startOfDay(for: now),
            "今天 = 今天 00:00"
        )
    }

    /// 标题去空白后为空：**拒绝**（不建提醒）——空标题在「提醒」App 里是一行看不见的条目。
    func testTodoComposerRejectsBlankTitle() {
        for blank in ["", "   ", "\n\t ", " \n \t\n"] {
            XCTAssertEqual(
                TodoComposer.draft(title: blank, due: .today),
                .rejectEmptyTitle,
                "\(blank.debugDescription) 是空标题"
            )
        }
    }

    /// 「明天」= `now + 1 天`的当天起点：跨月（9/30 → 10/1）与跨年（12/31 → 次年 1/1）都按自然日推进，
    /// 且**先加一天再取起点**（夏令时切换日「今天起点 + 1 天」与「现在 + 1 天」不是同一天）。
    func testTodoComposerTomorrowUsesNextDayStart() throws {
        let calendar = try fixedGregorian()
        func tomorrow(_ now: Date) -> DateComponents? {
            guard case let .create(_, components) = TodoComposer.draft(
                title: "x", due: .tomorrow, now: now, calendar: calendar
            ) else { return nil }
            return components
        }

        let acrossMonth = try XCTUnwrap(tomorrow(try instant(2026, 9, 30, 23, 50, calendar: calendar)))
        XCTAssertEqual([acrossMonth.year, acrossMonth.month, acrossMonth.day], [2026, 10, 1], "月末跨月")

        let acrossYear = try XCTUnwrap(tomorrow(try instant(2026, 12, 31, 0, 5, calendar: calendar)))
        XCTAssertEqual([acrossYear.year, acrossYear.month, acrossYear.day], [2027, 1, 1], "跨年")
    }

    /// 「无日期」给 nil：条目**没有** `dueDateComponents`——按 `TodoBucketing` 的硬规则它只出现在
    /// 「所有」里，这是刻意的（不是漏填）。
    func testTodoComposerNoDateYieldsNilDueComponents() {
        XCTAssertEqual(
            TodoComposer.draft(title: "收集", due: .none),
            .create(title: "收集", dueDateComponents: nil)
        )
    }

    /// 目标列表的兜底：默认列表（`defaultCalendarForNewReminders()` 可为 nil）优先，
    /// 取不到时退到第一个可用列表；两者都没有 → nil（调用方据此显示一行失败提示，而不是猜一个列表）。
    func testTodoComposerTargetListFallsBackToFirstAvailable() {
        XCTAssertEqual(
            TodoComposer.targetList(defaultList: "默认", availableLists: ["A", "B"]),
            "默认",
            "有默认列表就用默认列表（不碰第一个可用列表）"
        )
        XCTAssertEqual(
            TodoComposer.targetList(defaultList: String?.none, availableLists: ["A", "B"]),
            "A",
            "默认列表为 nil 时兜到第一个可用列表"
        )
        XCTAssertNil(
            TodoComposer.targetList(defaultList: String?.none, availableLists: []),
            "一个列表都没有 → nil（失败并回显提示，不静默）"
        )
    }

    /// 左列竖排三环的直径是**可用高度的纯函数**（2026-09-28 用户改版：「三个圈…放在左侧」）：
    /// 高度够就回到设计定稿的 52，不够就三等分剩余空间，缩到下限 30 为止；
    /// 高度取不到（GeometryReader 给 0）时不能出现 0 直径的环。
    func testTodoRingPickerDiameterFitsAvailableHeight() {
        XCTAssertEqual(
            TodoRingLayout.ringDiameter(fittingHeight: 400),
            TodoRingLayout.maximumDiameter,
            "面板调高后回到设计定稿的 52（不再因竖排缩小）"
        )
        XCTAssertEqual(
            TodoRingLayout.ringDiameter(fittingHeight: 0),
            TodoRingLayout.maximumDiameter,
            "高度取不到（0）时按上限，不出现 0 直径"
        )
        XCTAssertEqual(
            TodoRingLayout.ringDiameter(fittingHeight: TodoRingLayout.maximumDiameter * 3 + 200),
            TodoRingLayout.maximumDiameter,
            "远超所需的高度同样封顶在 52"
        )

        // 默认 200pt 面板扣掉上下 padding ≈ 180：三个环收缩后必须真的放得下（含标签与间距）
        let defaultHeight: CGFloat = 180
        let fitted = TodoRingLayout.ringDiameter(fittingHeight: defaultHeight)
        XCTAssertLessThan(fitted, TodoRingLayout.maximumDiameter, "默认高度下要收缩（52 三个环放不进 180）")
        XCTAssertGreaterThanOrEqual(fitted, TodoRingLayout.minimumDiameter)
        let used = fitted * 3
            + TodoRingLayout.ringSpacing * 2
            + TodoRingLayout.itemTextHeight * 3
        XCTAssertLessThanOrEqual(used, defaultHeight, "收缩后的三环 + 标签必须落在可用高度内")

        XCTAssertEqual(
            TodoRingLayout.ringDiameter(fittingHeight: 10),
            TodoRingLayout.minimumDiameter,
            "极矮的面板（用户把高度拖到最小）也保底 30，不缩成看不见的点"
        )
    }

    /// 首页块的**行数由块高算**（P5 / T1，D-02；docs/29 §接口与数据形状）：`rowCount(fittingHeight:)`
    /// 是 `floor((高度 − 表头 − 间距) / 行高)` 钳 `0…8` 的纯函数，**宽度不参与**。
    ///
    /// 验收 A2 的四个边界逐条钉住：**0 / 96 / 140 / 非有限值**。96 是小组件带的真实块高
    /// （`HomeStripFit.compactBlockHeight`，待办声明 `.compact`），所以这一条不是凑的数字。
    func testTodosHomeBlockLayoutRowCountFitsHeight() {
        XCTAssertEqual(TodosHomeBlockLayout.headerHeight, 16, "表头一行的高度是规格值")
        XCTAssertEqual(TodosHomeBlockLayout.rowHeight, 16, "清单一行的高度是规格值（行数是按它算的）")
        XCTAssertEqual(TodosHomeBlockLayout.maximumRows, 8, "行数上限是规格值（钳 0…8）")

        /// 「表头 + 一段间距 + N 行」的内容高：它是「恰好放得下 N 行」的那条高度线，
        /// 用例用它与渲染共用同一组常量，避免算式与渲染各写一套数字。
        func exactHeight(fittingRows rows: Int) -> CGFloat {
            TodosHomeBlockLayout.headerHeight + TodosHomeBlockLayout.listSpacing
                + CGFloat(rows) * TodosHomeBlockLayout.rowHeight
        }

        XCTAssertEqual(exactHeight(fittingRows: 4), 84, "16 + 4 + 4 × 16 = 84")
        XCTAssertEqual(TodosHomeBlockLayout.rowCount(fittingHeight: 96), 4, "96 高（真实块高）画 4 行")
        XCTAssertEqual(TodosHomeBlockLayout.rowCount(fittingHeight: 140), 7, "140 高画更多行（本算式给 7）")
        XCTAssertLessThanOrEqual(exactHeight(fittingRows: 4), 96, "96 高里 4 行的内容高不超可用高")

        // 高度取不到（首帧 GeometryReader 给 0 / NaN / ±∞）→ 0 行：先只画表头。
        // 这一支必须显式兜住——`Int(Double.nan)` 与 `Int(1e300)` 都是运行时陷阱，不是返回值。
        XCTAssertEqual(TodosHomeBlockLayout.rowCount(fittingHeight: 0), 0, "首帧高度 0 → 0 行")
        XCTAssertEqual(TodosHomeBlockLayout.rowCount(fittingHeight: .nan), 0, "NaN → 0 行")
        XCTAssertEqual(TodosHomeBlockLayout.rowCount(fittingHeight: .infinity), 0, "+∞ → 0 行")
        XCTAssertEqual(TodosHomeBlockLayout.rowCount(fittingHeight: -.infinity), 0, "−∞ → 0 行")
        XCTAssertEqual(TodosHomeBlockLayout.rowCount(fittingHeight: -50), 0, "负高度 → 0 行（不返回负数）")
        XCTAssertEqual(TodosHomeBlockLayout.rowCount(fittingHeight: 30), 0, "矮于「表头 + 间距 + 一行」→ 0 行")

        // 上限：高度再富余也停在 8 行（D-02 的钳位）
        XCTAssertEqual(TodosHomeBlockLayout.rowCount(fittingHeight: 10_000), 8, "高度富余时钳在 8 行")

        // **永不超可用高**：逐个高度验算「内容高 ≤ 块高」，并验「行数在恰好放得下时不变」
        // （后者说明算式与渲染的高度账目是同一套，不是两处各写一份）。
        for height: CGFloat in [36, 52, 84, 96, 140, 200, 10_000] {
            let count = TodosHomeBlockLayout.rowCount(fittingHeight: height)
            XCTAssertLessThanOrEqual(
                exactHeight(fittingRows: count), height,
                "高度 \(height)：表头 + 间距 + \(count) 行不得溢出块高"
            )
            XCTAssertEqual(
                TodosHomeBlockLayout.rowCount(fittingHeight: exactHeight(fittingRows: count)), count,
                "高度 \(height)：内容高恰好放得下 \(count) 行（不多不少）"
            )
        }

        // 关于高度单调不减（块变高只会多画行，不会少画）
        var previous = 0
        for height in stride(from: CGFloat(0), through: 200, by: 4) {
            let count = TodosHomeBlockLayout.rowCount(fittingHeight: height)
            XCTAssertGreaterThanOrEqual(count, previous, "高度 \(height)：行数不得随块变高而减少")
            previous = count
        }
    }

    /// 行形态分档**缩成两档**（P5 / T1，D-02）：块宽不再决定行数，只决定清单行的形态——
    /// `>= compactListWidth`（160，沿用既有值）画完整行（`TodoHomeRow`：状态圈 + 标题 + 过期红字）；
    /// 更窄（或宽度取不到）画紧凑行（`TodoHomeCompactRow`：只标题）。
    func testTodosHomeBlockLayoutTierHasTwoRowShapes() {
        XCTAssertEqual(TodosHomeBlockLayout.compactListWidth, 160, "行形态的分界线沿用既有值 160")

        XCTAssertEqual(TodosHomeBlockLayout.listTier(forWidth: 160), .full, "恰好在分界线上 → 完整行")
        XCTAssertEqual(TodosHomeBlockLayout.listTier(forWidth: 240), .full, "宿主的理想宽 240 → 完整行")
        XCTAssertEqual(
            TodosHomeBlockLayout.listTier(forWidth: 180.5),
            .full,
            "本机 770pt 面板实测块宽 180.5 ≥ 160 → 完整行（改动前这一档只画紧凑行）"
        )
        XCTAssertEqual(TodosHomeBlockLayout.listTier(forWidth: 159.9), .compact, "差一点落进紧凑行")
        XCTAssertEqual(TodosHomeBlockLayout.listTier(forWidth: 0), .compact, "首帧宽度 0 → 最保守的紧凑行")
        XCTAssertEqual(TodosHomeBlockLayout.listTier(forWidth: .nan), .compact, "非有限数 → 紧凑行")
    }

    /// 首页块**不含环**（P5 / T1，D-01：用户「只显示今日的就行，那三个圈不要了」）。
    ///
    /// `TodoHomeRingRow` 与它的两个环尺寸常量（`TodosHomeBlockLayout.ringSpacing` / `.ringDiameter`）
    /// 已删除——**删除本身是编译期约束**：本用例若再引用它们就编不过。运行期能钉住的是它们的替代契约：
    /// **任何宽度下都落进「有清单行」的两种形态之一**，旧三档里那个「只画三个 `0/0` 的环」的退化档
    /// （`.ringsOnly`）不再存在；今日有条目时块里画的是清单，不是环。
    func testTodosHomeBlockLayoutHasNoRingsOnlyFallback() {
        let today = (1...3).map { TodoBucketing.Item(id: "t\($0)", title: "t\($0)") }
        let widths: [CGFloat] = [0, 1, 100, 159.9, 160, 180.5, 220, 240, 1_000, .nan, .infinity, -.infinity]

        for width in widths {
            let tier = TodosHomeBlockLayout.listTier(forWidth: width)
            XCTAssertTrue(
                [.full, .compact].contains(tier),
                "宽度 \(width) 只能落进两种行形态（没有「只画环」这一档）"
            )

            // 真实块高（96）下今日有 3 条就画 3 行——不因宽度窄而改画环。
            let rows = TodosHomeBlockLayout.listedItems(
                today,
                count: TodosHomeBlockLayout.rowCount(fittingHeight: 96)
            )
            XCTAssertEqual(rows.map(\.id), ["t1", "t2", "t3"], "宽度 \(width)：96 高的块仍画今日清单")
        }
    }

    /// 表头之下画什么（P5 / T1 修复轮，审查 2 / 3）：空态行**只在三个条件同时成立**时画——
    /// **有完整授权**（未授权时 `store.items` 空是「读不到」而不是「今天没事」，画文案是正面假断言）、
    /// **块高放得下这一行**（`rowCount > 0`，空态行与清单行同高 16，画不下就会溢出块高）、
    /// **今日确实 0 条**。三者缺一 → `.nothing`（只留表头）。
    func testTodosHomeBlockLayoutTodayContentGatesEmptyState() {
        let items = (1...3).map { TodoBucketing.Item(id: "t\($0)", title: "t\($0)") }

        // ① 授权 + 放得下 + 有今日条目 → 按行数截取（顺序沿用 TodoBucketing）
        XCTAssertEqual(
            TodosHomeBlockLayout.todayContent(todayItems: items, hasFullAccess: true, rowCount: 2),
            .rows(Array(items.prefix(2))),
            "有授权、放得下 2 行 → 画前 2 条"
        )
        // ② 授权 + 放得下 + 今日 0 条 → 空态一行
        XCTAssertEqual(
            TodosHomeBlockLayout.todayContent(todayItems: [], hasFullAccess: true, rowCount: 4),
            .empty,
            "有授权、放得下、确实没有 → 才画空态"
        )
        XCTAssertEqual(
            TodosHomeBlockLayout.todayContent(todayItems: [], hasFullAccess: true, rowCount: 1),
            .empty,
            "一行放得下就够画空态（空态行与清单行同高）"
        )
        // ③ 未授权：空表是「读不到」→ 一行都不画（不画空态文案、也不画条目）
        XCTAssertEqual(
            TodosHomeBlockLayout.todayContent(todayItems: [], hasFullAccess: false, rowCount: 4),
            .nothing,
            "授权未就绪时不画「今日无待办」（那是正面假断言）"
        )
        XCTAssertEqual(
            TodosHomeBlockLayout.todayContent(todayItems: items, hasFullAccess: false, rowCount: 4),
            .nothing,
            "未授权时即使手里有陈旧条目也不画（读不到就是不知道）"
        )
        // ④ 块高连一行都放不下（`rowCount == 0`）→ 空态行同样溢出，不画
        XCTAssertEqual(
            TodosHomeBlockLayout.todayContent(todayItems: [], hasFullAccess: true, rowCount: 0),
            .nothing,
            "块矮到 0 行：16 + 4 + 16 = 36 > 块高，空态行也不画"
        )
        XCTAssertEqual(
            TodosHomeBlockLayout.todayContent(todayItems: items, hasFullAccess: true, rowCount: 0),
            .nothing,
            "块矮到 0 行：有今日条目也只留表头（宁可少画，不说谎也不溢出）"
        )
    }

    /// 清单的截取口径（P5 / T1）：`listedItems(_:count:)` 只按**条数**取前 N 条（条数由块高算，
    /// 见 `rowCount(fittingHeight:)`），顺序沿用 `TodoBucketing` 的排序（不在这里重排）；
    /// `count` 为 0 / 负数给空表（不崩），超过条目数时原样给全。
    func testTodosHomeBlockLayoutListedItemsByCount() {
        let items = (1...6).map { TodoBucketing.Item(id: "t\($0)", title: "t\($0)") }

        XCTAssertEqual(
            TodosHomeBlockLayout.listedItems(items, count: 4).map(\.id),
            ["t1", "t2", "t3", "t4"],
            "按块高算出的 4 行 = 前 4 条（1/4 之后的那些排在后面）"
        )
        XCTAssertEqual(
            TodosHomeBlockLayout.listedItems(Array(items.prefix(2)), count: 8).map(\.id),
            ["t1", "t2"],
            "不足 N 条时原样"
        )
        XCTAssertTrue(TodosHomeBlockLayout.listedItems(items, count: 0).isEmpty, "0 行（块太矮）→ 一条都不画")
        XCTAssertTrue(TodosHomeBlockLayout.listedItems(items, count: -3).isEmpty, "负数 → 空表（不崩）")
        XCTAssertTrue(TodosHomeBlockLayout.listedItems([], count: 8).isEmpty, "今日 0 条 → 空表（空态行由视图画）")
    }

    // MARK: - 首页块：今日日程 + 待办混合清单（docs/37 D-05）

    /// 混合清单的顺序与截断（纯函数）：**日程在前**（全天最前、各自按 `start` 升序）、
    /// **待办接在后面**（沿用 `TodoBucketing` 的既有次序），总数截到 `rowCount`；
    /// **未授权时日程照常、待办一条不给**（待办的授权状态读的是「读不到」，与日程那条 EventKit 授权
    /// 是两回事）。
    func testTodosHomeBlockMixedEntriesOrderAndTruncation() {
        let calendar = todoTestCalendar()
        let morning = todoTestEvent(
            id: "e-morning",
            start: todoTestTime(calendar, year: 2026, month: 10, day: 10, hour: 9, minute: 30),
            end: todoTestTime(calendar, year: 2026, month: 10, day: 10, hour: 10, minute: 0)
        )
        let allDay = todoTestEvent(
            id: "e-allday",
            start: todoTestTime(calendar, year: 2026, month: 10, day: 10, hour: 0),
            end: todoTestTime(calendar, year: 2026, month: 10, day: 11, hour: 0),
            isAllDay: true
        )
        let afternoon = todoTestEvent(
            id: "e-afternoon",
            start: todoTestTime(calendar, year: 2026, month: 10, day: 10, hour: 14),
            end: todoTestTime(calendar, year: 2026, month: 10, day: 10, hour: 15)
        )
        let todos = (1...3).map { TodoBucketing.Item(id: "t\($0)", title: "t\($0)") }

        // 乱序传入：全天 → 上午 → 下午 → 待办
        let entries = TodosHomeBlockLayout.listedEntries(
            events: [afternoon, morning, allDay],
            todos: todos,
            hasFullAccess: true,
            rowCount: 10
        )
        XCTAssertEqual(
            entries.map(\.id),
            ["event:e-allday", "event:e-morning", "event:e-afternoon", "todo:t1", "todo:t2", "todo:t3"],
            "日程按（全天在前、各自 start 升序）排，待办接在后面"
        )

        // 截断：只要前 2 条 → 两条日程（待办一条都进不来）
        XCTAssertEqual(
            TodosHomeBlockLayout.listedEntries(
                events: [afternoon, morning, allDay], todos: todos, hasFullAccess: true, rowCount: 2
            ).map(\.id),
            ["event:e-allday", "event:e-morning"]
        )
        // 0 行 / 负数 → 空表（不崩）
        XCTAssertTrue(
            TodosHomeBlockLayout.listedEntries(events: [morning], todos: todos, hasFullAccess: true, rowCount: 0).isEmpty
        )
        XCTAssertTrue(
            TodosHomeBlockLayout.listedEntries(events: [morning], todos: todos, hasFullAccess: true, rowCount: -2).isEmpty
        )
        // 未授权：日程照常，待办不画（读不到就是不知道——与 todayContent 的第 ① 条同源）
        XCTAssertEqual(
            TodosHomeBlockLayout.listedEntries(
                events: [morning], todos: todos, hasFullAccess: false, rowCount: 10
            ).map(\.id),
            ["event:e-morning"],
            "未授权时待办不给条目，日程不受影响（两条授权是两回事）"
        )
    }

    /// 空态判据（docs/37 D-05）：**有完整授权 + 有一行位置 + 日程与待办都为空** 才画
    /// 「今天没有安排」；未授权、放不下、或任一侧有内容都不画。
    func testTodosHomeBlockEmptyStateGatesOnBothSidesBeingEmpty() {
        XCTAssertTrue(
            TodosHomeBlockLayout.emptyStateShows(hasFullAccess: true, rowCount: 4, eventCount: 0, todoCount: 0)
        )
        XCTAssertFalse(
            TodosHomeBlockLayout.emptyStateShows(hasFullAccess: true, rowCount: 4, eventCount: 1, todoCount: 0),
            "有日程 → 不画空态"
        )
        XCTAssertFalse(
            TodosHomeBlockLayout.emptyStateShows(hasFullAccess: true, rowCount: 4, eventCount: 0, todoCount: 2),
            "有待办 → 不画空态"
        )
        XCTAssertFalse(
            TodosHomeBlockLayout.emptyStateShows(hasFullAccess: false, rowCount: 4, eventCount: 0, todoCount: 0),
            "未授权：读不到 ≠ 没有（旧 todayContent 的第 ① 条判据）"
        )
        XCTAssertFalse(
            TodosHomeBlockLayout.emptyStateShows(hasFullAccess: true, rowCount: 0, eventCount: 0, todoCount: 0),
            "块矮到一行都放不下 → 空态行同样溢出，不画"
        )
    }

    /// 日程行的时间列文案（纯函数）：全天 → `全天`；同日内定时 → `9:30 – 10:30`；
    /// 跨天 / 止点不晚于起点 → 只给起点。
    func testTodoTextEventTimeLabel() {
        let calendar = todoTestCalendar()
        let start = todoTestTime(calendar, year: 2026, month: 10, day: 10, hour: 9, minute: 30)

        let allDay = todoTestEvent(
            id: "allday",
            start: start,
            end: todoTestTime(calendar, year: 2026, month: 10, day: 11, hour: 0),
            isAllDay: true
        )
        XCTAssertEqual(
            TodoText.eventTimeLabel(for: allDay),
            TodoText.localized("module.todos.homeAllDay"),
            "全天条目给「全天」（与日历卡片的时间列同一口径）"
        )

        let timed = todoTestEvent(
            id: "timed",
            start: start,
            end: todoTestTime(calendar, year: 2026, month: 10, day: 10, hour: 10, minute: 30)
        )
        let label = TodoText.eventTimeLabel(for: timed)
        XCTAssertTrue(label.contains("–"), "同日内定时给区间：\(label)")

        let crossDay = todoTestEvent(
            id: "cross",
            start: start,
            end: todoTestTime(calendar, year: 2026, month: 10, day: 11, hour: 12)
        )
        XCTAssertFalse(TodoText.eventTimeLabel(for: crossDay).contains("–"), "跨天只给起点")

        let zeroLength = todoTestEvent(id: "zero", start: start, end: start)
        XCTAssertFalse(TodoText.eventTimeLabel(for: zeroLength).contains("–"), "止点不晚于起点只给起点")
    }

    // MARK: - 混合清单的夹具（docs/37 D-05；与网格用例的夹具分开命名，避免与别的测试类撞名）

    /// 固定周一起点的测试日历（与 `HomeStripLayoutTests` 的夹具同款口径）。
    private func todoTestCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// 固定日历下的一个时刻。
    private func todoTestTime(
        _ calendar: Calendar,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 一个日程条目（头衔 = id；系统色；非提醒）。
    private func todoTestEvent(
        id: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false
    ) -> EventModel {
        EventModel(
            id: id,
            start: start,
            end: end,
            title: id,
            location: nil,
            notes: nil,
            url: nil,
            isAllDay: isAllDay,
            type: .event(.accepted),
            calendar: CalendarModel(
                accountName: "Test",
                id: "test.calendar",
                title: "Test",
                color: .systemBlue,
                isSubscribed: false,
                isReminder: false
            ),
            participants: [],
            timeZone: TimeZone(secondsFromGMT: 0),
            hasRecurrenceRules: false,
            priority: nil,
            conferenceURL: nil
        )
    }

    /// `TODO` 日期选项的文案 key 与 `DueOption` 同源（加选项必须同时给 key，否则面板上出现裸 key）。
    func testTodoComposerDueOptionLabelKeys() {
        XCTAssertEqual(
            TodoComposer.DueOption.allCases.map(\.labelKey),
            ["module.todos.dueToday", "module.todos.dueTomorrow", "module.todos.dueNone"]
        )
    }

    /// `module.todos.*` 的 key 必须能从宿主 bundle 解析出文案（06 §3.3 R5 的 key 形态）：
    /// 解析不到时 `Bundle` 原样返回 key，断言因此能抓住漏编译 / 拼错的 key。
    func testTodosLocalizationKeysResolve() {
        let keys = [
            "module.todos.name",
            "module.todos.summary",
            "module.todos.scope.today",
            "module.todos.scope.week",
            "module.todos.scope.all",
            "module.todos.empty",
            "module.todos.overdue",
            "module.todos.permission",
            "module.todos.requestAccess",
            "module.todos.openSettings",
            // 增删（2026-09-28）：新增输入行、日期三选一、删除确认、写回失败的一行提示
            "module.todos.add",
            "module.todos.addPlaceholder",
            "module.todos.dueToday",
            "module.todos.dueTomorrow",
            "module.todos.dueNone",
            "module.todos.delete",
            "module.todos.deleteConfirm",
            "module.todos.cancel",
            "module.todos.writeFailed",
            // 四视图左导航 + 优先级胶囊（P1 / T2）：四个视图名、四档优先级、胶囊提示、已完成档的空态
            "module.todos.view.today",
            "module.todos.view.next7Days",
            "module.todos.view.all",
            "module.todos.view.completed",
            "module.todos.priority.none",
            "module.todos.priority.low",
            "module.todos.priority.medium",
            "module.todos.priority.high",
            "module.todos.priorityHint",
            "module.todos.completedEmpty",
            // 首页块的今日空态（P5 / T1）
            "module.todos.home.empty",
        ]
        for key in keys {
            let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(localized, key, "\(key) 没解析出文案（catalog 未编进宿主 bundle？）")
            XCTAssertFalse(localized.isEmpty, "\(key) 解析为空串")
        }
        // 三个类别的标签 key 与 `TodoBucketing.Bucket.rawValue` 同源
        XCTAssertEqual(TodoBucketing.Bucket.allCases.map(\.labelKey), [
            "module.todos.scope.today", "module.todos.scope.week", "module.todos.scope.all",
        ])
    }

    // MARK: - 待办的优先级胶囊与看板口径（P1 / T2，docs/18 §接口与数据形状 3/4）

    /// 优先级四档的词汇表与 EventKit 双向映射：0 → 无、1…4 → 高、5 → 中、6…9 → 低；
    /// 反向 无 → 0、高 → 1、中 → 5、低 → 9，且**双向可逆**（写回的值读回来仍是同一档）。
    /// 表外的值（负值 / 10，EventKit 不会给）按「无」处理——不崩、不猜档位。
    func testTodoPriorityMappingAndVocabulary() {
        XCTAssertEqual(
            TodoPriority.allCases.map(\.rawValue),
            ["none", "high", "medium", "low"],
            "词汇表与 docs/18 §接口与数据形状 3 一致，只加不改"
        )

        let forward: [(Int, TodoPriority)] = [
            (0, .none), (1, .high), (2, .high), (3, .high), (4, .high),
            (5, .medium), (6, .low), (7, .low), (8, .low), (9, .low),
        ]
        for (eventKit, expected) in forward {
            XCTAssertEqual(
                TodoPriority.priority(fromEventKit: eventKit),
                expected,
                "EventKit \(eventKit) 应映射到 \(expected.rawValue)"
            )
        }
        XCTAssertEqual(TodoPriority.priority(fromEventKit: -1), .none, "表外的负值按「无」")
        XCTAssertEqual(TodoPriority.priority(fromEventKit: 10), .none, "表外的 > 9 按「无」")

        XCTAssertEqual(TodoPriority.eventKitValue(of: .none), 0)
        XCTAssertEqual(TodoPriority.eventKitValue(of: .high), 1)
        XCTAssertEqual(TodoPriority.eventKitValue(of: .medium), 5)
        XCTAssertEqual(TodoPriority.eventKitValue(of: .low), 9)

        // 双向可逆：每一档写回的值读回来仍是同一档（写回不会把档位写跑偏）
        for priority in TodoPriority.allCases {
            XCTAssertEqual(
                TodoPriority.priority(fromEventKit: TodoPriority.eventKitValue(of: priority)),
                priority
            )
        }

        // 文案 key 由 rawValue 派生（面板上不会出现裸 key）
        XCTAssertEqual(TodoPriority.allCases.map(\.labelKey), [
            "module.todos.priority.none", "module.todos.priority.high",
            "module.todos.priority.medium", "module.todos.priority.low",
        ])
    }

    /// 点胶囊的循环顺序：无 → 低 → 中 → 高 → 无（四步回到起点）；
    /// 循环表必须覆盖四档且不重复（日后加档却忘了进循环表 → 这里红）。
    func testTodoPriorityCycleOrder() {
        XCTAssertEqual(TodoPriority.cycle, [.none, .low, .medium, .high], "循环顺序是交互口径，单列成表")
        XCTAssertEqual(Set(TodoPriority.cycle), Set(TodoPriority.allCases), "循环表覆盖全部四档")
        XCTAssertEqual(TodoPriority.cycle.count, TodoPriority.allCases.count, "循环表不重复档位")

        XCTAssertEqual(TodoPriority.cycled(from: .none), .low)
        XCTAssertEqual(TodoPriority.cycled(from: .low), .medium)
        XCTAssertEqual(TodoPriority.cycled(from: .medium), .high)
        XCTAssertEqual(TodoPriority.cycled(from: .high), .none, "高之后回到无")

        var priority = TodoPriority.none
        for _ in 0..<4 { priority = TodoPriority.cycled(from: priority) }
        XCTAssertEqual(priority, .none, "四步一循环，回到起点")
    }

    /// 写回闸门（幂等）：**同级不写**、跨级一律写——「先比对当前值」的判据。
    func testTodoPriorityWriteGateIsIdempotent() {
        for priority in TodoPriority.allCases {
            XCTAssertFalse(
                TodoPriority.shouldWrite(current: priority, target: priority),
                "同级（\(priority.rawValue)）不产生写回"
            )
            XCTAssertTrue(
                TodoPriority.shouldWrite(current: priority, target: TodoPriority.cycled(from: priority)),
                "循环的下一档必须写回"
            )
        }
        XCTAssertFalse(TodoPriority.shouldWrite(current: .high, target: .high), "重复点击同一档：不写")
    }

    /// 乐观层的完整口径（用**计数型假写回器**驱动生产代码 `TodoPriorityOverlay`）：
    /// ① 一次点击 = 一次乐观更新 + 一次写回（值取区间端点）；
    /// ② **同级重复请求不产生第二次写回**（`beginWrite` 返回 nil，写回计数不变）；
    /// ③ **写回失败 → `rollback`** 到读回的真值、写回成功 → **`confirm` 转正**（不停在错误值）；
    /// ④ 重取（`rebuild`）不抹掉在飞的乐观值。
    ///
    /// 这一条只钉**乐观层**；整条写回链（`TodoStore` + 注入的假写回器）另见下面两条 store 级用例。
    func testTodoPriorityOverlayCycleWriteBackAndRollback() {
        var overlay = TodoPriorityOverlay()
        overlay.rebuild(from: ["a": .none])

        /// 计数型假写回器：只记账（不碰 EventKit）。
        var writes: [Int] = []
        func fakeWrite(_ step: TodoPriorityStep) { writes.append(step.eventKitValue) }

        /// 与 `TodoStore.cyclePriority` 同形：取循环的下一档做为目标（生产的取档就在这里）。
        func cycle() -> TodoPriorityStep? {
            overlay.beginWrite("a", to: TodoPriority.cycled(from: overlay.value(for: "a")))
        }

        // ① 点一下：无 → 低，UI 先变（乐观），写回值 9
        guard let first = cycle() else {
            return XCTFail("无 → 低应给出写回计划")
        }
        fakeWrite(first)
        XCTAssertEqual(first.priority, .low)
        XCTAssertEqual(writes, [9])
        XCTAssertEqual(overlay.value(for: "a"), .low, "乐观更新：不等 EventKit 往返，显示值立刻是新档位")

        // ② 同一个目标再要一次（同级）→ nil：不写、也不动 UI
        XCTAssertNil(overlay.beginWrite("a", to: .low), "同级重复请求不产生第二次写回")
        XCTAssertEqual(writes.count, 1, "写回次数没有增加")

        // 主链路继续：低 → 中 → 高 → 无，每步各写一次（5 / 1 / 0）
        var visited: [TodoPriority] = []
        for _ in 0..<3 {
            guard let step = cycle() else {
                return XCTFail("循环途中不应出现同级请求")
            }
            visited.append(step.priority)
            fakeWrite(step)
            // 写回成功后的口径与 `TodoStore.setPriority` 同序：乐观值转正 + 重取把真值写进 baseline
            overlay.confirm("a")
            overlay.rebuild(from: ["a": step.priority])
        }
        XCTAssertEqual(visited, [.medium, .high, .none], "低 → 中 → 高 → 无")
        XCTAssertEqual(writes, [9, 5, 1, 0], "四步循环各写一次，值取每档区间的端点")

        // ③ 写回失败：先乐观（UI 已经变了），`rollback` 后回到真值
        guard let failing = cycle() else {
            return XCTFail("无 → 低应给出写回计划")
        }
        XCTAssertEqual(failing.eventKitValue, 9)
        XCTAssertEqual(overlay.value(for: "a"), .low, "乐观更新已经生效（此刻 UI 是低）")
        overlay.rollback("a")   // 写回返回 false → TodoStore 走这一句
        XCTAssertEqual(overlay.value(for: "a"), .none, "回滚到 baseline（读回的真值），不停在错误值")
        XCTAssertEqual(writes.count, 4, "失败的写回没记账（这一轮根本没调假写回器）")

        // 重取不冲掉"写回在飞"的乐观值：rebuild 只重建 baseline
        guard let inFlight = cycle() else {
            return XCTFail("无 → 低应给出写回计划")
        }
        overlay.rebuild(from: ["a": .none, "b": .high])
        XCTAssertEqual(overlay.value(for: "a"), inFlight.priority, "写回在飞时，一次重取不得抹掉乐观值")
        XCTAssertEqual(overlay.value(for: "b"), .high, "没点过的条目按读回的真值")
    }

    // MARK: - 待办优先级的**整条写回链**（P1 / T2 复审修 2：经 `TodoStore(writePriority:)` 接缝）

    /// 用例共用的假写回器：按 id 记账（EventKit 值），结果由参数决定。
    ///
    /// **不碰提醒库**：这组用例只经接缝驱动 `TodoStore` 的生产写回逻辑，
    /// 唯一会读到系统提醒的地方是失败路径末尾的那次只读 `refresh()`（不写任何数据）。
    @MainActor
    private final class FakePriorityWriter {
        private(set) var writes: [(id: String, eventKitValue: Int)] = []
        /// 返回给 `cyclePriority` / `setPriority` 的结果。
        var succeeds = true

        func write(reminderID: String, eventKitValue: Int) -> Bool {
            writes.append((reminderID, eventKitValue))
            return succeeds
        }

        var values: [Int] { writes.map(\.eventKitValue) }
    }

    /// 构造一个**不依赖本机 TCC** 的 store：授权读数注入 `.fullAccess`，写回走注入的假体。
    @MainActor
    private func todoStore(writer: FakePriorityWriter) -> TodoStore {
        TodoStore(
            logger: ModuleLogger(moduleID: "com.cmeng.gourd.todos", shortID: "todos"),
            writePriority: { reminderID, eventKitValue in
                writer.write(reminderID: reminderID, eventKitValue: eventKitValue)
            },
            authorizationStatus: { .fullAccess }
        )
    }

    /// **写回失败 → 回滚**（复审修 2）：注入「总是失败」的写回，经**生产的** `cyclePriority` 驱动——
    /// 乐观值先挂上（写回时看得见）、失败后被撤掉（显示值退回真值），并且失败**不静默**。
    ///
    /// 断言里带「写回被调用时的显示值」，正是为了钉住"乐观更新先于写回"这条口径：
    /// 写回执行时 `priority(for:)` 已经是新档位，而不是等 EventKit 往返之后才变。
    func testTodoStorePriorityRollsBackWhenWriteBackFails() async {
        let writer = FakePriorityWriter()
        writer.succeeds = false
        let item = TodoBucketing.Item(id: "t2-rollback", title: "回滚用例")
        /// 写回**开始那一刻**的显示值——"乐观更新先于写回"的直接证据。
        var displayedWhenWriteStarts: TodoPriority?
        var store: TodoStore?

        let created = TodoStore(
            logger: ModuleLogger(moduleID: "com.cmeng.gourd.todos", shortID: "todos"),
            writePriority: { reminderID, eventKitValue in
                displayedWhenWriteStarts = store?.priority(for: reminderID)
                return writer.write(reminderID: reminderID, eventKitValue: eventKitValue)
            },
            authorizationStatus: { .fullAccess }
        )
        store = created

        let ok = await created.cyclePriority(item)

        XCTAssertEqual(
            displayedWhenWriteStarts,
            .low,
            "写回开始那一刻显示值已经是新档位：乐观更新在写回之前就提交了"
        )
        XCTAssertFalse(ok, "写回失败 → cyclePriority 返回 false")
        XCTAssertEqual(writer.values, [9], "确实调了一次写回（无 → 低 = EventKit 9）")
        XCTAssertEqual(writer.writes.first?.id, item.id, "写的是这条待办")
        XCTAssertEqual(created.priority(for: item.id), .none, "回滚：乐观值被撤掉，显示值退回真值（无）")
        XCTAssertNotNil(created.writeFailure, "失败不静默：面板那一行「写入系统提醒失败」有值")
    }

    /// **同级不重复写回**（复审修 2）：同一个档位连要两次，只有第一次落到写回；
    /// 第二次直接 false、UI 不动（幂等）。换一档是真写回（对照：闸门没把一切都挡住）。
    func testTodoStorePriorityWritesOncePerTier() async {
        let writer = FakePriorityWriter()
        let store = todoStore(writer: writer)
        let item = TodoBucketing.Item(id: "t2-idempotent", title: "同级用例")

        // `XCTAssert*` 的表达式参数是 autoclosure（不支持 async）——先 await 到局部量再断言
        let firstWrite = await store.setPriority(item, to: .low)
        XCTAssertTrue(firstWrite, "第一次：写到低")
        XCTAssertEqual(writer.values, [9], "写回一次（低 = EventKit 9）")
        XCTAssertEqual(store.priority(for: item.id), .low, "成功 → 乐观值转正，显示值停在低")

        let sameTierAgain = await store.setPriority(item, to: .low)
        XCTAssertFalse(sameTierAgain, "同级再要一次：不写回")
        XCTAssertEqual(writer.values, [9], "写回次数没有增加（同级不产生第二次写回）")
        XCTAssertEqual(store.priority(for: item.id), .low, "同级请求也不动 UI")

        let changedTier = await store.setPriority(item, to: .high)
        XCTAssertTrue(changedTier, "换一档：真写回")
        XCTAssertEqual(writer.values, [9, 1], "高 = EventKit 1")
        XCTAssertEqual(store.priority(for: item.id), .high, "显示值跟进新高档")

        let sameHighAgain = await store.setPriority(item, to: .high)
        XCTAssertFalse(sameHighAgain, "再做一次同级请求（高档）：同样不写")
        XCTAssertEqual(writer.values, [9, 1], "仍然是两次写回")
    }

    /// 看板与徽标**同源**（控制器裁决 4：视图里不另写过滤）：左导航四个徽标数 =
    /// `TodoBucketing.items(in:...)` 的条数；固定数据 + 固定「今天」钉住四个数。
    func testTodoViewCountsMatchListedItems() throws {
        let calendar = try fixedGregorian()
        let now = try instant(2026, 9, 28, 10, calendar: calendar)
        let items = [
            todo("today-open", due: try instant(2026, 9, 28, 9, calendar: calendar)),
            todo(
                "today-done",
                due: try instant(2026, 9, 28, 8, calendar: calendar),
                completed: true,
                completedAt: try instant(2026, 9, 28, 9, calendar: calendar)
            ),
            todo("tomorrow-open", due: try instant(2026, 9, 29, 9, calendar: calendar)),
            todo("day6-open", due: try instant(2026, 10, 4, 9, calendar: calendar)),
            todo("day7-open", due: try instant(2026, 10, 5, 9, calendar: calendar)),
            todo("no-due-open", list: "收集箱"),
            todo(
                "overdue-done",
                due: try instant(2026, 9, 20, 9, calendar: calendar),
                completed: true,
                completedAt: try instant(2026, 9, 20, 10, calendar: calendar)
            ),
        ]

        let counts = TodoViewSource.counts(from: items, now: now, calendar: calendar)
        XCTAssertEqual(counts[.today], 1, "今天 = 今天到期且未完成")
        XCTAssertEqual(counts[.next7Days], 3, "最近 7 天 = [今天, 今天+7 天) 内未完成（含今天）")
        XCTAssertEqual(counts[.all], 5, "清单 = 全部未完成（含无到期日的）")
        XCTAssertEqual(counts[.completed], 2, "已完成 = 全部已完成（不论日期）")

        for view in TodoBucketing.TodoViewKind.allCases {
            let listed = TodoViewSource.items(in: view, from: items, now: now, calendar: calendar)
            XCTAssertEqual(counts[view], listed.count, "\(view) 的徽标数必须等于看板条数")
        }
        XCTAssertEqual(
            (counts[.all] ?? 0) + (counts[.completed] ?? 0),
            items.count,
            "「清单（未完成）」与「已完成」互补且覆盖全集"
        )

        // 空表：四个徽标都是 0、四个视图都空（不崩）
        let emptyCounts = TodoViewSource.counts(from: [], now: now, calendar: calendar)
        XCTAssertEqual(emptyCounts.count, TodoBucketing.TodoViewKind.allCases.count)
        for view in TodoBucketing.TodoViewKind.allCases {
            XCTAssertEqual(emptyCounts[view], 0)
            XCTAssertTrue(TodoViewSource.items(in: view, from: [], now: now, calendar: calendar).isEmpty)
        }
    }

    /// 四视图的**外壳词汇表**（左导航的文案 key / 图标、看板的空态 key）与左导航的高度预算：
    /// key 由 `rawValue` 派生；四项图标互不相同；4 项（26pt + 4pt 间距）放进默认面板可用高度。
    func testTodoViewChromeVocabularyAndNavBudget() {
        let views = TodoBucketing.TodoViewKind.allCases
        XCTAssertEqual(views.map { TodoViewChrome.labelKey(for: $0) }, [
            "module.todos.view.today", "module.todos.view.next7Days",
            "module.todos.view.all", "module.todos.view.completed",
        ])
        XCTAssertEqual(
            views.map { TodoViewChrome.symbolName(for: $0) },
            ["sun.max", "calendar", "tray.full", "checkmark.circle"]
        )
        XCTAssertEqual(
            Set(views.map { TodoViewChrome.symbolName(for: $0) }).count,
            views.count,
            "左导航四项的图标必须互不相同"
        )

        XCTAssertEqual(TodoViewChrome.emptyKey(for: .completed), "module.todos.completedEmpty")
        for view in [TodoBucketing.TodoViewKind.today, .next7Days, .all] {
            XCTAssertEqual(TodoViewChrome.emptyKey(for: view), "module.todos.empty", "非「已完成」档沿用既有空态文案")
        }

        let navHeight = TodoViewNavLayout.itemHeight * 4 + TodoViewNavLayout.itemSpacing * 3
        XCTAssertLessThanOrEqual(navHeight, 180, "默认面板可用高度（约 180pt）要放得下四项导航")
        XCTAssertGreaterThanOrEqual(
            TodoViewNavLayout.columnWidth,
            150,
            "列宽要容纳最长的标签「已完成（近 7 天）」（复审修 3 把 7 天窗口写进文案后变长）"
        )
    }

    /// 行内日期的显示口径（控制器裁决 2）：到期在**今天** → `.today`（走本地化文案）；
    /// 其余有到期日 → `M/D`（不补前导零、不带时刻）；**无到期日 → nil**（该行不显示日期）。
    func testTodoDueLabelFormat() throws {
        let calendar = try fixedGregorian()
        let now = try instant(2026, 9, 28, 10, calendar: calendar)

        XCTAssertNil(TodoDueLabel.label(for: todo("no-due"), now: now, calendar: calendar), "无到期日不显示日期")
        XCTAssertEqual(
            TodoDueLabel.label(
                for: todo("today", due: try instant(2026, 9, 28, 0, calendar: calendar)),
                now: now,
                calendar: calendar
            ),
            .today,
            "今天 00:00 到期 → 「今天」"
        )
        XCTAssertEqual(
            TodoDueLabel.label(
                for: todo("today-late", due: try instant(2026, 9, 28, 23, 59, calendar: calendar)),
                now: now,
                calendar: calendar
            ),
            .today,
            "今天 23:59 到期同样是「今天」（按自然日判，不按时刻）"
        )
        XCTAssertEqual(
            TodoDueLabel.label(
                for: todo("next-month", due: try instant(2026, 10, 5, 9, calendar: calendar)),
                now: now,
                calendar: calendar
            ),
            .day("10/5"),
            "M/D，不补前导零、不带时刻"
        )
        XCTAssertEqual(
            TodoDueLabel.label(
                for: todo("overdue", due: try instant(2026, 9, 7, 9, calendar: calendar)),
                now: now,
                calendar: calendar
            ),
            .day("9/7"),
            "已过期条目照样是 M/D（过期红字是另一段，不混进日期文本）"
        )
    }

    // MARK: - 通知上岛 notifications（P2c：探针 + 表）

    /// `NotificationText.relativeParts` 的分档边界（09 §5.5 的列表形态「3 分钟前」）：
    /// `< 1 分钟` / `59 分钟` / `1 小时` / `23 小时` / `1 天`，外加时钟回拨（未来时间）不得出负数。
    func testNotificationsRelativeTimeBoundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func parts(_ interval: TimeInterval) -> (key: String, value: Int) {
            NotificationText.relativeParts(since: now.addingTimeInterval(-interval), now: now)
        }

        XCTAssertEqual(parts(0).key, "module.notifications.justNow", "0 秒 = 刚刚")
        XCTAssertEqual(parts(0).value, 0)
        XCTAssertEqual(parts(59).key, "module.notifications.justNow", "59 秒未满 1 分钟，仍是「刚刚」")
        XCTAssertEqual(parts(60).key, "module.notifications.minutesAgo", "满 1 分钟进分钟档")
        XCTAssertEqual(parts(60).value, 1)
        XCTAssertEqual(parts(59 * 60).key, "module.notifications.minutesAgo", "59 分钟仍在分钟档")
        XCTAssertEqual(parts(59 * 60).value, 59)
        XCTAssertEqual(parts(3600).key, "module.notifications.hoursAgo", "满 1 小时进小时档")
        XCTAssertEqual(parts(3600).value, 1)
        XCTAssertEqual(parts(23 * 3600).key, "module.notifications.hoursAgo", "23 小时仍在小时档")
        XCTAssertEqual(parts(23 * 3600).value, 23)
        XCTAssertEqual(parts(24 * 3600).key, "module.notifications.daysAgo", "满 24 小时进天档")
        XCTAssertEqual(parts(24 * 3600).value, 1)
        XCTAssertEqual(parts(47 * 3600).value, 1, "47 小时向下取整仍是 1 天")
        XCTAssertEqual(parts(3 * 24 * 3600).value, 3)
        XCTAssertEqual(parts(-120).key, "module.notifications.justNow", "未来时间（时钟回拨）按「刚刚」，不出负数")
    }

    /// 相对时间的**成文**形态走本地化查表（`String(format:)` + `%d`）：查不到时 `Bundle` 原样返回 key，
    /// 且 `%d` 必须被替换掉——断言因此能抓住「key 漏编译」与「格式串写错」两类问题。
    func testNotificationsRelativeTimeTextIsLocalized() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let text = NotificationText.relative(now.addingTimeInterval(-3 * 60), now: now)
        XCTAssertFalse(text.contains("%d"), "格式串没被替换：\(text)")
        XCTAssertTrue(text.contains("3"), "应带上分钟数：\(text)")
        XCTAssertNotEqual(text, "module.notifications.minutesAgo", "key 没解析出文案")
    }

    /// `NotificationItem` 的字段拼装是**纯函数**：喂一个构造的二进制 plist（`req.titl` 等键）
    /// 应解出 title / subtitle / body / bundleIdentifier，缺省字段由调用方补。
    func testNotificationItemCompositionFromBinaryPlist() throws {
        let data = try Self.binaryPlist([
            "req": [
                "titl": "构建完成",
                "subt": "CI",
                "body": "全部任务通过",
                "cate": "",
                "app": "com.apple.Mail",
                "date": 800_000_000,
            ] as [String: Any],
        ])

        let payload = NotificationCenterReader.payload(fromRecord: data)
        XCTAssertEqual(payload.title, "构建完成")
        XCTAssertEqual(payload.subtitle, "CI")
        XCTAssertEqual(payload.body, "全部任务通过")
        XCTAssertEqual(payload.bundleIdentifier, "com.apple.Mail")
        XCTAssertTrue(payload.missingKeys.isEmpty, "键齐时不该报缺失：\(payload.missingKeys)")
        XCTAssertNil(payload.decodeError)

        let item = NotificationItem.make(recordID: 42, data: data, appName: "邮件")
        XCTAssertEqual(item.id, 42)
        XCTAssertEqual(item.bundleIdentifier, "com.apple.Mail")
        XCTAssertEqual(item.appName, "邮件")
        XCTAssertEqual(item.displayName, "邮件")
        XCTAssertEqual(item.title, "构建完成")
        XCTAssertEqual(item.subtitle, "CI")
        XCTAssertEqual(item.body, "全部任务通过")
        // plist 的时间是 Apple 纪元（2001）秒数：< 1e9 走 `timeIntervalSinceReferenceDate`
        XCTAssertEqual(item.deliveredDate, Date(timeIntervalSinceReferenceDate: 800_000_000))

        // 拿不到 `app` 表映射时退回 bundle id 的最后一段；两者都拿不到时留空串
        XCTAssertEqual(
            NotificationCenterReader.appDisplayName(bundleIdentifier: "com.apple.Mail", appMap: ["com.apple.Mail": "邮件"]),
            "邮件"
        )
        XCTAssertEqual(
            NotificationCenterReader.appDisplayName(bundleIdentifier: "com.apple.Mail", appMap: [:]),
            "Mail",
            "app 表取不到显示名时退回 bundle id 最后一段"
        )
        XCTAssertEqual(NotificationCenterReader.appDisplayName(bundleIdentifier: "", appMap: [:]), "")
        // 条目自身的兜底：appName 空 → 用 bundle id；两者都空 → `?`
        XCTAssertEqual(NotificationItem.make(recordID: 43, data: data).displayName, "com.apple.Mail")
        XCTAssertEqual(NotificationItem.make(recordID: 44, data: Data()).displayName, "?")
    }

    /// **防御式解码**（09 §5.5：schema 私有，Apple 改版即失效）：缺键给空并记录缺失键名、
    /// 垃圾字节 / 空 data 只记 `decodeError`，两种情形都**不许崩、不许抛错**。
    func testNotificationPayloadToleratesMissingKeysAndGarbage() throws {
        // 只有 titl：其余键全缺 → 空串 / nil + 可读的缺键清单（探针报告据此校准新键名）
        let partial = NotificationCenterReader.payload(fromRecord: try Self.binaryPlist([
            "req": ["titl": "只有标题"] as [String: Any],
        ]))
        XCTAssertEqual(partial.title, "只有标题")
        XCTAssertEqual(partial.body, "")
        XCTAssertNil(partial.subtitle)
        XCTAssertNil(partial.bundleIdentifier)
        XCTAssertNil(partial.decodeError)
        XCTAssertEqual(partial.missingKeys, ["subt", "body", "cate", "app", "date"])

        // 顶层直接给键（老格式没有 req 包一层）同样能解出
        let flat = NotificationCenterReader.payload(fromRecord: try Self.binaryPlist([
            "titl": "扁平标题",
            "body": "扁平正文",
        ]))
        XCTAssertEqual(flat.title, "扁平标题")
        XCTAssertEqual(flat.body, "扁平正文")

        // 非 plist 的垃圾字节：给空字段 + decodeError，不抛错
        let garbage = NotificationCenterReader.payload(fromRecord: Data([0x00, 0x01, 0x02]))
        XCTAssertEqual(garbage.title, "")
        XCTAssertEqual(garbage.body, "")
        XCTAssertNotNil(garbage.decodeError)
        XCTAssertEqual(garbage.missingKeys, ["titl", "subt", "body", "cate", "app", "date"])

        // 空 data（列是 NULL 或零长）
        let empty = NotificationCenterReader.payload(fromRecord: Data())
        XCTAssertEqual(empty.decodeError, "data 列为空")
        XCTAssertEqual(NotificationItem.make(recordID: 1, data: Data()).title, "")
    }

    /// `NotificationsModule.manifest` 的契约：id / surfaces / icon / placement / 默认启用 / 空权限 / 无配置；
    /// 并回走一次 JSON 路径（与宿主读 descriptor 同一条路）。
    func testNotificationsModuleManifestMatchesContract() throws {
        let manifest = NotificationsModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, "com.cmeng.gourd.notifications")
        XCTAssertEqual(manifest.shortID, "notifications")
        XCTAssertEqual(manifest.name.key, "module.notifications.name")
        XCTAssertEqual(manifest.summary?.key, "module.notifications.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "bell.badge"))
        XCTAssertEqual(manifest.kind, "builtin")
        // 顺序 + 内容都钉住：T1 起多一个 `.home`（首页 strip 的通知块），值的顺序即声明顺序
        XCTAssertEqual(manifest.surfaces, [.expanded, .compact, .home], "展开面板通知列表 + 折叠态未读数 + 首页块")
        XCTAssertTrue(manifest.surfaces.contains(.home), "首页块是 manifest 驱动的：通知组件必须声明 .home")
        XCTAssertEqual(manifest.defaultEnabled, true)
        XCTAssertEqual(manifest.defaultPlacement, Placement(slot: .center, order: 40))
        XCTAssertTrue(
            manifest.permissions.isEmpty,
            "06 §7.1 白名单里还没有 `notifications:read`（docs/14 标注「待落」）；完全磁盘访问是系统 TCC，不是模块 capability"
        )
        XCTAssertNil(manifest.config, "第一版不读配置")

        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// `module.notifications.*` 的 key 必须能从宿主 bundle 解析出文案（06 §3.3 R5 的 key 形态）。
    func testNotificationsLocalizationKeysResolve() {
        let keys = [
            "module.notifications.name",
            "module.notifications.summary",
            "module.notifications.empty",
            "module.notifications.needsFullDiskAccess",
            "module.notifications.openSettings",
            "module.notifications.recent",
            "module.notifications.justNow",
            "module.notifications.minutesAgo",
            "module.notifications.hoursAgo",
            "module.notifications.daysAgo",
            "module.notifications.capabilityHint",
            "module.notifications.newNotification",
            "module.notifications.clearAll",
            "module.notifications.dismiss",
            "module.notifications.closeSystemNotification",
            // 一次取数多条新通知时，浮层第二行末尾的计数后缀（浮层仍只展示最新一条）
            "module.notifications.moreCount",
            // 列表行 × 无句柄时的 .help / .accessibilityLabel（T2：有句柄才走 closeSystemNotification）
            "module.notifications.removeFromList",
        ]
        for key in keys {
            let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(localized, key, "\(key) 没解析出文案（catalog 未编进宿主 bundle？）")
            XCTAssertFalse(localized.isEmpty, "\(key) 解析为空串")
        }
    }

    /// **能力边界行的显示判据**（2026-10-08 用户反馈「通知的这个说明去掉，或者在上面简单描述」）：
    /// 只在**列表真有条目**时显示——空态里那行没有指代对象（用户截图就是空态那面文字墙），
    /// 权限引导 / 失败态各自的文案已经把「为什么没有列表」说清楚了，叠一行只会打架。
    ///
    /// 判据抽成纯函数（`showsNotificationCapabilityHint(state:itemCount:)`）就是为了这条用例能钉住
    /// 三个状态 × 有/无条目；视图只负责接上（与 `shouldShowScrollFadeMask` 同一条纪律）。
    func testNotificationCapabilityHintOnlyShowsWithRealItems() {
        XCTAssertFalse(
            showsNotificationCapabilityHint(state: .ok, itemCount: 0),
            "空态不显示（截图里那面文字墙就是它，用户要求去掉/上移）"
        )
        XCTAssertTrue(
            showsNotificationCapabilityHint(state: .ok, itemCount: 3),
            "有条目时显示（此时 × 与「滞后几秒」才有指代对象）"
        )
        XCTAssertFalse(
            showsNotificationCapabilityHint(state: .needsFullDiskAccess, itemCount: 3),
            "权限引导态不显示（那块自己的文案是主入口）"
        )
        XCTAssertFalse(
            showsNotificationCapabilityHint(state: .failure("库打不开"), itemCount: 3),
            "失败态不显示（原因行已经说明）"
        )
    }

    // MARK: - 通知首页块（T1：组件开关的可见效果）

    /// 通知组件声明 `.home`、激活后进首页块名单、`.home` 请求拿到 `.view`。
    ///
    /// 三条一起钉住「组件页里打开通知 → 首页真的多一块」这条链路的三段：
    /// manifest（声明）→ 注册表投影（名单）→ 内容转发（这块里画什么）。
    /// 与 todos 的同类用例同形（`Surfaces.contains(.home)` + `homeEntries` + `content(for:)`）。
    func testNotificationsModuleServesHomeBlock() async {
        // ① 声明：首页块名单的唯一来源是 manifest 的 surfaces
        XCTAssertTrue(
            NotificationsModule.manifest.surfaces.contains(.home),
            "通知组件必须声明 .home，否则首页块不会出现（T1 的验收前提）"
        )

        // ② 投影：激活后进块名单（按 order 升序：todos 20 → notifications 40）
        let registry = ModuleRegistry.shared
        let notificationsID = "com.cmeng.gourd.notifications"
        registerProbes([NotificationsModule.self])
        await registry.bootstrap()

        XCTAssertEqual(registry.homeEntries.map(\.id), [notificationsID], "声明 .home 的已激活模块应进块名单")
        XCTAssertEqual(registry.homeEntries.map(\.order), [40], "块顺序沿用 defaultPlacement.order")

        // ③ 内容：`.home` 请求答 `.view`（`.none` 意味着首页没有块——T1 的失败信号之一）
        if case .view = registry.content(for: notificationsID, request: ModuleRegistry.home) {
            // 预期分支
        } else {
            XCTFail("notifications 声明了 home，首页块内容应是 .view")
        }
    }

    /// 首页块的取舍与文案（纯函数）：**返回全部条目**（新的在前，不在这里重排；docs/40 D-01 起
    /// 不再裁到 6 条——`maxListRows` 只当**视口行数**，块高不变）、
    /// 两行式文案（第一行 App 名、第二行「标题 · 正文预览」，空串不留悬空分隔符、换行压成空格）、
    /// 标题行「通知 · 最近 N 条」（N == 0 只留模块名，不画空态文案）、
    /// 不可读 / 无权限时的那一行提示（可读给 nil——两种情形必须能区分开）。
    func testNotificationsHomeBlockLayoutLimitsRowsAndLabelsHeader() {
        XCTAssertEqual(
            NotificationsHomeBlockLayout.maxListRows, 6,
            "视口行数仍是 6（p13 / docs/38 D-11：4 → 6；docs/40 D-01 起只作视口行数，不再裁数据）"
        )
        XCTAssertEqual(
            NotificationsHomeBlockLayout.blockHeight,
            HomeBlockChrome.contentInsetTopText + 16 + 4 + 6 * 30 + 5 * 4,
            "申报的块高 = 内缩 5 + 表头 16 + 间距 4 + 视口 6 行 × 30 + 5 个条间距 4 = 225（不变）"
        )

        // 清单：**返回传入的全部条目，顺序原样**（docs/40 D-01：`store.items` 已是新的在前，
        // 第 7 条起不再被丢弃——全部进块内滚动区）
        let items = (1...7).map { notificationItem(Int64($0), title: "标题\($0)") }
        XCTAssertEqual(
            NotificationsHomeBlockLayout.listedItems(items).map(\.id),
            [1, 2, 3, 4, 5, 6, 7],
            "不再裁剪：7 条全返回，顺序与 store.items 一致（不在这里重排）"
        )
        XCTAssertTrue(NotificationsHomeBlockLayout.listedItems([]).isEmpty, "空列表给空（不画空态文案）")
        XCTAssertEqual(NotificationsHomeBlockLayout.listedItems(Array(items.prefix(2))).map(\.id), [1, 2], "不足视口行数时原样")

        // 第一行：App 名（App 名为空时退到标题，不留悬空分隔符）
        XCTAssertEqual(NotificationsHomeBlockLayout.sourceLabel(appName: "邮件", title: "构建完成"), "邮件")
        XCTAssertEqual(NotificationsHomeBlockLayout.sourceLabel(appName: "", title: "只有标题"), "只有标题")
        XCTAssertEqual(NotificationsHomeBlockLayout.sourceLabel(appName: "  ", title: "只有标题"), "只有标题")
        XCTAssertEqual(NotificationsHomeBlockLayout.sourceLabel(appName: "", title: ""), "", "两边都空给空串")

        // 第二行：标题 · 正文预览（docs/37 D-03 起正文可见）
        XCTAssertEqual(
            NotificationsHomeBlockLayout.detailLabel(title: "构建完成", body: "产物已上传"),
            "构建完成 · 产物已上传"
        )
        XCTAssertEqual(
            NotificationsHomeBlockLayout.detailLabel(title: "构建完成", body: "  "),
            "构建完成",
            "正文为空不留悬空分隔符"
        )
        XCTAssertEqual(
            NotificationsHomeBlockLayout.detailLabel(title: "", body: "只有正文"),
            "只有正文"
        )
        XCTAssertEqual(
            NotificationsHomeBlockLayout.detailLabel(title: "第一行\n第二行", body: "正文\n换行"),
            "第一行 第二行 · 正文 换行",
            "标题与正文里的换行都压成空格（第二行只有一行的预算）"
        )

        // 标题行：条数 > 0 → 「通知 · 最近 N 条」；== 0 → 只剩模块名（不画空态文案）
        let zero = NotificationText.homeHeader(shown: 0, total: 12)
        XCTAssertEqual(zero, NotificationText.localized("module.notifications.name"), "0 条时只显示「通知」")
        XCTAssertFalse(zero.contains("0"), "0 不显示成「最近 0 条」：\(zero)")
        let three = NotificationText.homeHeader(shown: 3, total: 3)
        let format = NotificationText.localized("module.notifications.homeRecent")
        XCTAssertNotEqual(format, "module.notifications.homeRecent", "首页块条数文案没解析出来（catalog 未编进宿主 bundle？）")
        XCTAssertEqual(
            three,
            NotificationText.localized("module.notifications.name") + " · " + String(format: format, 3),
            "条数走本地化格式串，拼在模块名之后（与展开 tab 的「最近 N 条」同一口径）"
        )
        XCTAssertTrue(three.contains("3"), "条数要出现在标题行：\(three)")

        // **块里画几条就说几条**（2026-10-11 修正）：列表总数多于块容量时，标题的后缀是**画出来的
        // 条数**（6），总数只作括注——改前这里收的是列表总数，标题与清单对不上（用户：
        // 「最近 40 条不对，这就显示 6 条」）。
        let capped = NotificationText.homeHeader(shown: 6, total: 40)
        XCTAssertTrue(capped.contains("6"), "画了 6 条就说 6 条：\(capped)")
        XCTAssertFalse(
            capped.contains(String(format: NotificationText.localized("module.notifications.homeRecent"), 40)),
            "不得把列表总数（40）说成「最近 N 条」：\(capped)"
        )
        XCTAssertTrue(
            capped.contains(String(format: NotificationText.localized("module.notifications.homeTotalMore"), 40)),
            "还有更多时补一句「共 M 条」：\(capped)"
        )
        XCTAssertEqual(
            NotificationText.homeHeader(shown: 6, total: 6),
            NotificationText.localized("module.notifications.name") + " · "
                + String(format: NotificationText.localized("module.notifications.homeRecent"), 6),
            "总数与画出来的条数相同时不加括注"
        )

        // 不可读 / 无权限的一行提示：可读给 nil（= 不画那一行），两个非 ok 分支各给一句本地化文案
        // ——这条钉住「取不到数据」与「可读但 0 条」在块上能区分开（审查发现 2）。
        XCTAssertNil(NotificationText.homeHint(.ok), "可读时不画提示行（0 条只留标题行）")
        let needsPermission = NotificationText.homeHint(.needsFullDiskAccess)
        XCTAssertEqual(needsPermission, NotificationText.localized("module.notifications.homeNeedsPermission"))
        XCTAssertNotEqual(needsPermission, "module.notifications.homeNeedsPermission", "无权限提示没解析出文案")
        let unreadable = NotificationText.homeHint(.failure("库文件不可访问"))
        XCTAssertEqual(unreadable, NotificationText.localized("module.notifications.homeUnreadable"))
        XCTAssertNotEqual(unreadable, "module.notifications.homeUnreadable", "不可读提示没解析出文案")
        XCTAssertNotEqual(needsPermission, unreadable, "无权限与取数失败是两件事，提示不能是同一句")
        XCTAssertNotEqual(
            unreadable,
            NotificationText.localized("module.notifications.name"),
            "不可读时不能退化成只显示模块名（那就与「0 条」同形了）"
        )
    }

    /// docs/40 D-01：`listedItems` **不裁剪**——不论传入多少条（含远超视口行数的 40 条），
    /// 全部按输入顺序返回；`maxListRows` 只作**视口行数**（块高算式沿用，不再拿它裁数据）。
    func testNotificationsHomeBlockLayoutListsEveryItemUncropped() {
        XCTAssertEqual(
            NotificationsHomeBlockLayout.maxListRows, 6,
            "视口行数仍是 6（块高算式 = 6 × 30 + 5 × 4 沿用；本断言钉住语义收窄后取值不变）"
        )

        // 40 条（远超视口 6 行）：全返回，顺序原样（id 递增＝新的在前）
        let many = (1...40).map { notificationItem(Int64($0), title: "标题\($0)") }
        let listed = NotificationsHomeBlockLayout.listedItems(many)
        XCTAssertEqual(
            listed.count, many.count,
            "全部已保留条目都要进滚动区（不再 prefix(maxListRows) 砍到 6 条）"
        )
        XCTAssertEqual(
            listed.map(\.id), many.map(\.id),
            "顺序原样＝store.items 的顺序（新的在前，不在这里重排）"
        )

        // 10 条（> 视口 6 行）同样全量：一条不少、顺序不变
        let ten = (1...10).map { notificationItem(Int64($0), title: "标题\($0)") }
        XCTAssertEqual(
            NotificationsHomeBlockLayout.listedItems(ten).map(\.id), Array(1...10),
            "10 条全量返回（第 7 条起不再不可达）"
        )
    }

    /// 首页块表头「清除」入口的**显示条件纯函数**（docs/42 D-02）：**列表非空才显示**
    /// ——判据与展开面板 header 的 `!store.items.isEmpty` 同口径（两处语义逐字一致）。
    func testNotificationsHomeBlockClearActionShowsOnlyWhenListNonEmpty() {
        XCTAssertFalse(NotificationsHomeBlockLayout.showsClearAction(itemCount: 0), "0 条不显示（空列表上无效按钮只会让人以为坏了）")
        XCTAssertFalse(NotificationsHomeBlockLayout.showsClearAction(itemCount: -1), "负数（防御式输入）也当空")
        XCTAssertTrue(NotificationsHomeBlockLayout.showsClearAction(itemCount: 1), "1 条就显示")
        XCTAssertTrue(NotificationsHomeBlockLayout.showsClearAction(itemCount: 40), "满列表（读取上限）显示")

        // 逐档钉住「与面板同一判据」：`!store.items.isEmpty` ≡ `itemCount > 0`
        for count in [0, 1, 2, 7, 40] {
            XCTAssertEqual(
                NotificationsHomeBlockLayout.showsClearAction(itemCount: count),
                count > 0,
                "必须与面板 header 的 `!store.items.isEmpty` 同口径：count=\(count)"
            )
        }
    }

    /// **首页「清除」复用的是面板同一个 `dismissAll()`**（docs/42 D-01/D-02）：**只从岛上移除**——
    /// 列表清空、把这批 id 追加进已关闭集合并落盘，而**通知库里的记录一条不动**
    /// （库里仍在 → 说明既没有删库记录、也没有走 AX 真关；`dismissAll` 压根不碰台账）。
    ///
    /// 夹具是临时目录里现造的一张通知库（`record(rec_id, data, delivered_date)`），
    /// **不碰系统通知库**（与 `testNotificationReaderModificationDateTracksWALSibling` 同一纪律）；
    /// 偏好卫生：先备份 `dismissedNotificationIDs`、结束时原样恢复（与
    /// `testNotificationListRowClosePredicateFollowsCloseHandleWindow` 同款），不给开发机的真实域留键。
    @MainActor
    func testNotificationDismissAllClearsLocalListAndPersistsWithoutTouchingDatabase() async throws {
        let dismissedKey = Defaults.Keys.dismissedNotificationIDs.name
        let savedDismissed = UserDefaults.standard.object(forKey: dismissedKey)
        defer {
            if let savedDismissed {
                UserDefaults.standard.set(savedDismissed, forKey: dismissedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: dismissedKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: dismissedKey)  // 从「没有已关闭条目」这一档起跑

        let database = try Self.makeNotificationDatabase(records: [
            (id: 11, title: "构建完成", body: "产物已上传"),
            (id: 12, title: "新邮件", body: "来自张三"),
            (id: 13, title: "日历", body: "10:00 站会"),
        ])
        defer { try? FileManager.default.removeItem(at: database.deletingLastPathComponent()) }

        let store = NotificationStore(
            logger: ModuleLogger(moduleID: "com.cmeng.gourd.notifications", shortID: "notifications"),
            reader: NotificationCenterReader(databasePath: database.path)
        )

        // 起跑：全量取数把三条装进列表（新的在前）——夹具自身的前提
        await store.refreshAll()
        XCTAssertEqual(store.state, .ok, "临时库要能读到（否则下面几条都在空调上断言）")
        XCTAssertEqual(store.items.map(\.id), [13, 12, 11], "三条全在列表里（新的在前）")
        XCTAssertTrue(store.dismissedRecordIDs.isEmpty, "起跑没有已关闭条目")
        XCTAssertTrue(
            NotificationsHomeBlockLayout.showsClearAction(itemCount: store.items.count),
            "列表非空 → 首页块的「清除」该出现"
        )

        // 点「清除」（首页块与面板调的是同一个方法）
        store.dismissAll()

        // ① 只从岛上移除：列表清空、这批 id 进已关闭集合并落盘
        XCTAssertTrue(store.items.isEmpty, "列表清空")
        XCTAssertEqual(store.dismissedRecordIDs, Set([11, 12, 13]), "三条都记进已关闭集合")
        XCTAssertFalse(
            NotificationsHomeBlockLayout.showsClearAction(itemCount: store.items.count),
            "清空后按钮该收起"
        )
        XCTAssertEqual(
            Defaults[.dismissedNotificationIDs].sorted(), [11, 12, 13],
            "已关闭 id 落盘（`persistDismissed` 写回）"
        )

        // ② 系统通知中心一条不动：**库里的记录仍在**（没删记录、没真关）
        let liveness = NotificationCenterReader(databasePath: database.path)
        XCTAssertEqual(
            liveness.fetchRecent(limit: 40).map(\.id).sorted(), [11, 12, 13],
            "清除不动通知库：记录一条不少（`dismissAll` 不写库、不走 AX 真关）"
        )

        // ③ 已关闭集被读取层用来过滤：再取一次数 → 列表仍为空（id 真的被持久化并生效）
        await store.refreshAll()
        XCTAssertTrue(store.items.isEmpty, "已关闭 id 生效：取数后列表仍是空的（不是把库清掉了才空）")
    }

    // MARK: - 已关闭集合的水位线自愈（P16 T2 / docs/42 §做法 ②、D-03）

    /// 水位线判定**纯函数**的四个边界（docs/42 §验收标准）：`databaseMax <= 0` → 保持原水位线
    /// （**库为空 / 读不到绝不重置**）、相等 → 保持、前进 → 推进、回退（且 > 0）→ 重置。
    ///
    /// 纯函数因此**不碰通知库、不碰存储**：单测只喂两个整数，不新增查询也不读库。
    func testNotificationDismissalPolicyReconcileBoundaries() {
        // ① 库为空 / 读不到（databaseMax 0 或负数）：保持、**不重置**——读失败不是回退证据
        XCTAssertEqual(
            NotificationDismissalPolicy.reconcile(watermark: 0, databaseMax: 0),
            .keep(newWatermark: 0),
            "水位线 0 + 库为空 0：什么都不做（首次启动前那一档）"
        )
        XCTAssertEqual(
            NotificationDismissalPolicy.reconcile(watermark: 294, databaseMax: 0),
            .keep(newWatermark: 294),
            "库为空 / 读不到时**绝不重置**（宁可漏一次也不误清）"
        )
        XCTAssertEqual(
            NotificationDismissalPolicy.reconcile(watermark: 294, databaseMax: -1),
            .keep(newWatermark: 294),
            "负数（防御式输入）与 0 同档：当空库处理"
        )

        // ② 前进：水位线推进到库最大号（水位线 0 + 有记录 = 首次建水位线）
        XCTAssertEqual(
            NotificationDismissalPolicy.reconcile(watermark: 0, databaseMax: 13),
            .keep(newWatermark: 13),
            "水位线 0 + 库最大号 13：只推进，不重置（首启这一档）"
        )
        XCTAssertEqual(
            NotificationDismissalPolicy.reconcile(watermark: 13, databaseMax: 27),
            .keep(newWatermark: 27),
            "库最大号前进 → 水位线跟着推进"
        )

        // ③ 相等：保持原值（不动集合，也不多写一次盘）
        XCTAssertEqual(
            NotificationDismissalPolicy.reconcile(watermark: 13, databaseMax: 13),
            .keep(newWatermark: 13),
            "相等（库里没有新记录）：水位线原地不动"
        )

        // ④ 回退（且 > 0）：编号倒退 = 库被重建 → 重置
        XCTAssertEqual(
            NotificationDismissalPolicy.reconcile(watermark: 13, databaseMax: 12),
            .resetDatabaseRolledOver,
            "库最大号 12 < 水位线 13（只差一号）：回退必须被认出来，不能按「前进」处理"
        )
        XCTAssertEqual(
            NotificationDismissalPolicy.reconcile(watermark: 294, databaseMax: 3),
            .resetDatabaseRolledOver,
            "2026-10-12 本机实况那一档：水位线 294、重建后库最大号 3"
        )
    }

    /// **回退才清空集合**——在真存储侧跑（夹具是临时目录里现造的库，**不碰系统通知库**）：
    ///
    /// 1. 全量刷新把水位线从 0 推到库最大号（13），`dismissAll()` 把三条记进已关闭集合并落盘；
    /// 2. 把库里那一号记录删掉（库最大号 13 → 12，**模拟库被重建、编号回退**）：下一次
    ///    `refreshAll()` 判定回退 → 内存两处已关闭状态清空 + 空集合落盘 + 水位线落到 12；
    /// 3. **再刷新一次列表就自己回来了**（集合清了，过滤条件不再命中）——这才是"自愈"的观测量；
    /// 4. 反过来，库不动的刷新（相等档）**集合一条不少**：不误清。
    ///
    /// 偏好卫生：备份 `dismissedNotificationIDs` 与新增的 `notificationsRecordIDWatermark` 两个键，
    /// 结束时按"原来有没有"原样恢复（与 `testNotificationDismissAll…` 同款）。
    @MainActor
    func testNotificationDismissedSetHealsOnRecordIDRolloverButNotOnStableDatabase() async throws {
        let dismissedKey = Defaults.Keys.dismissedNotificationIDs.name
        let watermarkKey = Defaults.Keys.notificationsRecordIDWatermark.name
        let savedDismissed = UserDefaults.standard.object(forKey: dismissedKey)
        let savedWatermark = UserDefaults.standard.object(forKey: watermarkKey)
        defer {
            for (key, saved) in [(dismissedKey, savedDismissed), (watermarkKey, savedWatermark)] {
                if let saved {
                    UserDefaults.standard.set(saved, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        UserDefaults.standard.removeObject(forKey: dismissedKey)
        UserDefaults.standard.removeObject(forKey: watermarkKey)

        let database = try Self.makeNotificationDatabase(records: [
            (id: 11, title: "构建完成", body: "产物已上传"),
            (id: 12, title: "新邮件", body: "来自张三"),
            (id: 13, title: "日历", body: "10:00 站会"),
        ])
        defer { try? FileManager.default.removeItem(at: database.deletingLastPathComponent()) }

        let store = NotificationStore(
            logger: ModuleLogger(moduleID: "com.cmeng.gourd.notifications", shortID: "notifications"),
            reader: NotificationCenterReader(databasePath: database.path)
        )

        // 1. 起跑：全量刷新把水位线推到库最大号（**无记录 → 只推进，绝不清空**）
        await store.refreshAll()
        XCTAssertEqual(store.items.map(\.id), [13, 12, 11], "三条进列表")
        XCTAssertEqual(
            Defaults[.notificationsRecordIDWatermark], 13,
            "水位线从 0 推进到库最大号 13（本键只在刷新后写）"
        )
        store.dismissAll()
        XCTAssertEqual(store.dismissedRecordIDs, Set([11, 12, 13]), "清除把三条记进已关闭集合")
        XCTAssertEqual(Defaults[.dismissedNotificationIDs].sorted(), [11, 12, 13], "并落盘")

        // 2. 库被重建：最大号回退（13 → 12），下一次全量刷新必须判定回退并自愈
        try Self.execNotificationDatabase(at: database, sql: "DELETE FROM record WHERE rec_id >= 13")
        await store.refreshAll()
        XCTAssertTrue(
            store.dismissedRecordIDs.isEmpty,
            "编号回退 → 清空内存已关闭集合（旧高位 id 从此不再撞新通知）"
        )
        XCTAssertTrue(Defaults[.dismissedNotificationIDs].isEmpty, "空集合落盘（`persistDismissed` 写回）")
        XCTAssertEqual(Defaults[.notificationsRecordIDWatermark], 12, "水位线落到重建后的库最大号 12")

        // 3. 自愈的观测量：再刷新一次，被挡掉的记录自己回到列表（集合清空后过滤不再命中）
        await store.refreshAll()
        XCTAssertEqual(store.items.map(\.id), [12, 11], "自愈后列表恢复（不是把库清掉了才变空/变满）")

        // 4. 反向：库不动的刷新（相等档）——集合一条不少，水位线原地不动（不误清）
        store.dismissAll()
        XCTAssertEqual(store.dismissedRecordIDs, Set([12, 11]), "先重新关闭这两条")
        await store.refreshAll()
        XCTAssertEqual(
            store.dismissedRecordIDs, Set([12, 11]),
            "库最大号（12）与水位线（12）相等 → 保持：已关闭集合一条不少"
        )
        XCTAssertEqual(Defaults[.dismissedNotificationIDs].sorted(), [11, 12], "落盘值也不受刷新影响")
        XCTAssertEqual(Defaults[.notificationsRecordIDWatermark], 12, "水位线原地不动")

        // 5. 库里的记录仍原样在（自愈**只动本应用的设置键**，通知库只读）
        XCTAssertEqual(
            NotificationCenterReader(databasePath: database.path).fetchRecent(limit: 40).map(\.id).sorted(),
            [11, 12],
            "自愈不写通知库：剩下的记录一条不少"
        )
    }

    /// **增量 / 兜底轮询路径也要判水位线**（P16 T2 补口）：回退可能**只在两次全量刷新之间**被读到——
    /// 库被重建后编号正从低位爬升，此刻 `rec_id > 基线` 必然为空（`refreshIncremental` 走早退），
    /// 而这正是**唯一**能观察到「库最大号 < 水位线」的窗口。判定因此必须在早退前、在增量路径上跑一次。
    ///
    /// 夹具同 `testNotificationDismissedSetHealsOnRecordIDRollover…`：临时目录现造的库，**不碰系统通知库**。
    /// 用 `pollOnce()`（60s 兜底轮询）驱动增量路径——它直接调 `refreshIncremental`，不需要文件事件。
    ///
    /// 偏好卫生：备份 / 恢复 `dismissedNotificationIDs` 与 `notificationsRecordIDWatermark` 两个键。
    @MainActor
    func testNotificationDismissedSetHealsOnRolloverViaIncrementalPath() async throws {
        let dismissedKey = Defaults.Keys.dismissedNotificationIDs.name
        let watermarkKey = Defaults.Keys.notificationsRecordIDWatermark.name
        let savedDismissed = UserDefaults.standard.object(forKey: dismissedKey)
        let savedWatermark = UserDefaults.standard.object(forKey: watermarkKey)
        defer {
            for (key, saved) in [(dismissedKey, savedDismissed), (watermarkKey, savedWatermark)] {
                if let saved {
                    UserDefaults.standard.set(saved, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        UserDefaults.standard.removeObject(forKey: dismissedKey)
        UserDefaults.standard.removeObject(forKey: watermarkKey)

        let database = try Self.makeNotificationDatabase(records: [
            (id: 11, title: "构建完成", body: "产物已上传"),
            (id: 12, title: "新邮件", body: "来自张三"),
            (id: 13, title: "日历", body: "10:00 站会"),
        ])
        defer { try? FileManager.default.removeItem(at: database.deletingLastPathComponent()) }

        let store = NotificationStore(
            logger: ModuleLogger(moduleID: "com.cmeng.gourd.notifications", shortID: "notifications"),
            reader: NotificationCenterReader(databasePath: database.path)
        )

        // 1. 起跑：全量刷新建基线 / 水位线，再「清除全部」
        await store.refreshAll()
        XCTAssertEqual(Defaults[.notificationsRecordIDWatermark], 13, "水位线推到库最大号 13")
        store.dismissAll()
        XCTAssertEqual(store.dismissedRecordIDs, Set([11, 12, 13]), "三条都进已关闭集合")

        // 2. 库被重建：最大号 13 → 12（集合里 11/12/13 都是旧高位 id）
        try Self.execNotificationDatabase(at: database, sql: "DELETE FROM record WHERE rec_id >= 13")

        // 3. 增量路径（兜底轮询）：`rec_id > 基线(13)` 为空 → 早退；判定必须在早退前跑，才看得到回退
        await store.pollOnce()
        XCTAssertTrue(
            store.dismissedRecordIDs.isEmpty,
            "增量读取也要判回退并自愈（不是只在 refreshAll 里）——否则回退在两次全量刷新之间被漏掉"
        )
        XCTAssertTrue(Defaults[.dismissedNotificationIDs].isEmpty, "空集合落盘（`persistDismissed` 写回）")
        XCTAssertEqual(Defaults[.notificationsRecordIDWatermark], 12, "水位线落到重建后的库最大号")

        // 4. 自愈观测量：下一次全量刷新把记录恢复出来
        await store.refreshAll()
        XCTAssertEqual(store.items.map(\.id), [12, 11], "自愈后列表恢复")

        // 5. 反向：库不动的增量读取（相等档）**不误清**
        store.dismissAll()
        XCTAssertEqual(store.dismissedRecordIDs, Set([12, 11]), "先重新关闭这两条")
        await store.pollOnce()
        XCTAssertEqual(
            store.dismissedRecordIDs, Set([12, 11]),
            "库最大号（12）== 水位线（12）→ 保持：增量路径也不误清"
        )
        XCTAssertEqual(Defaults[.notificationsRecordIDWatermark], 12, "水位线原地不动")

        // 6. 读失败也走同一条增量路径：`databaseMax <= 0` → 纯函数 `.keep`，**绝不重置**
        //    （reader 指向不存在的路径；`handleDatabaseChange` 不过 mtime 闸门，能直接进增量）
        let unreadable = Self.notificationStoreFixture()
        XCTAssertEqual(unreadable.dismissedRecordIDs, Set([12, 11]), "从落盘的已关闭集合起跑")
        await unreadable.handleDatabaseChange()
        XCTAssertEqual(
            unreadable.dismissedRecordIDs, Set([12, 11]),
            "读失败 → 集合一条不少（guard：`databaseMax <= 0` 给 `.keep`）"
        )
        XCTAssertEqual(Defaults[.notificationsRecordIDWatermark], 12, "读失败也不动水位线")
    }

    // MARK: - 通知浮层（P2d：基线 + 正文口径）

    /// 浮层候选是**纯函数**：只有 `rec_id > 基线` 的条目才可能触发，且多条时只取**最新一条**。
    ///
    /// 这条钉住「首次 activate 建基线」的语义——激活前就在库里的通知（≤ 基线）永远不弹浮层，
    /// 一次轮询进来一串新通知也不刷屏（其余只进未读计数）。
    func testNotificationHUDCandidateFiltersByBaseline() {
        // 激活前已存在（≤ 基线）→ 不弹
        XCTAssertNil(NotificationStore.hudCandidate(in: [], above: 10), "空集合没有候选")
        XCTAssertNil(
            NotificationStore.hudCandidate(in: [notificationItem(3), notificationItem(9), notificationItem(10)], above: 10),
            "等于基线的也不算新增（SQL 侧是 `rec_id > 基线`，此处必须同口径）"
        )

        // 严格大于基线才入选
        XCTAssertEqual(NotificationStore.hudCandidate(in: [notificationItem(10), notificationItem(11)], above: 10)?.id, 11)

        // 多条新通知只弹最新那一条（与到达顺序无关，按 id 取最大）
        XCTAssertEqual(
            NotificationStore.hudCandidate(
                in: [notificationItem(12), notificationItem(11), notificationItem(15), notificationItem(13)],
                above: 10
            )?.id,
            15,
            "一次轮询有多条新增时只弹最新一条"
        )

        // 基线与新记录混在一起：老的一条不得顶掉新的
        XCTAssertEqual(
            NotificationStore.hudCandidate(in: [notificationItem(2), notificationItem(7), notificationItem(8)], above: 6)?.id,
            8
        )
    }

    /// `showBodyInHUD` 的呈现口径（纯函数）：**默认为 true = 浮层显示正文**；
    /// 关掉后浮层第二行只剩「新通知」，正文一个字都不进浮层。
    func testNotificationHUDDetailHonorsShowBodyFlag() {
        let newNotification = NotificationText.localized("module.notifications.newNotification")
        XCTAssertNotEqual(newNotification, "module.notifications.newNotification", "新通知文案没解析出来")

        // 默认（true）：标题 + 正文
        XCTAssertEqual(
            NotificationText.hudDetail(title: "构建完成", body: "全部任务通过", showsBody: true),
            "构建完成 · 全部任务通过"
        )
        // 关掉：正文不进浮层
        let hidden = NotificationText.hudDetail(title: "构建完成", body: "全部任务通过", showsBody: false)
        XCTAssertEqual(hidden, newNotification)
        XCTAssertFalse(hidden.contains("全部任务通过"), "关掉后正文不得出现在浮层文案里")

        // 单边为空：只显示有的那一边；首尾空白不算内容
        XCTAssertEqual(NotificationText.hudDetail(title: "只有标题", body: "", showsBody: true), "只有标题")
        XCTAssertEqual(NotificationText.hudDetail(title: "   ", body: "只有正文", showsBody: true), "只有正文")
        XCTAssertEqual(
            NotificationText.hudDetail(title: "  ", body: "\n", showsBody: true),
            newNotification,
            "两边都空时不留一行空白"
        )
    }

    /// **超长内容策略**（2026-09-28 用户：「消息内容过多考虑下怎么显示」）：
    /// ① 正文里的换行**先压成空格**（浮层第二行只有 2 行预算，换行会白白吃掉一行）；
    /// ② 一次取数多条新通知只在末尾追加「等 N 条」计数后缀（浮层仍只展示最新一条）。
    func testNotificationHUDDetailFlattensNewlinesAndCountsExtraNotifications() {
        // ① 换行 / 制表符 / `\r\n` → 空格，连续空白折成一个，首尾去净
        XCTAssertEqual(
            NotificationText.hudDetail(title: "构建", body: "第一行\n第二行", showsBody: true),
            "构建 · 第一行 第二行"
        )
        XCTAssertEqual(
            NotificationText.hudDetail(title: "构建", body: "第一行\r\n\r\n第二行\t末尾  ", showsBody: true),
            "构建 · 第一行 第二行 末尾",
            "`\\r\\n` 与连续空白都归一成单个空格"
        )
        XCTAssertEqual(NotificationText.singleLine("\n  \n"), "", "全是空白 → 空串（不占第二行的预算）")
        XCTAssertEqual(NotificationText.singleLine("原样"), "原样")

        // ② 计数后缀：> 0 才追加，用的是本地化文案（`and %d more` / `等 %d 条`）
        let more = NotificationText.localized("module.notifications.moreCount")
        XCTAssertNotEqual(more, "module.notifications.moreCount", "计数文案没解析出来")
        XCTAssertEqual(
            NotificationText.hudDetail(title: "构建", body: "全部通过", showsBody: true, moreCount: 0),
            "构建 · 全部通过",
            "0 条不追加后缀"
        )
        let withMore = NotificationText.hudDetail(title: "构建", body: "全部通过", showsBody: true, moreCount: 3)
        XCTAssertTrue(withMore.hasPrefix("构建 · 全部通过"), "后缀追加在末尾，内容不动：\(withMore)")
        XCTAssertNotEqual(withMore, "构建 · 全部通过")
        XCTAssertTrue(withMore.contains("3"), "后缀要带上「还有几条」：\(withMore)")
        XCTAssertEqual(withMore, "构建 · 全部通过 " + String(format: more, 3))
        // 关掉正文时后缀照旧（「还有几条」与正文显示与否无关）
        let hidden = NotificationText.hudDetail(title: "构建", body: "全部通过", showsBody: false, moreCount: 2)
        XCTAssertEqual(hidden, NotificationText.localized("module.notifications.newNotification") + " "
            + String(format: more, 2))
    }

    /// 键本身的口径：`showBodyInHUD` 的**声明默认值是 true**（用户 2026-09-28 要求默认显示正文，
    /// 覆盖设计稿原口径的 false）——断言读 `defaultValue` 而不是当前生效值，
    /// 不受开发机上真实 UserDefaults 影响。
    func testShowBodyInHUDKeyDefaultsToTrue() {
        XCTAssertEqual(Defaults.Keys.showBodyInHUD.name, "showBodyInHUD", "键名与设计稿/设置页一致")
        XCTAssertTrue(
            Defaults.Keys.showBodyInHUD.defaultValue,
            "默认必须是 true（用户口径）；设计稿原口径的 false 已被覆盖"
        )
    }

    // MARK: - 浮层显示时长（D-25：可配 + 默认 8s）

    /// **显示时长可配**（2026-09-28 用户反馈「显示时长太短」）：设置值 → ttl 的映射与夹取。
    /// 边界取 1 / 8 / 15 / 20 —— 内核 `hudTTLRange`（1…15）的两端、设置默认值（8）与其外侧。
    func testNotificationHUDDurationMapsToTTLWithClamp() {
        XCTAssertEqual(NotificationHUDPolicy.ttl(forSettingSeconds: 8), 8, "默认档 8s 原样交给内核")
        XCTAssertEqual(NotificationHUDPolicy.ttl(forSettingSeconds: 2), 2, "滑块下界 2s")
        XCTAssertEqual(NotificationHUDPolicy.ttl(forSettingSeconds: 1), 1, "内核下界 1s 仍可达（不是 0）")
        XCTAssertEqual(
            NotificationHUDPolicy.ttl(forSettingSeconds: 0.2),
            1,
            "低于内核下界 → 夹到 1s（直接改 UserDefaults 写了个 0.2 也要有确定行为）"
        )
        XCTAssertEqual(NotificationHUDPolicy.ttl(forSettingSeconds: 15), 15, "内核上界 15s")
        XCTAssertEqual(
            NotificationHUDPolicy.ttl(forSettingSeconds: 20),
            15,
            "高于上界 → 夹到 15s（浮层不得变成常驻占位）"
        )
        XCTAssertEqual(
            NotificationHUDPolicy.durationRange,
            2...15,
            "设置滑块区间（2…15）与内核夹取区间（1…15）同源：滑块不会给出被夹掉的档位"
        )
    }

    /// 键本身的口径：**默认 8s**（原实现是模块里的代码常量 `hudTTL = 4`——用户 2026-09-28
    /// 反馈「显示时长太短」后改为可配）。断言 `defaultValue` 而不是当前生效值，
    /// 不受开发机上真实 UserDefaults 影响。
    func testNotificationHUDDurationKeyDefaultsToEightSeconds() {
        XCTAssertEqual(
            Defaults.Keys.notificationHUDDurationSeconds.name,
            "notificationHUDDurationSeconds",
            "键名与设置页 / 文档一致"
        )
        XCTAssertEqual(Defaults.Keys.notificationHUDDurationSeconds.defaultValue, 8, "默认 8s（原 4s）")
        XCTAssertTrue(
            ModuleRegistry.hudTTLRange.contains(Defaults.Keys.notificationHUDDurationSeconds.defaultValue),
            "默认值必须落在内核夹取区间（1…15）内，否则一装上就被夹、日志与实际不符"
        )
    }

    // MARK: - 通知浮层的配置区（D-25：总开关 / 背景样式）

    /// **总开关**（2026-09-28 用户要求「做一个配置项，要包含总开关…」）：关掉 → 判定函数直接给 `nil`，
    /// 模块因此**连 `presentTransient` 都不调**（两条通道共用这一个判据）。
    ///
    /// 用纯判定函数测（不起真窗口、不读开发机上的 UserDefaults）：`resolve` 就是「弹 / 不弹」
    /// 这条判据的唯一落点。
    func testNotificationHUDPresentationMasterSwitchGatesPresentation() {
        XCTAssertNil(
            NotificationHUDPresentation.resolve(enabled: false, showsBody: true, backgroundStyle: .liquidGlass),
            "总开关关掉 → 不弹浮层（这就是「不调用 presentTransient」的判据）"
        )
        XCTAssertNil(
            NotificationHUDPresentation.resolve(enabled: false, showsBody: false, backgroundStyle: .solid),
            "总开关优先于其余三项：它们怎么设都不弹"
        )

        XCTAssertEqual(
            NotificationHUDPresentation.resolve(enabled: true, showsBody: false, backgroundStyle: .solid),
            NotificationHUDPresentation(showsBody: false, backgroundStyle: .solid),
            "开起来时两项口径原样进快照"
        )
        XCTAssertEqual(
            NotificationHUDPresentation.resolve(enabled: true, showsBody: true, backgroundStyle: .liquidGlass),
            NotificationHUDPresentation(showsBody: true, backgroundStyle: .liquidGlass)
        )
    }

    /// 两个新键的**声明默认值** + 背景样式的**序列化往返**（写盘 → 读回）。
    ///
    /// 往返走一个**临时 suite**（不碰开发机 `com.cmeng.gourd` 域）：枚举存的是 `rawValue`
    /// 字符串（`RawRepresentable` 桥，同 `LockScreenGlassStyle` / `OSDMaterial`），
    /// 因此断言盘上真的出现 `"Solid"` 而不只是一个内存值。
    func testNotificationHUDConfigKeysDefaultsAndBackgroundRoundTrip() {
        XCTAssertEqual(Defaults.Keys.enableNotificationHUD.name, "enableNotificationHUD")
        XCTAssertTrue(Defaults.Keys.enableNotificationHUD.defaultValue, "总开关默认开（不给用户添意外）")
        XCTAssertEqual(
            Defaults.Keys.notificationHUDBackgroundStyle.defaultValue,
            .liquidGlass,
            "背景默认液态玻璃（用户 2026-09-28 口径：要能选「是否为液态玻璃模式」）"
        )

        // 取值词汇表：rawValue 是设置页 Picker 直接显示的字面量（同 OSD 的 Material 选择器）
        XCTAssertEqual(NotificationHUDBackgroundStyle.allCases.map(\.rawValue), ["Liquid glass", "Solid"])
        XCTAssertEqual(NotificationHUDBackgroundStyle(rawValue: "Liquid glass"), .liquidGlass)

        let suiteName = "com.cmeng.gourd.tests.notificationHUDBackgroundStyle"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return XCTFail("建不出临时 suite（\(suiteName)）")
        }
        defer { suite.removePersistentDomain(forName: suiteName) }
        let key = Defaults.Key<NotificationHUDBackgroundStyle>(
            "notificationHUDBackgroundStyle",
            default: .liquidGlass,
            suite: suite
        )

        XCTAssertEqual(Defaults[key], .liquidGlass, "没写过时读回声明默认值")
        Defaults[key] = .solid
        XCTAssertEqual(Defaults[key], .solid, "写盘 → 读回同一档")
        XCTAssertEqual(suite.string(forKey: key.name), "Solid", "盘上存的就是 rawValue 字符串")
        Defaults[key] = .liquidGlass
        XCTAssertEqual(Defaults[key], .liquidGlass, "再切回默认档同样往返")
    }

    // MARK: - 点击动作序列（2026-09-29：浮层卡片可点开 App / 列表行点完收起刘海）

    /// **列表行**：动作序列 = 打开 App → 收起刘海，且**不碰浮层**。
    ///
    /// 顺序是契约（`NotificationClickPolicy` 的文档）：收起会触发面板动画，先开应用可保证
    /// 前台切换不被动画延迟；执行器按数组顺序调用，这里用落地顺序做断言（不只是集合相等）。
    func testNotificationRowClickOpensAppThenCollapsesNotch() {
        var calls: [NotificationClickAction] = []

        NotificationClickPolicy.run(
            NotificationClickPolicy.row,
            openApp: { calls.append(.openApp) },
            collapseNotch: { calls.append(.collapseNotch) },
            dismissTransient: { calls.append(.dismissTransient) }
        )

        XCTAssertEqual(
            calls,
            [.openApp, .collapseNotch],
            "列表行：先打开 App、再收起刘海；不该动浮层（浮层与列表行是两条独立入口）"
        )
        XCTAssertEqual(NotificationClickPolicy.row, [.openApp, .collapseNotch], "序列本身是数据，直接钉住")
    }

    /// **浮层卡片本体**：动作序列 = 打开 App → 撤浮层（**不动刘海**——浮层出现时刘海本就是收起态）。
    func testNotificationHUDCardClickOpensAppThenDismissesTransient() {
        var calls: [NotificationClickAction] = []

        NotificationClickPolicy.run(
            NotificationClickPolicy.hudCard,
            openApp: { calls.append(.openApp) },
            collapseNotch: { calls.append(.collapseNotch) },
            dismissTransient: { calls.append(.dismissTransient) }
        )

        XCTAssertEqual(
            calls,
            [.openApp, .dismissTransient],
            "浮层卡片：先打开 App、再立刻撤浮层（不等 ttl）；收起刘海不在浮层的动作集里"
        )
        XCTAssertEqual(NotificationClickPolicy.hudCard, [.openApp, .dismissTransient], "序列本身是数据，直接钉住")
    }

    /// AX 通道的浮层没有 bundle id（`BannerEvent` 只有 App 名）：按名反查的两条来源——
    /// ① 列表里同名条目的 bundle id；② 运行中 App 的本地化名 / 包文件名。都落空给 nil（**不猜**，
    /// 打开一个同名的别的 App 比不打开更糟）。
    func testNotificationBundleIdentifierResolutionByName() throws {
        let item = NotificationItem(
            id: 7,
            bundleIdentifier: "com.apple.MobileSMS",
            appName: "信息",
            title: "标题",
            subtitle: nil,
            body: "正文",
            deliveredDate: nil
        )

        XCTAssertEqual(
            NotificationStore.bundleIdentifier(forAppName: "信息", in: [item], runningApps: []),
            "com.apple.MobileSMS",
            "来源 ①：列表里同名条目的 bundle id"
        )
        XCTAssertEqual(
            NotificationStore.bundleIdentifier(
                forAppName: "Safari",
                in: [],
                runningApps: [(localizedName: "Safari", bundleFileName: "Safari", bundleIdentifier: "com.apple.Safari")]
            ),
            "com.apple.Safari",
            "来源 ②：运行中 App 的本地化名"
        )
        XCTAssertEqual(
            NotificationStore.bundleIdentifier(
                forAppName: "Safari",
                in: [],
                runningApps: [(localizedName: "浏览器", bundleFileName: "Safari", bundleIdentifier: "com.apple.Safari")]
            ),
            "com.apple.Safari",
            "来源 ②：本地化名对不上时用包文件名（`Safari.app` → `Safari`）"
        )
        XCTAssertNil(
            NotificationStore.bundleIdentifier(forAppName: "不存在的 App", in: [item], runningApps: []),
            "两条来源都落空 → nil（不猜）"
        )
        XCTAssertNil(
            NotificationStore.bundleIdentifier(forAppName: "", in: [], runningApps: []),
            "空名直接给 nil（避免误配到某个名字为空的候选）"
        )
    }

    // MARK: - 通知浮层卡片的尺寸口径（D-23）

    /// **固定尺寸**（2026-09-28 用户：「尺寸不固定，要固定个初始大小」）：卡片 = **320 × 64 × 倍率**，
    /// 且**与窗口用同一个来源**（`ModuleHUDWindowHost.contentSize(scale:)`）——两处各写一份常量
    /// 就会出现「窗口 416pt、卡片 300pt」的错位。
    func testHUDWindowFixedContentSizeScalesAndClamps() {
        // 基准档（倍率 1.0）= 320 × 64
        XCTAssertEqual(ModuleHUDWindowHost.contentSize(scale: 1.0), CGSize(width: 320, height: 64))
        // 默认档（1.3）：320 × 1.3 = 416，64 × 1.3 = 83.2（保留两位小数，避开浮点尾巴）
        XCTAssertEqual(ModuleHUDWindowHost.contentSize(scale: 1.3), CGSize(width: 416, height: 83.2))
        XCTAssertEqual(ModuleHUDWindowHost.contentSize(scale: 2.0), CGSize(width: 640, height: 128))

        // 越界值夹取到区间端点（用户直接改 UserDefaults 写了个离谱值时也要有确定尺寸）
        XCTAssertEqual(ModuleHUDWindowHost.contentSize(scale: 5.0), ModuleHUDWindowHost.contentSize(scale: 2.0))
        XCTAssertEqual(ModuleHUDWindowHost.contentSize(scale: 0.1), ModuleHUDWindowHost.contentSize(scale: 0.8))
        XCTAssertEqual(ModuleHUDWindowHost.hudScaleRange, 0.8...2.0, "与设置滑块 0.8…2.0 同源")

        // 卡片与窗口同一来源（模块侧 metrics 的 cardSize 必须就是这一组常量）
        XCTAssertEqual(NotificationHUDCardLayout.metrics(scale: 1.3).cardSize, ModuleHUDWindowHost.contentSize(scale: 1.3))
        XCTAssertEqual(NotificationHUDCardLayout.scaleRange, ModuleHUDWindowHost.hudScaleRange)
    }

    /// **倍率越大、每一项都越大**：字号 / 图标 / 内边距 / 卡片尺寸随倍率单调增，
    /// 且默认值 1.3 明显大于改造前的口径（这就是用户要的「调大一些」）。
    func testNotificationHUDCardMetricsScaleWithSetting() {
        let small = NotificationHUDCardLayout.metrics(scale: 1.0)
        let scaled = NotificationHUDCardLayout.metrics(scale: 1.3)
        let large = NotificationHUDCardLayout.metrics(scale: 2.0)

        XCTAssertLessThan(small.titleSize, scaled.titleSize)
        XCTAssertLessThan(scaled.titleSize, large.titleSize)
        XCTAssertLessThan(small.bodySize, scaled.bodySize)
        XCTAssertLessThan(small.iconSize, scaled.iconSize)
        XCTAssertLessThan(small.padding, scaled.padding)
        XCTAssertLessThan(small.cardSize.width, scaled.cardSize.width)
        XCTAssertLessThan(small.cardSize.height, scaled.cardSize.height)

        // 1.3 倍 = 基准 × 1.3（保留两位小数，避开浮点尾巴）
        XCTAssertEqual(scaled.titleSize, 15.6, accuracy: 0.001)
        XCTAssertEqual(scaled.bodySize, 14.3, accuracy: 0.001)
        XCTAssertEqual(scaled.iconSize, 18.2, accuracy: 0.001)
        XCTAssertEqual(scaled.padding, 13, accuracy: 0.001)
        // 卡片尺寸 = 320 × 64 × 1.3（固定常量，不再按内容 / 屏幕分档）
        XCTAssertEqual(scaled.cardSize, CGSize(width: 416, height: 83.2))
    }

    /// **边界一：下限 0.8**——每一项按 0.8 缩放，字体仍可读（标题 ≥ 9pt），文字列不会被压到 0。
    func testNotificationHUDCardMetricsAtLowerBound() {
        let metrics = NotificationHUDCardLayout.metrics(scale: 0.8)
        XCTAssertEqual(metrics.titleSize, 9.6, accuracy: 0.001)
        XCTAssertEqual(metrics.bodySize, 8.8, accuracy: 0.001)
        XCTAssertEqual(metrics.iconSize, 11.2, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.titleSize, 8, "0.8 倍下标题仍要能读")
        XCTAssertGreaterThan(metrics.textMaxWidth, 0, "文字列宽度不得归零")
        XCTAssertEqual(metrics.cardSize, CGSize(width: 256, height: 51.2))
    }

    /// **边界二：上限 2.0**——字号翻倍、卡片也翻倍（640 × 128）；
    /// 卡片尺寸不再有「绝对上限」：固定尺寸下它就是常量 × 倍率，倍率本身已被夹到 2.0。
    func testNotificationHUDCardMetricsAtUpperBound() {
        let metrics = NotificationHUDCardLayout.metrics(scale: 2.0)
        XCTAssertEqual(metrics.titleSize, 24, accuracy: 0.001)
        XCTAssertEqual(metrics.bodySize, 22, accuracy: 0.001)
        XCTAssertEqual(metrics.iconSize, 28, accuracy: 0.001)
        XCTAssertEqual(metrics.cardSize, CGSize(width: 640, height: 128))
        // 文字列 = 卡片宽度 −（两侧内边距 + 图标 + 两个间距 + × 及其余量）
        XCTAssertLessThan(metrics.textMaxWidth, metrics.cardSize.width)
        XCTAssertGreaterThan(metrics.textMaxWidth, 500, "上限档下文字列仍要足够宽")
        // 间距 / × / 点击余量都按同一倍率缩放：改任一项都不会让内容比卡片宽（固定尺寸下就是右侧被裁）
        XCTAssertEqual(metrics.lineSpacing, 4, accuracy: 0.001)
        XCTAssertEqual(metrics.closeSize, 22, accuracy: 0.001)
    }

    /// **越界值夹取到区间端点**：用户直接改 UserDefaults 写了个离谱值（0.2 / 5.0）时，
    /// 呈现必须是确定的（同 `ttl` 的夹取口径），而不是崩或缩成一条。
    func testNotificationHUDCardMetricsClampsOutOfRangeScale() {
        XCTAssertEqual(
            NotificationHUDCardLayout.metrics(scale: 0.2),
            NotificationHUDCardLayout.metrics(scale: 0.8),
            "低于下限按 0.8 算"
        )
        XCTAssertEqual(
            NotificationHUDCardLayout.metrics(scale: 5.0),
            NotificationHUDCardLayout.metrics(scale: 2.0),
            "高于上限按 2.0 算"
        )
    }

    // MARK: - 展开面板通知页的字号档位（T3 / D-09）

    /// **展开面板的 17 处字号 + 行内垂直内边距逐项钉表**（docs/30 §接口与数据形状 机制四，
    /// 修复轮并入失败态 / 空态 / 权限引导 6 处）：
    /// 用户反馈「消息（通知）面板字体太小」——主行 +2pt、次要 +1pt，行内边距 3 → 4；
    /// 状态块按语义就近取档（提示/正文类 12、状态块图标取标题档 13），**任何一项不超过主行档位 13**。
    ///
    /// 视图里不许再出现裸字号字面量（都读 `NotificationRowMetrics`），本用例是这张档位表的
    /// **唯一执行依据**：改档只动常量表，改了却忘了对表在这里红。
    ///
    /// **首页通知块与 HUD 浮层卡片不在表内**（与展开页是不同代码路径：首页块定高 96 内画 3 行、
    /// HUD 卡片按用户倍率缩放，各自的字号口径见 `NotificationsHomeBlockView` 与
    /// `NotificationHUDCardLayout`）——这就是「放大展开页不会连带放大两者」的机制保证。
    func testNotificationRowMetricsMatchTheBumpedSizes() {
        // 档位表：（表项名, 常量, 目标值），顺序与 docs/30 机制四的表格逐行一致。
        let table: [(name: String, actual: CGFloat, expected: CGFloat)] = [
            ("模块名", NotificationRowMetrics.moduleName, 13),
            ("状态行「最近 N 条」", NotificationRowMetrics.status, 12),
            ("全部清除", NotificationRowMetrics.clearAll, 11),
            ("刷新图标", NotificationRowMetrics.refresh, 12),
            ("来源 App 名", NotificationRowMetrics.appName, 12),
            ("分隔「·」", NotificationRowMetrics.separator, 12),
            ("时间", NotificationRowMetrics.timestamp, 11),
            ("标题", NotificationRowMetrics.title, 13),
            ("正文", NotificationRowMetrics.body, 12),
            ("行内 ×", NotificationRowMetrics.dismissIcon, 11),
            ("脚注", NotificationRowMetrics.footnote, 10),
        ]
        XCTAssertEqual(table.count, 11, "档位表就是 11 项（多了少了都说明表被改动过）")
        for row in table {
            XCTAssertEqual(row.actual, row.expected, "\(row.name) 应为 \(row.expected)pt（档位表）")
        }

        // 行内垂直内边距 3 → 4：字号变大后行距跟着松一档（行高随之变高，列表更长、照常滚动）。
        XCTAssertEqual(NotificationRowMetrics.rowVerticalPadding, 4, "行内 padding 3 → 4")

        // T3 修复轮：失败态 / 空态 / 权限引导 6 处并表（同属展开页，留旧值会与放大后的列表行
        // 明显不一致）。取档：状态块图标取标题档 13（旧 16 / 18，上限即主行档位），文字取
        // 状态/提示档 12（旧 11 三处、12 一处）。
        let stateTable: [(name: String, actual: CGFloat, expected: CGFloat)] = [
            ("失败态图标", NotificationRowMetrics.failureIconFontSize, 13),
            ("失败原因", NotificationRowMetrics.failureReasonFontSize, 12),
            ("空态文案", NotificationRowMetrics.emptyStateFontSize, 12),
            ("权限引导图标", NotificationRowMetrics.permissionIconFontSize, 13),
            ("权限引导文案", NotificationRowMetrics.permissionHintFontSize, 12),
            ("权限引导按钮", NotificationRowMetrics.permissionActionFontSize, 12),
        ]
        XCTAssertEqual(stateTable.count, 6, "修复轮追加的就是 6 项（多了少了都说明表被改动过）")
        for row in stateTable {
            XCTAssertEqual(row.actual, row.expected, "\(row.name) 应为 \(row.expected)pt（状态/提示类档位）")
        }

        // 档位表的语义上限：**任何一项都不超过主行档位 13**（修复轮的硬约束，逐项兜住）。
        for row in table + stateTable {
            XCTAssertLessThanOrEqual(row.actual, 13, "\(row.name) 不得超过主行档位 13")
        }
    }

    // MARK: - 主面板背景（D-26）

    /// **主面板背景的生效范围是纯函数**（2026-09-28 用户要求给展开态主面板加「液态玻璃」配置）：
    /// 玻璃两档**只在「展开态」或「非刘海屏的浮动药丸」上生效**，刘海屏的折叠态保持纯黑
    /// （折叠态要与物理刘海对齐融合，玻璃会露出壁纸、在刘海下方形成一块突兀的方块）。
    ///
    /// 四条组合逐条钉住——这是「用户选了玻璃但折叠态没变」不算 bug 的唯一依据，
    /// 也是唯一一条把「状态」与「样式」绑在一起的判据（样式本身三档都能选）。
    func testPanelBackgroundUsesStyleOnlyForExpandedOrFloatingPill() {
        XCTAssertTrue(
            panelBackgroundUsesStyle(isOpen: true, isDynamicIslandMode: false),
            "展开态（用户截图里音乐 / 日历那一屏）：标准刘海屏也要走配置的样式"
        )
        XCTAssertTrue(
            panelBackgroundUsesStyle(isOpen: true, isDynamicIslandMode: true),
            "展开态 + 浮动药丸：两条件任一成立即生效"
        )
        XCTAssertTrue(
            panelBackgroundUsesStyle(isOpen: false, isDynamicIslandMode: true),
            "非刘海屏的折叠态就是那块浮动药丸：本身就是独立悬浮面板，没有要与物理刘海融合的前提"
        )
        XCTAssertFalse(
            panelBackgroundUsesStyle(isOpen: false, isDynamicIslandMode: false),
            "刘海屏的折叠态：**保持纯黑**（唯一的 false 组合，玻璃在这里会露出壁纸）"
        )
    }

    /// **滚动边缘的黑色渐隐遮罩只在纯黑档显示**（2026-09-28 用户反馈，截图是笔记 tab 且面板已切液态玻璃：
    /// 「这个上面和下面的黑色框是什么，得去掉」）。
    ///
    /// 遮罩（`Color.black.opacity(0.65) → .clear` 的 16pt 渐变）是给纯黑面板做的滚动边缘淡出，
    /// 换到玻璃底上就成了两条突兀的黑带。判据收在 `shouldShowScrollFadeMask`，消费点只有两处：
    /// 笔记 tab 的滚动网格（`NoteListView`）与计时器预设列表（`NotchTimerView.presetColumn`）。
    func testScrollFadeMaskOnlyShownForSolidBlackPanel() {
        XCTAssertTrue(
            shouldShowScrollFadeMask(panelBackgroundStyle: .solidBlack),
            "纯黑档：遮罩是它本来要干的事（黑底上的滚动边缘淡出），保持原样"
        )
        XCTAssertFalse(
            shouldShowScrollFadeMask(panelBackgroundStyle: .liquidGlass),
            "液态玻璃档：用户截图的那一档——黑色渐变必须消失"
        )
        XCTAssertFalse(
            shouldShowScrollFadeMask(panelBackgroundStyle: .frostedGlass),
            "毛玻璃档同理：黑带在任何玻璃底上都是异物"
        )
    }

    /// **面板顶部的不透明黑带高度**（2026-09-28 用户反馈「不能强硬拉伸，菜单栏里面的图标都变形了」；
    /// 2026-09-29 用户反馈「顶部的高度不够，比系统的黑色区域要窄」→ 改为 `max(刘海, 菜单栏) + 1`）：
    /// 玻璃两档都是 behindWindow 材质（`NSGlassEffectView` / `NSVisualEffectView.hudWindow`），
    /// 采样的就是窗口背后的画面；面板顶边与系统 UI 带同高，于是菜单栏图标被采进玻璃里糊成一片。
    /// 因此这条带必须不透明，高度取**系统 UI 带（刘海与菜单栏里更高的那个）+ 1pt**——
    /// 刘海屏上 `safeAreaInsets.top`（本机内置屏实测 32）比「屏顶 − visibleFrame 顶」（33）小 1pt，
    /// 只取刘海高度会从面板顶部露出 1pt 玻璃（用户看到的「比系统黑区窄」）。
    func testPanelTopOpaqueBandHeightPrefersNotchHeight() {
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 38, menuBarHeight: 24),
            39,
            "刘海屏：刘海高度（38）是两者里更高的那个 → 38 + 1"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 32, menuBarHeight: 33),
            34,
            "本机内置屏的实测口径：刘海 32 < 菜单栏 33 → 取菜单栏 33 + 1（盖住系统黑区）"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 32, menuBarHeight: 0),
            33,
            "菜单栏取不到（0）时只用刘海高度，仍 +1"
        )
    }

    /// **菜单栏比刘海高时取菜单栏高度**（2026-09-29 新增要求）：外接屏 / 缩放分辨率下
    /// 「屏顶 − visibleFrame 顶」可能比 `safeAreaInsets.top` 更大，这时黑带必须跟着菜单栏走，
    /// 否则玻璃会把菜单栏图标采进来（同 2026-09-28 那条反馈的根因）。
    func testPanelTopOpaqueBandHeightTakesMenuBarWhenTallerThanNotch() {
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 24, menuBarHeight: 38),
            39,
            "菜单栏 38 > 刘海 24 → 取 38 + 1（不再是「只认刘海高度」）"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 30, menuBarHeight: 999),
            1000,
            "悬殊口径下同样取大者：判据是 max 而不是「谁优先」"
        )
    }

    /// 非刘海屏取**菜单栏高度**（屏顶与 `visibleFrame` 顶之差，口径同
    /// `ModuleHUDWindowHost.topInset(safeAreaTop:frameMaxY:visibleFrameMaxY:)`）：
    /// 浮动药丸的顶边落在菜单栏带里，不盖住就会把菜单栏图标采进玻璃。
    /// 异常输入一律夹到 0（= 不加黑带，退回改造前观感），**不产生负高度**（负的 `frame(height:)` 会崩）。
    func testPanelTopOpaqueBandHeightFallsBackToMenuBarHeight() {
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 0, menuBarHeight: 24),
            25,
            "非刘海屏：黑带 = 菜单栏高度 + 1"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 0, menuBarHeight: -5),
            0,
            "可见框高于屏顶（异常）→ 夹到 0：不加黑带，不产生负高度"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 0, menuBarHeight: .nan),
            0,
            "非有限值同样夹到 0，不把 NaN 传进 frame(height:)"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: .nan, menuBarHeight: 0),
            0,
            "两个入参都取不到 → 0：不该凭空多出 1pt 黑边"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 0, menuBarHeight: 0),
            0,
            "没有系统 UI 带（都为 0）→ 0，而不是 1"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(for: nil),
            0,
            "取不到屏 → 0（不加黑带，退回改造前的玻璃底观感）"
        )
    }

    // MARK: - 展开态高度（120…850，按屏高 90% 收敛；2026-09-28「高度可以调」+ 2026-09-29 上限收 850）

    /// 下界恒定 120：低于它的值一律抬到 120（面板再矮就装不下 tab 栏与内容）。
    /// 上界与屏无关的两个极端（不管传多大的屏）也一并钉住。
    func testClampedOpenNotchHeightKeepsLowerBound() {
        XCTAssertEqual(
            clampedOpenNotchHeight(0, screenVisibleHeight: 1000),
            openNotchHeightRange.lowerBound,
            "0（用户直接改 UserDefaults）抬到 120"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(60, screenVisibleHeight: nil),
            openNotchHeightRange.lowerBound,
            "取不到屏时同样有下界"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(120, screenVisibleHeight: 1000),
            120,
            "正好是下界：原样保留"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(.nan, screenVisibleHeight: 1000),
            120,
            "非有限值不参与比较，退回下界（不崩、不产生 NaN 尺寸）"
        )
    }

    /// **可配上限就是 850**（2026-09-29 用户明确「展开的高度最高是 850」）：
    /// 高屏上有效上界 = 850（不再按 1000 放行）。
    func testOpenNotchHeightConfiguredUpperBoundIs850() {
        XCTAssertEqual(openNotchHeightRange, 120...850, "可配范围（也是滑块的两端）")
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: 1200),
            850,
            "1200 * 0.9 = 1080 > 850 → 取可配上限 850"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(850, screenVisibleHeight: 1200),
            850,
            "正好是可配上限：原样生效（滑块拖到底就是这个值）"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(851, screenVisibleHeight: 1200),
            850,
            "超过可配上限 1pt 也夹回 850"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(1500, screenVisibleHeight: nil),
            850,
            "取不到屏 → 回落可配上限 850"
        )
        // 850 与「屏高 90%」取小：949（本机内置屏的 visibleFrame 高）→ 854.1 > 850 → 850
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: 949),
            850,
            "本机内置屏：854.1 > 850 → 850"
        )
        // 矮屏上仍然按屏收敛（比 850 更小）
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: 900),
            810,
            "900 * 0.9 = 810 < 850 → 810"
        )
    }

    /// 区间内的值**原样通过**（用户拖到 800 时不能再被悄悄改掉）：这里用「可见高度 1200 → 上界 850」
    /// 的屏幕，800 落在区间内。改造前 400 的上限会把它夹成 400 —— 那正是用户反馈的问题。
    func testClampedOpenNotchHeightPassesValuesInsideRange() {
        let visible: CGFloat = 1200
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: visible),
            850,
            "1200 的 90% = 1080 > 850，因此上界是可配上限 850"
        )
        for value: CGFloat in [400, 401, 800, 850] {
            XCTAssertEqual(
                clampedOpenNotchHeight(value, screenVisibleHeight: visible),
                value,
                "\(value) 在 120…850 内且低于屏高 90%，必须原样生效"
            )
        }
    }

    /// 超过上界被**夹到屏高 90%**（矮屏）：900 可见高度的屏上，1500 与 850 都落在 810；
    /// 取不到屏时才回落到可配上限 850。
    func testClampedOpenNotchHeightClampsToScreenLimit() {
        let visible: CGFloat = 900
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: visible),
            810,
            "900 * 0.9 = 810（比可配上限 850 更小）"
        )
        XCTAssertEqual(clampedOpenNotchHeight(1500, screenVisibleHeight: visible), 810, "离谱值夹到屏高 90%")
        XCTAssertEqual(clampedOpenNotchHeight(850, screenVisibleHeight: visible), 810, "可配上限也要按屏收敛")
        XCTAssertEqual(clampedOpenNotchHeight(810, screenVisibleHeight: visible), 810, "正好在上界：原样保留")
        XCTAssertEqual(clampedOpenNotchHeight(1500, screenVisibleHeight: nil), 850, "取不到屏 → 回落 850")

        // 极矮的屏：90% 低于可配下界时区间会反向，必须保底到 120（而不是给一个 < 120 的上界）
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: 100),
            120,
            "100 * 0.9 = 90 < 120 → 上界保底 120"
        )
        XCTAssertEqual(clampedOpenNotchHeight(1000, screenVisibleHeight: 100), 120)
    }

    /// **滑块与夹取同源**：设置页滑块的上界就是 `effectiveOpenNotchHeightUpperBound`，
    /// 因此「滑块能拖到的每个值」都不会再被 `clampedOpenNotchHeight` 改掉——否则用户看到的是
    /// 「拖了没用」（本次改造要修的正是这种自相矛盾）。
    /// 屏高列表里特意放了本机内置屏（949 → 854.1，被 850 收住）与高屏（1200/2400 → 850）。
    func testOpenNotchHeightSliderUpperBoundMatchesClamp() {
        for visible: CGFloat in [600, 900, 949, 1112, 1200, 2400] {
            let upper = effectiveOpenNotchHeightUpperBound(screenVisibleHeight: visible)
            XCTAssertGreaterThanOrEqual(upper, openNotchHeightRange.lowerBound)
            XCTAssertLessThanOrEqual(upper, openNotchHeightRange.upperBound)
            for value in stride(from: openNotchHeightRange.lowerBound, through: upper, by: 10) {
                XCTAssertEqual(
                    clampedOpenNotchHeight(value, screenVisibleHeight: visible),
                    value,
                    "滑块能拖到的 \(value)（屏可见高度 \(visible)）必须原样生效"
                )
            }
        }
    }

    // MARK: - 展开态右下角拖动改宽高（2026-09-29，「刘海打开时直接拉动调整宽高」）

    /// **1:1 跟手的量法**：位移由两次**屏幕光标**（`NSEvent.mouseLocation`，AppKit 全局坐标、
    /// y 向上）算出，与视图 / 窗口怎么重排无关——这才是「手移动了多少」。
    /// 向右 / 向下拖都是正的（y 取反：屏幕 y 向下变小）。
    func testPanelResizeTranslationMatchesCursorDeltaOneToOne() {
        let start = CGPoint(x: 1217, y: 462)
        XCTAssertEqual(
            panelResizeTranslation(from: start, to: CGPoint(x: 1317, y: 462)),
            CGSize(width: 100, height: 0),
            "右移 100pt → 宽度位移 +100（原样，不带任何放大 / 衰减）"
        )
        XCTAssertEqual(
            panelResizeTranslation(from: start, to: CGPoint(x: 1217, y: 362)),
            CGSize(width: 0, height: 100),
            "下移 100pt（AppKit y 462 → 362）→ 高度位移 +100"
        )
        XCTAssertEqual(
            panelResizeTranslation(from: start, to: CGPoint(x: 1117, y: 562)),
            CGSize(width: -100, height: -100),
            "左上移 → 宽高都为负（缩小）"
        )
        XCTAssertEqual(
            panelResizeTranslation(from: start, to: start),
            .zero,
            "按下不移动 → 零位移（不会因为取整动一下）"
        )
    }

    /// 非有限读数按 0 处理（口径同 `resizedPanelSize` 对非有限位移的处理）：不让一次异常读数
    /// 把尺寸弹到边界。
    func testPanelResizeTranslationFallsBackOnNonFiniteValues() {
        XCTAssertEqual(
            panelResizeTranslation(
                from: CGPoint(x: CGFloat.nan, y: 0),
                to: CGPoint(x: 10, y: CGFloat.infinity)
            ),
            CGSize(width: 0, height: 0),
            "两端任一非有限 → 该方向按 0（不动），而不是弹到边界"
        )
    }

    /// 方向：把手在右下角 → 向右拖动变宽、向下拖动变高（两个方向一起动就是"同时改宽高"）。
    /// 边界取得足够宽，断言的是**纯位移**这一层（夹取另有用例）。
    func testResizedPanelSizeGrowsWithRightwardAndDownwardDrag() {
        let resized = resizedPanelSize(
            start: CGSize(width: 840, height: 400),
            translation: CGSize(width: 60, height: 120),
            minWidth: 640, maxWidth: 1452,
            minHeight: 120, maxHeight: 850
        )
        XCTAssertEqual(resized.width, 900, "向右拖 60pt → 840 + 60")
        XCTAssertEqual(resized.height, 520, "向下拖 120pt → 400 + 120（宽高同时变）")
    }

    /// 反方向：向左拖变窄、向上拖变矮（把手在右下角，向内拖就是缩小）。
    func testResizedPanelSizeShrinksWithLeftwardAndUpwardDrag() {
        let resized = resizedPanelSize(
            start: CGSize(width: 840, height: 400),
            translation: CGSize(width: -60, height: -120),
            minWidth: 640, maxWidth: 1452,
            minHeight: 120, maxHeight: 850
        )
        XCTAssertEqual(resized.width, 780)
        XCTAssertEqual(resized.height, 280)
    }

    /// 越界夹取：继续往右 / 往下拖到超出上界（宽上界 = 屏宽 − 60，高上界 = min(850, 屏高 × 0.9)），
    /// 继续往左 / 往上拖到低于下界，两个方向都停在边界上——与 `openNotchSize` / `clampedOpenNotchHeight`
    /// 的 `min(max(v, 下界), 上界)` 同一口径。
    func testResizedPanelSizeClampsBothDirections() {
        let oversized = resizedPanelSize(
            start: CGSize(width: 840, height: 400),
            translation: CGSize(width: 10_000, height: 10_000),
            minWidth: 640, maxWidth: 1452,
            minHeight: 120, maxHeight: 850
        )
        XCTAssertEqual(oversized.width, 1452, "拖过宽上界 → 停在屏宽 − 60")
        XCTAssertEqual(oversized.height, 850, "拖过高上界 → 停在 850（或屏高 × 0.9 更小者）")

        let undersized = resizedPanelSize(
            start: CGSize(width: 840, height: 400),
            translation: CGSize(width: -10_000, height: -10_000),
            minWidth: 640, maxWidth: 1452,
            minHeight: 120, maxHeight: 850
        )
        XCTAssertEqual(undersized.width, 640, "拖过宽下界 → 停在推荐最小宽度")
        XCTAssertEqual(undersized.height, 120, "拖过高下界 → 停在 120")
    }

    /// 零位移不动：按下就松手（`DragGesture(minimumDistance: 0)` 的单击）不改变尺寸。
    func testResizedPanelSizeKeepsStartOnZeroTranslation() {
        let start = CGSize(width: 840, height: 400)
        XCTAssertEqual(
            resizedPanelSize(
                start: start,
                translation: .zero,
                minWidth: 640, maxWidth: 1452,
                minHeight: 120, maxHeight: 850
            ),
            start,
            "零位移 → 原样返回起点（不会因为取整 / 夹取动一下）"
        )
        XCTAssertEqual(
            resizedPanelSize(
                start: start,
                translation: .zero,
                minWidth: 880, maxWidth: 1452,
                minHeight: 500, maxHeight: 850
            ),
            CGSize(width: 880, height: 500),
            "起点本身越界时，零位移也被抬到下界（存量默认值超界时拖动会先落到合法区间）"
        )
    }

    /// 非有限值一律退回下界 / 按 0 处理（同 `clampedOpenNotchHeight` 对 NaN 的处理）：
    /// 不把 NaN / ∞ 写进 `Defaults`（那会让面板尺寸整块失效）。
    func testResizedPanelSizeFallsBackOnNonFiniteValues() {
        XCTAssertEqual(
            resizedPanelSize(
                start: CGSize(width: 840, height: 400),
                translation: CGSize(width: CGFloat.nan, height: .infinity),
                minWidth: 640, maxWidth: 1452,
                minHeight: 120, maxHeight: 850
            ),
            CGSize(width: 840, height: 400),
            "非有限位移按 0 处理 → 尺寸不变（不是弹到边界）"
        )
        XCTAssertEqual(
            resizedPanelSize(
                start: CGSize(width: CGFloat.nan, height: CGFloat.nan),
                translation: CGSize(width: 100, height: 100),
                minWidth: 640, maxWidth: 1452,
                minHeight: 120, maxHeight: 850
            ),
            CGSize(width: 740, height: 220),
            "非有限起点退回下界，再叠加位移（640 + 100 / 120 + 100）"
        )
    }

    /// 判据与**档位数量**同源：给 `NotchPanelBackgroundStyle` 加第四档时，这条会失败并提醒
    /// 「新档要不要显示遮罩」必须显式表态（而不是默默沿用某个默认）。
    func testScrollFadeMaskDecisionCoversEveryPanelBackgroundStyle() {
        let shownStyles = NotchPanelBackgroundStyle.allCases.filter {
            shouldShowScrollFadeMask(panelBackgroundStyle: $0)
        }
        XCTAssertEqual(
            shownStyles,
            [.solidBlack],
            "三档里**只有纯黑档**显示遮罩；新增档位必须在此显式登记"
        )
    }

    /// 主面板背景键的**声明默认值** + 三档取值词汇表 + **序列化往返**（写盘 → 读回）。
    ///
    /// 默认必须是 `.solidBlack`：改造前主面板底是 `ContentView` 里写死的 `.background(.black)`，
    /// 新键的默认值不该改变任何老用户的观感（升级即变色是回归）。
    /// 往返走临时 suite（不碰开发机 `com.cmeng.gourd` 域）：枚举存的是 `rawValue` 字符串
    /// （`RawRepresentable` 桥，同 `notificationHUDBackgroundStyle`），因此断言盘上真的出现
    /// `"Liquid glass"` 而不只是一个内存值。
    func testNotchPanelBackgroundStyleKeyDefaultsAndRoundTrip() {
        XCTAssertEqual(Defaults.Keys.notchPanelBackgroundStyle.name, "notchPanelBackgroundStyle")
        XCTAssertEqual(
            Defaults.Keys.notchPanelBackgroundStyle.defaultValue,
            .solidBlack,
            "默认纯黑（与改造前写死的 .background(.black) 完全一致）"
        )

        // 取值词汇表：rawValue 是设置页 Picker 直接显示的字面量（同 OSD 的 Material 选择器）
        XCTAssertEqual(
            NotchPanelBackgroundStyle.allCases.map(\.rawValue),
            ["Solid black", "Liquid glass", "Frosted glass"]
        )
        XCTAssertEqual(NotchPanelBackgroundStyle(rawValue: "Liquid glass"), .liquidGlass)
        XCTAssertEqual(NotchPanelBackgroundStyle(rawValue: "Frosted glass"), .frostedGlass)
        XCTAssertEqual(Set(NotchPanelBackgroundStyle.allCases.map(\.id)).count, 3, "三档 id 互不相同")

        let suiteName = "com.cmeng.gourd.tests.notchPanelBackgroundStyle"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return XCTFail("建不出临时 suite（\(suiteName)）")
        }
        defer { suite.removePersistentDomain(forName: suiteName) }
        let key = Defaults.Key<NotchPanelBackgroundStyle>(
            "notchPanelBackgroundStyle",
            default: .solidBlack,
            suite: suite
        )

        XCTAssertEqual(Defaults[key], .solidBlack, "没写过时读回声明默认值")
        Defaults[key] = .liquidGlass
        XCTAssertEqual(Defaults[key], .liquidGlass, "写盘 → 读回同一档")
        XCTAssertEqual(suite.string(forKey: key.name), "Liquid glass", "盘上存的就是 rawValue 字符串")
        Defaults[key] = .frostedGlass
        XCTAssertEqual(Defaults[key], .frostedGlass, "第三档同样往返")
        XCTAssertEqual(suite.string(forKey: key.name), "Frosted glass")
        Defaults[key] = .solidBlack
        XCTAssertEqual(Defaults[key], .solidBlack, "再切回默认档同样往返")
    }

    /// **固定尺寸与内容无关**（用户：「外接屏可以显示，但尺寸不固定」）：`metrics` 只吃倍率——
    /// 卡片没有「按内容」「按刘海 / 非刘海屏」的第二条输入，内容再长也不改尺寸
    /// （超长内容按 `lineLimit` 在卡片内截断，见 `hudDetail` 的用例）。
    func testNotificationHUDCardMetricsDependOnScaleOnly() {
        let scaleOne = NotificationHUDCardLayout.metrics(scale: 1.0)
        XCTAssertEqual(scaleOne.cardSize, CGSize(width: 320, height: 64), "同一倍率只有一个尺寸")
        // 文字列宽度是「卡片宽度 − 其它元素」的确定值：不同倍率下按同一条算式缩放
        let ratio = scaleOne.textMaxWidth / scaleOne.cardSize.width
        let largeRatio = NotificationHUDCardLayout.metrics(scale: 2.0).textMaxWidth
            / NotificationHUDCardLayout.metrics(scale: 2.0).cardSize.width
        XCTAssertEqual(ratio, largeRatio, accuracy: 0.01, "文字列占比不随倍率变（同一套算式）")
    }

    /// **高度预算够「标题 + 正文 2 行」**（实测踩到的坑，钉住它）：固定高度 64 × 倍率，
    /// 上下内边距若与左右同档（10 × 倍率 = 13pt），正文会被挤成 **1 行 + `…`**——
    /// 长正文通知因此丢掉了「最多 2 行」的呈现。所以垂直内边距单列一档（5 × 倍率）。
    ///
    /// 估算口径：系统字体的行高按 **1.3 × 字号**算（保守偏大）；要求
    /// `标题 + 行间距 + 2 × 正文 ≤ 卡片高度 − 上下内边距`。
    func testNotificationHUDCardHeightFitsTitleAndTwoBodyLines() {
        for scale in [0.8, 1.0, 1.3, 2.0] {
            let metrics = NotificationHUDCardLayout.metrics(scale: scale)
            let contentHeight = metrics.cardSize.height - metrics.verticalPadding * 2
            let needed = metrics.titleSize * 1.3 + metrics.lineSpacing + metrics.bodySize * 1.3 * 2
            XCTAssertLessThanOrEqual(needed, contentHeight, "倍率 \(scale)：高度预算不够 2 行正文（会被挤成 1 行 + …）")
            XCTAssertLessThan(metrics.verticalPadding, metrics.padding, "垂直内边距必须比水平小一档")
        }

        // 反证：上下内边距与左右同档时预算不够（这就是修复前的形态）
        let defaultMetrics = NotificationHUDCardLayout.metrics(scale: 1.3)
        let uniformPaddingBudget = defaultMetrics.cardSize.height - defaultMetrics.padding * 2
        let needed = defaultMetrics.titleSize * 1.3 + defaultMetrics.lineSpacing + defaultMetrics.bodySize * 1.3 * 2
        XCTAssertGreaterThan(
            needed,
            uniformPaddingBudget,
            "同档内边距下确实装不下（记录的实测根因：\(needed) > \(uniformPaddingBudget)）"
        )
    }

    /// 键本身的口径：`notificationHUDScale` 的**声明默认值是 1.3**（2026-09-28 用户要求
    /// 「外接屏太小，需要调大一些」）——断言读 `defaultValue`，不受开发机上真实 UserDefaults 影响。
    func testNotificationHUDScaleKeyDefaultsToLargerThanBefore() {
        XCTAssertEqual(Defaults.Keys.notificationHUDScale.name, "notificationHUDScale", "键名与设置滑块一致")
        XCTAssertEqual(Defaults.Keys.notificationHUDScale.defaultValue, 1.3, accuracy: 0.0001)
        XCTAssertGreaterThan(
            Defaults.Keys.notificationHUDScale.defaultValue,
            1.0,
            "默认必须比改造前大（改造前的字号口径 = 1.0）"
        )
        // 默认值必须落在滑块区间内，否则设置页一打开滑块就跳到端点
        XCTAssertTrue(
            NotificationHUDCardLayout.scaleRange.contains(Defaults.Keys.notificationHUDScale.defaultValue),
            "默认值必须落在 \(NotificationHUDCardLayout.scaleRange) 内"
        )
    }

    /// **新记录筛选**是纯函数（实时化的核心判据）：`id > 基线`、**按 id 升序**、**按 id 去重**。
    ///
    /// 它与 SQL 侧的 `WHERE rec_id > ? ORDER BY rec_id ASC` 是同一口径——单测钉住它，
    /// 就不必为了验证「哪些算新增」去读真实的系统通知库（那既慢又要完全磁盘访问）。
    func testNotificationNewRecordsFilterSortAndDeduplicate() {
        // 空集：没有输入就没有输出（事件驱动下"文件变了但没有新记录"是常态，不能崩）
        XCTAssertTrue(NotificationStore.newRecords(in: [], above: 10).isEmpty)
        XCTAssertTrue(NotificationStore.newRecords(in: [], above: 0).isEmpty)

        // 全部 ≤ 基线：旧记录一条都不算新增（含**恰好等于基线**的那条——判据是 `>` 不是 `>=`）
        XCTAssertTrue(
            NotificationStore.newRecords(
                in: [notificationItem(3), notificationItem(9), notificationItem(10)],
                above: 10
            ).isEmpty
        )

        // 乱序输入 → 输出按 id 升序（调用方按到达顺序累加，`hudCandidate` 取 `.last` = 最新）
        XCTAssertEqual(
            NotificationStore.newRecords(
                in: [notificationItem(15), notificationItem(11), notificationItem(18), notificationItem(13)],
                above: 10
            ).map(\.id),
            [11, 13, 15, 18]
        )

        // 重复 id（同一批里重复投递 / 事件重放）只算一条：不过滤会让未读数虚高
        XCTAssertEqual(
            NotificationStore.newRecords(
                in: [notificationItem(11), notificationItem(12), notificationItem(11), notificationItem(12)],
                above: 10
            ).map(\.id),
            [11, 12]
        )

        // 重复 + 乱序 + 基线的混合：一条不多、一条不少、顺序稳定
        XCTAssertEqual(
            NotificationStore.newRecords(
                in: [
                    notificationItem(10), notificationItem(12), notificationItem(11),
                    notificationItem(2), notificationItem(12), notificationItem(11),
                ],
                above: 10
            ).map(\.id),
            [11, 12]
        )

        // 基线 0（空库 / 首次取数）：全部都是新增，整段升序
        XCTAssertEqual(
            NotificationStore.newRecords(in: [notificationItem(2), notificationItem(1)], above: 0).map(\.id),
            [1, 2]
        )
        // 负基线（理论上的回退）不改变判据
        XCTAssertEqual(NotificationStore.newRecords(in: [notificationItem(1)], above: -5).map(\.id), [1])
    }

    /// 浮层候选与新记录筛选是同一口径（`hudCandidate` = 升序结果的 `.last`）：
    /// 去重不会让「最新那一条」变成别人，`>` 基线也不会漏掉紧邻基线的第一条。
    func testNotificationHUDCandidateMatchesNewRecordsOrdering() {
        let newItems = [notificationItem(12), notificationItem(11), notificationItem(12)]
        XCTAssertEqual(NotificationStore.newRecords(in: newItems, above: 10).last?.id, 12)
        XCTAssertEqual(NotificationStore.hudCandidate(in: newItems, above: 10)?.id, 12)
        // 只有一条晚于基线时，浮层就是那一条（实时性验收里最常见的形态）
        XCTAssertEqual(NotificationStore.hudCandidate(in: [notificationItem(4), notificationItem(11)], above: 10)?.id, 11)
        XCTAssertNil(NotificationStore.hudCandidate(in: [notificationItem(4), notificationItem(10)], above: 10))
    }

    /// 事件驱动 / 兜底轮询的两个常量口径：兜底是 **60s**（原来 30s 轮询的替代），
    /// 不能再回到「亚秒轮询」——实时性由文件事件负责（09 §5.5）。
    func testNotificationFallbackPollIntervalIsCoarse() {
        XCTAssertEqual(NotificationStore.fallbackPollInterval, 60, "兜底轮询是 60s；实时性靠文件事件")
    }

    /// 「关闭 / 清除」的过滤是**纯函数**：`fetchRecent` / `fetchNew` 返回前按 id 滤掉已关闭的条目。
    ///
    /// 这是只读原则在代码上的落点：**过滤只发生在我们这一侧**，函数既不排序也不去重，
    /// 更不触碰任何库状态——关闭只是「岛上不再显示这一条」。
    func testNotificationDismissedFilterIsPure() {
        let items = [notificationItem(11), notificationItem(12), notificationItem(13)]

        // 没有已关闭条目（热路径）：原样返回，且**同一个数组实例**
        let untouched = NotificationCenterReader.visible(in: items, excluding: [])
        XCTAssertEqual(untouched.map(\.id), [11, 12, 13])

        // 空输入：空输出（不给下游留 nil/崩溃路径）
        XCTAssertTrue(NotificationCenterReader.visible(in: [], excluding: [11, 12]).isEmpty)

        // 滤掉命中项，保持输入顺序（不排序、不去重）
        XCTAssertEqual(
            NotificationCenterReader.visible(in: items, excluding: [12]).map(\.id),
            [11, 13]
        )
        // 关闭集合里有「不在这一批里」的 id：不影响结果（跨批次的关闭状态）
        XCTAssertEqual(
            NotificationCenterReader.visible(in: items, excluding: [1, 99, 1000]).map(\.id),
            [11, 12, 13]
        )
        // 全部关闭 → 空列表（面板显示「暂无通知」，不是错误）
        XCTAssertTrue(NotificationCenterReader.visible(in: items, excluding: [11, 12, 13]).isEmpty)
    }

    /// 已关闭集合的**落盘裁剪**是纯函数：只保留最近 `limit` 个（尾部 = 最近关闭的）并去重。
    /// 上限存在的意义是「用一年后 UserDefaults 里不该堆几万个 id」。
    func testNotificationDismissedTrimmingKeepsMostRecent() {
        XCTAssertEqual(NotificationStore.dismissedLimit, 500, "上限口径：保留最近 500 个")

        // 未超上限：原样（保序）
        XCTAssertEqual(NotificationStore.trimmed([3, 1, 2], limit: 5), [3, 1, 2])
        // 恰好等于上限：不裁剪
        XCTAssertEqual(NotificationStore.trimmed([1, 2, 3], limit: 3), [1, 2, 3])
        // 超上限：只留**最近** limit 个（尾部），最旧的被丢掉
        XCTAssertEqual(NotificationStore.trimmed([1, 2, 3, 4, 5], limit: 3), [3, 4, 5])
        // 重复 id 去重（重复只算一次关闭）
        XCTAssertEqual(NotificationStore.trimmed([7, 7, 8, 8, 9], limit: 10), [7, 8, 9])
        // 去重后再裁剪：`[5,5,6,6,7,7]` 去重成 3 个，limit 2 → 留最近两个
        XCTAssertEqual(NotificationStore.trimmed([5, 5, 6, 6, 7, 7], limit: 2), [6, 7])
        // 边界：空输入、limit 0（丢弃一切）、limit 1
        XCTAssertTrue(NotificationStore.trimmed([], limit: 10).isEmpty)
        XCTAssertTrue(NotificationStore.trimmed([1, 2, 3], limit: 0).isEmpty)
        XCTAssertEqual(NotificationStore.trimmed([1, 2, 3], limit: 1), [3])
    }

    /// `dismissedNotificationIDs` 键本身的口径：键名与类型（`[Int]`）固定，默认空。
    /// 断言读 `defaultValue` 而不是当前生效值——不受开发机上真实 UserDefaults 影响。
    func testDismissedNotificationIDsKeyShape() {
        XCTAssertEqual(Defaults.Keys.dismissedNotificationIDs.name, "dismissedNotificationIDs")
        XCTAssertEqual(Defaults.Keys.dismissedNotificationIDs.defaultValue, [], "默认没有已关闭条目")
    }

    /// `notificationsRecordIDWatermark` 键本身的口径（P16 T2）：键名固定、类型 `Int`、**默认 0**
    /// ——默认 0 是自愈判据的前提（首启水位线为 0 时任何正数都算「前进」，绝不误判回退）。
    /// 断言读 `defaultValue` 而不是当前生效值——不受开发机上真实 UserDefaults 影响。
    func testNotificationsRecordIDWatermarkKeyShape() {
        XCTAssertEqual(Defaults.Keys.notificationsRecordIDWatermark.name, "notificationsRecordIDWatermark")
        XCTAssertEqual(Defaults.Keys.notificationsRecordIDWatermark.defaultValue, 0, "默认 0：没记过水位线")
    }

    // MARK: - AX 横幅通道（P2e：实时 + 真关闭）

    /// **本机实测（macOS 27）**的横幅树形状 → 解析结果。
    ///
    /// 夹具逐字对齐 `~/Library/Logs/Gourd/ax-banner-probe.log` 里的真配置探针原文：
    /// 静态文本是 标题 → 副标题 → 正文（App 名**不在**里面）；关闭是**横幅容器上的自定义动作**，
    /// 名字含「关闭」；容器描述形如 `"<App 名> <标题>, <副标题>, <正文>"`。
    func testNotificationBannerParseMatchesMacOS27Shape() {
        let snapshot = Self.bannerSnapshot(
            description: "脚本编辑器 无副标题测试, 正文只有一行",
            texts: ["无副标题测试", "正文只有一行"],
            actions: ["AXPress", "Name:关闭\nTarget:0x0\nSelector:(null)"]
        )

        let content = NotificationBannerParser.parse(snapshot)
        XCTAssertTrue(content.foundBannerRoot, "subrole=AXNotificationCenterBanner 必须被认成横幅")
        XCTAssertEqual(content.appName, "脚本编辑器", "App 名从容器描述首段剥掉标题得到")
        XCTAssertEqual(content.title, "无副标题测试", "第一个静态文本 = 标题")
        XCTAssertEqual(content.subtitle, "", "两个静态文本时没有副标题")
        XCTAssertEqual(content.body, "正文只有一行", "最后一个静态文本 = 正文")
        XCTAssertEqual(content.closeActionName, "Name:关闭\nTarget:0x0\nSelector:(null)", "自定义动作名要原样保留（截断就执行不了）")
        XCTAssertEqual(content.closeLabel, "自定义动作: Name:关闭\nTarget:0x0\nSelector:(null)")

        // 带副标题（三个静态文本）：标题 / 副标题 / 正文 依次取
        let withSubtitle = NotificationBannerParser.parse(
            Self.bannerSnapshot(
                description: "脚本编辑器 AX 探针, 副标题, AX 实时测试",
                texts: ["AX 探针", "副标题", "AX 实时测试"],
                actions: ["AXPress", "Name:关闭\nTarget:0x0\nSelector:(null)"]
            )
        )
        XCTAssertEqual(withSubtitle.appName, "脚本编辑器")
        XCTAssertEqual(withSubtitle.title, "AX 探针")
        XCTAssertEqual(withSubtitle.subtitle, "副标题")
        XCTAssertEqual(withSubtitle.body, "AX 实时测试")
    }

    /// 关闭控件的**两条路**与「没有关闭控件」：按钮（`AXPress`）优先于自定义动作；
    /// 都没有时 `closeActionName == nil`（调用方据此退化为「仅从岛上隐藏」）。
    func testNotificationBannerCloseControlVariants() {
        // ① 真按钮（带副标题的横幅本机偶尔暴露）：命中后动作用 AXPress
        let button = NotificationBannerParser.parse(
            Self.bannerSnapshot(
                description: "脚本编辑器 标题, 正文",
                texts: ["标题", "正文"],
                buttons: ["显示", "关闭"],
                actions: ["AXPress"]
            )
        )
        XCTAssertEqual(button.closeActionName, kAXPressAction as String)
        XCTAssertEqual(button.closeLabel, "AXButton: 关闭")

        // ② 英文按钮 + 其它关键词（大小写不敏感）
        XCTAssertEqual(
            NotificationBannerParser.parse(Self.bannerSnapshot(buttons: ["CLOSE"])).closeActionName,
            kAXPressAction as String
        )
        XCTAssertEqual(
            NotificationBannerParser.parse(Self.bannerSnapshot(buttons: ["Dismiss"])).closeActionName,
            kAXPressAction as String
        )
        XCTAssertEqual(
            NotificationBannerParser.parse(Self.bannerSnapshot(buttons: ["清除"])).closeActionName,
            kAXPressAction as String
        )
        // ③ 非关闭按钮（「显示」）不算
        XCTAssertNil(NotificationBannerParser.parse(Self.bannerSnapshot(buttons: ["显示"])).closeActionName)
        // ④ 都没有 → nil
        let none = NotificationBannerParser.parse(Self.bannerSnapshot(texts: ["标题"]))
        XCTAssertNil(none.closeActionName)
        XCTAssertNil(none.closeLabel)

        // ⑤ 关键词判据本身
        XCTAssertTrue(NotificationBannerParser.matchesCloseKeyword("Close"))
        XCTAssertTrue(NotificationBannerParser.matchesCloseKeyword("关闭"))
        XCTAssertTrue(NotificationBannerParser.matchesCloseKeyword("dismiss notification"))
        XCTAssertFalse(NotificationBannerParser.matchesCloseKeyword("显示"))
        XCTAssertFalse(NotificationBannerParser.matchesCloseKeyword(""))
    }

    /// **防御式解析**（AX 树随系统版本变）：
    /// 空树 / 没有横幅子角色 / App 名剥不出来 / 超深超宽 —— 一律给空值，**不崩不抛**。
    func testNotificationBannerParseIsDefensive() {
        let empty = NotificationBannerParser.parse(AXNodeSnapshot())
        XCTAssertFalse(empty.foundBannerRoot)
        XCTAssertFalse(empty.hasContent)
        XCTAssertNil(empty.closeActionName)

        // 没有横幅子角色（例如通知中心面板开着）：仍尽力解析，但 foundBannerRoot = false
        let panel = NotificationBannerParser.parse(
            AXNodeSnapshot(
                role: "AXWindow",
                title: "Notification Center",
                children: [AXNodeSnapshot(role: "AXStaticText", value: "某条通知")]
            )
        )
        XCTAssertFalse(panel.foundBannerRoot, "不是横幅窗口不得被认成横幅")
        XCTAssertEqual(panel.title, "某条通知", "兜底解析仍给出尽力而为的结果（探针要它）")
        XCTAssertEqual(panel.appName, "", "描述为空 → 不猜 App 名")

        // App 名剥不出来（描述首段就是标题本身）→ 给空串，**不把标题当 App 名**
        XCTAssertEqual(
            NotificationBannerParser.appName(fromDescription: "标题甲", title: "标题甲", body: "正文"),
            ""
        )
        XCTAssertEqual(NotificationBannerParser.appName(fromDescription: "", title: "标题", body: ""), "")
        // 描述首段以正文结尾（标题为空）也能剥
        XCTAssertEqual(
            NotificationBannerParser.appName(fromDescription: "脚本编辑器 正文乙", title: "", body: "正文乙"),
            "脚本编辑器"
        )

        // 超深树：不爆栈、不卡死（深度上限 8）
        var deep = AXNodeSnapshot(role: "AXStaticText", value: "最深处")
        for _ in 0..<40 { deep = AXNodeSnapshot(role: "AXGroup", children: [deep]) }
        _ = NotificationBannerParser.parse(deep)
        XCTAssertLessThanOrEqual(NotificationBannerParser.render(deep).count, NotificationBannerParser.maxNodes + 1)

        // 超宽树：节点数上限 200，渲染截断并留一行说明
        let wide = AXNodeSnapshot(
            role: "AXGroup",
            children: (0..<500).map { AXNodeSnapshot(role: "AXStaticText", value: "第 \($0) 条") }
        )
        XCTAssertLessThanOrEqual(NotificationBannerParser.render(wide).count, NotificationBannerParser.maxNodes + 1)
        XCTAssertGreaterThanOrEqual(NotificationBannerParser.staticTexts(in: wide).count, 1)
    }

    /// 探针渲染：一行一个元素、关键字段齐全、换行转义（BOM 是单文件追加，靠这些行 grep）。
    func testNotificationBannerProbeRendering() {
        let snapshot = Self.bannerSnapshot(
            description: "脚本编辑器 标题, 正文",
            texts: ["标题", "正文"],
            actions: ["Name:关闭\nTarget:0x0\nSelector:(null)"]
        )
        let lines = NotificationBannerParser.render(snapshot)
        XCTAssertGreaterThan(lines.count, 3)
        let bannerLine = lines.first { $0.contains(NotificationBannerParser.bannerSubrole) }
        XCTAssertNotNil(bannerLine, "探针必须写出横幅容器那一行（校准靠它）")
        XCTAssertTrue(bannerLine?.contains("description=") == true)
        XCTAssertTrue(bannerLine?.contains("actions=") == true)
        XCTAssertFalse(lines.joined().contains("\n\n"), "动作名里的换行必须转义，否则一行一个元素的约定就废了")

        XCTAssertEqual(NotificationBannerParser.escaped("a\"b\nc", limit: 80), "a\\\"b\\nc")
        XCTAssertEqual(NotificationBannerParser.escaped(String(repeating: "x", count: 100), limit: 10).count, 11, "超长截断 + 省略号")
    }

    /// 指纹归一化：去首尾空白、折叠内部空白、小写——AX 的 App 名与 DB 的 App 名来源不同，
    /// 不归一化就会「同一条通知弹两次」。
    func testNotificationFingerprintNormalization() {
        let axSide = NotificationFingerprint(appName: "脚本编辑器", title: "构建 完成", body: "全部通过")
        let dbSide = NotificationFingerprint(appName: " 脚本编辑器 ", title: "构建\t完成", body: "全部通过\n")
        XCTAssertEqual(axSide, dbSide, "空白/大小写差异不得影响去重")
        XCTAssertNotEqual(axSide, NotificationFingerprint(appName: "脚本编辑器", title: "构建 完成", body: "别的正文"))
        XCTAssertNotEqual(axSide, NotificationFingerprint(appName: "别的 App", title: "构建 完成", body: "全部通过"))
        XCTAssertEqual(NotificationFingerprint.normalized("  A  b\nC "), "a b c")
        XCTAssertEqual(NotificationFingerprint.normalized(""), "")
    }

    /// 去重台账（**AX 优先** + 10s 窗口 + 句柄台账）：
    /// - 同指纹 10s 内只弹一次：AX 先到 → DB 那条（约 5s 后）不再弹浮层；
    /// - AX 没到（未授权 / 树变了）时 DB 照常弹——两条通道都不会被对方饿死；
    /// - 窗口过期后同指纹可再弹；
    /// - 窗口期内保留 AX 的真关闭句柄，过期即丢；DB 来源不留句柄。
    func testNotificationBannerLedgerDedupWindowAndAXPriority() {
        XCTAssertEqual(NotificationBannerLedger.window, 10, "去重窗口是 10s（覆盖 DB 约 5s 的落盘延迟）")

        let key = NotificationFingerprint(appName: "邮件", title: "新邮件", body: "来自张三")
        let other = NotificationFingerprint(appName: "邮件", title: "新邮件", body: "来自李四")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var ledger = NotificationBannerLedger()

        // AX 先到：弹
        XCTAssertTrue(ledger.shouldPresent(key, source: .ax, now: start))
        // 同指纹再来（AX 重放 / DB 那条晚到 5s）：窗口内不弹（**AX 优先**）
        XCTAssertFalse(ledger.shouldPresent(key, source: .ax, now: start.addingTimeInterval(0.4)))
        XCTAssertFalse(ledger.shouldPresent(key, source: .database, now: start.addingTimeInterval(5.1)))
        // 不同指纹不受影响（未读数与列表照旧，只是浮层不重复）
        XCTAssertTrue(ledger.shouldPresent(other, source: .database, now: start.addingTimeInterval(5.2)))
        // 窗口外（≥ 10s）同指纹可再弹
        XCTAssertFalse(ledger.shouldPresent(key, source: .database, now: start.addingTimeInterval(9.9)))
        XCTAssertTrue(ledger.shouldPresent(key, source: .database, now: start.addingTimeInterval(10.1)))
        // 台账不随运行时长增长：过期登记会被清掉（20.2s 时前两条登记都已过期，只剩刚登记的这条）
        XCTAssertEqual(ledger.count, 2, "10.1s：key 刚登记，other（5.2s 登记）仍在 10s 窗口内")
        XCTAssertTrue(ledger.shouldPresent(key, source: .ax, now: start.addingTimeInterval(20.2)))
        XCTAssertEqual(ledger.count, 1, "两条旧登记都已过期并被清掉，台账只保存最近 10s 内的")

        // 反向：DB 先到（AX 没拿到）→ AX 后到来时窗口内不弹，但通道本身没死
        var databaseFirst = NotificationBannerLedger()
        XCTAssertTrue(databaseFirst.shouldPresent(key, source: .database, now: start))
        XCTAssertFalse(databaseFirst.shouldPresent(key, source: .ax, now: start.addingTimeInterval(1)))
        XCTAssertTrue(databaseFirst.shouldPresent(key, source: .ax, now: start.addingTimeInterval(11)))
    }

    /// 真关闭句柄的台账口径：**只有 AX 来源**在窗口期内能取到句柄，过期即 nil，DB 来源恒 nil。
    func testNotificationBannerLedgerCloseHandleWindow() {
        let key = NotificationFingerprint(appName: "邮件", title: "新邮件", body: "来自张三")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var ledger = NotificationBannerLedger()

        // DB 来源：窗口期内也取不到句柄（它没有 AX 横幅）
        XCTAssertTrue(ledger.shouldPresent(key, source: .database, now: start))
        XCTAssertNil(ledger.closeHandle(for: key, now: start.addingTimeInterval(1)))

        // 同指纹的 AX 横幅在窗口外到来 → 登记成功；窗口内可取句柄
        let later = start.addingTimeInterval(11)
        let handle = Self.closeHandleFixture()
        XCTAssertTrue(ledger.shouldPresent(key, source: .ax, closeHandle: handle, now: later))
        XCTAssertEqual(ledger.closeHandle(for: key, now: later.addingTimeInterval(9.9))?.label, handle.label)
        XCTAssertNil(ledger.closeHandle(for: key, now: later.addingTimeInterval(10.1)), "过期即丢")
        XCTAssertNil(ledger.closeHandle(for: NotificationFingerprint(appName: "别的", title: "", body: ""), now: later))
    }

    /// **列表行 × 的谓词**（`NotificationStore.willAlsoCloseSystemBanner`）——`d23ede48` 留的缺口的补口
    /// （docs/21 §已知限制 10 记过：「谓词恒 false 时全量用例无一条变红」）。
    ///
    /// 构造方式照 `testNotificationBannerLedgerCloseHandleWindow` 的 `closeHandleFixture`：只建一个
    /// **指向本进程**的 AX 对象（不申请权限、不读写任何元素、**不执行任何动作**），登记进台账后由谓词读。
    /// 三档：**有句柄 → true；无句柄（AX 解析不到关闭控件 / DB 通道那条）→ false；超 10 秒窗口 → false**。
    /// 谓词是只读的（§接口与数据形状 3），本用例因此不点任何真实界面——它只回答"文案该说哪一档"。
    func testNotificationListRowClosePredicateFollowsCloseHandleWindow() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let item = Self.notificationItemFixture(id: 91, body: "来自张三")

        // 偏好卫生：`NotificationStore.init` 会读 `dismissedNotificationIDs`（值超上限 / 有重复时顺带
        // 裁剪回写）。本用例只想读谓词——先原样备份、结束时按"原来有没有这个键"原样恢复，
        // **不给开发机的真实域留键、也不改值**（与 `ModuleToggleTests` 的清场口径同一条）。
        let dismissedKey = Defaults.Keys.dismissedNotificationIDs.name
        let savedDismissed = UserDefaults.standard.object(forKey: dismissedKey)
        defer {
            if let savedDismissed {
                UserDefaults.standard.set(savedDismissed, forKey: dismissedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: dismissedKey)
            }
        }

        let store = Self.notificationStoreFixture()

        // ① 什么都没登记：false（没有 AX 横幅就没有句柄，点 × 只从列表移除）
        XCTAssertFalse(store.willAlsoCloseSystemBanner(for: item, now: start))
        XCTAssertNil(store.closeHandle(for: item, now: start), "没登记过就没有句柄")

        // ② 同指纹的 AX 横幅**带句柄**到来 → 窗口内 true（＝ `dismiss` 这一刻会顺带真关）
        let handle = Self.closeHandleFixture()
        XCTAssertTrue(
            store.shouldPresentBanner(
                BannerEvent(
                    appName: "邮件",
                    title: "新邮件",
                    subtitle: "",
                    body: "来自张三",
                    closeHandle: handle,
                    receivedAt: start
                ),
                now: start
            ),
            "首次同指纹：该弹浮层并登记句柄"
        )
        let inWindow = start.addingTimeInterval(9.9)
        XCTAssertTrue(
            store.willAlsoCloseSystemBanner(for: item, now: inWindow),
            "近 10 秒内有同指纹句柄 → 文案说「同时关掉系统通知」，行为侧就必须拿得到句柄"
        )
        XCTAssertEqual(
            store.willAlsoCloseSystemBanner(for: item, now: inWindow),
            store.closeHandle(for: item, now: inWindow) != nil,
            "谓词与 `dismiss` 的判据是同一份（只问真假，不复制第二份）"
        )

        // ③ 超 10 秒：句柄随窗口过期 → false（谓词不得比行为乐观，docs/21 §已知限制 11）
        XCTAssertFalse(
            store.willAlsoCloseSystemBanner(for: item, now: start.addingTimeInterval(10.1)),
            "窗口过期后只从列表移除，谓词必须跟着变 false"
        )

        // ④ 同窗口内、另一个指纹**没有句柄**（横幅在，但解析不到关闭控件那一档）→ false
        let handlelessItem = Self.notificationItemFixture(id: 92, body: "来自李四")
        XCTAssertTrue(
            store.shouldPresentBanner(
                BannerEvent(
                    appName: "邮件",
                    title: "新邮件",
                    subtitle: "",
                    body: "来自李四",
                    closeHandle: nil,
                    receivedAt: start.addingTimeInterval(0.5)
                ),
                now: start.addingTimeInterval(0.5)
            ),
            "不同指纹不受影响（窗口按指纹分开）"
        )
        XCTAssertFalse(
            store.willAlsoCloseSystemBanner(for: handlelessItem, now: start.addingTimeInterval(1)),
            "登记过但没句柄 → 只从列表移除"
        )

        // ⑤ DB 通道那一条：窗口内登记成功，但句柄恒 nil（它本来就没有 AX 横幅）
        let databaseItem = Self.notificationItemFixture(id: 93, body: "来自王五")
        XCTAssertTrue(store.shouldPresentDatabaseItem(databaseItem, now: start.addingTimeInterval(2)))
        XCTAssertFalse(
            store.willAlsoCloseSystemBanner(for: databaseItem, now: start.addingTimeInterval(2.1)),
            "数据库通道没有句柄，谓词恒 false"
        )
    }

    /// 通知条目的最小夹具（id + 正文；其余字段固定）——指纹取自 `displayName + title + body`。
    private static func notificationItemFixture(id: Int64, body: String) -> NotificationItem {
        NotificationItem(
            id: id,
            bundleIdentifier: "com.apple.Mail",
            appName: "邮件",
            title: "新邮件",
            subtitle: nil,
            body: body,
            deliveredDate: nil
        )
    }

    /// 通知 store 夹具：**不取数、不监听、不碰 TCC、不碰真实通知库**——`reader` 只存一个不存在的路径
    /// （`NotificationCenterReader.init(databasePath:)` 无 IO），用例只读那份内存台账。
    private static func notificationStoreFixture() -> NotificationStore {
        NotificationStore(
            logger: ModuleLogger(moduleID: "com.cmeng.gourd.notifications", shortID: "notifications"),
            reader: NotificationCenterReader(databasePath: "/nonexistent/gourd-tests/notificationcenter.db")
        )
    }

    /// 造一张**临时**通知库（`record(rec_id, data, delivered_date)`，`data` 列写真的二进制 plist），
    /// 返回库文件 URL——`dismissAll` 语义用例用它把列表喂满，**不碰系统通知库**（临时目录里的新库）。
    ///
    /// 与真库同形的三两处：`rec_id` 单调 id、`data` 是 `["req": [...]]` 形态的二进制 plist、
    /// 另有一张 `app` 表（本夹具不给显示名列，读侧按候选列自动跳过）。
    private static func makeNotificationDatabase(
        records: [(id: Int64, title: String, body: String)]
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gourd-notification-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("db")

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let db
        else { throw NotificationDatabaseFixtureError.sqlite("sqlite3_open_v2 失败") }
        defer { sqlite3_close(db) }

        try sqliteExec(db, "CREATE TABLE record (rec_id INTEGER PRIMARY KEY, data BLOB, delivered_date REAL)")
        try sqliteExec(db, "CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier TEXT)")

        for record in records {
            let payload: [String: Any] = ["req": ["titl": record.title, "body": record.body]]
            let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                db,
                "INSERT INTO record (rec_id, data, delivered_date) VALUES (?, ?, ?)",
                -1, &statement, nil
            ) == SQLITE_OK, let statement
            else { throw NotificationDatabaseFixtureError.sqlite(String(cString: sqlite3_errmsg(db))) }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, record.id)
            data.withUnsafeBytes { buffer in
                _ = sqlite3_bind_blob(
                    statement, 2, buffer.baseAddress, Int32(data.count),
                    unsafeBitCast(-1, to: sqlite3_destructor_type.self)  // SQLITE_TRANSIENT
                )
            }
            sqlite3_bind_double(statement, 3, 1_700_000_000 + Double(record.id))  // Unix 秒（读侧按启发式认）
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NotificationDatabaseFixtureError.sqlite(String(cString: sqlite3_errmsg(db)))
            }
        }
        return url
    }

    /// 对**已存在**的临时通知库执行一句 SQL：只给用例改夹具用（例如删掉高号记录，模拟
    /// 「库被重建、编号回退」）。路径由调用方给出，**绝不指向系统通知库**。
    private static func execNotificationDatabase(at url: URL, sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            throw NotificationDatabaseFixtureError.sqlite("sqlite3_open_v2 失败（\(url.path)）")
        }
        defer { sqlite3_close(db) }
        try sqliteExec(db, sql)
    }

    /// 一句 `sqlite3_exec`（夹具建表用；失败抛错而不是默默吞掉）。
    private static func sqliteExec(_ db: OpaquePointer, _ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "未知错误"
            sqlite3_free(errorPointer)
            throw NotificationDatabaseFixtureError.sqlite("\(sql)：\(message)")
        }
    }

    /// 模块接缝：DB 侧指纹取自 `NotificationItem`（`displayName + title + body`），
    /// 与 AX 侧的 `BannerEvent.fingerprint` 同一口径 —— 这条钉住「两条通道能对上」。
    func testNotificationFingerprintFromItemMatchesBannerEvent() {
        let item = NotificationItem(
            id: 77,
            bundleIdentifier: "com.apple.Mail",
            appName: "邮件",
            title: "新邮件",
            subtitle: nil,
            body: "来自张三",
            deliveredDate: nil
        )
        let event = BannerEvent(
            appName: "邮件",
            title: "新邮件",
            subtitle: "",
            body: "来自张三",
            closeHandle: Self.closeHandleFixture(),
            receivedAt: Date()
        )
        XCTAssertEqual(NotificationStore.fingerprint(for: item), event.fingerprint, "两条通道的指纹必须一致，否则去重失效")

        // 没有显示名时退回 bundle id（`displayName` 的兜底链）
        let unnamed = NotificationItem(
            id: 78,
            bundleIdentifier: "com.apple.Mail",
            appName: "",
            title: "新邮件",
            subtitle: nil,
            body: "来自张三",
            deliveredDate: nil
        )
        XCTAssertEqual(NotificationStore.fingerprint(for: unnamed).appName, "com.apple.mail")
    }

    /// AX 通道新增文案：× 的「真关闭」提示必须能解析出译文（06 §3.3 R5 的 key 形态）。
    func testNotificationCloseSystemKeyResolves() {
        let localized = Bundle.main.localizedString(
            forKey: "module.notifications.closeSystemNotification",
            value: nil,
            table: nil
        )
        XCTAssertNotEqual(localized, "module.notifications.closeSystemNotification", "key 没解析出文案")
        XCTAssertFalse(localized.isEmpty)
    }

    /// 关闭句柄夹具：**只构造、不执行**（单测不该起 AX IPC、也不该动任何真实界面）。
    /// `AXUIElementCreateApplication(getpid())` 只建一个指向本进程的 CF 对象——不申请权限、
    /// 不读写任何元素；台账只搬运这个句柄，从不碰它的内容。
    private static func closeHandleFixture(label: String = "自定义动作: 关闭") -> NotificationBannerCloseHandle {
        NotificationBannerCloseHandle(
            element: AXUIElementCreateApplication(getpid()),
            actionName: "关闭",
            label: label
        )
    }

    /// 构造一棵**横幅树**夹具（形状逐字对齐真探针原文；`buttons` 可选，macOS 27 通常没有）。
    private static func bannerSnapshot(
        description: String = "",
        texts: [String] = [],
        buttons: [String] = [],
        actions: [String] = []
    ) -> AXNodeSnapshot {
        var bannerChildren = texts.map { AXNodeSnapshot(role: "AXStaticText", value: $0) }
        bannerChildren += buttons.map { AXNodeSnapshot(role: "AXButton", description: $0) }
        let banner = AXNodeSnapshot(
            role: "AXGroup",
            subrole: NotificationBannerParser.bannerSubrole,
            description: description,
            actionNames: actions,
            children: bannerChildren
        )
        return AXNodeSnapshot(
            role: "AXWindow",
            subrole: "AXSystemDialog",
            title: "Notification Center",
            children: [
                AXNodeSnapshot(
                    role: "AXGroup",
                    subrole: "AXHostingView",
                    children: [
                        AXNodeSnapshot(
                            role: "AXGroup",
                            children: [
                                AXNodeSnapshot(role: "AXScrollArea", children: [banner])
                            ]
                        )
                    ]
                )
            ]
        )
    }

    /// 构造一条通知夹具（只关心 id 的用例用它）。
    private func notificationItem(_ id: Int64, title: String = "", body: String = "") -> NotificationItem {
        NotificationItem(
            id: id,
            bundleIdentifier: "com.apple.Mail",
            appName: "邮件",
            title: title,
            subtitle: nil,
            body: body,
            deliveredDate: nil
        )
    }

    /// `modificationDate` 必须把 **WAL 旁文件**算进来（2026-09-28 实测：库是 WAL 模式，
    /// 新通知只改 `db-wal`，主库 mtime 纹丝不动）。只认主库会让 30s 轮询永远早退——
    /// 增量与浮层都不再触发。夹具用临时文件，**不碰系统通知库**。
    func testNotificationReaderModificationDateTracksWALSibling() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gourd-wal-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = directory.appendingPathComponent("db")
        try Data([0x00]).write(to: database)
        let mainDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: mainDate], ofItemAtPath: database.path)

        let reader = NotificationCenterReader(databasePath: database.path)
        XCTAssertEqual(reader.modificationDate, mainDate, "没有 -wal 时退化成只看主库")

        // WAL 比主库新 → 闸门看到的是 WAL 的时间（新通知写在这里）
        let wal = directory.appendingPathComponent("db-wal")
        let walDate = mainDate.addingTimeInterval(600)
        try Data([0x00]).write(to: wal)
        try FileManager.default.setAttributes([.modificationDate: walDate], ofItemAtPath: wal.path)
        XCTAssertEqual(reader.modificationDate, walDate, "WAL 较新时必须取 WAL 的时间")

        // WAL 较旧（例如 checkpoint 后主库被改写）→ 取主库
        try FileManager.default.setAttributes(
            [.modificationDate: mainDate.addingTimeInterval(1200)],
            ofItemAtPath: database.path
        )
        XCTAssertEqual(reader.modificationDate, mainDate.addingTimeInterval(1200), "主库较新时取主库")

        // 库文件不存在 → nil（`pollOnce` 据此报「库文件不可访问」而不是静默早退）
        let missing = NotificationCenterReader(
            databasePath: directory.appendingPathComponent("nope").path
        )
        XCTAssertNil(missing.modificationDate)
    }

    /// 构造二进制 plist 夹具（通知库的 `record.data` 就是二进制 plist）——**不读系统通知库**。
    private static func binaryPlist(_ object: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
    }
}

// MARK: - 假体

/// 临时通知库夹具的失败（只在本文件的 `makeNotificationDatabase` 里用；不是产品错误类型）。
private enum NotificationDatabaseFixtureError: Error {
    case sqlite(String)
}

/// 最小假体：不读也不写，只满足 `ConfigHandle` 的签名（真实现属 T2 的 `ModuleContextFactory`）。
private final class StubConfigHandle: ConfigHandle {
    func get<T: Codable & Sendable>(_ key: String, as: T.Type) -> T? { nil }
    func set<T: Codable & Sendable>(_ key: String, to value: T) -> Bool { false }
}

@MainActor
private final class StubUIHandle: UIHandle {
    var redrawCount = 0
    /// 收到的瞬时浮层请求（`ttl` 逐条记下，断言夹取/覆盖语义时不必等真实到期）。
    var presentedTTLs: [TimeInterval] = []
    /// 收到的主动撤浮层请求次数（只记次数：假体不持有注册表，转发语义由别处钉）。
    var dismissCount = 0
    /// 收到的收起刘海请求次数（D-28）：假体没有窗口，只记「模块调过来了」。
    var collapseCount = 0
    func requestRedraw() { redrawCount += 1 }
    var isLowPower: Bool { false }
    func presentTransient(view: AnyView, ttl: TimeInterval) { presentedTTLs.append(ttl) }
    func dismissTransient() { dismissCount += 1 }
    func requestCollapse() { collapseCount += 1 }
}

@MainActor
private final class StubModule: GourdModule {
    static var manifest: ModuleManifest {
        ModuleManifest(
            manifestVersion: 1,
            id: "com.cmeng.gourd.stub",
            name: LocalizedText(key: "module.stub.name"),
            summary: nil,
            icon: IconSpec(type: "symbol", name: "square"),
            version: "1.0.0",
            apiVersion: HostInfo.currentAPIVersion,
            kind: "builtin",
            surfaces: [.expanded],
            defaultPlacement: nil,
            defaultEnabled: true,
            permissions: [],
            config: nil
        )
    }

    let context: ModuleContext

    init(context: ModuleContext) {
        self.context = context
    }

    func activate() async throws {}
    func deactivate() async {}

    func content(for request: ContentRequest) -> ModuleContent {
        .unavailable(reason: "stub 未实现内容")
    }
}

// MARK: - T2 假模块（注册表夹具）

/// 假模块的 manifest 工厂：**字面量构造**，不走 `ModuleManifest.decode(from:)`
/// （T1 的口径：`kind == builtin` 时顶层出现 `entry` 会被判 `unexpectedEntry`，夹具因此不碰该键）。
private enum RegistryFixture {
    static func manifest(
        shortID: String,
        surfaces: [Surface] = [.expanded],
        order: Int? = nil,
        name: LocalizedText? = nil,
        defaultEnabled: Bool = true
    ) -> ModuleManifest {
        ModuleManifest(
            manifestVersion: 1,
            id: "com.cmeng.gourd.\(shortID)",
            name: name ?? LocalizedText(key: "module.\(shortID).name"),
            summary: nil,
            icon: IconSpec(type: "symbol", name: "square"),
            version: "1.0.0",
            apiVersion: HostInfo.currentAPIVersion,
            kind: "builtin",
            surfaces: surfaces,
            defaultPlacement: order.map { Placement(slot: .center, order: $0) },
            defaultEnabled: defaultEnabled,
            permissions: [],
            config: nil
        )
    }
}

/// 记录 `requestRedraw` 的转发次数（T2 的 `UIHandle` 实现体是文件私有的，只能从注入闭包侧观测）。
private final class RedrawProbe {
    var count = 0
}

/// 假模块基线：`activate()` 不抛错、`content(for:)` 返回 `.none`。
/// manifest 由子类覆写 `class var` 提供（`GourdModule` 的 `static var manifest` 可由 `class var` 满足），
/// 六个夹具因此共享同一份 `init(context:)` / `deactivate()`。
@MainActor
private class ProbeModule: GourdModule {
    class var manifest: ModuleManifest { RegistryFixture.manifest(shortID: "probe") }

    required init(context: ModuleContext) {}

    func activate() async throws {}

    func deactivate() async {}

    /// 与注册表对未激活模块返回的 `.unavailable` 区分开：激活的模块转发到这里。
    func content(for request: ContentRequest) -> ModuleContent { .none }
}

/// order 10 + 声明 `.expanded`
private final class AlphaProbeModule: ProbeModule {
    override class var manifest: ModuleManifest { RegistryFixture.manifest(shortID: "probe-alpha", order: 10) }
}

/// 与 `AlphaProbeModule` **同 id**：验证重复注册被忽略（而不是覆盖）
private final class AlphaImpostorModule: ProbeModule {
    override class var manifest: ModuleManifest { RegistryFixture.manifest(shortID: "probe-alpha", order: 10) }
}

/// `activate()` 必抛错
private final class BetaProbeModule: ProbeModule {
    struct ActivationFailure: Error {}

    override class var manifest: ModuleManifest { RegistryFixture.manifest(shortID: "probe-beta", order: 5) }

    override func activate() async throws { throw ActivationFailure() }
}

/// order 10（与 alpha 同序 → 比 id 字典序）+ name 用 locale 表形态
private final class GammaProbeModule: ProbeModule {
    override class var manifest: ModuleManifest {
        RegistryFixture.manifest(shortID: "probe-gamma", order: 10, name: LocalizedText(table: ["en": "Gamma Probe"]))
    }
}

/// 无 `defaultPlacement`（order = `Int.max`）
private final class DeltaProbeModule: ProbeModule {
    override class var manifest: ModuleManifest { RegistryFixture.manifest(shortID: "probe-delta") }
}

/// 只声明 `.compact`：即使激活也不进展开面板
private final class CompactProbeModule: ProbeModule {
    override class var manifest: ModuleManifest {
        RegistryFixture.manifest(shortID: "probe-compact", surfaces: [.compact], order: 1)
    }
}

/// `defaultEnabled = false`
private final class OptInProbeModule: ProbeModule {
    override class var manifest: ModuleManifest {
        RegistryFixture.manifest(shortID: "probe-optin", order: 2, defaultEnabled: false)
    }
}

/// `compact` + `expanded`、order 1（与 `CompactProbeModule` 同序 → 比 id 字典序）；
/// `compact` 请求答一个**可辨认**的 `.unavailable`（默认假体答 `.none`，与注册表「无候选」同形，
/// 无法证明 `compactSlotContent()` 转发到了谁），其余 surface 仍答 `.none`。
private final class DualSurfaceProbeModule: ProbeModule {
    override class var manifest: ModuleManifest {
        RegistryFixture.manifest(shortID: "probe-dual", surfaces: [.compact, .expanded], order: 1)
    }

    override func content(for request: ContentRequest) -> ModuleContent {
        request.surface == .compact ? .unavailable(reason: "probe-dual 的 compact 内容") : .none
    }
}

/// 只声明 `compact`、order 40：验证折叠态候选按 `order` 升序（排在两个 order 1 的后面）
private final class CompactLateProbeModule: ProbeModule {
    override class var manifest: ModuleManifest {
        RegistryFixture.manifest(shortID: "probe-compact-late", surfaces: [.compact], order: 40)
    }
}

// MARK: - 笔记同步：「最近删除」过滤

/// `AppleNotesTrashFilter` 是纯函数，直接对表测。
/// 背景：`notes of default account` 会把「最近删除」里的笔记一起枚举出来，被删条目因此
/// 永远留在 merge 的 `linkedRemoteIds` 里，本地对应项清不掉（岛上残留 / 同名重复）。
/// 这里只覆盖判定的三条性质：表内命中、表外不命中（含空串）、大小写与首尾空白无关。
final class AppleNotesTrashFilterTests: XCTestCase {

    /// 表中各语言的「最近删除」名称逐字命中。三例都要留着：本机实测（系统语言 zh-Hans-CN）
    /// AppleScript 侧返回的其实是英文 `Recently Deleted`，只按 UI 语言准备一条会在真机漏判。
    func testKnownTrashedFolderNamesAreDetected() {
        XCTAssertTrue(AppleNotesTrashFilter.isTrashed(containerName: "最近删除"), "zh-Hans")
        XCTAssertTrue(AppleNotesTrashFilter.isTrashed(containerName: "最近刪除"), "zh-Hant")
        XCTAssertTrue(AppleNotesTrashFilter.isTrashed(containerName: "Recently Deleted"), "en")
    }

    /// 普通文件夹名与空串不算垃圾：**空串（旧格式记录 / 取不到容器名）必须保持旧行为**，
    /// 否则升级后会把所有笔记误判为已删除。
    func testOrdinaryFolderNamesAreNotTrashed() {
        XCTAssertFalse(AppleNotesTrashFilter.isTrashed(containerName: "备忘录"), "用户自己的文件夹")
        XCTAssertFalse(AppleNotesTrashFilter.isTrashed(containerName: "Notes"), "en 普通文件夹")
        XCTAssertFalse(AppleNotesTrashFilter.isTrashed(containerName: ""), "空容器名 = 不过滤")
    }

    /// 大小写与首尾空白（含换行）不影响判定。
    func testMatchIsCaseAndWhitespaceInsensitive() {
        XCTAssertTrue(AppleNotesTrashFilter.isTrashed(containerName: "  recently DELETED  "))
        XCTAssertTrue(AppleNotesTrashFilter.isTrashed(containerName: "\n最近删除\t"))
        XCTAssertFalse(AppleNotesTrashFilter.isTrashed(containerName: "   "))
        XCTAssertFalse(AppleNotesTrashFilter.isTrashed(containerName: " recently deleted extra"))
    }
}

// MARK: - 首页日历块：日期轮下标算术（2026-09-29 T1）

/// 日期轮的「选中日 ↔ 项下标」换算（`WheelPickerIndexMath`，纯函数）。
///
/// 这一组用例钉的是**定位落点**：`WheelPicker` 的初始定位就是
/// `scrollPosition = indexForDate(selectedDate)`（`scrollToToday`），落点算错 = 展开后不在选中日上。
/// 注意「hover 展开的日期轮是空条」那条 bug 的**根因不在算术**（实测滚动位置一直是对的，是容器
/// 把 AppKit 背书的 `ScrollView` 裁没了），渲染层测不了——由
/// `.workflow/p2-calendar-row/reports/` 的对照实验与截图覆盖；这里保证算术不回归。
///
/// **P11 / T7**：原与本组同类的「首页今日紧凑列表行容量 / 时间列（固定 24 小时制）」用例（旧
/// 行容量档的纯函数断言）随旧紧凑行本批退休，已整组删除——本类只留日期轮算术
/// （`WheelPicker` 与日期头 hover 逻辑按 T7 判决保留不动）。
final class WheelPickerIndexMathTests: XCTestCase {

    private func wheelCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        return calendar
    }

    private func wheelDate(_ calendar: Calendar, day: Int, month: Int = 9, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// 项总数：`ceil((past + future) / steps) + 1`（`steps` 用 `max(_, 1)` 兜底）。
    func testWheelPickerIndexMathTotalItemsFollowsSteps() {
        var config = Config()
        config.past = 7
        config.future = 14
        config.steps = 1
        XCTAssertEqual(WheelPickerIndexMath.totalItems(config: config), 22, "默认窗口 21 天 + 今天 = 22 项")

        config.steps = 3
        XCTAssertEqual(WheelPickerIndexMath.totalItems(config: config), 8, "每 3 天一跳：ceil(21/3)+1 = 8")

        config.past = 0
        config.future = 0
        config.steps = 1
        XCTAssertEqual(WheelPickerIndexMath.totalItems(config: config), 1, "只有今天 = 1 项")

        config.past = 7
        config.future = 14
        config.steps = 0
        XCTAssertEqual(WheelPickerIndexMath.totalItems(config: config), 22, "step = 0 按 1 兜底（不除以零）")
    }

    /// 今天落在 `offset + past`；窗口外的日期左闭右夹到两端（不会算出越界下标）。
    func testWheelPickerIndexMathClampsOutsideWindow() {
        let calendar = wheelCalendar()
        let now = wheelDate(calendar, day: 29)
        let config = Config()   // past 7 / future 14 / steps 1 / offset 2

        XCTAssertEqual(WheelPickerIndexMath.index(for: now, config: config, now: now, calendar: calendar), 9,
                       "今天是第 9 项（前导 2 个占位格 + past 7 天）")
        XCTAssertEqual(
            WheelPickerIndexMath.index(for: wheelDate(calendar, day: 26), config: config, now: now, calendar: calendar),
            6, "3 天前"
        )
        XCTAssertEqual(
            WheelPickerIndexMath.index(for: wheelDate(calendar, day: 13, month: 10), config: config, now: now, calendar: calendar),
            23, "窗口右端（now + 14 天）"
        )
        XCTAssertEqual(
            WheelPickerIndexMath.index(for: wheelDate(calendar, day: 30, month: 11), config: config, now: now, calendar: calendar),
            23, "超出右端：夹到最后一格，不越界"
        )
        XCTAssertEqual(
            WheelPickerIndexMath.index(for: wheelDate(calendar, day: 1), config: config, now: now, calendar: calendar),
            2, "超出左端：夹到第一格"
        )
    }

    /// 选中日在窗口内时，`index(for:)` 与 `date(atItemIndex:)` 互为逆运算（展开时落在选中日上）。
    func testWheelPickerIndexMathRoundTripsInsideWindow() {
        let calendar = wheelCalendar()
        let now = wheelDate(calendar, day: 29)
        let config = Config()

        for index in config.offset...(config.offset + WheelPickerIndexMath.totalItems(config: config) - 1) {
            let date = WheelPickerIndexMath.date(atItemIndex: index, spacerNum: config.offset, config: config, now: now, calendar: calendar)
            XCTAssertEqual(
                WheelPickerIndexMath.index(for: date, config: config, now: now, calendar: calendar), index,
                "第 \(index) 项应往返回到同一格"
            )
        }

        XCTAssertEqual(
            WheelPickerIndexMath.index(
                for: WheelPickerIndexMath.date(atItemIndex: 9, spacerNum: config.offset, config: config, now: now, calendar: calendar),
                config: config, now: now, calendar: calendar
            ),
            9, "今天那一格"
        )
    }

    /// `steps > 1`：项与项的日期间隔就是 `steps` 天（拨一格走 3 天）。
    func testWheelPickerIndexMathStepsSkipDays() {
        let calendar = wheelCalendar()
        let now = wheelDate(calendar, day: 29)
        var config = Config()
        config.past = 6
        config.future = 9
        config.steps = 3

        XCTAssertEqual(WheelPickerIndexMath.totalItems(config: config), 6, "ceil(15/3)+1 = 6 项")
        XCTAssertEqual(
            WheelPickerIndexMath.index(for: wheelDate(calendar, day: 29), config: config, now: now, calendar: calendar),
            4, "offset 2 + 6/3 = 第 4 项（下标 4）"
        )
        XCTAssertEqual(
            WheelPickerIndexMath.index(for: wheelDate(calendar, day: 2, month: 10), config: config, now: now, calendar: calendar),
            5, "3 天后 = 下一格"
        )
        XCTAssertEqual(
            WheelPickerIndexMath.date(atItemIndex: 5, spacerNum: config.offset, config: config, now: now, calendar: calendar),
            wheelDate(calendar, day: 2, month: 10, hour: 0), "第 5 项 = now + 3 天（按天归一，落在当天 00:00）"        )
    }

    /// 换算按 `startOfDay` 归一：同一天的不同时刻落在同一格（`now` 的时刻不参与判据）。
    func testWheelPickerIndexMathNormalizesToStartOfDay() {
        let calendar = wheelCalendar()
        let nowLate = wheelDate(calendar, day: 29, hour: 23)
        let config = Config()

        let early = wheelDate(calendar, day: 26, hour: 0)
        let late = wheelDate(calendar, day: 26, hour: 23)
        XCTAssertEqual(
            WheelPickerIndexMath.index(for: early, config: config, now: nowLate, calendar: calendar),
            WheelPickerIndexMath.index(for: late, config: config, now: nowLate, calendar: calendar),
            "同一天的 00:xx 与 23:xx 是同一格"
        )
        XCTAssertEqual(
            WheelPickerIndexMath.index(for: early, config: config, now: nowLate, calendar: calendar), 6,
            "3 天前 = 第 6 项（与 `now` 的时刻无关）"
        )
    }
}

// MARK: - 首页日历行 · 整月网格（P2 批次 / T2）

/// `MonthGridLayout.days(forMonth:calendar:)` 是纯函数（不读 `Defaults`、不碰「今天」）：
/// 用例全部用**固定 `Calendar`（固定时区 + 固定 `firstWeekday`）与固定月份**，不依赖运行时的今天。
@MainActor
final class MonthGridLayoutTests: XCTestCase {

    /// 固定日历：格里高利 + GMT（不受本机时区影响）+ `en_US_POSIX`（`veryShortStandaloneWeekdaySymbols`
    /// / 周起点判定都随 locale，钉住才可复现）。
    private func gridCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    /// 当天的 **00:00**：网格的每一格都是「那天零点」（`dateInterval(of:.weekOfMonth).start` 的
    /// 口径），补格与首末格都按同一口径比较。
    private func gridDay(_ calendar: Calendar, year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func gridMonth(_ calendar: Calendar, year: Int, month: Int) -> Date {
        gridDay(calendar, year: year, month: month, day: 1)
    }

    /// 网格首格是**当周起点**（`firstWeekday = 1` = 周日）、末格是**当周末日所在那一周的终点**，
    /// 总格数是 7 的整数倍、逐格 +1 天。用例取 2026 年 9 月（9/1 是周二、9/30 是周三）。
    func testDaysStartOnFirstWeekdayAndEndOnWeekEnd() throws {
        let calendar = gridCalendar(firstWeekday: 1)
        let days = MonthGridLayout.days(forMonth: gridMonth(calendar, year: 2026, month: 9), calendar: calendar)

        XCTAssertEqual(days.count, 35, "2026 年 9 月落在 5 周里（8/30 周日 → 10/3 周六）")
        XCTAssertEqual(try XCTUnwrap(days.first), gridDay(calendar, year: 2026, month: 8, day: 30), "首格 = 当月首日所在周的起点")
        XCTAssertEqual(try XCTUnwrap(days.last), gridDay(calendar, year: 2026, month: 10, day: 3), "末格 = 当月末日所在周的终点")
        XCTAssertEqual(calendar.component(.weekday, from: days[0]), calendar.firstWeekday, "首格落在周起点上")
        XCTAssertEqual(days.count % 7, 0, "整月网格恒为整周数")

        for (index, pair) in zip(days.indices, zip(days, days.dropFirst())) {
            XCTAssertEqual(
                calendar.dateComponents([.day], from: pair.0, to: pair.1).day, 1,
                "第 \(index) 格与下一格应相差 1 天"
            )
        }
    }

    /// 网格**完整覆盖当月**：1 号与月末都在里面，且每个日子只出现一次（跨月补格是别月的日期，
    /// 不会与当月日期重复）。
    func testDaysCoverWholeMonthExactlyOnce() {
        let calendar = gridCalendar(firstWeekday: 1)
        let days = MonthGridLayout.days(forMonth: gridMonth(calendar, year: 2026, month: 9), calendar: calendar)
        let stamps = Set(days.map { calendar.startOfDay(for: $0) })

        XCTAssertEqual(days.count, stamps.count, "同一格不应重复")
        XCTAssertTrue(stamps.contains(calendar.startOfDay(for: gridDay(calendar, year: 2026, month: 9, day: 1))), "含当月 1 号")
        XCTAssertTrue(stamps.contains(calendar.startOfDay(for: gridDay(calendar, year: 2026, month: 9, day: 30))), "含当月最后一天")
        XCTAssertEqual(
            stamps.filter { calendar.component(.month, from: $0) == 9 }.count, 30,
            "9 月 30 天全部在内"
        )
    }

    /// 周起点跟着 `firstWeekday` 走（与星期表头同一来源）：同一月份换 `firstWeekday = 2`（周一）
    /// 后首格从 8/30 变 8/31、末格从 10/3 变 10/4。
    func testDaysFollowFirstWeekday() throws {
        let calendar = gridCalendar(firstWeekday: 2)
        let days = MonthGridLayout.days(forMonth: gridMonth(calendar, year: 2026, month: 9), calendar: calendar)

        XCTAssertEqual(days.count, 35, "换周起点不改变格数（本月恰好仍占 5 周）")
        XCTAssertEqual(try XCTUnwrap(days.first), gridDay(calendar, year: 2026, month: 8, day: 31), "周一起点：首格 = 8/31 周一")
        XCTAssertEqual(try XCTUnwrap(days.last), gridDay(calendar, year: 2026, month: 10, day: 4), "末格 = 10/4 周日")
        XCTAssertEqual(calendar.component(.weekday, from: days[0]), calendar.firstWeekday)
    }

    /// **恰好四周**的月份没有补格：2026 年 2 月（2/1 是周日、2/28 是周六）在周日起点下＝28 格，
    /// 每一格都在当月内。
    func testExactFourWeekMonthHasNoPadding() throws {
        let calendar = gridCalendar(firstWeekday: 1)
        let days = MonthGridLayout.days(forMonth: gridMonth(calendar, year: 2026, month: 2), calendar: calendar)

        XCTAssertEqual(days.count, 28, "2026 年 2 月恰好 4 周")
        XCTAssertEqual(try XCTUnwrap(days.first), gridDay(calendar, year: 2026, month: 2, day: 1), "首格 = 2/1（周日）")
        XCTAssertEqual(try XCTUnwrap(days.last), gridDay(calendar, year: 2026, month: 2, day: 28), "末格 = 2/28（周六）")
        XCTAssertTrue(
            days.allSatisfy { calendar.component(.month, from: $0) == 2 && calendar.component(.year, from: $0) == 2026 },
            "没有补格：每一格都在当月"
        )
    }

    /// 跨月补格**来自相邻月份**（且没有多算一格）：2026 年 9 月的网格 = 8/30、8/31 + 9 月 30 天 + 10/1~10/3。
    func testPaddingCellsComeFromAdjacentMonths() {
        let calendar = gridCalendar(firstWeekday: 1)
        let days = MonthGridLayout.days(forMonth: gridMonth(calendar, year: 2026, month: 9), calendar: calendar)
        XCTAssertEqual(days.count, 35, "先钉住格数，下面的下标才有意义")

        let leading = days.prefix(2).map { calendar.component(.month, from: $0) }
        XCTAssertEqual(leading, [8, 8], "前两格是 8 月的补格")
        XCTAssertEqual(calendar.component(.month, from: days[2]), 9, "第 3 格才是当月 1 号")
        XCTAssertEqual(calendar.component(.day, from: days[2]), 1, "第 3 格 = 9/1")

        let trailing = days.suffix(3).map { calendar.component(.month, from: $0) }
        XCTAssertEqual(trailing, [10, 10, 10], "后三格是 10 月的补格")
        XCTAssertEqual(calendar.component(.month, from: days[31]), 9, "下标 31 仍是当月")
        XCTAssertEqual(calendar.component(.day, from: days[31]), 30, "下标 31 是当月最后一天（9/30）")
        XCTAssertEqual(calendar.component(.day, from: days[32]), 1, "下标 32 进入 10 月")
    }

    // MARK: - 有事件的日期（日格标记）

    /// 固定 `Calendar` 下的一个条目（`CalendarModel` 用系统色；`type` 决定它是不是提醒）。
    /// 时刻由调用方用 `gridTime` / `gridDay` 给出，本 helper 不碰「今天」。
    private func gridEvent(
        id: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        type: EventType = .event(.accepted)
    ) -> EventModel {
        EventModel(
            id: id,
            start: start,
            end: end,
            title: id,
            location: nil,
            notes: nil,
            url: nil,
            isAllDay: isAllDay,
            type: type,
            calendar: CalendarModel(
                accountName: "Test",
                id: "test.calendar",
                title: "Test",
                color: .systemBlue,
                isSubscribed: false,
                isReminder: type.isReminder
            ),
            participants: [],
            timeZone: TimeZone(secondsFromGMT: 0),
            hasRecurrenceRules: false,
            priority: nil,
            conferenceURL: nil
        )
    }

    /// 固定 `Calendar` 下的某个时刻（年 / 月 / 日 / 时 / 分）。
    private func gridTime(_ calendar: Calendar, year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func gridDaysWithEvents(_ calendar: Calendar, _ events: [EventModel]) -> Set<Date> {
        MonthGridLayout.daysWithEvents(
            inMonth: gridMonth(calendar, year: 2026, month: 9), events: events, calendar: calendar
        )
    }

    /// 定时条目只标记它**自己那天**（前后一天都不点），且返回的是那天**零点**（视图就是拿
    /// `calendar.startOfDay(for: day)` 去 `contains` 的）。
    func testDaysWithEventsMarksTimedEventDayOnly() {
        let calendar = gridCalendar(firstWeekday: 1)
        let events = [
            gridEvent(
                id: "standup",
                start: gridTime(calendar, year: 2026, month: 9, day: 29, hour: 9),
                end: gridTime(calendar, year: 2026, month: 9, day: 29, hour: 10)
            )
        ]

        XCTAssertEqual(
            gridDaysWithEvents(calendar, events), [gridDay(calendar, year: 2026, month: 9, day: 29)],
            "9/29 09:00–10:00 → 只有 9/29 那格有点，且是那天的零点"
        )
    }

    /// 全天条目的 `end` 是 EventKit 的**次日零点排他值**（9/29 全天 = 9/29 00:00 → 9/30 00:00）：
    /// 只标记 9/29，**不能**把 9/30 也标上（覆盖区间末日按 `end − 1s` 所在日算）。
    func testAllDayEventExclusiveEndDoesNotMarkNextDay() {
        let calendar = gridCalendar(firstWeekday: 1)
        let events = [
            gridEvent(
                id: "holiday",
                start: gridDay(calendar, year: 2026, month: 9, day: 29),
                end: gridDay(calendar, year: 2026, month: 9, day: 30),
                isAllDay: true
            )
        ]

        let days = gridDaysWithEvents(calendar, events)
        XCTAssertEqual(days, [gridDay(calendar, year: 2026, month: 9, day: 29)], "全天条目的次日零点不是「覆盖」")
        XCTAssertFalse(days.contains(gridDay(calendar, year: 2026, month: 9, day: 30)), "9/30 不该有点")
    }

    /// 跨天条目**覆盖到的每一天**都标记：定时跨零点（9/29 23:00 → 9/30 01:00）= 两天；
    /// 多天全天（9/28 00:00 → 10/1 00:00）= 9/28 / 9/29 / 9/30 三天。
    func testCrossDayEventMarksEveryCoveredDay() {
        let calendar = gridCalendar(firstWeekday: 1)
        let overnight = gridEvent(
            id: "overnight",
            start: gridTime(calendar, year: 2026, month: 9, day: 29, hour: 23),
            end: gridTime(calendar, year: 2026, month: 9, day: 30, hour: 1)
        )
        XCTAssertEqual(
            gridDaysWithEvents(calendar, [overnight]),
            [gridDay(calendar, year: 2026, month: 9, day: 29), gridDay(calendar, year: 2026, month: 9, day: 30)],
            "跨零点的定时条目两天都算"
        )

        let multiDay = gridEvent(
            id: "trip",
            start: gridDay(calendar, year: 2026, month: 9, day: 28),
            end: gridDay(calendar, year: 2026, month: 10, day: 1),
            isAllDay: true
        )
        XCTAssertEqual(
            gridDaysWithEvents(calendar, [multiDay]),
            [
                gridDay(calendar, year: 2026, month: 9, day: 28),
                gridDay(calendar, year: 2026, month: 9, day: 29),
                gridDay(calendar, year: 2026, month: 9, day: 30)
            ],
            "多天全天条目：覆盖到的三天都有点（10/1 是排他端、不算）"
        )
    }

    /// **跨月边界**：标记落在**正确的格子**上——9/1 与 9/30（当月首尾）都在网格里；10/1 是这张网格的
    /// 补格（2026 年 9 月的网格 = 8/30…10/3），补格照样有点；10/15 不在网格里，**不进集合**
    /// （跨月条目因此不会把标记画到看不见的格子上）。
    func testMonthBoundaryEventsLandOnTheirOwnCells() {
        let calendar = gridCalendar(firstWeekday: 1)
        let events = [
            gridEvent(id: "first", start: gridTime(calendar, year: 2026, month: 9, day: 1, hour: 8),
                      end: gridTime(calendar, year: 2026, month: 9, day: 1, hour: 9)),
            gridEvent(id: "last", start: gridTime(calendar, year: 2026, month: 9, day: 30, hour: 8),
                      end: gridTime(calendar, year: 2026, month: 9, day: 30, hour: 9)),
            gridEvent(id: "nextMonthPadding", start: gridDay(calendar, year: 2026, month: 10, day: 1),
                      end: gridDay(calendar, year: 2026, month: 10, day: 2), isAllDay: true),
            gridEvent(id: "outsideGrid", start: gridTime(calendar, year: 2026, month: 10, day: 15, hour: 8),
                      end: gridTime(calendar, year: 2026, month: 10, day: 15, hour: 9))
        ]

        let days = gridDaysWithEvents(calendar, events)
        XCTAssertTrue(days.contains(gridDay(calendar, year: 2026, month: 9, day: 1)), "9/1（当月首日）有点")
        XCTAssertTrue(days.contains(gridDay(calendar, year: 2026, month: 9, day: 30)), "9/30（当月末日）有点")
        XCTAssertTrue(days.contains(gridDay(calendar, year: 2026, month: 10, day: 1)), "10/1 是补格，照样有点")
        XCTAssertFalse(days.contains(gridDay(calendar, year: 2026, month: 10, day: 15)), "网格外的日期不进集合")
        XCTAssertEqual(days.count, 3, "四条条目 → 三个有事件的日期（10/15 那条被裁掉）")
    }

    /// **被过滤掉的条目**不产生标记：先过 `CalendarEventFilters.filtered`（与两个宿主同一套口径）——
    /// 已完成提醒（`hideCompletedReminders`）与全天条目（`hideAllDayEvents`）各一例，
    /// 两种偏好都打开时是**空集**；偏好关掉时两条都在（证明「没标记」是过滤造成的，不是别的原因）。
    func testFilteredOutEventsProduceNoMarks() {
        let calendar = gridCalendar(firstWeekday: 1)
        let events = [
            gridEvent(id: "done-reminder",
                      start: gridTime(calendar, year: 2026, month: 9, day: 29, hour: 9),
                      end: gridTime(calendar, year: 2026, month: 9, day: 29, hour: 10),
                      type: .reminder(completed: true)),
            gridEvent(id: "all-day", start: gridDay(calendar, year: 2026, month: 9, day: 29),
                      end: gridDay(calendar, year: 2026, month: 9, day: 30), isAllDay: true)
        ]

        let hidden = CalendarEventFilters.filtered(
            events: events, hideCompletedReminders: true, hideAllDayEvents: true
        )
        XCTAssertTrue(hidden.isEmpty, "两条都被偏好隐藏")
        XCTAssertTrue(gridDaysWithEvents(calendar, hidden).isEmpty, "被过滤掉的条目不产生任何标记")

        let shown = CalendarEventFilters.filtered(
            events: events, hideCompletedReminders: false, hideAllDayEvents: false
        )
        XCTAssertEqual(shown.count, 2, "偏好关掉时两条都在（过滤才是「没标记」的原因）")
        XCTAssertEqual(
            gridDaysWithEvents(calendar, shown), [gridDay(calendar, year: 2026, month: 9, day: 29)],
            "同一天的两条合并成一个点"
        )
    }

    /// 没有条目 → 空集（调用方没有条目时一个点都不该画）。
    func testNoEventsMeansNoMarks() {
        let calendar = gridCalendar(firstWeekday: 1)
        XCTAssertTrue(gridDaysWithEvents(calendar, []).isEmpty, "空输入 → 空集")
    }

    // MARK: - 按月数据的抓取窗口（`CalendarManager.monthEvents` 的窗口判据）

    /// EventKit 谓词的窗口是**半开区间** `[start, end)`。`DateInterval.contains` 是**闭**区间
    /// （末点也算在内，实测 `contains(10/4) == true`），拿它判边界会让「窗口少抓一天」的用例假绿，
    /// 所以这里显式按半开写。
    private func gridWindowContains(_ window: DateInterval, _ day: Date) -> Bool {
        day >= window.start && day < window.end
    }

    /// **窗口必须覆盖网格能画出的每一格**：逐月走完 2026 年，每个月都验「网格的每一个日格都落在
    /// `monthWindow` 内」，且窗口两端就是网格的首格、末格的次日零点。
    ///
    /// 这是「月历上只有选中日有点」那个缺陷的回归钉：按月数据的抓取窗口只要比网格小一格，
    /// 那一格的事件就抓不到、永远没有标记（上一版的窗口是**一天**，所以整月只剩选中日有点）。
    func testMonthWindowCoversEveryMonthGridOfAYear() throws {
        let calendar = gridCalendar(firstWeekday: 1)

        for month in 1...12 {
            let monthDate = gridMonth(calendar, year: 2026, month: month)
            let gridDays = MonthGridLayout.days(forMonth: monthDate, calendar: calendar)
            let window = try XCTUnwrap(
                MonthGridLayout.monthWindow(forMonth: monthDate, calendar: calendar),
                "\(month) 月应能算出窗口"
            )

            XCTAssertTrue(
                gridDays.allSatisfy { gridWindowContains(window, $0) },
                "\(month) 月：每一个日格都在抓取窗口内"
            )
            XCTAssertEqual(window.start, gridDays.first, "\(month) 月：窗口起点 = 网格首格（当周起点）")
            XCTAssertEqual(
                window.end,
                try XCTUnwrap(gridDays.last).addingTimeInterval(24 * 3600),
                "\(month) 月：窗口终点 = 网格末格的次日零点（末尾排他）"
            )
        }
    }

    /// 2026 年 9 月（周日起点）的窗口 = **8/30 00:00 → 10/4 00:00**：起点是当月首日所在周的起点
    /// （8/30 周日）、终点是网格末格（10/3）的**次日零点**——末尾排他，正好是 EventKit 谓词的
    /// `end` 口径，因此 10/3 在窗口内、10/4 不在。
    func testMonthWindowMatchesGridBoundsForSeptember() throws {
        let calendar = gridCalendar(firstWeekday: 1)
        let window = try XCTUnwrap(
            MonthGridLayout.monthWindow(forMonth: gridMonth(calendar, year: 2026, month: 9), calendar: calendar)
        )

        XCTAssertEqual(window.start, gridDay(calendar, year: 2026, month: 8, day: 30), "起点 = 网格首格（8/30 周日）")
        XCTAssertEqual(window.end, gridDay(calendar, year: 2026, month: 10, day: 4), "终点 = 末格次日零点")
        XCTAssertTrue(gridWindowContains(window, gridDay(calendar, year: 2026, month: 8, day: 30)), "首格（补格）在窗口内")
        XCTAssertTrue(gridWindowContains(window, gridDay(calendar, year: 2026, month: 10, day: 3)), "末格（补格）在窗口内")
        XCTAssertFalse(gridWindowContains(window, gridDay(calendar, year: 2026, month: 10, day: 4)), "末尾排他：10/4 不在窗口内")
    }

    /// 窗口跟着 `firstWeekday` 走（与 `days(forMonth:)` 同源）：同一月份换周一起点后窗口两端各挪一天。
    func testMonthWindowFollowsFirstWeekday() throws {
        let sundayStart = gridCalendar(firstWeekday: 1)
        let mondayStart = gridCalendar(firstWeekday: 2)

        let sundayWindow = try XCTUnwrap(
            MonthGridLayout.monthWindow(forMonth: gridMonth(sundayStart, year: 2026, month: 9), calendar: sundayStart)
        )
        let mondayWindow = try XCTUnwrap(
            MonthGridLayout.monthWindow(forMonth: gridMonth(mondayStart, year: 2026, month: 9), calendar: mondayStart)
        )

        XCTAssertEqual(sundayWindow.start, gridDay(sundayStart, year: 2026, month: 8, day: 30), "周日起点：8/30")
        XCTAssertEqual(mondayWindow.start, gridDay(mondayStart, year: 2026, month: 8, day: 31), "周一起点：8/31")
        XCTAssertEqual(sundayWindow.end, gridDay(sundayStart, year: 2026, month: 10, day: 4), "周日起点：10/4")
        XCTAssertEqual(mondayWindow.end, gridDay(mondayStart, year: 2026, month: 10, day: 5), "周一起点：10/5")
    }

    /// **恰好四周**的月份没有补格：2026 年 2 月（2/1 周日 → 2/28 周六）的窗口 = 2/1 00:00 → 3/1 00:00，
    /// 一个月一天都不多抓。
    func testMonthWindowForExactFourWeekMonth() throws {
        let calendar = gridCalendar(firstWeekday: 1)
        let window = try XCTUnwrap(
            MonthGridLayout.monthWindow(forMonth: gridMonth(calendar, year: 2026, month: 2), calendar: calendar)
        )

        XCTAssertEqual(window.start, gridDay(calendar, year: 2026, month: 2, day: 1), "起点 = 2/1（周日）")
        XCTAssertEqual(window.end, gridDay(calendar, year: 2026, month: 3, day: 1), "终点 = 2/28 的次日零点")
    }

    /// `firstDay(ofMonth:)` 把月内任意一天归一化到**该月 1 日零点**——按月数据的键
    /// （`MonthEventSnapshot.month` 与 `MonthGridView.displayedMonth` 都用它比较、管理器用它去重）。
    func testFirstDayOfMonthNormalizesAnyDayInThatMonth() {
        let calendar = gridCalendar(firstWeekday: 1)
        let septemberFirst = gridDay(calendar, year: 2026, month: 9, day: 1)

        for day in [1, 15, 30] {
            XCTAssertEqual(
                MonthGridLayout.firstDay(ofMonth: gridTime(calendar, year: 2026, month: 9, day: day, hour: 13), calendar: calendar),
                septemberFirst,
                "9/\(day)（含带时刻的）都归一化到 9/1 零点"
            )
        }
        XCTAssertEqual(
            MonthGridLayout.firstDay(ofMonth: gridDay(calendar, year: 2026, month: 10, day: 1), calendar: calendar),
            gridDay(calendar, year: 2026, month: 10, day: 1),
            "月首日本身不动"
        )
    }

    // MARK: - 按月快照 → 日格标记（含「翻月期间不出错点」的判据）

    private func gridSnapshot(_ calendar: Calendar, year: Int, month: Int, events: [EventModel]) -> MonthEventSnapshot {
        MonthEventSnapshot(month: gridMonth(calendar, year: year, month: month), events: events)
    }

    private func gridEventDays(_ calendar: Calendar, displayedMonth: Int, snapshot: MonthEventSnapshot) -> Set<Date> {
        MonthGridLayout.eventDays(
            forDisplayedMonth: gridMonth(calendar, year: 2026, month: displayedMonth),
            snapshot: snapshot,
            calendar: calendar
        )
    }

    /// **一个月里多个日期都有点**：按月窗口内的条目（8/31、9/1、9/30、10/2）在 9 月网格上各得一点
    /// ——上一版用「选中日那一天的条目」只可能有一个点，这条用例是那件事的正向对照。
    func testEventDaysMarksEveryDayWithEventsInTheMonthWindow() {
        let calendar = gridCalendar(firstWeekday: 1)
        let events = [
            gridEvent(id: "august-padding",
                      start: gridTime(calendar, year: 2026, month: 8, day: 31, hour: 9),
                      end: gridTime(calendar, year: 2026, month: 8, day: 31, hour: 10)),
            gridEvent(id: "first-of-month",
                      start: gridTime(calendar, year: 2026, month: 9, day: 1, hour: 9),
                      end: gridTime(calendar, year: 2026, month: 9, day: 1, hour: 10)),
            gridEvent(id: "last-of-month",
                      start: gridTime(calendar, year: 2026, month: 9, day: 30, hour: 9),
                      end: gridTime(calendar, year: 2026, month: 9, day: 30, hour: 10)),
            gridEvent(id: "october-padding",
                      start: gridTime(calendar, year: 2026, month: 10, day: 2, hour: 9),
                      end: gridTime(calendar, year: 2026, month: 10, day: 2, hour: 10))
        ]

        XCTAssertEqual(
            gridEventDays(calendar, displayedMonth: 9, snapshot: gridSnapshot(calendar, year: 2026, month: 9, events: events)),
            [
                gridDay(calendar, year: 2026, month: 8, day: 31),
                gridDay(calendar, year: 2026, month: 9, day: 1),
                gridDay(calendar, year: 2026, month: 9, day: 30),
                gridDay(calendar, year: 2026, month: 10, day: 2)
            ],
            "9 月网格里 4 个不同的日期都有点（含两个跨月补格）"
        )
    }

    /// **快照月份与显示月份不同月 → 一个点都不出**：翻月后新数据还在路上时，手上还是上个月的条目，
    /// 拿它算新月份就会把点画到错的格子上——此刻宁可空着。同一份条目在对齐月份里才出点。
    func testEventDaysIgnoresSnapshotFromAnotherMonth() {
        let calendar = gridCalendar(firstWeekday: 1)
        let septemberEvent = gridEvent(
            id: "standup",
            start: gridTime(calendar, year: 2026, month: 9, day: 29, hour: 9),
            end: gridTime(calendar, year: 2026, month: 9, day: 29, hour: 10)
        )

        // 10 月的窗口（9/27…10/31）本来就含 9/29，所以「10 月快照里有 9/29 的条目」是真实形态。
        let octoberSnapshot = gridSnapshot(calendar, year: 2026, month: 10, events: [septemberEvent])
        XCTAssertTrue(
            gridEventDays(calendar, displayedMonth: 9, snapshot: octoberSnapshot).isEmpty,
            "显示 9 月、快照是 10 月 → 不出点（哪怕条目本身落在 9/29）"
        )

        let augustSnapshot = gridSnapshot(calendar, year: 2026, month: 8, events: [septemberEvent])
        XCTAssertTrue(
            gridEventDays(calendar, displayedMonth: 9, snapshot: augustSnapshot).isEmpty,
            "显示 9 月、快照是 8 月 → 不出点"
        )

        let septemberSnapshot = gridSnapshot(calendar, year: 2026, month: 9, events: [septemberEvent])
        XCTAssertEqual(
            gridEventDays(calendar, displayedMonth: 9, snapshot: septemberSnapshot),
            [gridDay(calendar, year: 2026, month: 9, day: 29)],
            "月份对齐时同一个条目才出点（证明上面的空集是月份不齐造成的）"
        )
    }

    /// 还没有按月数据（`.empty`）/ 该月没有条目 → 一个点都不画。
    func testEventDaysWithEmptySnapshotHasNoMarks() {
        let calendar = gridCalendar(firstWeekday: 1)

        XCTAssertTrue(
            gridEventDays(calendar, displayedMonth: 9, snapshot: .empty).isEmpty,
            "还没有按月数据 → 空集"
        )
        XCTAssertTrue(
            gridEventDays(calendar, displayedMonth: 9, snapshot: gridSnapshot(calendar, year: 2026, month: 9, events: [])).isEmpty,
            "该月没有条目 → 空集"
        )
    }

    // MARK: - 日格事件标记：分色与数量角标（2026-10-12，docs/43 D-01 / D-02 / D-03）

    /// 指定可写性 / 订阅性的 `CalendarModel`（分类用例要造订阅与只读日历）。
    private func gridCalendarModel(
        id: String,
        isSubscribed: Bool = false,
        allowsContentModifications: Bool = true
    ) -> CalendarModel {
        CalendarModel(
            accountName: "Test",
            id: id,
            title: id,
            color: .systemBlue,
            isSubscribed: isSubscribed,
            isReminder: false,
            allowsContentModifications: allowsContentModifications
        )
    }

    /// 与 `gridEvent` 同款，但**日历由调用方给定**（`calendarModel:` 标签与既有重载不冲突）。
    private func gridEvent(
        id: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarModel: CalendarModel,
        type: EventType = .event(.accepted)
    ) -> EventModel {
        EventModel(
            id: id,
            start: start,
            end: end,
            title: id,
            location: nil,
            notes: nil,
            url: nil,
            isAllDay: isAllDay,
            type: type,
            calendar: calendarModel,
            participants: [],
            timeZone: TimeZone(secondsFromGMT: 0),
            hasRecurrenceRules: false,
            priority: nil,
            conferenceURL: nil
        )
    }

    private func gridMarks(_ calendar: Calendar, day: Int, month: Int = 10, events: [EventModel]) -> MonthDayEventMarks {
        MonthDayEventMarksBuilder.marks(
            for: gridDay(calendar, year: 2026, month: month, day: day), events: events, calendar: calendar
        )
    }

    /// **(a) 可写日历**的条目算「我的」、且**不是**信息类（判据的唯一一条分支）。
    func testWritableCalendarEventsCountAsMine() {
        let calendar = gridCalendar(firstWeekday: 2)
        let writable = gridCalendarModel(id: "writable")
        XCTAssertFalse(MonthDayEventMarksBuilder.isInformational(writable), "可写日历 → 不是信息类")

        let event = gridEvent(
            id: "mine",
            start: gridTime(calendar, year: 2026, month: 10, day: 12, hour: 9),
            end: gridTime(calendar, year: 2026, month: 10, day: 12, hour: 10),
            calendarModel: writable
        )
        XCTAssertEqual(
            gridMarks(calendar, day: 12, events: [event]), MonthDayEventMarks(mine: 1, hasInfo: false),
            "可写日历条目 → 我的 1 条、无信息类"
        )
    }

    /// **(b) 订阅**日历与**只读**（`allowsContentModifications == false`）日历都算信息类：`mine == 0`。
    /// 两条分别钉住判据的 `||` 两侧。
    func testSubscribedAndReadOnlyCalendarsCountAsInformational() {
        let calendar = gridCalendar(firstWeekday: 2)
        let subscribed = gridCalendarModel(id: "holiday", isSubscribed: true)
        let readOnly = gridCalendarModel(id: "shared", allowsContentModifications: false)
        XCTAssertTrue(MonthDayEventMarksBuilder.isInformational(subscribed), "订阅 → 信息类")
        XCTAssertTrue(MonthDayEventMarksBuilder.isInformational(readOnly), "只读（不允许改）→ 信息类")

        let events = [
            gridEvent(
                id: "holiday",
                start: gridDay(calendar, year: 2026, month: 10, day: 12),
                end: gridDay(calendar, year: 2026, month: 10, day: 13),
                isAllDay: true,
                calendarModel: subscribed
            ),
            gridEvent(
                id: "shared",
                start: gridTime(calendar, year: 2026, month: 10, day: 12, hour: 14),
                end: gridTime(calendar, year: 2026, month: 10, day: 12, hour: 15),
                calendarModel: readOnly
            )
        ]
        XCTAssertEqual(
            gridMarks(calendar, day: 12, events: events), MonthDayEventMarks(mine: 0, hasInfo: true),
            "订阅 / 只读条目都只算信息类、不进「我的」计数"
        )
    }

    /// **(c) 累加**：同一天多条可写日历条目全部进 `mine`。
    func testSeveralEventsOnOneDayAccumulateIntoMine() {
        let calendar = gridCalendar(firstWeekday: 2)
        let writable = gridCalendarModel(id: "writable")
        let events = (9...11).map { hour in
            gridEvent(
                id: "mine-\(hour)",
                start: gridTime(calendar, year: 2026, month: 10, day: 12, hour: hour),
                end: gridTime(calendar, year: 2026, month: 10, day: 12, hour: hour + 1),
                calendarModel: writable
            )
        }
        XCTAssertEqual(
            gridMarks(calendar, day: 12, events: events), MonthDayEventMarks(mine: 3, hasInfo: false),
            "3 条可写条目 → mine = 3"
        )
    }

    /// **(d) 两类并存**：同一天既有我的日程又有信息类条目 → 两样都给（橙点 + 蓝点，角标数 = 我的条数）。
    func testDayWithBothKindsYieldsBoth() {
        let calendar = gridCalendar(firstWeekday: 2)
        let events = [
            gridEvent(
                id: "mine",
                start: gridTime(calendar, year: 2026, month: 10, day: 12, hour: 9),
                end: gridTime(calendar, year: 2026, month: 10, day: 12, hour: 10),
                calendarModel: gridCalendarModel(id: "writable")
            ),
            gridEvent(
                id: "holiday",
                start: gridDay(calendar, year: 2026, month: 10, day: 12),
                end: gridDay(calendar, year: 2026, month: 10, day: 13),
                isAllDay: true,
                calendarModel: gridCalendarModel(id: "holiday", isSubscribed: true)
            )
        ]
        XCTAssertEqual(
            gridMarks(calendar, day: 12, events: events), MonthDayEventMarks(mine: 1, hasInfo: true),
            "两类并存 → mine = 1、hasInfo = true"
        )
    }

    /// **(e) 全天与跨日**条目落在**正确的天**上——覆盖口径与既有日格查找逐字同源：
    /// 9/29 全天（`end` = 9/30 零点排他）只落 9/29；跨零点定时条目 9/29 23:00 → 9/30 01:00 两天都落。
    func testAllDayAndCrossDayEventsLandOnTheirDays() {
        let calendar = gridCalendar(firstWeekday: 2)
        let writable = gridCalendarModel(id: "writable")

        let allDay = gridEvent(
            id: "all-day",
            start: gridDay(calendar, year: 2026, month: 9, day: 29),
            end: gridDay(calendar, year: 2026, month: 9, day: 30),
            isAllDay: true,
            calendarModel: writable
        )
        XCTAssertEqual(
            gridMarks(calendar, day: 29, month: 9, events: [allDay]), MonthDayEventMarks(mine: 1, hasInfo: false),
            "全天条目落在起始日"
        )
        XCTAssertEqual(
            gridMarks(calendar, day: 30, month: 9, events: [allDay]), MonthDayEventMarks(mine: 0, hasInfo: false),
            "全天条目的次日零点（排他端）不落"
        )

        let overnight = gridEvent(
            id: "overnight",
            start: gridTime(calendar, year: 2026, month: 9, day: 29, hour: 23),
            end: gridTime(calendar, year: 2026, month: 9, day: 30, hour: 1),
            calendarModel: writable
        )
        XCTAssertEqual(
            gridMarks(calendar, day: 29, month: 9, events: [overnight]), MonthDayEventMarks(mine: 1, hasInfo: false)
        )
        XCTAssertEqual(
            gridMarks(calendar, day: 30, month: 9, events: [overnight]), MonthDayEventMarks(mine: 1, hasInfo: false),
            "跨零点的定时条目两天都落"
        )
    }

    /// **(f) `badgeLabel` 边界**：0 → 不画；1–9 直显；≥10 一律 `"9+"`（含 10 与 99）。
    func testBadgeLabelBoundaries() {
        XCTAssertNil(MonthDayEventMarksBuilder.badgeLabel(count: 0), "0 条 → 不画角标")
        XCTAssertEqual(MonthDayEventMarksBuilder.badgeLabel(count: 1), "1")
        XCTAssertEqual(MonthDayEventMarksBuilder.badgeLabel(count: 9), "9")
        XCTAssertEqual(MonthDayEventMarksBuilder.badgeLabel(count: 10), "9+")
        XCTAssertEqual(MonthDayEventMarksBuilder.badgeLabel(count: 99), "9+")
        XCTAssertNil(MonthDayEventMarksBuilder.badgeLabel(count: -1), "异常负数同样按「不画」处理")
    }
}

// MARK: - 周起点契约（p9 / T2，docs/34 §做法 机制一 / §接口与数据形状）

/// 两个日历面板（首页整宽日历行 + 展开面板日历页）的周起点**固定周一**的契约——唯一落点是
/// `Calendar.gourdDisplay`，默认参数那一档就是它。
///
/// **时区前提**：本组用例刻意**不注入 `Calendar`**（走的正是默认参数 = 宿主机时区），因此期望值的
/// `Date` 一律按**宿主机时区**的零点构造（`hostDay`）；GMT 夹具算出来的期望值在 UTC+8 上会差 8 小时
/// 而红（`MonthGridLayoutTests` 的 GMT 夹具只服务「显式注入日历」的判据）。
///
/// 把 `gourdDisplay` 的 `firstWeekday` 改回 1（周日）时，②③⑥ 必须变红——这是它们存在的理由；
/// ⑤（`firstDay(ofMonth:)` 的默认值切换）不写成用例：它的结果与周起点无关，用例钉不住「默认值改没改」
/// ——那一条由源码检查覆盖（P11 / T7 退休旧紧凑行后，`DynamicIslandCalendar.swift` 里
/// `Calendar = .current` 的默认参数已清零，其余显式 `Calendar` 默认参数一律是 `.gourdDisplay`）。
@MainActor
final class CalendarWeekStartTests: XCTestCase {

    /// 默认档（= `Calendar.gourdDisplay`，宿主机时区）某天的零点。构造只用到年月日——与
    /// `firstWeekday` 无关，因此这条夹具不会被「改回周日」那一行带着一起动，判据钉得死。
    private func hostDay(year: Int, month: Int, day: Int) -> Date {
        Calendar.gourdDisplay.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// 宿主机时区下的月首零点。
    private func hostMonth(year: Int, month: Int) -> Date {
        hostDay(year: year, month: month, day: 1)
    }

    /// 同一宿主机时区、指定 `firstWeekday` 的显式日历（两档对照用；与默认档共享时区，`Date` 可直接比较）。
    private func hostCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar.gourdDisplay
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// ① 显示日历的周起点就是周一（Foundation 的 1-based 口径：`1 = 周日`、`2 = 周一`）。
    func testDisplayCalendarStartsOnMonday() {
        XCTAssertEqual(Calendar.gourdDisplay.firstWeekday, 2, "显示日历的周起点 = 周一")
    }

    /// ② 默认参数下 2026-10 的网格 = 9/28（周一）… 11/1（周日）、5 周；同一月份换周日起点的显式
    /// 日历后两端各不同（9/27 … 10/31）——两档不同正是本次改动（周起点固定周一）的可观察结果。
    func testDefaultGridOfOctober2026StartsOnMonday() throws {
        let october = hostMonth(year: 2026, month: 10)
        let days = MonthGridLayout.days(forMonth: october)
        XCTAssertEqual(days.count, 35, "2026-10 = 5 周（35 格）")
        XCTAssertEqual(try XCTUnwrap(days.first), hostDay(year: 2026, month: 9, day: 28), "首格 = 9/28（周一）")
        XCTAssertEqual(try XCTUnwrap(days.last), hostDay(year: 2026, month: 11, day: 1), "末格 = 11/1（周日）")
        XCTAssertEqual(MonthGridLayout.weekCount(for: october), 5, "默认参数下 2026-10 = 5 周")

        // 对照：同一时区、周日起点的显式日历——两端各挪一天（9/27 … 10/31）。
        let sundayDays = MonthGridLayout.days(forMonth: october, calendar: hostCalendar(firstWeekday: 1))
        let sundayFirst = try XCTUnwrap(sundayDays.first)
        let sundayLast = try XCTUnwrap(sundayDays.last)
        XCTAssertEqual(sundayFirst, hostDay(year: 2026, month: 9, day: 27), "周日起点：首格 = 9/27（周日）")
        XCTAssertEqual(sundayLast, hostDay(year: 2026, month: 10, day: 31), "周日起点：末格 = 10/31（周六）")
        XCTAssertNotEqual(try XCTUnwrap(days.first), sundayFirst, "两档首格不同（周一档才是产品档）")
        XCTAssertNotEqual(try XCTUnwrap(days.last), sundayLast, "两档末格不同（周一档才是产品档）")
    }

    /// ③ 默认参数下 2026-10 的按月窗口 = `[9/28 00:00, 11/2 00:00)`，且与网格的
    /// `[首格, 末格 + 1 天)` **逐字一致**——「事件窗口与网格同源」的不变量（窗口一旦比网格小一节，
    /// 网格末端那天就永远没有事件点）。
    func testDefaultMonthWindowMatchesGridBounds() throws {
        let october = hostMonth(year: 2026, month: 10)
        let window = try XCTUnwrap(MonthGridLayout.monthWindow(forMonth: october))
        XCTAssertEqual(window.start, hostDay(year: 2026, month: 9, day: 28), "窗口起点 = 网格首格（9/28 零点）")
        XCTAssertEqual(window.end, hostDay(year: 2026, month: 11, day: 2), "窗口终点 = 末格次日零点（11/2，末尾排他）")

        let gridDays = MonthGridLayout.days(forMonth: october)
        let gridLast = try XCTUnwrap(gridDays.last)
        XCTAssertEqual(window.start, try XCTUnwrap(gridDays.first), "窗口起点 = 网格首格（逐字同源）")
        XCTAssertEqual(
            window.end,
            try XCTUnwrap(Calendar.gourdDisplay.date(byAdding: .day, value: 1, to: gridLast)),
            "窗口终点 = 网格末格 + 1 天（逐字同源）"
        )
    }

    /// ④ `weekdaySymbols(for:)` 的**算式**（区域无关）：显式构造的 `zh_CN` 日历按 `firstWeekday`
    /// 旋转极短独立符号——周一起点 = 「一…日」、周日起点 = 「日…六」。
    /// 只断言这个显式日历；**不读宿主机 `.current` 的文案**（它随 locale，换台机器就红）。
    func testWeekdaySymbolsFormulaIsLocaleIndependent() {
        var chineseCalendar = Calendar(identifier: .gregorian)
        chineseCalendar.locale = Locale(identifier: "zh_CN")
        XCTAssertEqual(
            chineseCalendar.veryShortStandaloneWeekdaySymbols, ["日", "一", "二", "三", "四", "五", "六"],
            "前提：zh_CN 的极短独立符号本身是系统顺序（旋转发生在 weekdaySymbols(for:) 里）"
        )

        chineseCalendar.firstWeekday = 2
        XCTAssertEqual(
            MonthGridLayout.weekdaySymbols(for: chineseCalendar),
            ["一", "二", "三", "四", "五", "六", "日"],
            "周一起点：从下标 1 开始取（旋转）"
        )

        chineseCalendar.firstWeekday = 1
        XCTAssertEqual(
            MonthGridLayout.weekdaySymbols(for: chineseCalendar),
            ["日", "一", "二", "三", "四", "五", "六"],
            "周日起点：系统顺序原样"
        )
    }

    /// ⑥ 默认参数下 2026-11 是 6 周（周一起始；周日起始是 5 周）→ 网格高度 `43 × 6 + 63 = 321`
    /// （`MonthGridLayout.scale = 1.2` 等比放大并逐档取整后；放大前 `36 × 6 + 52 = 268`）。
    func testDefaultNovember2026NeedsSixWeeks() {
        let november = hostMonth(year: 2026, month: 11)
        XCTAssertEqual(MonthGridLayout.weekCount(for: november), 6, "2026-11 周一起始 = 6 周")
        // `43N + 63` 逐档取整后是精确整数（`scale` 派生值先 `.rounded()` 再相加），公差只是紧口径。
        XCTAssertEqual(
            MonthGridLayout.monthGridHeight(forMonth: november), 321, accuracy: 1e-9,
            "43 × 6 + 63 = 321"
        )
    }
}

// MARK: - 月网格行高 · 卡片列视口（P2 批次 / T2；p13 改指面板「日历」页）

/// 月网格的**行高**（`MonthGridLayout.monthGridHeight` = `43N + 63`，N = 当月周数）与卡片列
/// 视口（行高 − 表头高 `CalendarEventCardList.headerHeight`）是同一组数字，算错就会出现
/// 「卡片列溢出到行外」或「行内留白」——这里把这条算术钉住。
///
/// **p13 改口径**（docs/38-home-v5-layout.md D-07）：改前这条算式的消费者是首页那条全宽日历行
/// （`HomeCalendarRow`，已随月历退出首页整条退休）；今天它是**面板「日历」页左栏**的行高
/// （`StandaloneCalendarView` 直接调它，见 `PanelContentHeight` 的 measuredTabs 说明），
/// 算式本身一个字没改。
@MainActor
final class MonthGridRowHeightTests: XCTestCase {

    /// 2026-10 = 5 周（p6-ui-polish / T8 起行高按当月实际周数：`43 × 5 + 63 = 278`，
    /// `MonthGridLayout.scale = 1.2` 等比放大并逐档取整前是 `36 × 5 + 52 = 232`；
    /// T8 前是「最坏 6 周」的固定 294、T8 首版 258）− 31（收起态日期头 `CalendarEventCardList.headerHeight`
    /// = `(26 × scale).rounded()`，原 26，
    /// 含与列表之间的 4pt 间距）= 247 → 卡片列视口高度（条目多于它时栏内滚动——P11 / T7 起
    /// 不再有 `+N` 与容量算式，D-13）。
    ///
    /// 固定到 2026-10 再取行高：算式随运行日所在月的周数走，直接拿当前月参与字面量断言
    /// 换个 6 周月就整片红。
    func testRowHeightYieldsCardColumnViewportHeight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        let october2026 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!

        // 5 周月的行高（2026-10 在两种周起点下都是 5 周，见 HomeStripLayoutTests 的同源用例）。
        let rowHeight = MonthGridLayout.monthGridHeight(forMonth: october2026, calendar: calendar)
        // `43N + 63` 逐档取整是精确整数，公差只是紧口径。
        XCTAssertEqual(rowHeight, 278, accuracy: 1e-9, "43 × 5 + 63")
        let listHeight = rowHeight - CalendarEventCardList.headerHeight
        XCTAssertEqual(listHeight, 247, accuracy: 1e-9, "278 − 31（表头高 = (26 × scale).rounded()）")
        XCTAssertGreaterThan(listHeight, 0, "卡片列视口必须为正——列按它钉高（D-13 滚动列）")
    }
}

// MARK: - 日历页次要文字的不透明度（p18 / T1）

/// 面板「日历」页的次要文字（星期行 / 年份 / 农历副标 / 跨月补格 / 空态 / 右栏卡片）原先用**不透明中灰**
/// （`Color(white: 0.35 / 0.5 / 0.55 / 0.65 / 0.75)`）表达层级——那套取值只在**深色底**上成立：面板底色
/// 有两档不是纯黑（`.liquidGlass` / `.frostedGlass`），浅色系统外观下这两档渲染成浅色 / 中间调玻璃
/// （≈0.55–0.7 亮度），中灰与底色**几乎同亮度、对比度归零**，星期行（0.55 + `caption2` 小字）最惨。
///
/// 修法是把这些次要文字提进**白系 + 不透明度**（常量集中在 `MonthGridLayout`），本组用例钉住**下界**与
/// **层级顺序**：日后有人再把这些不透明度调低、或又把某处写回固定中灰，这里先红。
///
/// 常量是纯数据（不读 `Defaults`、不碰视图），直接读 `MonthGridLayout` 的静态常量即可，无需夹具。
@MainActor
final class CalendarSecondaryTextOpacityTests: XCTestCase {

    /// 全部次要文字档的（名字，取值）——「硬底线 > 0.4」与层级顺序共用这一份清单。
    private var allSecondaryOpacityTiers: [(name: String, value: Double)] {
        [
            ("weekdayOpacity", MonthGridLayout.weekdayOpacity),
            ("yearOpacity", MonthGridLayout.yearOpacity),
            ("subtitleOpacity", MonthGridLayout.subtitleOpacity),
            ("emptyStateOpacity", MonthGridLayout.emptyStateOpacity),
            ("cardSecondaryOpacity", MonthGridLayout.cardSecondaryOpacity),
            ("cardSecondaryStrongOpacity", MonthGridLayout.cardSecondaryStrongOpacity),
            ("outOfMonthOpacity", MonthGridLayout.outOfMonthOpacity),
        ]
    }

    /// 星期行（「一 二 三 …」）是浅色玻璃下最先消失的一行（`caption2` 小字 + 极短笔画），下界 0.8。
    func testWeekdayOpacityFloor() {
        XCTAssertGreaterThanOrEqual(
            MonthGridLayout.weekdayOpacity, 0.8,
            "星期行是白系最高档：0.8 以下在中间调玻璃上对比度不足（p18 根因）"
        )
    }

    /// 农历 / 节假日副标（本月日格）下界 0.7。
    func testSubtitleOpacityFloor() {
        XCTAssertGreaterThanOrEqual(
            MonthGridLayout.subtitleOpacity, 0.7,
            "农历 / 节假日副标不得低于 0.7——它比星期行弱、但必须在浅底上读得出来"
        )
    }

    /// 跨月补格（日号与副标）下界 0.4：全表最低档，但绝不能退回固定中灰那一档。
    func testOutOfMonthOpacityFloor() {
        XCTAssertGreaterThanOrEqual(
            MonthGridLayout.outOfMonthOpacity, 0.4,
            "跨月补格是最低档，但 0.4 以下在中间调玻璃上对比度归零（p18 根因）"
        )
    }

    /// 硬底线：**每一档都 > 0.4**。0.4 及以下 = 又回到「不透明中灰」那套只在深色底成立的取值。
    func testEverySecondaryOpacityStaysAboveOpaqueMidGreyTier() {
        for (name, value) in allSecondaryOpacityTiers {
            XCTAssertGreaterThan(
                value, 0.4,
                "\(name) 必须 > 0.4：不透明中灰（0.35–0.75）在浅色 / 中间调玻璃上对比度归零，正是 p18 的 bug"
            )
        }
    }

    /// 层级顺序：星期行 / 年份 / 副标 **亮于** 跨月补格（次要的再弱也弱不过补格），
    /// 卡片两档之间也是「更靠近主文字的更强」。
    func testSecondaryTextHierarchyIsStrictlyOrdered() {
        XCTAssertGreaterThan(
            MonthGridLayout.weekdayOpacity, MonthGridLayout.outOfMonthOpacity,
            "星期行应亮于跨月补格"
        )
        XCTAssertGreaterThan(
            MonthGridLayout.subtitleOpacity, MonthGridLayout.outOfMonthOpacity,
            "本月副标应亮于跨月补格"
        )
        XCTAssertGreaterThan(
            MonthGridLayout.yearOpacity, MonthGridLayout.outOfMonthOpacity,
            "年份应亮于跨月补格"
        )
        XCTAssertGreaterThan(
            MonthGridLayout.cardSecondaryStrongOpacity, MonthGridLayout.cardSecondaryOpacity,
            "卡片里靠近主文字的那一档（待办开始时间）应亮于普通次要文字"
        )
    }
}

// MARK: - 首页行滚动卡片列的展示顺序（P11 / T2，docs/36 §接口与数据形状）

/// `CalendarEventCardList.ordered(_:)` 的展示顺序（纯函数）——口径**逐字沿用**旧紧凑行的
/// `orderedEvents`：`partitionEvents` 后**全天在前、各自按 `start` 升序**；
/// 提醒与日程走同一把尺子混排（旧清单本来就是一条竖列，不分「提醒一档、日程一档」）。
///
/// **时区前提**：夹具用固定 GMT 日历构造时刻（不读本机时区），期望值全部是同一份日历下的
/// `Date` 比较——`ordered` 只比 `Date`，固定日历只为让夹具可复现。
@MainActor
final class CalendarEventCardListOrderTests: XCTestCase {

    /// 固定日历：格里高利 + GMT（不受本机时区影响）+ `en_US_POSIX`（与同文件日历用例同口径）。
    private func cardCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    /// 2026-10 里某天某时刻（年 / 月 / 日 / 时 / 分，构造口径同同文件既有的 `gridTime`）。
    private func cardTime(_ calendar: Calendar, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// 一个条目（`CalendarModel` 用系统色；`type` 决定它是不是提醒）——构造口径照同文件既有的
    /// `gridEvent` 夹具，本类自带一份私有副本（原夹具是别的类的私有成员，拿不到）。
    private func cardEvent(
        id: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        type: EventType = .event(.accepted)
    ) -> EventModel {
        EventModel(
            id: id,
            start: start,
            end: end,
            title: id,
            location: nil,
            notes: nil,
            url: nil,
            isAllDay: isAllDay,
            type: type,
            calendar: CalendarModel(
                accountName: "Test",
                id: "test.calendar",
                title: "Test",
                color: .systemBlue,
                isSubscribed: false,
                isReminder: type.isReminder
            ),
            participants: [],
            timeZone: TimeZone(secondsFromGMT: 0),
            hasRecurrenceRules: false,
            priority: nil,
            conferenceURL: nil
        )
    }

    /// **全天在前**：输入刻意乱序（全天组内部也乱序、定时条目夹在中间），输出 = 全天组
    /// （内部按 `start` 升序）+ 定时组（内部按 `start` 升序），条目不增不减。
    /// 全天组用**跨天与单日**两条不同 `start` 的条目，全天内部才有先后可分。
    func testOrderedPutsAllDayFirstAndSortsEachGroupByStart() {
        let calendar = cardCalendar()
        let timedEarly = cardEvent(
            id: "timed-early",
            start: cardTime(calendar, day: 1, hour: 9),
            end: cardTime(calendar, day: 1, hour: 10)
        )
        // 单日全天（10/2）与跨天全天（10/1 起）：start 分别是 10/2 与 10/1。
        let allDayShort = cardEvent(
            id: "allday-short",
            start: cardTime(calendar, day: 2, hour: 0),
            end: cardTime(calendar, day: 3, hour: 0),
            isAllDay: true
        )
        let timedLate = cardEvent(
            id: "timed-late",
            start: cardTime(calendar, day: 1, hour: 15),
            end: cardTime(calendar, day: 1, hour: 16)
        )
        let allDayLong = cardEvent(
            id: "allday-long",
            start: cardTime(calendar, day: 1, hour: 0),
            end: cardTime(calendar, day: 3, hour: 0),
            isAllDay: true
        )

        let ordered = CalendarEventCardList.ordered([timedEarly, allDayShort, timedLate, allDayLong])

        XCTAssertEqual(
            ordered.map(\.id),
            ["allday-long", "allday-short", "timed-early", "timed-late"],
            "全天在前（全天组内部按 start 升序：10/1 的跨天条目在 10/2 的单日条目之前）、定时在后（按 start 升序）"
        )
        XCTAssertEqual(ordered.count, 4, "排序不增不减条目")
    }

    /// **定时按 `start` 升序**：输入 15:00、09:00、12:00（乱序）→ 输出 09:00、12:00、15:00。
    func testOrderedSortsTimedEventsByStart() {
        let calendar = cardCalendar()
        let ordered = CalendarEventCardList.ordered([
            cardEvent(id: "15:00", start: cardTime(calendar, day: 1, hour: 15), end: cardTime(calendar, day: 1, hour: 16)),
            cardEvent(id: "09:00", start: cardTime(calendar, day: 1, hour: 9), end: cardTime(calendar, day: 1, hour: 10)),
            cardEvent(id: "12:00", start: cardTime(calendar, day: 1, hour: 12), end: cardTime(calendar, day: 1, hour: 13)),
        ])

        XCTAssertEqual(ordered.map(\.id), ["09:00", "12:00", "15:00"], "定时条目按开始时间升序")
    }

    /// **提醒与日程混排一起排**：定时提醒按它自己的 `start` 插在两条日程之间（不做提醒 / 日程分档）；
    /// 全天提醒落进全天组（在全部定时条目之前）。
    func testOrderedSortsRemindersTogetherWithEvents() {
        let calendar = cardCalendar()
        let allDayReminder = cardEvent(
            id: "reminder-allday",
            start: cardTime(calendar, day: 1, hour: 0),
            end: cardTime(calendar, day: 2, hour: 0),
            isAllDay: true,
            type: .reminder(completed: false)
        )
        let morningEvent = cardEvent(
            id: "event-07:30",
            start: cardTime(calendar, day: 1, hour: 7, minute: 30),
            end: cardTime(calendar, day: 1, hour: 8, minute: 30)
        )
        let middayReminder = cardEvent(
            id: "reminder-08:30",
            start: cardTime(calendar, day: 1, hour: 8, minute: 30),
            end: cardTime(calendar, day: 1, hour: 8, minute: 30),
            type: .reminder(completed: true)
        )
        let eveningEvent = cardEvent(
            id: "event-18:00",
            start: cardTime(calendar, day: 1, hour: 18),
            end: cardTime(calendar, day: 1, hour: 19)
        )

        let ordered = CalendarEventCardList.ordered([eveningEvent, middayReminder, allDayReminder, morningEvent])

        XCTAssertEqual(
            ordered.map(\.id),
            ["reminder-allday", "event-07:30", "reminder-08:30", "event-18:00"],
            "全天提醒在前；定时提醒与日程按同一把 start 尺子混排"
        )
    }

    /// 空数组返回空（宿主据此走 `EmptyEventsView`；组件自身不造任何兜底条目）。
    func testOrderedEmptyReturnsEmpty() {
        XCTAssertTrue(CalendarEventCardList.ordered([]).isEmpty, "空输入 → 空输出")
    }
}

// MARK: - 首页块顺序（P1 / T3）

/// `HomeBlockOrdering` 的纯函数口径（docs/18-p1-todos-and-order.md §接口与数据形状 1、§验收标准）：
/// 覆盖值优先 → 缺键回落默认序号 → 同值按 id 字典序 → **未知 id 不参与排序**；空表不变序。
/// 另钉住「上移 / 下移」的边界与整表序号的写入口径（`table(for:)`）。
///
/// p20 批次 / T1 加一档：`movedInGroup` 的**组内**相邻交换与三类越界返回 `nil`（组首上移 /
/// 组尾下移、单元素组的两个方向、id 不在任何组），以及 `ModuleSettingsSection.homeOrderGroups`
/// 的「环境带 ++ 可变流」规范顺序（docs/44-home-order-groups.md D-01~D-04）。
@MainActor
final class HomeBlockOrderingTests: XCTestCase {

    /// 排序用例的输入形状：块 = id + 默认序号。
    private struct Block: Equatable {
        let id: String
        let order: Int
    }

    private func sorted(_ blocks: [Block], _ overrides: [String: Int]) -> [String] {
        HomeBlockOrdering.sorted(
            blocks,
            defaultOrder: { $0.order },
            id: { $0.id },
            overrides: overrides
        ).map(\.id)
    }

    /// 内置块的 id 与默认序号：`builtin.<rawValue>`、音乐 0 → 日历 1 → 镜子 2（= 改动前写死的顺序）。
    /// 日历块已从首页移除，但 id 与序号的**既有含义**要留着（老覆盖表里可能有这个键）。
    func testBuiltinBlockVocabulary() {
        XCTAssertEqual(
            HomeBlockOrdering.BuiltinBlock.allCases.map(\.id),
            ["builtin.music", "builtin.calendar", "builtin.mirror"]
        )
        XCTAssertEqual(
            HomeBlockOrdering.BuiltinBlock.allCases.map(\.defaultOrder),
            [0, 1, 2]
        )
    }

    /// ① 有覆盖：覆盖值优先于默认序号，整表重排（把默认的末位提到首位）。
    func testOverrideWins() {
        let blocks = [
            Block(id: "builtin.music", order: 0),
            Block(id: "com.cmeng.gourd.todos", order: 20),
            Block(id: "com.cmeng.gourd.notifications", order: 40),
        ]
        let overrides = [
            "com.cmeng.gourd.notifications": 0,
            "builtin.music": 1,
            "com.cmeng.gourd.todos": 2,
        ]

        XCTAssertEqual(
            sorted(blocks, overrides),
            ["com.cmeng.gourd.notifications", "builtin.music", "com.cmeng.gourd.todos"]
        )
        // 覆盖只改顺序、不改名单：三条一个不少、也不多
        XCTAssertEqual(sorted(blocks, overrides).count, blocks.count)
    }

    /// ② 缺键回落：表里没有的块用默认序号，**与覆盖值混排**时也能算对
    /// （这是「升级用户 / 没调过顺序的用户行为不变」的判据）。
    func testMissingKeysFallBackToDefaultOrder() {
        let blocks = [
            Block(id: "builtin.music", order: 0),
            Block(id: "builtin.mirror", order: 2),
            Block(id: "com.cmeng.gourd.todos", order: 20),
        ]

        // 空表 = 完全按默认序号（未表达的用户路径）
        XCTAssertEqual(sorted(blocks, [:]), ["builtin.music", "builtin.mirror", "com.cmeng.gourd.todos"])

        // 只有待办被移动过：它写 0，两个内置块回落到 0 / 2 → 待办与音乐同值 0，按 id 字典序
        // "builtin.music" < "com.cmeng.gourd.todos"，音乐仍在待办之前
        XCTAssertEqual(
            sorted(blocks, ["com.cmeng.gourd.todos": 0]),
            ["builtin.music", "com.cmeng.gourd.todos", "builtin.mirror"],
            "同值 0 的两条按 id 字典序：builtin.music 在前"
        )
        // 镜子被移动到 -1：单条覆盖即可越到最前，两条内置块仍按 id 字典序（这里只有一个更小）
        XCTAssertEqual(
            sorted(blocks, ["builtin.mirror": -1]),
            ["builtin.mirror", "builtin.music", "com.cmeng.gourd.todos"]
        )
    }

    /// ③ 未知 id 忽略：表里出现、名单里没有的键**不占位、不报错、不影响任何块**；
    /// 名单里的块一个都不消失（失败信号「未知 id 让排序崩或块消失」的反面）。
    func testUnknownIDsAreIgnored() {
        let blocks = [
            Block(id: "builtin.music", order: 0),
            Block(id: "com.cmeng.gourd.todos", order: 20),
        ]
        let overrides = [
            "builtin.calendar": 0,              // 已移除的日历块：老表里的历史键
            "com.cmeng.gourd.removed": -100,    // 被移除 / 改名的模块
            "": 3,                              // 空串 id
        ]

        XCTAssertEqual(sorted(blocks, overrides), ["builtin.music", "com.cmeng.gourd.todos"], "未知键只被忽略")
        XCTAssertEqual(sorted(blocks, overrides).count, blocks.count, "块不因未知键而消失")

        // 未知键与已知键混在一起：已知的照样生效
        var mixed = overrides
        mixed["com.cmeng.gourd.todos"] = -1
        XCTAssertEqual(sorted(blocks, mixed), ["com.cmeng.gourd.todos", "builtin.music"])
    }

    /// ④ 空表：`overrides` 为空 → 默认序号序；`items` 为空 → 空结果（都不崩）。
    func testEmptyTableAndEmptyItems() {
        let blocks = [
            Block(id: "b", order: 1),
            Block(id: "a", order: 1),
            Block(id: "c", order: 0),
        ]
        XCTAssertEqual(sorted(blocks, [:]), ["c", "a", "b"], "同值 1 的两条按 id 字典序")
        XCTAssertTrue(sorted([], [:]).isEmpty)
        XCTAssertTrue(sorted([], ["a": 0]).isEmpty)
    }

    /// 上移 / 下移的边界：与相邻项互换；**到顶 / 到底 / id 不在名单里 → 原样返回**。
    func testMoveBoundaries() {
        let ids = ["a", "b", "c"]

        XCTAssertEqual(HomeBlockOrdering.moved(ids, moving: "b", direction: .up), ["b", "a", "c"])
        XCTAssertEqual(HomeBlockOrdering.moved(ids, moving: "b", direction: .down), ["a", "c", "b"])
        XCTAssertEqual(HomeBlockOrdering.moved(ids, moving: "a", direction: .up), ids, "已在顶：不动")
        XCTAssertEqual(HomeBlockOrdering.moved(ids, moving: "c", direction: .down), ids, "已在底：不动")
        XCTAssertEqual(HomeBlockOrdering.moved(ids, moving: "missing", direction: .up), ids, "不在名单里：不动")
        XCTAssertEqual(HomeBlockOrdering.moved(["only"], moving: "only", direction: .up), ["only"])
        XCTAssertEqual(HomeBlockOrdering.moved([], moving: "a", direction: .up), [])
    }

    /// 整表序号：名单顺序即 0…n-1；重复 id 取首次出现（不崩）。
    func testTableRenumbersWholeList() {
        XCTAssertEqual(HomeBlockOrdering.table(for: ["b", "a", "c"]), ["b": 0, "a": 1, "c": 2])
        XCTAssertEqual(HomeBlockOrdering.table(for: []), [:])
        XCTAssertEqual(HomeBlockOrdering.table(for: ["x", "x", "y"]), ["x": 0, "y": 2], "重复键取首次出现，不崩")
    }

    /// 端到端（纯函数链）：默认名单 → 把末位块上移 → 整表落盘的值能让 `sorted` 复现屏幕上的顺序。
    func testMoveThenSortRoundTrip() {
        let blocks = [
            Block(id: "builtin.music", order: 0),
            Block(id: "com.cmeng.gourd.todos", order: 20),
            Block(id: "com.cmeng.gourd.notifications", order: 40),
        ]
        let movedIDs = HomeBlockOrdering.moved(blocks.map(\.id), moving: "com.cmeng.gourd.notifications", direction: .up)
        XCTAssertEqual(movedIDs, ["builtin.music", "com.cmeng.gourd.notifications", "com.cmeng.gourd.todos"])

        let table = HomeBlockOrdering.table(for: movedIDs)
        XCTAssertEqual(
            sorted(blocks, table),
            ["builtin.music", "com.cmeng.gourd.notifications", "com.cmeng.gourd.todos"],
            "落盘的值读回来排出的顺序 = 移动后屏幕上的顺序"
        )
    }

    /// `homeBlockOrder` 键的**声明默认值**（空表 = 用户未表达）+ **序列化往返**（写盘 → 读回）。
    ///
    /// 往返走一个**临时 suite**（不碰开发机 `com.cmeng.gourd` 域，同 `notificationHUDBackgroundStyle`
    /// / `notchPanelBackgroundStyle` 的既有口径）；断言盘上真的出现**字典**而不只是内存值——
    /// 「顺序落盘、重启保持」靠的就是这一层（同一键被设置页与首页两处读）。
    func testHomeBlockOrderKeyDefaultsAndRoundTrip() {
        XCTAssertEqual(Defaults.Keys.homeBlockOrder.name, "homeBlockOrder")
        XCTAssertEqual(
            Defaults.Keys.homeBlockOrder.defaultValue,
            [:],
            "缺键 = 用户未表达（回落 manifest 的 defaultPlacement.order / 内置块的 0 / 1 / 2）"
        )

        let suiteName = "com.cmeng.gourd.tests.homeBlockOrder"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return XCTFail("建不出临时 suite（\(suiteName)）")
        }
        defer { suite.removePersistentDomain(forName: suiteName) }
        let key = Defaults.Key<[String: Int]>("homeBlockOrder", default: [:], suite: suite)

        XCTAssertEqual(Defaults[key], [:], "没写过时读回空表")
        let table = ["builtin.music": 1, "com.cmeng.gourd.todos": 0]
        Defaults[key] = table
        XCTAssertEqual(Defaults[key], table, "写盘 → 读回同一张表")
        XCTAssertEqual(suite.dictionary(forKey: key.name) as? [String: Int], table, "盘上存的是字典（不是字符串）")
        Defaults[key] = [:]
        XCTAssertEqual(Defaults[key], [:], "清空同样往返（回到「用户未表达」）")
    }

    // MARK: 组内移动（p20 / T1）

    /// **组内相邻交换**（docs/44 D-01~D-04）：`movedInGroup` 只在 `id` 所在的那一组里换位；
    /// 组间顺序与**其它组**的成员在结果里逐字不变，且纯函数不改入参。
    func testMovedInGroupSwapsInsideOwningGroup() {
        let groups = [["e1", "e2", "e3"], ["f1", "f2", "f3"]]

        XCTAssertEqual(
            HomeBlockOrdering.movedInGroup(groups, moving: "f2", direction: .up),
            [["e1", "e2", "e3"], ["f2", "f1", "f3"]],
            "可变流里上移一格"
        )
        XCTAssertEqual(
            HomeBlockOrdering.movedInGroup(groups, moving: "f2", direction: .down),
            [["e1", "e2", "e3"], ["f1", "f3", "f2"]]
        )

        let movedEnv = HomeBlockOrdering.movedInGroup(groups, moving: "e2", direction: .up)
        XCTAssertEqual(movedEnv, [["e2", "e1", "e3"], ["f1", "f2", "f3"]], "环境带里上移一格")
        XCTAssertEqual(movedEnv?[1], groups[1], "另一组逐字不变")
        XCTAssertEqual(groups, [["e1", "e2", "e3"], ["f1", "f2", "f3"]], "纯函数不改入参")
    }

    /// **组内移动的三类越界一律返回 `nil`**（不是原样返回）：组首上移 / 组尾下移、单元素组的两个
    /// 方向、`id` 不在任何一组里——调用方据此不写盘（docs/44 D-03）。
    func testMovedInGroupBoundariesReturnNil() {
        let groups = [["e1", "e2"], ["f1", "f2"]]

        XCTAssertNil(HomeBlockOrdering.movedInGroup(groups, moving: "e1", direction: .up), "组首上移")
        XCTAssertNil(HomeBlockOrdering.movedInGroup(groups, moving: "f2", direction: .down), "组尾下移")
        XCTAssertNil(HomeBlockOrdering.movedInGroup(groups, moving: "missing", direction: .up), "不在任何组里")
        XCTAssertNil(HomeBlockOrdering.movedInGroup(groups, moving: "missing", direction: .down))
        XCTAssertNil(HomeBlockOrdering.movedInGroup([["only"], ["f1"]], moving: "only", direction: .up), "单元素组上移")
        XCTAssertNil(HomeBlockOrdering.movedInGroup([["only"], ["f1"]], moving: "only", direction: .down), "单元素组下移")
        XCTAssertNil(HomeBlockOrdering.movedInGroup([], moving: "a", direction: .up), "空输入")
        XCTAssertNil(HomeBlockOrdering.movedInGroup([[]], moving: "a", direction: .up), "只有一个空组")
    }

    /// **两节的分组算式 + 回落整表的规范顺序**（docs/44 §做法②③ / D-03）：`homeOrderGroups` 把
    /// 排序后的首页名单拆成 `[环境带, 可变流]`（返回顺序恒为「环境带 ++ 可变流」，每组保持入参顺序）；
    /// 组内交换后 `.flatMap { $0 }` 就是这个规范顺序，交给 `table(for:)` 得到整表 rank——另一组逐字不变。
    func testHomeOrderGroupsSplitAndCanonicalFlattenOrder() {
        let ids = ["com.cmeng.gourd.todos", "com.cmeng.gourd.music",
                   "com.cmeng.gourd.notifications", "com.cmeng.gourd.stats"]
        let environmentIDs: Set<String> = ["com.cmeng.gourd.music", "com.cmeng.gourd.stats"]

        let groups = ModuleSettingsSection.homeOrderGroups(ids, environmentIDs: environmentIDs)
        XCTAssertEqual(
            groups,
            [["com.cmeng.gourd.music", "com.cmeng.gourd.stats"],
             ["com.cmeng.gourd.todos", "com.cmeng.gourd.notifications"]],
            "环境带在前、可变流在后；每组保持入参顺序"
        )

        // 环境带内上移一格：拼回整表的规范顺序 = 环境带 ++ 可变流（另一组逐字不变）。
        let moved = HomeBlockOrdering.movedInGroup(groups, moving: "com.cmeng.gourd.stats", direction: .up)
        XCTAssertEqual(
            moved?.flatMap { $0 },
            ["com.cmeng.gourd.stats", "com.cmeng.gourd.music",
             "com.cmeng.gourd.todos", "com.cmeng.gourd.notifications"]
        )
        XCTAssertEqual(moved?[1], groups[1], "另一组逐字不变")

        XCTAssertEqual(
            HomeBlockOrdering.table(for: moved?.flatMap { $0 } ?? []),
            ["com.cmeng.gourd.stats": 0, "com.cmeng.gourd.music": 1,
             "com.cmeng.gourd.todos": 2, "com.cmeng.gourd.notifications": 3],
            "落盘仍是整表 rank（环境带 ++ 可变流）"
        )
    }
}

// MARK: - 启动台：扫描 / 排序 / 过滤（P2 / T1）

/// `LauncherAppScanner` 与 `LauncherRanking` 的口径（docs/19-launcher.md §接口与数据形状 1、2、
/// §改动点设计 1；两个类型都是纯函数 / 纯 I/O，无 UI 依赖）。
///
/// **夹具一律是临时目录树**：`<root>/Foo.app/Contents/Info.plist` 这一级形态就够
/// （`Bundle(url:)` 读的是 `Contents/Info.plist`，不需要真的可执行文件）。绝不扫真实
/// `/Applications`——那种用例会随「这台机器装了什么 App」而绿或红。
final class LauncherScannerRankingTests: XCTestCase {

    /// 每个用例一份临时目录树，`tearDown` 清掉。
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gourd-launcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root = fixtureRoot { try? FileManager.default.removeItem(at: root) }
        fixtureRoot = nil
    }

    /// 在 fixture 根下建一个子目录（当一个「应用目录」用）。
    private func makeFixtureDirectory(_ name: String) throws -> URL {
        let directory = fixtureRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 造一个 `.app` 目录：`<directory>/<folderName>/Contents/Info.plist`。
    /// `plist == nil` 时不写 Info.plist（模拟没有清单的空壳包）。
    @discardableResult
    private func makeApp(in directory: URL, named folderName: String, plist: [String: String]? = nil) throws -> URL {
        let app = directory.appendingPathComponent(folderName, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        if let plist {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        return app
    }

    /// 排序 / 过滤用例的输入形状（`url` 只是个值，不碰文件系统；
    /// `file` 用来造出「显示名与文件名不同」的用例）。
    private func app(_ id: String, _ name: String, file: String? = nil) -> LauncherApp {
        LauncherApp(id: id, name: name, url: URL(fileURLWithPath: "/fixture-apps/\(file ?? name).app"))
    }

    // MARK: 扫描

    /// 基本列举：一层里的 `.app` 全列出（含没有 Info.plist 的），非 `.app` 的目录与普通文件不列。
    func testScanListsTopLevelAppsOnly() throws {
        let root = try makeFixtureDirectory("Root")
        try makeApp(in: root, named: "Alpha.app", plist: ["CFBundleIdentifier": "com.example.alpha"])
        try makeApp(in: root, named: "Beta.app", plist: ["CFBundleIdentifier": "com.example.beta"])
        let shell = try makeApp(in: root, named: "NoPlist.app")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("NotAnApp", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("readme".utf8).write(to: root.appendingPathComponent("readme.txt"))

        let apps = LauncherAppScanner.scan(rootURLs: [root])

        XCTAssertEqual(
            Set(apps.map(\.id)),
            ["com.example.alpha", "com.example.beta", shell.standardizedFileURL.path],
            "无 plist 的 `.app` 用路径当 id；非 `.app` 目录与文件不列"
        )
        XCTAssertEqual(apps.map(\.name), ["Alpha", "Beta", "NoPlist"], "无 plist 时名称回落文件名（去 .app）")
        XCTAssertTrue(apps.allSatisfy { $0.url.path.hasSuffix(".app") })
    }

    /// 去重按 **`url.standardizedFileURL`**：同一个根被传两次、以及带尾斜杠的同一路径，都只留一项。
    func testScanDeduplicatesByStandardizedURL() throws {
        let root = try makeFixtureDirectory("Root")
        try makeApp(in: root, named: "Alpha.app", plist: ["CFBundleIdentifier": "com.example.alpha"])
        try makeApp(in: root, named: "Beta.app", plist: ["CFBundleIdentifier": "com.example.beta"])

        let once = LauncherAppScanner.scan(rootURLs: [root])
        let twice = LauncherAppScanner.scan(rootURLs: [root, root])
        let withTrailingSlash = LauncherAppScanner.scan(
            rootURLs: [root, URL(fileURLWithPath: root.path + "/", isDirectory: true)]
        )

        XCTAssertEqual(once.count, 2)
        XCTAssertEqual(twice.map(\.id), once.map(\.id), "同一个根传两次不该出现重复项")
        XCTAssertEqual(withTrailingSlash.map(\.id), once.map(\.id), "带尾斜杠的同一路径是同一个根")
        XCTAssertEqual(Set(twice.map(\.url)).count, 2)
    }

    /// `.app` **内部的嵌套 `.app`** 不是独立应用：只扫一层，嵌套包不出现在清单里。
    func testScanSkipsAppsNestedInsideAppBundles() throws {
        let root = try makeFixtureDirectory("Root")
        let outer = try makeApp(in: root, named: "Outer.app", plist: ["CFBundleIdentifier": "com.example.outer"])
        try makeApp(
            in: outer.appendingPathComponent("Contents/Applications", isDirectory: true),
            named: "Inner.app",
            plist: ["CFBundleIdentifier": "com.example.inner"]
        )

        let apps = LauncherAppScanner.scan(rootURLs: [root])

        XCTAssertEqual(apps.map(\.id), ["com.example.outer"])
        XCTAssertEqual(apps.map(\.url), [outer.standardizedFileURL])
        XCTAssertFalse(apps.contains { $0.name == "Inner" }, "嵌套包不进网格")
    }

    /// 名称三级回落：`CFBundleDisplayName` → `CFBundleName` → 文件名（去 `.app`）；
    /// 空串 / 纯空白等同于「没这个键」（否则网格里会留一行看不见的标题）。
    func testScanNameFallsBackThroughBundleKeys() throws {
        let root = try makeFixtureDirectory("Root")
        try makeApp(in: root, named: "Display.app", plist: [
            "CFBundleIdentifier": "com.example.display",
            "CFBundleDisplayName": "显示名",
            "CFBundleName": "包名",
        ])
        try makeApp(in: root, named: "BundleNameOnly.app", plist: [
            "CFBundleIdentifier": "com.example.bundlename",
            "CFBundleName": "只有包名",
        ])
        try makeApp(in: root, named: "NoKeys.app", plist: ["CFBundleIdentifier": "com.example.nokeys"])
        try makeApp(in: root, named: "BlankDisplay.app", plist: [
            "CFBundleIdentifier": "com.example.blank",
            "CFBundleDisplayName": "   ",
            "CFBundleName": "空白回落",
        ])

        let names = Dictionary(uniqueKeysWithValues: LauncherAppScanner.scan(rootURLs: [root]).map { ($0.id, $0.name) })

        XCTAssertEqual(names["com.example.display"], "显示名", "① 显示名优先")
        XCTAssertEqual(names["com.example.bundlename"], "只有包名", "② 缺显示名 → 包名")
        XCTAssertEqual(names["com.example.nokeys"], "NoKeys", "③ 两个键都缺 → 文件名去 .app")
        XCTAssertEqual(names["com.example.blank"], "空白回落", "显示名是纯空白 → 当没有，继续回落")
    }

    /// 单个根读失败（不存在 / 是文件 / 无权限）**只跳过它**：其余根正常返回，不抛错、不空表。
    func testScanToleratesMissingOrUnreadableRoots() throws {
        let root = try makeFixtureDirectory("Root")
        try makeApp(in: root, named: "Alpha.app", plist: ["CFBundleIdentifier": "com.example.alpha"])
        let missing = fixtureRoot.appendingPathComponent("Nope", isDirectory: true)
        let notADirectory = fixtureRoot.appendingPathComponent("plain.txt")
        try Data("text".utf8).write(to: notADirectory)

        let onlyMissing = LauncherAppScanner.scan(rootURLs: [missing])
        let mixed = LauncherAppScanner.scan(rootURLs: [missing, notADirectory, root])

        XCTAssertTrue(onlyMissing.isEmpty, "只有坏根时给空表（不是崩）")
        XCTAssertEqual(mixed.map(\.id), ["com.example.alpha"], "坏根不影响好根")
    }

    /// 同名不同路径是**两个**应用（去重只看 url，不看名字）——这正是不用路径当唯一键的原因之一。
    func testScanKeepsSameNameAppsFromDifferentPaths() throws {
        let one = try makeFixtureDirectory("One")
        let two = try makeFixtureDirectory("Two")
        let first = try makeApp(in: one, named: "Same.app", plist: ["CFBundleDisplayName": "同名"])
        let second = try makeApp(in: two, named: "Same.app", plist: ["CFBundleDisplayName": "同名"])

        let apps = LauncherAppScanner.scan(rootURLs: [one, two])

        XCTAssertEqual(apps.count, 2)
        XCTAssertEqual(apps.map(\.name), ["同名", "同名"])
        XCTAssertEqual(Set(apps.map(\.url)), [first.standardizedFileURL, second.standardizedFileURL])
        XCTAssertEqual(Set(apps.map(\.id)).count, 2, "没有 bundle id 时 id 回落各自的绝对路径")
    }

    /// `defaultRoots` 的形状（**只断言取值，不扫目录**——扫真实目录的用例会随机器状态抖动）。
    func testDefaultRootsAreTheThreeApplicationDirectories() {
        let roots = LauncherAppScanner.defaultRoots

        XCTAssertEqual(roots.count, 3)
        XCTAssertTrue(roots.allSatisfy { $0.isFileURL && $0.lastPathComponent == "Applications" })
        XCTAssertEqual(roots[1].path, FileManager.default.homeDirectoryForCurrentUser.path + "/Applications")
    }

    // MARK: 排序

    /// 固定项恒在前——**即便它没有任何使用数据**，而没固定的项最近刚用过（固定是本地数据，
    /// Spotlight 查询失败不该把固定项丢了：docs/19 §改动点设计 4 的陷阱）。
    func testRankPutsPinnedFirst() {
        let apps = [app("hot", "Zeta"), app("pin", "Alpha"), app("cold", "Beta")]
        let usage = ["hot": LauncherUsage(lastUsed: Date(timeIntervalSince1970: 900), useCount: 50)]

        XCTAssertEqual(
            LauncherRanking.rank(apps, pinned: ["pin"], usage: usage).map(\.id),
            ["pin", "hot", "cold"]
        )
        XCTAssertEqual(
            LauncherRanking.rank(apps, pinned: ["cold", "pin"], usage: usage).map(\.id),
            ["pin", "cold", "hot"],
            "多个固定项之间仍按同一套键：都无使用数据 → 名称升序（Alpha 在 Beta 前）"
        )
    }

    /// 最近使用降序；**没有 `lastUsed` 的项排在有数据的之后**（`useCount` 再大也不能越位）。
    func testRankOrdersByLastUsedDescending() {
        let apps = [app("old", "Alpha"), app("new", "Beta"), app("counted", "Gamma")]
        let usage: [String: LauncherUsage] = [
            "old": LauncherUsage(lastUsed: Date(timeIntervalSince1970: 100), useCount: 1),
            "new": LauncherUsage(lastUsed: Date(timeIntervalSince1970: 300), useCount: 1),
            "counted": LauncherUsage(lastUsed: nil, useCount: 99),
        ]

        XCTAssertEqual(
            LauncherRanking.rank(apps, pinned: [], usage: usage).map(\.id),
            ["new", "old", "counted"],
            "新的在前；只有次数没有时间的排在所有有时间的之后"
        )
    }

    /// `lastUsed` 相同时按使用次数降序（两个字段都缺才是「无数据」）。
    func testRankOrdersByUseCountDescending() {
        let sameMoment = Date(timeIntervalSince1970: 500)
        let apps = [app("few", "Alpha"), app("many", "Beta"), app("none", "Gamma")]
        let usage: [String: LauncherUsage] = [
            "few": LauncherUsage(lastUsed: sameMoment, useCount: 2),
            "many": LauncherUsage(lastUsed: sameMoment, useCount: 8),
            "none": LauncherUsage(lastUsed: sameMoment, useCount: nil),
        ]

        XCTAssertEqual(
            LauncherRanking.rank(apps, pinned: [], usage: usage).map(\.id),
            ["many", "few", "none"],
            "同一时刻：次数多的在前，没次数的垫底"
        )
    }

    /// 没有使用数据时**一律按名称**（`localizedStandardCompare`，数字按数值比而不是字典序）；
    /// `usage` 里有条目但两个字段都是 `nil`，仍按「无数据」处理。
    func testRankFallsBackToNameWithoutUsage() {
        let apps = [app("ten", "App 10"), app("two", "App 2"), app("zebra", "Zebra")]

        XCTAssertEqual(
            LauncherRanking.rank(apps, pinned: [], usage: [:]).map(\.id),
            ["two", "ten", "zebra"],
            "App 2 在 App 10 之前（本地化比较按数值，不是字典序）"
        )
        XCTAssertEqual(
            LauncherRanking.rank(apps, pinned: [], usage: ["ten": LauncherUsage(lastUsed: nil, useCount: nil)]).map(\.id),
            ["two", "ten", "zebra"],
            "usage 里存在但两个字段都空 = 无数据"
        )
        XCTAssertEqual(
            LauncherRanking.rank(apps, pinned: [], usage: ["zebra": LauncherUsage(lastUsed: Date(timeIntervalSince1970: 1), useCount: 1)]).map(\.id),
            ["zebra", "two", "ten"],
            "有数据的提到前面，其余照旧按名称"
        )
    }

    /// `pinned` 里清单中没有的 id（已卸载 / 已移动的 App 留下的残留）**一律忽略**：不崩、不乱序。
    func testRankIgnoresUnknownPinnedIDs() {
        let apps = [app("b", "Beta"), app("a", "Alpha")]

        XCTAssertEqual(
            LauncherRanking.rank(apps, pinned: ["ghost", "b"], usage: [:]).map(\.id),
            ["b", "a"],
            "未知 id 忽略，已知的固定项照样优先"
        )
        XCTAssertEqual(
            LauncherRanking.rank(apps, pinned: ["ghost"], usage: [:]).map(\.id),
            ["a", "b"],
            "全是未知 id：等价于没有固定项"
        )
        XCTAssertTrue(LauncherRanking.rank([], pinned: ["ghost"], usage: [:]).isEmpty)
    }

    /// 四项键全相等（同名且都没使用数据）时按 `id` 定序：同样的输入换个顺序进来，输出一致
    /// （否则界面顺序取决于文件系统枚举顺序，会随机跳动）。
    func testRankIsDeterministicForIdenticalKeys() {
        let apps = [app("zeta", "同名"), app("alpha", "同名")]

        XCTAssertEqual(LauncherRanking.rank(apps, pinned: [], usage: [:]).map(\.id), ["alpha", "zeta"])
        XCTAssertEqual(
            LauncherRanking.rank(apps.reversed(), pinned: [], usage: [:]).map(\.id),
            ["alpha", "zeta"],
            "输入顺序不影响输出"
        )
    }

    // MARK: 过滤

    /// 大小写不敏感（`localizedCaseInsensitiveContains`）。
    func testFilterIsCaseInsensitive() {
        let apps = [app("safari", "Safari"), app("calc", "Calculator")]

        XCTAssertEqual(LauncherRanking.filter(apps, query: "saf").map(\.id), ["safari"])
        XCTAssertEqual(LauncherRanking.filter(apps, query: "CALC").map(\.id), ["calc"])
        XCTAssertTrue(LauncherRanking.filter(apps, query: "edge").isEmpty)
    }

    /// 显示名与文件名都要匹配：中文本地化的 App 用英文名也能搜到。
    func testFilterMatchesDisplayNameOrFileName() {
        let apps = [app("chrome", "谷歌浏览器", file: "Google Chrome"), app("safari", "Safari")]

        XCTAssertEqual(LauncherRanking.filter(apps, query: "浏览").map(\.id), ["chrome"], "显示名命中")
        XCTAssertEqual(LauncherRanking.filter(apps, query: "chrome").map(\.id), ["chrome"], "显示名不中 → 文件名命中")
        XCTAssertEqual(LauncherRanking.filter(apps, query: "SAFARI").map(\.id), ["safari"])
    }

    /// 空查询 / 纯空白返回**原列表**（同一顺序，不是空表）；首尾空白对命中无影响。
    func testFilterEmptyQueryReturnsOriginalList() {
        let apps = [app("b", "Beta"), app("a", "Alpha")]

        XCTAssertEqual(LauncherRanking.filter(apps, query: "").map(\.id), ["b", "a"], "空查询原样返回")
        XCTAssertEqual(LauncherRanking.filter(apps, query: "   ").map(\.id), ["b", "a"], "纯空白同上")
        XCTAssertEqual(LauncherRanking.filter([], query: "x"), [])
    }

    /// 中文名匹配 + 查询串首尾空白（与「纯空白 = 空查询」同口径，命中的关键词是去掉空白后的）。
    func testFilterMatchesChineseNameWithSurroundingWhitespace() {
        let apps = [app("notes", "备忘录"), app("photos", "照片")]

        XCTAssertEqual(LauncherRanking.filter(apps, query: "备忘").map(\.id), ["notes"])
        XCTAssertEqual(LauncherRanking.filter(apps, query: " 备忘录 ").map(\.id), ["notes"])
        XCTAssertEqual(LauncherRanking.filter(apps, query: "照片").map(\.id), ["photos"])
    }
}

// MARK: - 启动台：分区与拖放（p7：上区「快捷启动」/ 下区网格）

/// `LauncherPartition` 与 `LauncherQuickDrop` 的口径（docs/31-home-workday-launcher.md
/// §接口与数据形状 2）：上区顺序 = 固定先后、下区剔除固定项且保序、拖放四象限与未知/外来输入的 no-op。
///
/// 两个类型都是**纯函数**：不读 `Defaults`、不碰文件系统、不查 Spotlight——夹具是构造的
/// `LauncherApp` 值，没有临时目录、没有盘上状态。扫描 / 排序 / 过滤的用例在同文件的
/// `LauncherScannerRankingTests`，模块接线与固定项读写接缝在 `LauncherModuleTests`。
final class LauncherPartitionDropTests: XCTestCase {

    /// 构造一个 `LauncherApp` 值（`url` 只是个值，不碰文件系统）。
    private func app(_ id: String, _ name: String, file: String? = nil) -> LauncherApp {
        LauncherApp(id: id, name: name, url: URL(fileURLWithPath: "/fixture-apps/\(file ?? name).app"))
    }

    /// 分区：上区顺序 = **固定先后**（`pinnedIDs` 表序，不吃 rank 序）、下区 = `ranked` 剔除固定项
    /// 且**保序**；未知 id 忽略、重复 id 保留首次；空表 / 全固定两边界。
    func testLauncherPartitionSplitsQuickAndGridStably() {
        let apps = [app("a", "Alpha"), app("b", "Beta"), app("c", "Gamma")]

        let split = LauncherPartition.split(ranked: apps, pinnedIDs: ["c", "a"])
        XCTAssertEqual(split.quick.map(\.id), ["c", "a"], "上区顺序 = 固定先后（表序），与 ranked 的先后无关")
        XCTAssertEqual(split.grid.map(\.id), ["b"], "下区 = ranked 剔除固定项后保序")

        // 同一份 rank 结果（固定项恒在前 → 名称升序）喂进分区：上区仍按固定先后，不按 rank 序
        let ranked = LauncherRanking.rank(apps, pinned: ["c", "a"], usage: [:])
        XCTAssertEqual(ranked.map(\.id), ["a", "c", "b"], "底座：rank 的固定项段按名称排（Alpha 在 Gamma 前）")
        XCTAssertEqual(
            LauncherPartition.split(ranked: ranked, pinnedIDs: ["c", "a"]).quick.map(\.id),
            ["c", "a"],
            "上区不沿用 rank 的固定项段次序——固定先后才是唯一口径"
        )

        // 上区不随 Spotlight 数据抖动：换一份 usage（rank 序确实变了）上区逐字不变
        let usageA = LauncherRanking.rank(apps, pinned: ["b"], usage: [:])
        let usageB = LauncherRanking.rank(
            apps, pinned: ["b"],
            usage: ["c": LauncherUsage(lastUsed: Date(timeIntervalSince1970: 999), useCount: 9)]
        )
        XCTAssertNotEqual(usageA.map(\.id), usageB.map(\.id), "夹具自证：两份 usage 的下区顺序不同")
        XCTAssertEqual(
            LauncherPartition.split(ranked: usageA, pinnedIDs: ["b"]).quick.map(\.id),
            LauncherPartition.split(ranked: usageB, pinnedIDs: ["b"]).quick.map(\.id),
            "上区顺序 = 固定先后：Spotlight 数据变了也不动"
        )

        // 未知 id（残留的已卸载 App）不占位；下区不受影响
        let withGhost = LauncherPartition.split(ranked: apps, pinnedIDs: ["ghost", "b"])
        XCTAssertEqual(withGhost.quick.map(\.id), ["b"], "未知 id 忽略")
        XCTAssertEqual(withGhost.grid.map(\.id), ["a", "c"], "未知 id 不被当作固定项剔除网格")

        // 重复固定（手改 UserDefaults 塞重复项）：保留首次，上区不出现重复格子
        let duplicated = LauncherPartition.split(ranked: apps, pinnedIDs: ["b", "a", "b"])
        XCTAssertEqual(duplicated.quick.map(\.id), ["b", "a"], "同 id 只保留第一次")
        XCTAssertEqual(duplicated.grid.map(\.id), ["c"])

        // 边界：空 pinned → 全进下区（原顺序）；全固定 → 下区空（视图侧由上区兜底）
        let none = LauncherPartition.split(ranked: apps, pinnedIDs: [])
        XCTAssertTrue(none.quick.isEmpty)
        XCTAssertEqual(none.grid.map(\.id), apps.map(\.id), "没有固定项：全部留在下区，顺序不变")

        let all = LauncherPartition.split(ranked: apps, pinnedIDs: ["c", "b", "a"])
        XCTAssertEqual(all.quick.map(\.id), ["c", "b", "a"])
        XCTAssertTrue(all.grid.isEmpty, "全固定：下区空")

        let empty = LauncherPartition.split(ranked: [], pinnedIDs: ["ghost"])
        XCTAssertTrue(empty.quick.isEmpty && empty.grid.isEmpty, "清单为空：两区都空，不崩")
    }

    /// 拖放解析矩阵（docs/31 §接口与数据形状 2）：quick+未固定 → 追加表尾；grid+已固定 → 移除
    /// 全部同 id；quick+已固定 / grid+未固定 / 未知 id / 空 id → 一律 no-op（nil）。
    func testLauncherQuickDropResolveMatrix() {
        let known: Set<String> = ["a", "b", "c"]

        // quick + 未固定 → 固定，追加到表尾（与 LauncherPinning.adding 同口径）
        XCTAssertEqual(
            LauncherQuickDrop.resolve(draggedID: "c", target: .quick, pinnedIDs: ["a"], knownIDs: known),
            ["a", "c"]
        )
        XCTAssertEqual(
            LauncherQuickDrop.resolve(draggedID: "c", target: .quick, pinnedIDs: [], knownIDs: known),
            ["c"]
        )

        // grid + 已固定 → 取消固定，移除全部同 id
        XCTAssertEqual(
            LauncherQuickDrop.resolve(draggedID: "a", target: .grid, pinnedIDs: ["a", "b", "a"], knownIDs: known),
            ["b"],
            "同 id 的重复项一并清掉（与 LauncherPinning.removing 同口径）"
        )

        // 四象限的两个反向：quick 收到已固定、grid 收到未固定 → no-op
        XCTAssertNil(
            LauncherQuickDrop.resolve(draggedID: "a", target: .quick, pinnedIDs: ["a"], knownIDs: known),
            "拖上已固定的应用不产生重复项"
        )
        XCTAssertNil(
            LauncherQuickDrop.resolve(draggedID: "c", target: .grid, pinnedIDs: ["a"], knownIDs: known),
            "拖下未固定的应用无可取消"
        )

        // 未知 id（外来文本 / 本次扫描不存在的 id）→ 两区都 no-op，不被固定、也不被误删
        XCTAssertNil(LauncherQuickDrop.resolve(draggedID: "ghost", target: .quick, pinnedIDs: [], knownIDs: known))
        XCTAssertNil(LauncherQuickDrop.resolve(draggedID: "ghost", target: .grid, pinnedIDs: ["ghost"], knownIDs: known))

        // 空 id → no-op（即便它混进了 knownIDs，显式空判据也先落 nil）
        XCTAssertNil(LauncherQuickDrop.resolve(draggedID: "", target: .quick, pinnedIDs: [], knownIDs: known))
        XCTAssertNil(LauncherQuickDrop.resolve(draggedID: "", target: .quick, pinnedIDs: [], knownIDs: ["", "a"]))
        XCTAssertNil(LauncherQuickDrop.resolve(draggedID: "", target: .grid, pinnedIDs: [""], knownIDs: ["", "a"]))

        // 纯函数：只返回新表，不改传入的表（落盘是 store 的事）
        let pinned = ["a"]
        _ = LauncherQuickDrop.resolve(draggedID: "c", target: .quick, pinnedIDs: pinned, knownIDs: known)
        XCTAssertEqual(pinned, ["a"], "resolve 不修改输入")
    }
}


// MARK: - 启动台：模块 / 固定 / 配置 / 使用数据（P2 / T2）

/// `LauncherModule` 与它的三个注入点（`LauncherPins` / `LauncherSettings` / `LauncherUsageQuery`）
/// 的口径（docs/19-launcher.md §接口与数据形状 3、§改动点设计 2/3/4、§验收标准）。
///
/// **不碰真实 `Defaults` 域**：固定项的用例一律走 `LauncherPins` 的注入式假体（内存表 + 写盘计数），
/// 只有 `pinnedApps` 键的往返用例用一个**临时 suite**（同 `homeBlockOrder` 的既有口径）。
/// 扫描用例一律用**临时目录树** fixture，绝不扫真实 `/Applications`。
@MainActor
final class LauncherModuleTests: XCTestCase {

    // MARK: 夹具

    /// 固定项的**内存假体**：一对读 / 写闭包 + 写盘计数（用例据此断言幂等与"先落盘再刷新"）。
    private final class PinDisk {
        private(set) var table: [String] = []
        private(set) var writes = 0

        var pins: LauncherPins {
            LauncherPins(
                read: { self.table },
                write: { self.table = $0; self.writes += 1 }
            )
        }
    }

    /// 按字典给值的配置假体（同文件的 `StubConfigHandle` 只返回 nil；这里要验「用户覆盖生效」）。
    private final class ConfigStub: ConfigHandle {
        private let values: [String: Any]

        init(values: [String: Any] = [:]) { self.values = values }

        func get<T: Codable & Sendable>(_ key: String, as: T.Type) -> T? { values[key] as? T }
        func set<T: Codable & Sendable>(_ key: String, to value: T) -> Bool { false }
    }

    private func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gourd-launcher-module-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// 造一个 `.app` 目录：`<root>/<folderName>/Contents/Info.plist`（`Bundle(url:)` 读的就是这一级）。
    @discardableResult
    private func makeApp(in root: URL, folderName: String, bundleID: String) throws -> URL {
        let app = root.appendingPathComponent(folderName, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: String] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": folderName.replacingOccurrences(of: ".app", with: ""),
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    private func logger() -> ModuleLogger {
        ModuleLogger(moduleID: LauncherModule.manifest.id, shortID: "launcher")
    }

    /// 模块的 `ModuleContext` 假体（config 全是 nil → 走 `LauncherConfigDefaults`）。
    private func context(config: ConfigHandle? = nil) -> ModuleContext {
        ModuleContext(
            moduleID: LauncherModule.manifest.id,
            host: HostInfo(appVersion: "0", apiVersion: HostInfo.currentAPIVersion, macOSVersion: "15.0"),
            config: config ?? ConfigStub(),
            logger: logger(),
            ui: StubUIHandle()
        )
    }

    private func request(_ surface: Surface = .expanded) -> ContentRequest {
        ContentRequest(surface: surface, phase: .expanded, reason: .initial)
    }

    // MARK: manifest 契约

    /// manifest 逐字段对齐 docs/19 §接口与数据形状 4：**只声明 `expanded`**（不声明 compact / home /
    /// lockscreen）、默认关、零权限、无 placement、config 三个键；文案 key 都能从宿主 bundle 解析。
    func testLauncherManifestContract() throws {
        let manifest = LauncherModule.manifest
        XCTAssertNoThrow(try manifest.validate(), "真模块的 manifest 必须过校验（含 symbol 可解析性）")

        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.launcher")
        XCTAssertEqual(manifest.shortID, "launcher")
        XCTAssertEqual(manifest.name.key, "module.launcher.name")
        XCTAssertEqual(manifest.summary?.key, "module.launcher.summary")
        XCTAssertEqual(manifest.icon.type, "symbol")
        XCTAssertEqual(manifest.icon.name, "square.grid.2x2")
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.apiVersion, HostInfo.currentAPIVersion)
        XCTAssertEqual(manifest.kind, "builtin")

        XCTAssertEqual(manifest.surfaces, [.expanded], "只声明 expanded（D-02）")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "折叠态不占（控制器裁决 1：左右槽位未落地）")
        XCTAssertFalse(manifest.surfaces.contains(.home), "首页块不占（控制器裁决 1：用户没要求）")
        XCTAssertFalse(manifest.surfaces.contains(.lockscreen))

        XCTAssertEqual(manifest.defaultEnabled, false, "新增模块一律默认关（docs/14 T-12 / D-04）")
        XCTAssertEqual(manifest.permissions, [], "零权限（扫目录 + 启动 App 都不需要 TCC）")
        XCTAssertNil(manifest.defaultPlacement, "placement 只在含 compact 时有意义，本批不给")

        let properties = try XCTUnwrap(manifest.config?.properties)
        XCTAssertEqual(Set(properties.keys), ["iconSize", "density", "showRecents"], "config 只有这三个键")
        XCTAssertEqual(properties["iconSize"]?.type, "number")
        XCTAssertEqual(properties["density"]?.type, "number")
        XCTAssertEqual(properties["showRecents"]?.type, "boolean")
        // 默认值只有一个来源：`LauncherConfigDefaults`（这里同时把数值钉在文档口径上）
        XCTAssertEqual(LauncherConfigDefaults.iconSize, 44)
        XCTAssertEqual(LauncherConfigDefaults.density, 1)
        XCTAssertEqual(LauncherConfigDefaults.showRecents, true)
        XCTAssertEqual(properties["iconSize"]?.default, .double(LauncherConfigDefaults.iconSize))
        XCTAssertEqual(properties["density"]?.default, .double(LauncherConfigDefaults.density))
        XCTAssertEqual(properties["showRecents"]?.default, .bool(LauncherConfigDefaults.showRecents))

        // 文案 key 可解析（06 §3.3 R5：视图内不写字面量文案；catalog 没编进宿主 bundle 时这里会红）
        for key in [
            "module.launcher.name",
            "module.launcher.summary",
            "module.launcher.searchPlaceholder",
            "module.launcher.pin",
            "module.launcher.unpin",
            "module.launcher.empty",
            "module.launcher.noMatch",
            "module.launcher.loading",
        ] {
            let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(localized, key, "\(key) 没解析出文案（catalog 未编进宿主 bundle？）")
            XCTAssertFalse(localized.isEmpty, "\(key) 解析为空串")
        }

        // manifest 可导出为 JSON 且往返不丢字段。**比 JSON 字节而不是比 `ConfigValue`**：
        // `iconSize` 的默认值 `.double(44)` 走 JSON 是 `44`，回来按 T1 的解码规则是 `.int(44)`
        //（`ConfigValue.init(from:)` 里整数先于浮点），两个值对象不相等但语义逐字相同。
        // 编码用 `.sortedKeys`：`config.properties` 是字典，不排序的话两次编码的键序会不同。
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(manifest)
        let decoded = try ModuleManifest.decode(from: encoded)
        XCTAssertEqual(try encoder.encode(decoded), encoded, "manifest 往返（编 → 解 → 再编）逐字节一致")
    }

    /// 内容分发：`expanded` 给 `.view`；**`.compact` / `.lockscreen` / `.home` 一律 `.none`**
    /// （不占位、不算失败——本批的契约，也是"首页与折叠态没有多出东西"的判据）。
    func testLauncherModuleServesOnlyExpandedSurface() async throws {
        let module = LauncherModule(context: context())
        try await module.activate()

        guard case .view = module.content(for: request(.expanded)) else {
            return XCTFail("expanded 请求应拿到应用网格的 .view")
        }
        for surface in [Surface.compact, .lockscreen, .home] {
            guard case .none = module.content(for: request(surface)) else {
                return XCTFail("\(surface.rawValue) 未声明 → 必须答 .none（不占位）")
            }
        }

        await module.deactivate()
    }

    // MARK: 固定（幂等 + 先落盘再刷新）

    /// 固定 / 取消固定的**幂等**（docs/19 §验收标准「重复固定 / 取消不产生重复项」）：
    /// 走 `LauncherPins` 的内存假体，**不碰真实 `Defaults` 域**；写盘计数同时钉住"表没变就不写盘"。
    ///
    /// 三个动作的语义要分清（右键菜单只用到第三个）：
    /// - `pin` = 固定（已在表里 → 不变）；
    /// - `unpin` = 取消（不在表里 → 不变）；
    /// - `toggle` = **取反**（连点两次回到原状态——这是"固定 / 取消固定"菜单项的语义，不是幂等动作）。
    func testLauncherPinToggleIsIdempotent() {
        let disk = PinDisk()
        let pins = disk.pins

        XCTAssertEqual(pins.load(), [], "缺键 = 没有固定项")

        // `pin`：重复固定不产生重复项、也不重复落盘
        XCTAssertEqual(pins.pin("com.example.alpha"), ["com.example.alpha"])
        XCTAssertEqual(disk.writes, 1, "固定一次落盘一次")
        XCTAssertEqual(disk.table, pins.load(), "返回值就是盘上的值（先落盘再刷新）")
        XCTAssertTrue(LauncherPinning.isPinned("com.example.alpha", in: pins.load()))
        XCTAssertEqual(pins.pin("com.example.alpha"), ["com.example.alpha"], "重复固定：表不变")
        XCTAssertEqual(disk.writes, 1, "重复固定不再落盘（幂等）")

        // `unpin`：重复取消 / 取消一个不在表里的 id 都是空操作
        XCTAssertEqual(pins.unpin("com.example.alpha"), [], "取消固定")
        XCTAssertEqual(disk.writes, 2, "取消固定落盘一次")
        XCTAssertEqual(pins.unpin("com.example.alpha"), [], "重复取消：表不变")
        XCTAssertEqual(pins.unpin("com.example.never-pinned"), [], "取消一个不在表里的 id 也是幂等空操作")
        XCTAssertEqual(disk.writes, 2, "两种空操作都不落盘")

        // `toggle`：取反（右键菜单的唯一入口），两次回到原状态
        XCTAssertEqual(pins.toggle("com.example.beta"), ["com.example.beta"], "点一下：固定")
        XCTAssertEqual(pins.toggle("com.example.beta"), [], "再点一下：取消固定")
        XCTAssertEqual(disk.writes, 4, "两次取反都真的改了表（各落盘一次）")
        XCTAssertEqual(pins.load(), [])

        // 顺序：表尾追加、一次只动一项（`rank` 只把这张表当集合用，顺序只为可读）
        XCTAssertEqual(pins.pin("a"), ["a"])
        XCTAssertEqual(pins.pin("b"), ["a", "b"])
        XCTAssertEqual(pins.unpin("a"), ["b"])
        XCTAssertEqual(disk.table, ["b"])
    }

    /// 纯函数口径（`LauncherPinning`）：加 / 删 / 取反，含**同 id 的脏数据**（手改 UserDefaults 塞重复项）。
    func testLauncherPinningPureFunctions() {
        XCTAssertTrue(LauncherPinning.isPinned("a", in: ["b", "a"]))
        XCTAssertFalse(LauncherPinning.isPinned("a", in: []))

        XCTAssertEqual(LauncherPinning.adding("a", to: []), ["a"])
        XCTAssertEqual(LauncherPinning.adding("a", to: ["a", "b"]), ["a", "b"], "已在表里 → 原样返回")
        XCTAssertEqual(LauncherPinning.removing("a", from: ["a", "a", "b"]), ["b"], "同 id 的重复项一并清掉")
        XCTAssertEqual(LauncherPinning.removing("a", from: ["b"]), ["b"])
        XCTAssertEqual(LauncherPinning.toggled("b", in: []), ["b"])
        XCTAssertEqual(LauncherPinning.toggled("b", in: ["b"]), [])
    }

    /// `pinnedApps` 键的**声明默认值**（空表 = 没有固定项）+ **序列化往返**（写盘 → 读回）。
    ///
    /// 往返走一个**临时 suite**（不碰开发机 `com.cmeng.gourd` 域，同 `homeBlockOrder` /
    /// `notificationHUDBackgroundStyle` 的既有口径）；断言盘上真的出现**字符串数组**而不只是内存值——
    /// 「固定项落盘、重启保持」靠的就是这一层。
    func testPinnedAppsKeyDefaultsAndRoundTrip() {
        XCTAssertEqual(Defaults.Keys.pinnedApps.name, "pinnedApps")
        XCTAssertEqual(Defaults.Keys.pinnedApps.defaultValue, [], "缺键 = 没有固定项")

        let suiteName = "com.cmeng.gourd.tests.pinnedApps"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return XCTFail("建不出临时 suite（\(suiteName)）")
        }
        defer { suite.removePersistentDomain(forName: suiteName) }
        let key = Defaults.Key<[String]>("pinnedApps", default: [], suite: suite)

        XCTAssertEqual(Defaults[key], [], "没写过时读回空表")

        // 生产形态的读写接缝（`LauncherPins`）接在这个临时键上：走的就是模块的写路径
        let pins = LauncherPins(read: { Defaults[key] }, write: { Defaults[key] = $0 })
        XCTAssertEqual(pins.load(), [])

        pins.pin("com.example.alpha")
        pins.pin("com.example.beta")
        XCTAssertEqual(
            Defaults[key],
            ["com.example.alpha", "com.example.beta"],
            "写盘 → 读回同一张表（顺序 = 动作顺序）"
        )
        XCTAssertEqual(
            suite.stringArray(forKey: key.name),
            ["com.example.alpha", "com.example.beta"],
            "盘上存的是字符串数组（不是 JSON 串 / 不是字典）"
        )

        pins.unpin("com.example.alpha")
        XCTAssertEqual(Defaults[key], ["com.example.beta"])
        XCTAssertEqual(pins.load(), ["com.example.beta"], "重启后读到的就是盘上这份")

        Defaults[key] = []
        XCTAssertEqual(Defaults[key], [], "清空同样往返（回到「没有固定项」）")
    }

    // MARK: 分区（上区 = 固定先后 / 下区 = 剔除固定项保序）

    /// **pin / unpin 驱动两区**（p7 / T5，docs/31-home-workday-launcher.md §接口与数据形状 2）：
    /// 走生产的 `LauncherStore.pin` / `.unpin`（内存假体 `LauncherPins`），断言**先落盘再刷新**与
    /// 两区结果——pin 后上区含、下区不含、盘上值正确；unpin 后回落下区；重复 pin / unpin 幂等
    /// （表不变、不写盘）。
    ///
    /// 取数与其他 store 用例同款：临时目录 fixture + 注入的空使用数据（不查 Spotlight、不碰开发机
    /// 真实 `Defaults` 域——固定表只有一个内存假体）。
    func testLauncherStorePinUnpinUpdatesPartitions() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(in: root, folderName: "Alpha.app", bundleID: "com.example.alpha")
        try makeApp(in: root, folderName: "Beta.app", bundleID: "com.example.beta")
        try makeApp(in: root, folderName: "Gamma.app", bundleID: "com.example.gamma")

        let disk = PinDisk()
        let store = LauncherStore(
            logger: logger(),
            roots: [root],
            pins: disk.pins,
            settings: { LauncherSettings(iconSize: 44, density: 1, showRecents: false) },
            fetchUsage: { _ in [:] }
        )
        store.prepare()
        await store.load()

        // 起步：没有固定项 → 上区空（视图画提示格）、下区 = 排名全量（无使用数据 → 名称序）
        XCTAssertTrue(store.quickApps.isEmpty, "空 `pinnedApps` → 上区是空的")
        XCTAssertEqual(store.gridApps.map(\.name), ["Alpha", "Beta", "Gamma"], "下区 = 排名全量")
        XCTAssertEqual(disk.table, [])

        let alpha = try XCTUnwrap(store.apps.first { $0.name == "Alpha" })
        let beta = try XCTUnwrap(store.apps.first { $0.name == "Beta" })

        // pin：**先落盘再刷新**——盘上先有值，内存镜像随之更新，两区（现算）立即跟随
        store.pin(beta)
        XCTAssertEqual(disk.table, ["com.example.beta"], "固定已经落盘")
        XCTAssertEqual(disk.writes, 1, "固定一次落盘一次")
        XCTAssertEqual(store.pinned, ["com.example.beta"], "内存镜像 = 盘上值")
        XCTAssertEqual(store.quickApps.map(\.id), ["com.example.beta"], "上区含固定项")
        XCTAssertEqual(store.gridApps.map(\.name), ["Alpha", "Gamma"], "下区剔除固定项、保序")

        // 重复 pin：幂等（表不变、不写盘、上区不出现第二枚同 id 格子）
        store.pin(beta)
        XCTAssertEqual(disk.writes, 1, "重复固定不再落盘（幂等）")
        XCTAssertEqual(store.quickApps.map(\.id), ["com.example.beta"])

        // 再固定一个：追加表尾 → 上区顺序 = **固定先后**（不是名称序）
        store.pin(alpha)
        XCTAssertEqual(disk.table, ["com.example.beta", "com.example.alpha"])
        XCTAssertEqual(store.quickApps.map(\.name), ["Beta", "Alpha"], "上区顺序 = 固定先后")
        XCTAssertEqual(store.gridApps.map(\.name), ["Gamma"])

        // unpin：取消固定 → **回落**下区（按 rank 序该在哪就在哪）
        store.unpin(beta)
        XCTAssertEqual(disk.table, ["com.example.alpha"], "取消固定已经落盘")
        XCTAssertEqual(disk.writes, 3, "两次 pin + 一次 unpin 各落盘一次")
        XCTAssertEqual(store.quickApps.map(\.name), ["Alpha"])
        XCTAssertEqual(store.gridApps.map(\.name), ["Beta", "Gamma"], "回落下区、保序")

        // 重复 unpin：幂等（表不变、不写盘）
        store.unpin(beta)
        XCTAssertEqual(disk.table, ["com.example.alpha"])
        XCTAssertEqual(disk.writes, 3, "重复取消不再落盘")
        XCTAssertEqual(store.quickApps.map(\.name), ["Alpha"])
        XCTAssertEqual(store.gridApps.map(\.name), ["Beta", "Gamma"])
    }

    // MARK: 排序接入（先名称、后 Spotlight、固定恒优先）

    /// 取数全链（临时目录 fixture + 内存固定表 + 注入的使用数据）：
    /// ① 没有使用数据 → 按名称；② 使用数据回来 → 最近使用优先；③ **固定项恒在最前**；
    /// ④ 取消固定 → 回到使用数据 / 名称序。
    func testLauncherStoreRankingWithPinnedAndUsage() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(in: root, folderName: "Zebra.app", bundleID: "com.example.zebra")
        try makeApp(in: root, folderName: "Alpha.app", bundleID: "com.example.alpha")

        let disk = PinDisk()
        let store = LauncherStore(
            logger: logger(),
            roots: [root],
            pins: disk.pins,
            settings: { LauncherSettings(iconSize: 44, density: 1, showRecents: true) },
            // 空样本 = Spotlight 没数据（docs/19 §已知限制 2 的回落）
            fetchUsage: { _ in [:] }
        )
        store.prepare()
        await store.load()

        XCTAssertEqual(store.apps.count, 2, "临时目录里就两个 `.app`")
        XCTAssertEqual(store.ranked.map(\.name), ["Alpha", "Zebra"], "没有使用数据 → 按名称（固定项也没有）")
        XCTAssertTrue(store.usage.isEmpty, "空样本 → 使用数据表为空（不是「全部 0 次」）")

        // ② 使用数据（注入样本，键 = 路径）回来 → 直接重排：最近使用的在前
        let zebra = try XCTUnwrap(store.apps.first { $0.name == "Zebra" })
        let alpha = try XCTUnwrap(store.apps.first { $0.name == "Alpha" })
        let withUsage = LauncherStore(
            logger: logger(),
            roots: [root],
            pins: disk.pins,
            settings: { LauncherSettings(iconSize: 44, density: 1, showRecents: true) },
            fetchUsage: { _ in
                [zebra.url.path: LauncherUsageSample(path: zebra.url.path, lastUsed: Date(), useCount: 1)]
            }
        )
        await withUsage.load()
        XCTAssertEqual(withUsage.ranked.map(\.name), ["Zebra", "Alpha"], "有使用数据 → 最近使用的排前面")

        // ③ 固定恒优先：固定那个"没被用过"的，它照样排到最前；盘上立刻可见（先落盘再刷新）
        withUsage.togglePin(alpha)
        XCTAssertEqual(withUsage.ranked.map(\.name), ["Alpha", "Zebra"], "固定项恒在未固定项之前")
        XCTAssertEqual(disk.table, ["com.example.alpha"], "固定项已经落盘")
        XCTAssertEqual(disk.writes, 1, "固定一次只落盘一次（幂等）")

        // ④ 取消固定 → 回到使用数据决定的顺序
        withUsage.togglePin(alpha)
        XCTAssertEqual(withUsage.ranked.map(\.name), ["Zebra", "Alpha"], "取消固定后按使用数据排")
        XCTAssertEqual(disk.table, [])
    }

    /// `showRecents = false`：**不查 Spotlight**（注入的取数器一次都不该被调到），
    /// 顺序仍是 固定 → 名称。
    func testLauncherStoreSkipsSpotlightWhenRecentsDisabled() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(in: root, folderName: "Zebra.app", bundleID: "com.example.zebra")
        try makeApp(in: root, folderName: "Alpha.app", bundleID: "com.example.alpha")

        let disk = PinDisk()
        var fetchCount = 0
        let store = LauncherStore(
            logger: logger(),
            roots: [root],
            pins: disk.pins,
            settings: { LauncherSettings(iconSize: 44, density: 1, showRecents: false) },
            fetchUsage: { _ in
                fetchCount += 1
                return [:]
            }
        )
        await store.load()

        XCTAssertEqual(fetchCount, 0, "showRecents = false → 不发起 Spotlight 查询")
        XCTAssertEqual(store.ranked.map(\.name), ["Alpha", "Zebra"], "顺序 = 固定（空）→ 名称")
    }

    // MARK: 点图标 → 启动 → 收起

    /// **「点图标 → 启动 → 收起」整条链路**（P2 复审修 1）：经两个注入点驱动**生产的** `launch`
    /// （`openApp` = 记录型假体、`collapse` = 记录型假体），于是"点了没反应 / 点了不收起"这两种
    /// 失败都能被断言，而用例本身不会真的拉起任何 App。
    ///
    /// 断言三件：启动的是**这一项**的 URL、两个动作**各一次**、顺序是**先打开后收起**
    /// （`docs/19` §处理链路的两步：先发启动不等完成，再请求收起）。
    func testLauncherLaunchOpensAppThenCollapses() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp(in: root, folderName: "Alpha.app", bundleID: "com.example.alpha")

        /// 两个动作都往同一串里记，先后顺序因此可判（跨闭包的共享可变状态只在这个用例内）。
        var calls: [String] = []
        var openedURLs: [URL] = []
        let store = LauncherStore(
            logger: logger(),
            roots: [root],
            pins: PinDisk().pins,
            settings: { LauncherSettings(iconSize: 44, density: 1, showRecents: false) },
            collapse: { calls.append("collapse") },
            openApp: { url in
                calls.append("open")
                openedURLs.append(url)
            }
        )
        await store.load()

        let app = try XCTUnwrap(store.apps.first, "临时目录里应扫到一个 `.app`")
        store.launch(app)

        XCTAssertEqual(openedURLs, [app.url], "打开的正是这一项的 URL（一次）")
        XCTAssertEqual(calls, ["open", "collapse"], "先启动、后收起，各一次")

        // 再点一次：仍然是"这一项各一次"（没有攒状态、也没有漏掉收起）
        store.launch(app)
        XCTAssertEqual(openedURLs, [app.url, app.url], "重复点击 = 再启动一次（`openApplication` 对已启动的 App 只是激活）")
        XCTAssertEqual(calls, ["open", "collapse", "open", "collapse"], "重复点击同样两次调用都发生")
    }

    /// 使用数据的映射：**键 = `LauncherApp.id`**（与固定项同源）；清单里没有的路径忽略；
    /// 同一个 bundle id 的两份拷贝合并（最近使用取更晚、次数取更大）。
    func testLauncherUsageMappingUsesAppIDAsKey() throws {
        let alpha = LauncherApp(
            id: "com.example.alpha",
            name: "Alpha",
            url: URL(fileURLWithPath: "/fixture/Alpha.app")
        )
        let twin = LauncherApp(
            id: "com.example.alpha",
            name: "Alpha Twin",
            url: URL(fileURLWithPath: "/other/Alpha.app")
        )
        let shell = LauncherApp(
            id: "/fixture/Shell.app",
            name: "Shell",
            url: URL(fileURLWithPath: "/fixture/Shell.app")
        )
        let samples = [
            "/fixture/Alpha.app": LauncherUsageSample(
                path: "/fixture/Alpha.app",
                lastUsed: Date(timeIntervalSince1970: 100),
                useCount: 3
            ),
            "/other/Alpha.app": LauncherUsageSample(
                path: "/other/Alpha.app",
                lastUsed: Date(timeIntervalSince1970: 300),
                useCount: 1
            ),
            "/fixture/Shell.app": LauncherUsageSample(path: "/fixture/Shell.app", lastUsed: nil, useCount: nil),
            "/not-in-list.app": LauncherUsageSample(
                path: "/not-in-list.app",
                lastUsed: Date(timeIntervalSince1970: 900),
                useCount: 99
            ),
        ]

        let usage = LauncherUsageQuery.usageByID(for: [alpha, twin, shell], samples: samples)

        XCTAssertEqual(
            Set(usage.keys),
            ["com.example.alpha", "/fixture/Shell.app"],
            "键 = LauncherApp.id（无 bundle id 的包用路径）；清单里没有的路径忽略"
        )
        XCTAssertEqual(
            usage["com.example.alpha"]?.lastUsed,
            Date(timeIntervalSince1970: 300),
            "同 id 的两份拷贝：最近使用取更晚的一次"
        )
        XCTAssertEqual(usage["com.example.alpha"]?.useCount, 3, "使用次数取更大的一个")
        XCTAssertNil(usage["/fixture/Shell.app"]?.lastUsed)
        XCTAssertNil(usage["/fixture/Shell.app"]?.useCount, "两个字段都缺 = 无数据（不是 0）")
    }

    /// **属性映射**（P2 复审修 2）：`samples(from:)` 里把 `NSMetadataItem` 的属性变成样本的那段逻辑，
    /// 经"属性名 → 值"的闭包接缝（`LauncherUsageQuery.sample(attribute:)`）用构造的数据钉住。
    ///
    /// 这条用例存在的理由：真查询在**没开索引 / 属性名写错**时都返回空表，"降级成按名称"是静默的；
    /// 只有把映射抽出来才能让"读的是哪三个属性、类型不对怎么处理"变成可失败断言。
    func testLauncherUsageSampleMappingReadsDocumentedAttributes() throws {
        // ① 属性名（被改错就红）：路径 / 最近使用用 SDK 导出的常量，使用次数是文档里的属性名
        XCTAssertEqual(LauncherUsageQuery.pathAttribute, "kMDItemPath")
        XCTAssertEqual(LauncherUsageQuery.lastUsedAttribute, NSMetadataItemLastUsedDateKey, "SDK 常量，别再抄字面量")
        XCTAssertEqual(LauncherUsageQuery.lastUsedAttribute, "kMDItemLastUsedDate")
        XCTAssertEqual(LauncherUsageQuery.useCountAttribute, "kMDItemUseCount", "公开的 Spotlight 元数据属性名")

        // ② 正常值（日期 = Date、次数 = NSNumber）→ 映射正确，且**读的就是这三个属性名**
        let lastUsed = Date(timeIntervalSince1970: 1_700_000_000)
        var asked: [String] = []
        let sample = try XCTUnwrap(LauncherUsageQuery.sample(attribute: { key -> Any? in
            asked.append(key)
            switch key {
            case LauncherUsageQuery.pathAttribute: return "/Applications/Alpha.app"
            case LauncherUsageQuery.lastUsedAttribute: return lastUsed
            case LauncherUsageQuery.useCountAttribute: return NSNumber(value: 42)
            default: return nil
            }
        }))

        XCTAssertEqual(
            sample,
            LauncherUsageSample(path: "/Applications/Alpha.app", lastUsed: lastUsed, useCount: 42)
        )
        XCTAssertEqual(
            Set(asked),
            [LauncherUsageQuery.pathAttribute, LauncherUsageQuery.lastUsedAttribute, LauncherUsageQuery.useCountAttribute],
            "映射问的就是这三个属性名（名字在这条断言里被钉住）"
        )

        // ③ 次数是**数字字符串**（索引的另一种形态，含首尾空白）：照样认
        let stringCount = try XCTUnwrap(LauncherUsageQuery.sample(attribute: { key -> Any? in
            switch key {
            case LauncherUsageQuery.pathAttribute: return "/Applications/Beta.app"
            case LauncherUsageQuery.useCountAttribute: return " 17 "
            default: return nil
            }
        }))
        XCTAssertEqual(stringCount.useCount, 17)
        XCTAssertNil(stringCount.lastUsed, "没有最近使用属性 → nil（不是当前时间）")

        // ④ 属性缺失 / 类型不对（nil、非数字字符串、别的类型）：不崩、按"无数据"处理
        let missing = try XCTUnwrap(LauncherUsageQuery.sample(attribute: { key -> Any? in
            key == LauncherUsageQuery.pathAttribute ? "/Applications/Gamma.app" : nil
        }))
        XCTAssertNil(missing.lastUsed)
        XCTAssertNil(missing.useCount)

        let wrongTypes = try XCTUnwrap(LauncherUsageQuery.sample(attribute: { key -> Any? in
            switch key {
            case LauncherUsageQuery.pathAttribute: return "/Applications/Delta.app"
            case LauncherUsageQuery.lastUsedAttribute: return "昨天"   // 不是 Date
            case LauncherUsageQuery.useCountAttribute: return "很多次"  // 不是数字
            default: return nil
            }
        }))
        XCTAssertNil(wrongTypes.lastUsed)
        XCTAssertNil(wrongTypes.useCount)

        // ⑤ 没有路径 = 这条结果用不上（不是"拿空路径建一条"）
        XCTAssertNil(LauncherUsageQuery.sample(attribute: { _ in nil }))
        XCTAssertNil(LauncherUsageQuery.sample(attribute: { key -> Any? in
            key == LauncherUsageQuery.useCountAttribute ? NSNumber(value: 1) : nil
        }))

        // ⑥ `useCount(from:)` 的形态表
        XCTAssertEqual(LauncherUsageQuery.useCount(from: NSNumber(value: 7)), 7)
        XCTAssertEqual(LauncherUsageQuery.useCount(from: "12"), 12)
        XCTAssertNil(LauncherUsageQuery.useCount(from: "abc"))
        XCTAssertNil(LauncherUsageQuery.useCount(from: ""))
        XCTAssertNil(LauncherUsageQuery.useCount(from: nil))
        XCTAssertNil(LauncherUsageQuery.useCount(from: Date()), "表外类型一律无数据")
    }

    /// 图标的**惰性缓存**：同路径第二次不再读盘（返回同一个对象）。
    func testLauncherIconCacheReadsEachPathOnce() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = try makeApp(in: root, folderName: "Alpha.app", bundleID: "com.example.alpha")
        let app = LauncherApp(id: "com.example.alpha", name: "Alpha", url: appURL.standardizedFileURL)

        let cache = LauncherIconCache()
        XCTAssertEqual(cache.cachedCount, 0, "没画到就不取（惰性的判据）")

        let first = cache.icon(for: app)
        XCTAssertEqual(cache.cachedCount, 1)
        let second = cache.icon(for: app)
        XCTAssertTrue(first === second, "同路径命中缓存，不第二次读盘")
        XCTAssertEqual(cache.cachedCount, 1)
    }

    // MARK: 配置

    /// config 的三个键：**用户覆盖生效**、缺值兜到 `LauncherConfigDefaults`（= manifest 默认值）。
    func testLauncherSettingsReadsConfigWithFallback() {
        XCTAssertEqual(
            LauncherSettings.read(from: ConfigStub()),
            LauncherSettings(
                iconSize: LauncherConfigDefaults.iconSize,
                density: LauncherConfigDefaults.density,
                showRecents: LauncherConfigDefaults.showRecents
            ),
            "config 给不出值（schema 缺键）时兜到 manifest 默认值"
        )

        let overridden = LauncherSettings.read(from: ConfigStub(values: [
            "iconSize": 64.0,
            "density": 1.4,
            "showRecents": false,
        ]))
        XCTAssertEqual(overridden, LauncherSettings(iconSize: 64, density: 1.4, showRecents: false))
    }

    /// 网格尺寸口径：`iconSize` / `density` 越界（用户直接改 UserDefaults）时**夹取到区间端点**，
    /// 不除以零、也不画出一个 1000pt 的图标。
    func testLauncherGridMetricsClampsBoundaries() {
        let normal = LauncherGridMetrics.metrics(iconSize: 44, density: 1)
        XCTAssertEqual(normal.iconSide, 44)
        XCTAssertEqual(normal.itemSpacing, LauncherGridMetrics.baseSpacing)
        XCTAssertEqual(normal.minimumItemWidth, 44 + LauncherGridMetrics.labelMargin)
        XCTAssertEqual(normal.labelFontSize, 10)

        let tiny = LauncherGridMetrics.metrics(iconSize: 1, density: 0)
        XCTAssertEqual(tiny.iconSide, LauncherGridMetrics.iconSizeRange.lowerBound)
        XCTAssertEqual(tiny.itemSpacing, LauncherGridMetrics.baseSpacing * CGFloat(LauncherGridMetrics.densityRange.lowerBound))
        XCTAssertEqual(tiny.labelFontSize, 9, "小图标配小字")

        let huge = LauncherGridMetrics.metrics(iconSize: 1000, density: 9)
        XCTAssertEqual(huge.iconSide, LauncherGridMetrics.iconSizeRange.upperBound)
        XCTAssertEqual(huge.itemSpacing, LauncherGridMetrics.baseSpacing * CGFloat(LauncherGridMetrics.densityRange.upperBound))
    }

    // MARK: 取数器（Spotlight）

    /// 取数器**必须在主 actor 上被主 run loop 推进**（`LauncherUsageQuery` 的类型级 `@MainActor`
    /// 就是这条）：`NSMetadataQuery` 由调用线程的 run loop 驱动，在协作线程池上它永远收集不完，
    /// 表现为"等满超时 → 使用数据永远为空 → 排序永远按名称"（P2 / T2 取证时实测踩到过一次）。
    ///
    /// 判据用**耗时**而不是结果条数：临时目录不会被 Spotlight 收录（结果必定为空），但"**收集结束**"
    /// 这件事与有没有结果无关——挂住的那一版一定等满 `timeout`。所以"远早于超时返回"正好钉住这条回归，
    /// 且与本机装了什么 App、索引开没开都无关。
    func testLauncherUsageFetchIsPumpedByMainRunLoop() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let timeout: TimeInterval = 4
        let startedAt = Date()
        let samples = await LauncherUsageQuery.fetch(rootURLs: [root], timeout: timeout)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertTrue(samples.isEmpty, "临时目录里没有 `.app`（Spotlight 也不收录它）")
        XCTAssertLessThan(elapsed, timeout / 2, "收集结束即返回（挂住的表现是等满 \(timeout)s 超时）")

        let emptyStartedAt = Date()
        let empty = await LauncherUsageQuery.fetch(rootURLs: [], timeout: timeout)
        XCTAssertTrue(empty.isEmpty, "空根目录直接返回空表")
        XCTAssertLessThan(Date().timeIntervalSince(emptyStartedAt), 0.1, "空根目录不发起查询")
    }
}

// MARK: - 隔空投送字形的几何（p9 / T5）

/// `AirDropGlyphMetrics` 的**量取值**（从用户 2026-10-09 给的控制中心参考图量出，见
/// `DynamicIsland/components/Tabs/PanelIcon.swift` 里该结构上方的说明与 docs/34 §做法 机制二那张表：
/// 点 `0.13R`、三段弧环心 `0.33 / 0.65 / 0.90R`、线宽 `0.113R`、底部开口每侧 35°）。
///
/// **逐字钉量取值**：不写「递增 / 落在某区间」这类断言——那种断言在把比例改成别的量（例如
/// `[0.5, 0.6, 0.7]`）时仍然是绿的，钉不住「与参考图量出来的那一组数」。本文件这一组管**常量值**
/// 这一层；视图渲出来的结构（圆心点 + 三段同心环 + 缺口在视觉正下方）由渲染取证脚本
/// `.workflow/p9-calendar-week-icon/evidence/glyph-structure.py` 的像素判据覆盖（脚本，退出码 0）。
final class AirDropGlyphMetricsTests: XCTestCase {

    /// 四个常量逐字：改动任何一个比例 / 角度即红。
    func testMetricsPinTheMeasuredValuesFromTheReferenceImage() {
        XCTAssertEqual(AirDropGlyphMetrics.dotRadiusFactor, 0.13, "圆心点半径（以字形外缘半径 R 为单位）")
        XCTAssertEqual(
            AirDropGlyphMetrics.ringRadiusFactors,
            [0.33, 0.65, 0.90],
            "三段弧的环心半径（顺序 = 从内到外）"
        )
        XCTAssertEqual(AirDropGlyphMetrics.strokeFactor, 0.113, "弧的线宽（圆头线帽）")
        XCTAssertEqual(AirDropGlyphMetrics.gapDegrees, 70, "底部开口的总跨度（每侧 35°）")
    }

    /// 实例读法与静态读法**同源**（T3 给的两种读法都能编译：`AirDropGlyphMetrics.dotRadiusFactor`
    /// 与 `AirDropGlyphMetrics().dotRadiusFactor`）——镜像属性被换成第二个来源时这条红。
    func testInstanceMirrorReadsTheSameValues() {
        let metrics = AirDropGlyphMetrics()
        XCTAssertEqual(metrics.dotRadiusFactor, AirDropGlyphMetrics.dotRadiusFactor, "点半径：实例读法 = 静态读法")
        XCTAssertEqual(metrics.ringRadiusFactors, AirDropGlyphMetrics.ringRadiusFactors, "环心半径：实例读法 = 静态读法")
        XCTAssertEqual(metrics.strokeFactor, AirDropGlyphMetrics.strokeFactor, "线宽：实例读法 = 静态读法")
        XCTAssertEqual(metrics.gapDegrees, AirDropGlyphMetrics.gapDegrees, "开口角度：实例读法 = 静态读法")
    }
}

// MARK: - 快速新增的口径纯函数（P11 / T5，docs/36 §做法 机制三）

/// `CalendarQuickAdd` 六条纯函数——两处日历「+」内联表单的输入口径
/// （D-11 宽松时间解析、D-08 默认时段与全天口径、起止同自然日校验）。
///
/// **时区前提**：夹具一律用固定 `Asia/Shanghai` 的格里高利历构造时刻（不读本机时区），
/// 期望值是同一份日历下的 `Date`——这些函数只按传入的 `calendar` 算账，固定日历只为让断言可复现。
///
/// **不碰真 EventKit**：本类全部是纯函数断言，没有 TCC 依赖；服务层的真实写入
/// （`CalendarService.createReminder` / `createEvent` 落库）不在这里验证——单测环境没有可控的
/// 授权与干净日历库，归 T8 上屏真写 + 系统 App 侧复核（docs/36 §验收标准 2）。
final class CalendarQuickAddTests: XCTestCase {

    /// 固定日历：格里高利 + `Asia/Shanghai` + `en_US_POSIX`（构造口径同同文件其他日历用例，
    /// 例 `CalendarEventCardListOrderTests.cardCalendar`，只是时区固定为用户所在时区而非 GMT）。
    private func quickAddCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// 2026-10 里某天某时刻（构造口径同同文件既有的 `gridTime` / `cardTime`）。
    private func quickAddMoment(
        _ calendar: Calendar,
        day: Int,
        hour: Int,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second)
        )!
    }

    // MARK: parseTime（宽松解析，D-11）

    /// **收**：`15:30` / `1530` / `930` / `9` / `9:5` / `" 15:30 "` / `15:30:45`（秒归零）/
    /// `0:00` / `23:59` 全部解析成**选中日当天**该时分、秒 = 0、不滚动到别的日期。
    func testParseTimeAcceptsLenientFormatsWithSecondsZeroed() {
        let calendar = quickAddCalendar()
        let day = quickAddMoment(calendar, day: 10, hour: 0)

        let accepted: [(text: String, hour: Int, minute: Int)] = [
            ("15:30", 15, 30),
            ("1530", 15, 30),
            ("930", 9, 30),
            ("9", 9, 0),
            ("9:5", 9, 5),
            (" 15:30 ", 15, 30),
            ("15:30:45", 15, 30),
            ("0:00", 0, 0),
            ("23:59", 23, 59)
        ]

        for item in accepted {
            let parsed = CalendarQuickAdd.parseTime(item.text, on: day, calendar: calendar)
            XCTAssertNotNil(parsed, "「\(item.text)」应可解析")
            XCTAssertEqual(
                parsed,
                quickAddMoment(calendar, day: 10, hour: item.hour, minute: item.minute),
                "「\(item.text)」应落到选中日的 \(item.hour):\(item.minute)（秒归零）"
            )
            if let parsed {
                XCTAssertEqual(calendar.component(.second, from: parsed), 0, "「\(item.text)」的秒归零")
                XCTAssertEqual(calendar.component(.day, from: parsed), 10, "「\(item.text)」落在选中日当天")
            }
        }
    }

    /// **拒**：越界（时 / 分 / 秒）与非数字字符一律 nil——`24:00` / `15:60` / `-1:00` / `15:3a` /
    /// `abc` / 空串 / 5 位纯数字 `15300`；外加三条**同规则派生**的边界：`"   "`（trim 后为空）、
    /// `25`（两位纯数字 → 时 25 越界）、`2400`（时 24 越界）、`15:30:99`（秒越界）。
    func testParseTimeRejectsOutOfRangeAndNonNumericInputs() {
        let calendar = quickAddCalendar()
        let day = quickAddMoment(calendar, day: 10, hour: 0)

        let rejected = ["24:00", "15:60", "-1:00", "15:3a", "abc", "", "15300", "   ", "25", "2400", "15:30:99"]

        for text in rejected {
            XCTAssertNil(
                CalendarQuickAdd.parseTime(text, on: day, calendar: calendar),
                "「\(text.debugDescription)」应被拒（nil）"
            )
        }
    }

    /// 解析的落点跟着传入的 `day` 走：同一条 `"15:30"` 在 10 日 / 12 日上各落各的。
    func testParseTimeLandsOnThePassedDay() {
        let calendar = quickAddCalendar()
        XCTAssertEqual(
            CalendarQuickAdd.parseTime("15:30", on: quickAddMoment(calendar, day: 12, hour: 0), calendar: calendar),
            quickAddMoment(calendar, day: 12, hour: 15, minute: 30)
        )
    }

    // MARK: defaultStart / defaultEnd（默认时段，D-08）

    /// 今天取**下一个整点**：14:20 → 15:00；22:59 → 23:00（23 点前最后一档）。
    func testDefaultStartPicksNextWholeHourOnToday() {
        let calendar = quickAddCalendar()
        let day = quickAddMoment(calendar, day: 10, hour: 0)

        XCTAssertEqual(
            CalendarQuickAdd.defaultStart(
                on: day,
                now: quickAddMoment(calendar, day: 10, hour: 14, minute: 20),
                calendar: calendar
            ),
            quickAddMoment(calendar, day: 10, hour: 15)
        )
        XCTAssertEqual(
            CalendarQuickAdd.defaultStart(
                on: day,
                now: quickAddMoment(calendar, day: 10, hour: 22, minute: 59),
                calendar: calendar
            ),
            quickAddMoment(calendar, day: 10, hour: 23)
        )
    }

    /// 恰在整点 → **取当前这个整点**（09:00:00 → 09:00；14:00:00 → 14:00），不跳下一个。
    func testDefaultStartKeepsCurrentHourWhenNowIsExactlyOnTheHour() {
        let calendar = quickAddCalendar()
        let day = quickAddMoment(calendar, day: 10, hour: 0)

        XCTAssertEqual(
            CalendarQuickAdd.defaultStart(
                on: day,
                now: quickAddMoment(calendar, day: 10, hour: 9),
                calendar: calendar
            ),
            quickAddMoment(calendar, day: 10, hour: 9)
        )
        XCTAssertEqual(
            CalendarQuickAdd.defaultStart(
                on: day,
                now: quickAddMoment(calendar, day: 10, hour: 14),
                calendar: calendar
            ),
            quickAddMoment(calendar, day: 10, hour: 14)
        )
    }

    /// 今天 23 点起（23:00 整 / 23:10）回退**当天 09:00**（不跳次日——日期一律 = 选中日）。
    func testDefaultStartFallsBackToNineOnTheSelectedDayWhenLate() {
        let calendar = quickAddCalendar()
        let day = quickAddMoment(calendar, day: 10, hour: 0)

        XCTAssertEqual(
            CalendarQuickAdd.defaultStart(
                on: day,
                now: quickAddMoment(calendar, day: 10, hour: 23, minute: 0),
                calendar: calendar
            ),
            quickAddMoment(calendar, day: 10, hour: 9)
        )
        XCTAssertEqual(
            CalendarQuickAdd.defaultStart(
                on: day,
                now: quickAddMoment(calendar, day: 10, hour: 23, minute: 10),
                calendar: calendar
            ),
            quickAddMoment(calendar, day: 10, hour: 9)
        )
    }

    /// 选中日**不是今天** → 选中日 09:00（今天几点都不看，含今天 23:30）。
    func testDefaultStartUsesNineOnDaysThatAreNotToday() {
        let calendar = quickAddCalendar()
        let tomorrow = quickAddMoment(calendar, day: 11, hour: 0)

        XCTAssertEqual(
            CalendarQuickAdd.defaultStart(
                on: tomorrow,
                now: quickAddMoment(calendar, day: 10, hour: 14, minute: 20),
                calendar: calendar
            ),
            quickAddMoment(calendar, day: 11, hour: 9)
        )
        XCTAssertEqual(
            CalendarQuickAdd.defaultStart(
                on: tomorrow,
                now: quickAddMoment(calendar, day: 10, hour: 23, minute: 30),
                calendar: calendar
            ),
            quickAddMoment(calendar, day: 11, hour: 9)
        )
    }

    /// `defaultEnd` = 开始 + 1 小时（09:00–10:00 默认档的另一半）。
    func testDefaultEndAddsOneHour() {
        let calendar = quickAddCalendar()
        let start = quickAddMoment(calendar, day: 10, hour: 15)

        XCTAssertEqual(CalendarQuickAdd.defaultEnd(start: start), quickAddMoment(calendar, day: 10, hour: 16))
        XCTAssertEqual(CalendarQuickAdd.defaultEnd(start: start), start.addingTimeInterval(3600))
    }

    // MARK: isValidRange / allDayRange / reminderDueComponents

    /// `isValidRange`：`end > start` 且**同一自然日**；相等 / 倒挂 / 跨日（23:00 → 次日 00:30）都拒。
    func testIsValidRangeRequiresEndAfterStartOnTheSameDay() {
        let calendar = quickAddCalendar()

        XCTAssertTrue(
            CalendarQuickAdd.isValidRange(
                start: quickAddMoment(calendar, day: 10, hour: 15),
                end: quickAddMoment(calendar, day: 10, hour: 16),
                calendar: calendar
            ),
            "15:00 → 16:00 正常"
        )
        XCTAssertFalse(
            CalendarQuickAdd.isValidRange(
                start: quickAddMoment(calendar, day: 10, hour: 15),
                end: quickAddMoment(calendar, day: 10, hour: 15),
                calendar: calendar
            ),
            "相等拒"
        )
        XCTAssertFalse(
            CalendarQuickAdd.isValidRange(
                start: quickAddMoment(calendar, day: 10, hour: 16),
                end: quickAddMoment(calendar, day: 10, hour: 15),
                calendar: calendar
            ),
            "倒挂拒"
        )
        XCTAssertFalse(
            CalendarQuickAdd.isValidRange(
                start: quickAddMoment(calendar, day: 10, hour: 23),
                end: quickAddMoment(calendar, day: 11, hour: 0, minute: 30),
                calendar: calendar
            ),
            "跨日拒"
        )
    }

    /// `allDayRange`：选中日当天 00:00 → **次日 00:00**（与选中日上是几点无关）。
    func testAllDayRangeSpansSelectedDayToNextMidnight() {
        let calendar = quickAddCalendar()
        let range = CalendarQuickAdd.allDayRange(
            on: quickAddMoment(calendar, day: 10, hour: 13, minute: 37),
            calendar: calendar
        )

        XCTAssertEqual(range.start, quickAddMoment(calendar, day: 10, hour: 0))
        XCTAssertEqual(range.end, quickAddMoment(calendar, day: 11, hour: 0))
    }

    /// `reminderDueComponents`：只带 `[.year, .month, .day]` 三个 key——选中日上的**任意时刻**
    /// （这里 00:00 与 15:30 两档）都归一化成同一个组件；未请求的 hour / minute / second / timeZone
    /// 全为 nil（`EventModel.init?(from: EKReminder)` 用 `dueDateComponents.hour == nil` 判全天待办）。
    func testReminderDueComponentsCarryOnlyYearMonthDay() {
        let calendar = quickAddCalendar()
        let components = CalendarQuickAdd.reminderDueComponents(
            on: quickAddMoment(calendar, day: 10, hour: 15, minute: 30),
            calendar: calendar
        )

        XCTAssertEqual(
            components,
            DateComponents(year: 2026, month: 10, day: 10),
            "逐字段等于只带年月日的组件（多余字段全为 nil）"
        )
        XCTAssertNil(components.hour)
        XCTAssertNil(components.minute)
        XCTAssertNil(components.second)
        XCTAssertNil(components.timeZone)
        XCTAssertEqual(
            CalendarQuickAdd.reminderDueComponents(
                on: quickAddMoment(calendar, day: 10, hour: 0),
                calendar: calendar
            ),
            components,
            "选中日的任意时刻都归一化到同一个组件"
        )
    }
}


// MARK: - 日历安全写入与独立今日快照（docs/39 / T1）

@MainActor
final class CalendarInteractionTests: XCTestCase {
    func testLifecycleSingleOwnerLocalDepartureReturnsToListAndKeepsResumableDraft() {
        for presentation in 0..<4 {
            let session = panelSession(service: panelBackend())
            session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
            session.draft?.title = "Local retained draft"
            let original = session.draft
            let lifecycle = CalendarEditorLifecycle(session: session)
            if presentation == 0 { lifecycle.setEditorFocus(true) }
            if presentation == 1 { lifecycle.setOwnedMenuCount(1) }
            if presentation == 2 { lifecycle.setDatePopoverPresented(true) }
            lifecycle.departLocally()
            XCTAssertEqual(session.route, .list)
            XCTAssertEqual(session.draft, original)
            XCTAssertFalse(session.shouldProtectAutoClose)
            lifecycle.stop()
            lifecycle.stop()
            session.resumeDraft()
            XCTAssertEqual(session.route, .editor)
            XCTAssertEqual(session.draft, original)
            lifecycle.stop()
            XCTAssertEqual(session.route, .editor, "已停止的旧页面不能再暂停新恢复的编辑页")
        }
    }

    func testLifecycleLocalDepartureRespectsEveryOtherOwnerPresentation() {
        for presentation in 0..<3 {
            let session = panelSession(service: panelBackend())
            session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
            session.draft?.title = "Other window remains active"
            let lifecycleA = CalendarEditorLifecycle(session: session)
            let lifecycleB = CalendarEditorLifecycle(session: session)
            lifecycleA.setEditorFocus(true)
            if presentation == 0 { lifecycleB.setEditorFocus(true) }
            if presentation == 1 { lifecycleB.setOwnedMenuCount(1) }
            if presentation == 2 { lifecycleB.setDatePopoverPresented(true) }
            lifecycleA.departLocally()
            lifecycleA.stop()
            lifecycleA.stop()
            XCTAssertEqual(session.route, .editor)
            XCTAssertEqual(session.editorHasFocus, presentation == 0)
            XCTAssertEqual(session.ownedMenuCount, presentation == 1 ? 1 : 0)
            XCTAssertEqual(session.datePopoverPresented, presentation == 2)
            XCTAssertTrue(session.shouldProtectAutoClose)
            lifecycleB.stop()
            XCTAssertEqual(session.route, .list)
            XCTAssertEqual(session.draft?.title, "Other window remains active")
        }
    }

    func testLifecycleLocalDepartureDuringSubmissionRetainsSameWriteAndRepeatedStopIsIdempotent() async {
        let backend = panelBackend()
        let started = expectation(description: "local departure save started")
        var gate: CheckedContinuation<Void, Never>?
        let session = panelSession(service: backend, save: { input, id in
            await withCheckedContinuation { gate = $0; started.fulfill() }
            return try await backend.saveEvent(input: input, eventID: id)
        })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Keep writing across local departure"
        let lifecycle = CalendarEditorLifecycle(session: session)
        lifecycle.setEditorFocus(true)
        let saving = Task { await session.save() }
        await fulfillment(of: [started], timeout: 2)
        lifecycle.departLocally()
        lifecycle.stop()
        lifecycle.stop()
        XCTAssertEqual(session.route, .list)
        XCTAssertTrue(session.isSubmitting)
        XCTAssertEqual(session.draft?.title, "Keep writing across local departure")
        gate?.resume()
        let saved = await saving.value
        XCTAssertTrue(saved)
        XCTAssertFalse(session.isSubmitting)
        XCTAssertEqual(backend.writeAttempts, 1)
        XCTAssertEqual(session.route, .list)
    }

    private func lifecycleWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    func testLifecycleCalendarWindowTransferBeforeDestinationFocusDoesNotSuspendSharedEditor() {
        let session = panelSession(service: panelBackend())
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Transfer before native click dispatch"
        let windowA = lifecycleWindow(), windowB = lifecycleWindow()
        let lifecycleA = CalendarEditorLifecycle(session: session)
        let lifecycleB = CalendarEditorLifecycle(session: session)
        lifecycleA.attach(to: windowA)
        lifecycleB.attach(to: windowB)
        defer { lifecycleA.stop(); lifecycleB.stop(); windowA.close(); windowB.close() }
        lifecycleA.setEditorFocus(true)
        XCTAssertEqual(lifecycleA.windowContext(for: windowB), .otherCalendar)
        lifecycleA.handleLocalClick(in: windowB)
        XCTAssertFalse(session.editorHasFocus, "目的窗口尚未发布焦点，不能伪造其 ownership")
        XCTAssertEqual(session.route, .editor)
        lifecycleA.departLocally()
        lifecycleA.stop()
        lifecycleA.stop()
        XCTAssertEqual(session.route, .editor)
        lifecycleB.setEditorFocus(true)
        XCTAssertTrue(session.editorHasFocus)
        XCTAssertEqual(session.draft?.title, "Transfer before native click dispatch")
    }

    func testLifecycleCalendarWindowAndChildKeyTransferPreservesOtherOwnerAndRestoresFocus() {
        for presentation in 0..<3 {
            let session = panelSession(service: panelBackend())
            session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
            session.draft?.title = "Calendar-to-calendar transfer"
            let windowA = lifecycleWindow(), windowB = lifecycleWindow(), child = lifecycleWindow()
            windowB.addChildWindow(child, ordered: .above)
            let lifecycleA = CalendarEditorLifecycle(session: session)
            let lifecycleB = CalendarEditorLifecycle(session: session)
            lifecycleA.attach(to: windowA)
            lifecycleB.attach(to: windowB)
            lifecycleA.setEditorFocus(true)
            if presentation == 0 { lifecycleB.setEditorFocus(true) }
            if presentation == 1 { lifecycleB.setOwnedMenuCount(1) }
            if presentation == 2 { lifecycleB.setDatePopoverPresented(true) }
            XCTAssertEqual(lifecycleA.windowContext(for: child), .otherCalendar)
            lifecycleA.handleLocalClick(in: child)
            lifecycleA.handleKeyLoss(to: child)
            XCTAssertEqual(session.route, .editor)
            XCTAssertEqual(session.editorHasFocus, presentation == 0)
            XCTAssertEqual(session.ownedMenuCount, presentation == 1 ? 1 : 0)
            XCTAssertEqual(session.datePopoverPresented, presentation == 2)
            lifecycleA.restoreTransferredFocus()
            XCTAssertTrue(session.editorHasFocus)
            XCTAssertEqual(session.route, .editor)
            lifecycleA.stop()
            XCTAssertEqual(session.route, .editor)
            lifecycleB.stop()
            XCTAssertEqual(session.route, .list)
            XCTAssertEqual(lifecycleA.windowContext(for: windowB), .external, "停止后移除弱窗口注册")
            windowB.removeChildWindow(child)
            child.close(); windowA.close(); windowB.close()
        }
    }

    func testLifecycleUnparentedOwnedPresentationUsesAggregateBeforeRealExternalDeparture() {
        let session = panelSession(service: panelBackend())
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Owned native presentation"
        let lifecycleA = CalendarEditorLifecycle(session: session)
        let lifecycleB = CalendarEditorLifecycle(session: session)
        let unrelated = lifecycleWindow()
        defer { lifecycleA.stop(); lifecycleB.stop(); unrelated.close() }
        lifecycleA.setEditorFocus(true)
        lifecycleB.setOwnedMenuCount(1)
        XCTAssertEqual(lifecycleA.windowContext(for: unrelated), .ownedPresentation)
        lifecycleA.handleKeyLoss(to: unrelated)
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.ownedMenuCount, 1)
        lifecycleB.setOwnedMenuCount(0)
        lifecycleB.setDatePopoverPresented(true)
        lifecycleA.handleKeyLoss(to: unrelated)
        XCTAssertEqual(session.route, .editor)
        XCTAssertTrue(session.datePopoverPresented)
        lifecycleB.setDatePopoverPresented(false)
        XCTAssertEqual(lifecycleA.windowContext(for: unrelated), .external)
        lifecycleA.handleLocalClick(in: unrelated)
        XCTAssertEqual(session.route, .list)
        XCTAssertFalse(session.shouldProtectAutoClose)
        XCTAssertEqual(session.draft?.title, "Owned native presentation")
        session.resumeDraft()
        lifecycleB.setDatePopoverPresented(true)
        lifecycleA.suspendForExternalDeparture()
        XCTAssertEqual(session.route, .list, "真正外部应用不受所属弹层聚合状态阻挡")
        XCTAssertFalse(session.datePopoverPresented)
    }

    func testShortcutDeadlineIsCancelledWhenEnteringEditorEvenAfterReturningToList() async {
        let session = panelSession(service: panelBackend())
        let closed = expectation(description: "old editor deadline must not close")
        closed.isInverted = true
        var pending: DispatchWorkItem?
        var cancellationCalls = 0
        let protection = CalendarShortcutCloseProtection(session: session) {
            cancellationCalls += 1
            pending?.cancel()
            pending = nil
        }
        let item = DispatchWorkItem { closed.fulfill() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.suspend()
        XCTAssertEqual(session.route, .list)
        XCTAssertEqual(cancellationCalls, 1)
        XCTAssertTrue(item.isCancelled)
        XCTAssertNil(pending)
        await fulfillment(of: [closed], timeout: 0.12)
        withExtendedLifetime(protection) {}
    }

    func testShortcutDeadlineIsCancelledWhenSubmissionStartsEvenAfterItFinishes() async throws {
        let backend = panelBackend()
        let session = panelSession(service: backend)
        let closed = expectation(description: "old submission deadline must not close")
        closed.isInverted = true
        var pending: DispatchWorkItem?
        var cancellationCalls = 0
        let protection = CalendarShortcutCloseProtection(session: session) {
            cancellationCalls += 1
            pending?.cancel()
            pending = nil
        }
        let item = DispatchWorkItem { closed.fulfill() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
        let reminder = try XCTUnwrap(backend.event(withID: "fixture-reminder-02"))
        let completed = await session.complete(reminder, completed: true)
        XCTAssertTrue(completed)
        XCTAssertFalse(session.isSubmitting)
        XCTAssertEqual(session.route, .list)
        XCTAssertEqual(cancellationCalls, 1)
        XCTAssertTrue(item.isCancelled)
        XCTAssertNil(pending)
        await fulfillment(of: [closed], timeout: 0.12)
        withExtendedLifetime(protection) {}
    }

    /// **2026-10-16 口径反转**（用户：编辑 / 新增场景阻止灵动岛自动收起）：过去是「只有输入焦点 /
    /// 菜单 / 日期弹层才保护，光在看或光有草稿不保护」；现在**整个编辑档都保护**，释放只发生在
    /// 离开编辑档（保存 / 取消 / 挂起 / 收面板）那一刻。
    func testLifecycleEditorSessionProtectsAutoCloseUntilTheEditorCloses() {
        let session = panelSession(service: panelBackend())
        var protected = false
        var hoverChecks = 0
        let lifecycle = CalendarEditorLifecycle(session: session, setProtection: { active, _ in protected = active },
                                                recheckHover: { hoverChecks += 1 })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Retained input"
        lifecycle.setEditorFocus(false)
        XCTAssertTrue(session.hasDirtyDraft)
        XCTAssertTrue(protected, "编辑档一开出来就保护——不看焦点、也不看有没有改过")
        lifecycle.setEditorFocus(true)
        XCTAssertTrue(protected)
        lifecycle.setEditorFocus(false)
        XCTAssertTrue(protected, "焦点走掉仍保护（旧口径在这里会释放）")
        XCTAssertEqual(hoverChecks, 0, "保护没撤，就不该复查 hover")
        // 离开编辑档才释放：`suspend()`（保存 / 取消 / 切页 / 收面板都经它或 route 变化）。
        // 真实链路里，页面在 `.onChange(of: session.route)` 里调 `clearLocalInput()`——用例照它走
        // （`connect(to:)` 才装发布订阅，而那个入口会把 `setProtection` 换成 vm 的那份）。
        session.suspend()
        lifecycle.clearLocalInput()
        XCTAssertFalse(protected)
        XCTAssertEqual(hoverChecks, 1, "释放保护后复查 hover")
        XCTAssertEqual(session.draft?.title, "Retained input", "挂起保留草稿")
        lifecycle.stop()
    }

    /// 保护窗口的**变更后信号**：`@Published` 是 willSet 发的，宿主若拿它重算会读到旧 route；
    /// 会话因此在 route / isSubmitting 变完之后补发一次 `autoCloseProtectionRevision`。
    func testProtectionRevisionFiresAfterRouteAndSubmissionChanges() {
        let session = panelSession(service: panelBackend())
        var revisions: [Int] = []
        let subscription = session.$autoCloseProtectionRevision.sink { revisions.append($0) }
        defer { subscription.cancel() }
        XCTAssertEqual(revisions, [0], "订阅时先来一条当前值")

        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        XCTAssertEqual(revisions.count, 2, "进编辑档：改完之后发一条")
        XCTAssertEqual(session.route, .editor, "发的时候 route 已经是新值（这是这条信号存在的理由）")
        session.suspend()
        XCTAssertEqual(revisions.count, 3, "离开编辑档：再发一条")
        XCTAssertEqual(session.route, .list)
    }

    func testLifecycleLocalTeardownKeepsOtherOwnerAndUnrelatedTokens() {
        let session = panelSession(service: panelBackend())
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Two windows"
        let unrelated = UUID()
        var protection: Set<UUID> = [unrelated]
        var scrolling: Set<UUID> = [unrelated]
        let lifecycleA = CalendarEditorLifecycle(session: session, setProtection: { active, token in
            if active { protection.insert(token) } else { protection.remove(token) }
        }, setScroll: { active, token in
            if active { scrolling.insert(token) } else { scrolling.remove(token) }
        })
        let lifecycleB = CalendarEditorLifecycle(session: session)
        lifecycleA.setEditorFocus(true)
        lifecycleA.setScrolling(true)
        lifecycleB.setEditorFocus(true)
        lifecycleB.setOwnedMenuCount(1)
        lifecycleB.setDatePopoverPresented(true)
        XCTAssertEqual(protection.count, 2)
        XCTAssertEqual(scrolling.count, 2)
        lifecycleA.stop()
        lifecycleA.stop()
        XCTAssertEqual(protection, [unrelated])
        XCTAssertEqual(scrolling, [unrelated])
        XCTAssertTrue(session.editorHasFocus)
        XCTAssertEqual(session.ownedMenuCount, 1)
        XCTAssertTrue(session.datePopoverPresented)
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draft?.title, "Two windows")
        lifecycleB.stop()
        XCTAssertFalse(session.shouldProtectAutoClose)
    }

    func testLifecycleExternalDepartureSuspendsAllOwnersAndReleasesOwnTokens() {
        let session = panelSession(service: panelBackend())
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Keep on departure"
        let original = session.draft
        var protected = false
        var scrolling = false
        let lifecycle = CalendarEditorLifecycle(session: session, setProtection: { active, _ in protected = active },
                                                setScroll: { active, _ in scrolling = active })
        lifecycle.setEditorFocus(true)
        lifecycle.setScrolling(true)
        session.setEditorFocus(true, ownerID: UUID())
        lifecycle.suspendForExternalDeparture()
        XCTAssertEqual(session.route, .list)
        XCTAssertFalse(session.editorHasFocus)
        XCTAssertFalse(protected)
        XCTAssertFalse(scrolling)
        XCTAssertEqual(session.draft, original)
        session.resumeDraft()
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draft, original)
        lifecycle.stop()
    }

    func testLifecycleLockSuspendsBeforeClosingEveryPanelAndPreservesDraft() {
        let session = panelSession(service: panelBackend())
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Locked draft"
        session.setEditorFocus(true, ownerID: UUID())
        var closedPanels: [Int] = []
        CalendarEditorLifecycle.closeForLock(session: session, closePanels: (0..<3).map { panel in
            {
                XCTAssertEqual(session.route, .list)
                XCTAssertFalse(session.editorHasFocus)
                closedPanels.append(panel)
            }
        })
        XCTAssertEqual(closedPanels, [0, 1, 2])
        XCTAssertEqual(session.draft?.title, "Locked draft")
    }

    func testTerminationControllerSerializesSavePromptAndRestartAfterSuccess() async {
        let backend = panelBackend()
        let started = expectation(description: "save started")
        var gate: CheckedContinuation<Void, Never>?
        let session = panelSession(service: backend, save: { input, id in
            await withCheckedContinuation { gate = $0; started.fulfill() }
            return try await backend.saveEvent(input: input, eventID: id)
        })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Quit once"
        let controller = CalendarTerminationController()
        var prompts = 0
        var restarts = 0
        controller.requestRestart()
        let first = Task { await controller.resolve(session: session, choose: { prompts += 1; return .save }, restart: {
            XCTAssertFalse(session.hasDirtyDraft)
            XCTAssertEqual(backend.writeAttempts, 1)
            restarts += 1
        }) }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { await controller.resolve(session: session, choose: { prompts += 1; return .discard }, restart: { restarts += 1 }) }
        await Task.yield()
        XCTAssertEqual(restarts, 0, "裁决通过前不能启动第二实例")
        gate?.resume()
        let firstAllowed = await first.value
        let secondAllowed = await second.value
        XCTAssertTrue(firstAllowed)
        XCTAssertTrue(secondAllowed)
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(backend.writeAttempts, 1)
        XCTAssertEqual(restarts, 1)
        XCTAssertFalse(controller.restartPending)
    }

    func testTerminationControllerCancellationAndSaveFailureClearPendingRestart() async {
        for failSave in [false, true] {
            let backend = panelBackend()
            let session = panelSession(service: backend)
            session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
            session.draft?.title = "Keep after refused quit"
            if failSave { backend.writeFailure = .readOnlyCalendar }
            let controller = CalendarTerminationController()
            var restarts = 0
            controller.requestRestart()
            let allowed = await controller.resolve(session: session, choose: { failSave ? .save : .cancel }, restart: { restarts += 1 })
            XCTAssertFalse(allowed)
            XCTAssertFalse(controller.restartPending)
            XCTAssertEqual(restarts, 0)
            XCTAssertEqual(session.draft?.title, "Keep after refused quit")
            XCTAssertEqual(backend.writeAttempts, failSave ? 1 : 0)
        }
    }

    func testTerminationControllerWaitsForExistingOperationThenRechecksDraft() async throws {
        let backend = panelBackend()
        let started = expectation(description: "completion started")
        var gate: CheckedContinuation<Void, Never>?
        let session = panelSession(service: backend, complete: { id, completed in
            await withCheckedContinuation { gate = $0; started.fulfill() }
            return try await backend.completeReminder(id: id, completed: completed)
        })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Still unsaved"
        let reminder = try XCTUnwrap(backend.event(withID: "fixture-reminder-02"))
        let completing = Task { await session.complete(reminder, completed: true) }
        await fulfillment(of: [started], timeout: 2)
        var prompts = 0
        let controller = CalendarTerminationController()
        let quitting = Task { await controller.resolve(session: session, choose: {
            XCTAssertFalse(session.isSubmitting)
            XCTAssertTrue(session.hasDirtyDraft)
            prompts += 1
            return .cancel
        }) }
        await Task.yield()
        XCTAssertEqual(prompts, 0)
        gate?.resume()
        let completed = await completing.value
        let allowed = await quitting.value
        XCTAssertTrue(completed)
        XCTAssertFalse(allowed)
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(backend.writeAttempts, 1, "退出只等待已有操作，不重复完成或保存")
        XCTAssertEqual(session.draft?.title, "Still unsaved")
    }

    func testTerminationControllerFailedExistingSubmissionRefusesQuitWithoutPromptOrRestart() async {
        let backend = panelBackend()
        let started = expectation(description: "failing save started")
        var gate: CheckedContinuation<Void, Never>?
        let session = panelSession(service: backend, save: { input, id in
            await withCheckedContinuation { gate = $0; started.fulfill() }
            return try await backend.saveEvent(input: input, eventID: id)
        })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Pending failed save"
        let saving = Task { await session.save() }
        await fulfillment(of: [started], timeout: 2)
        let controller = CalendarTerminationController()
        controller.requestRestart()
        var prompts = 0
        var restarts = 0
        let quitting = Task { await controller.resolve(session: session, choose: { prompts += 1; return .save }, restart: { restarts += 1 }) }
        await Task.yield()
        backend.writeFailure = .readOnlyCalendar
        gate?.resume()
        let saved = await saving.value
        let allowed = await quitting.value
        XCTAssertFalse(saved)
        XCTAssertFalse(allowed)
        XCTAssertEqual(prompts, 0)
        XCTAssertEqual(restarts, 0)
        XCTAssertFalse(controller.restartPending)
        XCTAssertEqual(backend.writeAttempts, 1)
        XCTAssertNotNil(session.draft)
    }

    #if DEBUG
    func testFixtureReadinessNeedsBothBootstrapAndRealWindowsAndPublishesOnlyAfterOpen() {
        for windowsFirst in [false, true] {
            let readiness = CalendarFixtureReadiness()
            XCTAssertFalse(readiness.beginOpening())
            if windowsFirst { readiness.didCreateWindows() } else { readiness.didBootstrap() }
            XCTAssertFalse(readiness.beginOpening())
            if windowsFirst { readiness.didBootstrap() } else { readiness.didCreateWindows() }
            XCTAssertTrue(readiness.beginOpening())
            XCTAssertFalse(readiness.ready)
            XCTAssertFalse(readiness.beginOpening())
            readiness.didOpen()
            XCTAssertTrue(readiness.ready)
            XCTAssertFalse(readiness.beginOpening())
        }
    }
    #endif

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(day: Int, hour: Int = 0) -> Date {
        testCalendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func pageDraft(start: Date, end: Date, allDay: Bool = false) -> CalendarDraft {
        CalendarDraft(kind: .event, eventID: nil, originalDate: start, title: "Draft",
                      start: start, end: end, isAllDay: allDay, calendarID: "events")
    }

    func testCalendarPageNewEventSaveSupportsFullAndWriteOnlyAccess() {
        let draft = pageDraft(start: date(day: 11, hour: 9), end: date(day: 11, hour: 10))
        XCTAssertTrue(CalendarPanelAccess.canSave(draft: draft, authorization: .fullAccess))
        XCTAssertTrue(CalendarPanelAccess.canSave(draft: draft, authorization: .writeOnly))
    }

    func testCalendarPageExistingEventSaveRequiresReadAccess() {
        var draft = pageDraft(start: date(day: 11, hour: 9), end: date(day: 11, hour: 10))
        draft.eventID = "existing-event"
        XCTAssertTrue(CalendarPanelAccess.canSave(draft: draft, authorization: .fullAccess))
        XCTAssertFalse(CalendarPanelAccess.canSave(draft: draft, authorization: .writeOnly))
    }

    func testCalendarPageReminderSaveNeverUsesWriteOnlyAccess() {
        var draft = pageDraft(start: date(day: 11), end: date(day: 12))
        draft.kind = .reminder
        XCTAssertTrue(CalendarPanelAccess.canSave(draft: draft, authorization: .fullAccess))
        XCTAssertFalse(CalendarPanelAccess.canSave(draft: draft, authorization: .writeOnly))
        draft.eventID = "existing-reminder"
        XCTAssertFalse(CalendarPanelAccess.canSave(draft: draft, authorization: .writeOnly))
    }

    func testCalendarPageSaveRejectsMissingDraftAndUnavailableAuthorization() {
        XCTAssertFalse(CalendarPanelAccess.canSave(draft: nil, authorization: .fullAccess))
        XCTAssertFalse(CalendarPanelAccess.canSave(draft: nil, authorization: .writeOnly))
        let event = pageDraft(start: date(day: 11, hour: 9), end: date(day: 11, hour: 10))
        var reminder = event
        reminder.kind = .reminder
        for status: EKAuthorizationStatus in [.notDetermined, .denied, .restricted] {
            XCTAssertFalse(CalendarPanelAccess.canSave(draft: event, authorization: status))
            XCTAssertFalse(CalendarPanelAccess.canSave(draft: reminder, authorization: status))
        }
    }

    func testCalendarPageTimedCrossDayRangeRemainsValid() throws {
        let draft = pageDraft(start: date(day: 11, hour: 23), end: date(day: 12, hour: 2))
        let input = try draft.eventInput(calendar: testCalendar)
        XCTAssertEqual(input.start, date(day: 11, hour: 23))
        XCTAssertEqual(input.end, date(day: 12, hour: 2))
    }

    func testCalendarPageSingleDayAllDayConvertsToExclusiveEndAndBack() throws {
        let draft = pageDraft(start: date(day: 11, hour: 9), end: date(day: 11, hour: 10))
        let allDay = CalendarPanelDates.settingAllDay(true, in: draft, calendar: testCalendar)
        XCTAssertEqual(allDay.start, date(day: 11))
        XCTAssertEqual(allDay.end, date(day: 12))
        XCTAssertEqual(CalendarPanelDates.includedEnd(of: allDay, calendar: testCalendar), date(day: 11))
        XCTAssertNoThrow(try allDay.eventInput(calendar: testCalendar))
        XCTAssertEqual(CalendarPanelDates.settingAllDay(false, in: allDay, calendar: testCalendar), draft)
        XCTAssertEqual(CalendarPanelDates.settingAllDay(true, in: allDay, calendar: testCalendar), allDay)
    }

    func testCalendarPageMultiDayAllDayKeepsLastIncludedDayOnToggle() throws {
        let draft = pageDraft(start: date(day: 11, hour: 23), end: date(day: 13, hour: 2))
        let allDay = CalendarPanelDates.settingAllDay(true, in: draft, calendar: testCalendar)
        XCTAssertEqual(allDay.start, date(day: 11))
        XCTAssertEqual(allDay.end, date(day: 14))
        XCTAssertEqual(CalendarPanelDates.includedEnd(of: allDay, calendar: testCalendar), date(day: 13))
        let extended = CalendarPanelDates.settingEnd(date(day: 15), in: allDay, calendar: testCalendar)
        XCTAssertEqual(extended.end, date(day: 16))
        let timed = CalendarPanelDates.settingAllDay(false, in: extended, calendar: testCalendar)
        XCTAssertEqual(timed.start, date(day: 11, hour: 9))
        XCTAssertEqual(timed.end, date(day: 15, hour: 10))
        XCTAssertNoThrow(try timed.eventInput(calendar: testCalendar))
    }

    func testCalendarPageTimedMidnightEndDoesNotAddAnExtraAllDayDate() {
        let draft = pageDraft(start: date(day: 11, hour: 23), end: date(day: 12))
        let allDay = CalendarPanelDates.settingAllDay(true, in: draft, calendar: testCalendar)
        XCTAssertEqual(allDay.end, date(day: 12))
        XCTAssertEqual(CalendarPanelDates.includedEnd(of: allDay, calendar: testCalendar), date(day: 11))
    }

    func testCalendarPageAllDayNaturalDayConversionAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let next = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!
        let draft = pageDraft(start: first, end: next, allDay: true)
        XCTAssertEqual(next.timeIntervalSince(first), 23 * 3600)
        XCTAssertEqual(CalendarPanelDates.includedEnd(of: draft, calendar: calendar), first)
        XCTAssertEqual(CalendarPanelDates.settingEnd(first, in: draft, calendar: calendar).end, next)
        let timed = CalendarPanelDates.settingAllDay(false, in: draft, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: timed.start), 9)
        XCTAssertEqual(calendar.component(.hour, from: timed.end), 10)
        XCTAssertNoThrow(try timed.eventInput(calendar: calendar))
    }

    func testCalendarPageChangingDatePreservesTimeAndNoDueSentinelIsNotADate() {
        let changed = CalendarPanelDates.changingDay(date(day: 13), preservingTimeOf: date(day: 11, hour: 23), calendar: testCalendar)
        XCTAssertEqual(changed, date(day: 13, hour: 23))
        XCTAssertFalse(CalendarPanelDates.hasDueDate(record("no-due", start: .distantFuture, type: .reminder(completed: false))))
        XCTAssertTrue(CalendarPanelDates.hasDueDate(record("due", type: .reminder(completed: false))))
    }

    private func source(_ id: String = "events", reminder: Bool = false, writable: Bool = true) -> CalendarModel {
        CalendarModel(
            accountName: "Fixture", id: id, title: id, color: .systemBlue,
            isSubscribed: false, isReminder: reminder, allowsContentModifications: writable
        )
    }

    private func record(
        _ id: String = "event", start: Date? = nil, end: Date? = nil,
        type: EventType = .event(.unknown), writable: Bool = true,
        recurring: Bool = false, detached: Bool = false, meeting: Bool = false
    ) -> EventModel {
        EventModel(
            id: id, start: start ?? date(day: 11, hour: 9), end: end ?? date(day: 11, hour: 10),
            title: "Fixture", location: nil, notes: nil, url: nil, isAllDay: false, type: type,
            calendar: source(type.isReminder ? "reminders" : "events", reminder: type.isReminder, writable: writable),
            participants: meeting ? [Participant(name: "Attendee", status: .accepted, isOrganizer: false, isCurrentUser: false)] : [],
            timeZone: nil, hasRecurrenceRules: recurring, priority: nil, conferenceURL: nil, isDetached: detached
        )
    }

    func testRestrictedEventsNeverInvokeTheCommonStoreWriteClosure() {
        let cases: [(EventModel, CalendarMutationError)] = [
            (record(writable: false), .readOnlyCalendar),
            (record(recurring: true), .recurringEvent),
            (record(detached: true), .detachedEvent),
            (record(meeting: true), .meetingEvent),
            (record(type: .birthday), .birthdayEvent),
            (record(type: .reminder(completed: false)), .wrongRecordType)
        ]
        for (event, expected) in cases {
            var writes = 0
            XCTAssertFalse(event.canModifyInIsland)
            XCTAssertThrowsError(try CalendarMutationPolicy.performEventWrite(event: event) { writes += 1 }) {
                XCTAssertEqual($0 as? CalendarMutationError, expected)
            }
            XCTAssertEqual(writes, 0, "与真实 save/remove 相同的守卫拒绝后，写闭包调用必须为 0")
        }
        var writes = 0
        let returnedID = try? CalendarMutationPolicy.performEventWrite(event: record()) {
            writes += 1
            return "saved-id"
        }
        XCTAssertEqual(returnedID, "saved-id")
        XCTAssertEqual(writes, 1)
    }

    func testReminderWritesRequireWritableReminderType() {
        for event in [record(), record(type: .reminder(completed: false), writable: false)] {
            var writes = 0
            XCTAssertFalse(event.canCompleteReminderInIsland)
            XCTAssertThrowsError(try CalendarMutationPolicy.performReminderWrite(event: event) { writes += 1 })
            XCTAssertEqual(writes, 0)
        }
        let reminder = record(type: .reminder(completed: false))
        XCTAssertTrue(reminder.canCompleteReminderInIsland)
        XCTAssertEqual(try CalendarMutationPolicy.performReminderWrite(event: reminder) { "reminder-id" }, "reminder-id")
    }

    func testRecurringReminderCompletionAndPriorityReachTheCommonWriteClosure() throws {
        let reminder = record(type: .reminder(completed: false), recurring: true)
        XCTAssertTrue(reminder.canCompleteReminderInIsland)
        var completions = 0
        var priorities = 0
        let completedID = try CalendarAccessPolicy.performWrite(status: .fullAccess, type: .reminder, creating: false) {
            try CalendarMutationPolicy.performReminderWrite(event: reminder) {
                completions += 1
                return reminder.id
            }
        }
        let priorityWritten = try CalendarAccessPolicy.performWrite(status: .fullAccess, type: .reminder, creating: false) {
            try CalendarMutationPolicy.performReminderWrite(event: reminder) {
                priorities += 1
                return true
            }
        }
        XCTAssertEqual(completedID, reminder.id)
        XCTAssertTrue(priorityWritten)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(priorities, 1)
    }

    func testWriteOnlyAllowsNewEventsAndTargetsWhileExistingRecordWritesRequireFullAccess() throws {
        let statuses: [EKAuthorizationStatus] = [.notDetermined, .denied, .restricted, .writeOnly, .fullAccess]
        let operations: [(name: String, type: EKEntityType, creating: Bool)] = [
            ("new event", .event, true), ("edit event", .event, false), ("delete event", .event, false),
            ("new reminder", .reminder, true), ("complete reminder", .reminder, false), ("priority", .reminder, false)
        ]
        for status in statuses {
            XCTAssertEqual(CalendarAccessPolicy.canRead(status: status), status == .fullAccess)
            XCTAssertEqual(CalendarAccessPolicy.canCreate(status: status, for: .event), status == .fullAccess || status == .writeOnly)
            XCTAssertEqual(CalendarAccessPolicy.canCreate(status: status, for: .reminder), status == .fullAccess)
            for operation in operations {
                var writes = 0
                let allowed = status == .fullAccess || (status == .writeOnly && operation.type == .event && operation.creating)
                do {
                    let id = try CalendarAccessPolicy.performWrite(status: status, type: operation.type, creating: operation.creating) {
                        writes += 1
                        return "current-created-instance-id"
                    }
                    XCTAssertTrue(allowed, operation.name)
                    XCTAssertEqual(id, "current-created-instance-id")
                } catch {
                    XCTAssertFalse(allowed, operation.name)
                    XCTAssertEqual(error as? CalendarMutationError, .accessDenied)
                }
                XCTAssertEqual(writes, allowed ? 1 : 0, operation.name)
            }
        }
    }

    func testExplicitTargetsRejectInvalidReadOnlyAndWrongTypesWithoutFallback() throws {
        let calendars = [source("events"), source("read-only", writable: false), source("reminders", reminder: true)]
        for (id, error) in [("missing", CalendarMutationError.invalidCalendar),
                            ("read-only", .readOnlyCalendar), ("reminders", .wrongRecordType)] {
            XCTAssertThrowsError(try CalendarMutationPolicy.targetCalendarID(
                requestedID: id, defaultID: "events", calendars: calendars, isReminder: false
            )) { XCTAssertEqual($0 as? CalendarMutationError, error) }
        }
        for (id, error) in [("missing", CalendarMutationError.invalidCalendar), ("events", .wrongRecordType)] {
            XCTAssertThrowsError(try CalendarMutationPolicy.targetCalendarID(
                requestedID: id, defaultID: "reminders", calendars: calendars, isReminder: true
            )) { XCTAssertEqual($0 as? CalendarMutationError, error) }
        }
        XCTAssertThrowsError(try CalendarMutationPolicy.targetCalendarID(
            requestedID: "read-only-list", defaultID: "reminders",
            calendars: calendars + [source("read-only-list", reminder: true, writable: false)], isReminder: true
        )) { XCTAssertEqual($0 as? CalendarMutationError, .readOnlyCalendar) }
    }

    func testNilEditTargetKeepsOriginalAndNilCreateUsesWritableDefaultThenFallback() throws {
        let calendars = [source("first", reminder: true), source("default", reminder: true),
                         source("readonly", reminder: true, writable: false)]
        XCTAssertEqual(try CalendarMutationPolicy.targetCalendarID(
            requestedID: nil, originalID: "first", defaultID: "default", calendars: calendars, isReminder: true
        ), "first")
        XCTAssertEqual(try CalendarMutationPolicy.targetCalendarID(
            requestedID: nil, defaultID: "default", calendars: calendars, isReminder: true
        ), "default")
        XCTAssertEqual(try CalendarMutationPolicy.targetCalendarID(
            requestedID: nil, defaultID: "readonly", calendars: calendars, isReminder: true
        ), "first")
        XCTAssertThrowsError(try CalendarMutationPolicy.targetCalendarID(
            requestedID: nil, defaultID: nil, calendars: [], isReminder: true
        )) { XCTAssertEqual($0 as? CalendarMutationError, .noWritableCalendar) }
    }

    func testCrossDayInputIsValidAndEmptyTitleOrInvertedRangeIsRejected() throws {
        var input = CalendarEventInput(title: "  Overnight  ", start: date(day: 11, hour: 23), end: date(day: 12, hour: 1), isAllDay: false)
        XCTAssertEqual(try input.validated(calendar: testCalendar).title, "Overnight")
        input.end = input.start
        XCTAssertThrowsError(try input.validated(calendar: testCalendar)) {
            XCTAssertEqual($0 as? CalendarMutationError, .invalidDateRange)
        }
        input.end = date(day: 12)
        input.title = "  \n "
        XCTAssertThrowsError(try input.validated(calendar: testCalendar)) {
            XCTAssertEqual($0 as? CalendarMutationError, .invalidTitle)
        }
    }

    func testAllDayExclusiveEndUsesNaturalDaysAcrossDSTAndMultiDayRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for (month, day, expectedHours) in [(3, 8, 23.0), (11, 1, 25.0)] {
            let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
            let end = try XCTUnwrap(CalendarEventInput.exclusiveAllDayEnd(including: start, calendar: calendar))
            XCTAssertEqual(end.timeIntervalSince(start), expectedHours * 3600)
            XCTAssertEqual(CalendarEventInput.includedAllDayEnd(exclusiveEnd: end, calendar: calendar), start)
            XCTAssertNoThrow(try CalendarEventInput(title: "All day", start: start, end: end, isAllDay: true).validated(calendar: calendar))
        }
        let lastDay = date(day: 14, hour: 12)
        let exclusiveEnd = try XCTUnwrap(CalendarEventInput.exclusiveAllDayEnd(including: lastDay, calendar: testCalendar))
        XCTAssertEqual(exclusiveEnd, date(day: 15))
        XCTAssertEqual(CalendarEventInput.includedAllDayEnd(exclusiveEnd: exclusiveEnd, calendar: testCalendar), date(day: 14))
        XCTAssertNoThrow(try CalendarEventInput(title: "Trip", start: date(day: 11), end: exclusiveEnd, isAllDay: true).validated(calendar: testCalendar))
        XCTAssertThrowsError(try CalendarEventInput(title: "Bad", start: date(day: 11, hour: 1), end: exclusiveEnd, isAllDay: true).validated(calendar: testCalendar))
    }

    func testTodaySnapshotIsIndependentIncludesOverlappingEventsAndExcludesReminders() async {
        let service = CalendarInteractionServiceFake()
        let manager = CalendarManager(service: service, now: { self.date(day: 11, hour: 12) }, calendar: testCalendar, startMonitoring: false)
        let today = record("today")
        let overnight = record("overnight", start: date(day: 10, hour: 23), end: date(day: 11, hour: 1))
        let midnightEnd = record("ended", start: date(day: 10), end: date(day: 11))
        let tomorrow = record("tomorrow", start: date(day: 12), end: date(day: 12, hour: 1))
        let reminder = record("reminder", type: .reminder(completed: false))
        let unrelated = record("selected", start: date(day: 14, hour: 10), end: date(day: 14, hour: 11))
        service.fetch = { start, _, _ in start == self.date(day: 11) ? [today, overnight, midnightEnd, tomorrow, reminder] : [unrelated] }
        await manager.updateTodayEvents(force: true)
        XCTAssertEqual(manager.todayEvents.map(\.id), ["today", "overnight"])
        await manager.updateCurrentDate(date(day: 14))
        XCTAssertEqual(manager.events.map(\.id), ["selected"])
        XCTAssertEqual(manager.todayEvents.map(\.id), ["today", "overnight"])
        XCTAssertEqual(service.accessRequests, 0)
    }

    func testSelectedDateDropsOldFetchBeforePublishingTheNewDate() async {
        let service = CalendarInteractionServiceFake()
        let manager = CalendarManager(service: service, now: { self.date(day: 11) }, calendar: testCalendar, startMonitoring: false)
        let firstStarted = expectation(description: "First fetch")
        let secondStarted = expectation(description: "Second fetch")
        var firstResult: CheckedContinuation<[EventModel], Never>?
        var secondResult: CheckedContinuation<[EventModel], Never>?
        service.fetch = { start, end, _ in
            if end.timeIntervalSince(start) != 86400 { return [] }
            if start == self.date(day: 14) {
                return await withCheckedContinuation { firstResult = $0; firstStarted.fulfill() }
            }
            if start == self.date(day: 15) {
                return await withCheckedContinuation { secondResult = $0; secondStarted.fulfill() }
            }
            return []
        }
        let first = Task { await manager.updateCurrentDate(date(day: 14)) }
        await fulfillment(of: [firstStarted], timeout: 2)
        let second = Task { await manager.updateCurrentDate(date(day: 15)) }
        await Task.yield()
        firstResult?.resume(returning: [record("old")])
        await fulfillment(of: [secondStarted], timeout: 2)
        XCTAssertTrue(manager.events.isEmpty, "迟到旧结果不能在新请求完成前发布")
        secondResult?.resume(returning: [record("new")])
        await first.value
        await second.value
        XCTAssertEqual(manager.events.map(\.id), ["new"])
    }

    func testTodayDropsOlderSameDayRefreshAndRequeriesAcrossMidnight() async {
        let service = CalendarInteractionServiceFake()
        var now = date(day: 11, hour: 23)
        let manager = CalendarManager(service: service, now: { now }, calendar: testCalendar, startMonitoring: false)
        let firstStarted = expectation(description: "Old today fetch")
        let secondStarted = expectation(description: "Latest today fetch")
        var firstResult: CheckedContinuation<[EventModel], Never>?
        var secondResult: CheckedContinuation<[EventModel], Never>?
        var count = 0
        service.fetch = { _, _, _ in
            count += 1
            if count == 1 { return await withCheckedContinuation { firstResult = $0; firstStarted.fulfill() } }
            return await withCheckedContinuation { secondResult = $0; secondStarted.fulfill() }
        }
        let first = Task { await manager.updateTodayEvents(force: true) }
        await fulfillment(of: [firstStarted], timeout: 2)
        let second = Task { await manager.updateTodayEvents(force: true) }
        await Task.yield()
        firstResult?.resume(returning: [record("old")])
        await fulfillment(of: [secondStarted], timeout: 2)
        XCTAssertTrue(manager.todayEvents.isEmpty)
        secondResult?.resume(returning: [record("latest")])
        await first.value
        await second.value
        XCTAssertEqual(manager.todayEvents.map(\.id), ["latest"])

        let midnightStarted = expectation(description: "Fetch before midnight")
        var midnightResult: CheckedContinuation<[EventModel], Never>?
        let nextDay = record("next-day", start: date(day: 12, hour: 9), end: date(day: 12, hour: 10))
        service.fetch = { start, _, _ in
            if start == self.date(day: 11) {
                return await withCheckedContinuation { midnightResult = $0; midnightStarted.fulfill() }
            }
            XCTAssertEqual(start, self.date(day: 12))
            return [nextDay]
        }
        let midnight = Task { await manager.updateTodayEvents(force: true) }
        await fulfillment(of: [midnightStarted], timeout: 2)
        now = date(day: 12)
        midnightResult?.resume(returning: [record("yesterday")])
        await midnight.value
        XCTAssertEqual(manager.todayEvents.map(\.id), ["next-day"])
    }

    func testManagerReturnsRealRecordsRefreshesAfterSuccessAndPreservesFailure() async throws {
        let service = CalendarInteractionServiceFake()
        let manager = CalendarManager(service: service, now: { self.date(day: 11) }, calendar: testCalendar, startMonitoring: false)
        let saved = record("real-event-id")
        let completed = record("real-reminder-id", type: .reminder(completed: true))
        service.savedRecord = saved
        service.reminderRecord = completed
        service.fetch = { _, _, _ in [saved] }
        let input = CalendarEventInput(title: "Input", start: saved.start, end: saved.end, isAllDay: false)
        let savedResult = try await manager.saveEvent(input: input, eventID: "existing-id")
        XCTAssertEqual(savedResult, saved)
        XCTAssertEqual(service.lastEventID, "existing-id")
        XCTAssertEqual(manager.todayEvents, [saved])
        XCTAssertEqual(manager.events, [saved])
        let createdReminder = try await manager.createReminderRecord(title: "Task", due: date(day: 11), listID: "explicit-list")
        XCTAssertEqual(createdReminder, completed)
        XCTAssertEqual(service.lastListID, "explicit-list")
        let completedReminder = try await manager.completeReminder(id: completed.id, completed: true)
        XCTAssertEqual(completedReminder, completed)
        XCTAssertEqual(manager.event(withID: saved.id), saved)
        try await manager.deleteEvent(id: saved.id)
        XCTAssertEqual(service.deletedID, saved.id)
        let fetches = service.fetchCount
        service.writeError = .readOnlyCalendar
        do {
            _ = try await manager.saveEvent(input: input)
            XCTFail("Error must be propagated")
        } catch { XCTAssertEqual(error as? CalendarMutationError, .readOnlyCalendar) }
        XCTAssertEqual(service.fetchCount, fetches, "失败不触发刷新")
        XCTAssertEqual(manager.todayEvents, [saved])
        XCTAssertEqual(service.accessRequests, 0)
        XCTAssertEqual(manager.liveCalendarAuthorization, .fullAccess)
    }

    func testWriteFailureRollsBackMutableStateAndSuccessfulWriteDoesNotRollback() throws {
        var title = "Original"
        var completed = false
        var completionDate: Date?
        var rollbacks = 0
        XCTAssertThrowsError(try CalendarMutationPolicy.performWithRollback(write: {
            title = "Edited"
            completed = true
            completionDate = date(day: 11)
            throw CalendarMutationError.readOnlyCalendar
        }, rollback: {
            title = "Original"
            completed = false
            completionDate = nil
            rollbacks += 1
        })) { XCTAssertEqual($0 as? CalendarMutationError, .readOnlyCalendar) }
        XCTAssertEqual(title, "Original")
        XCTAssertFalse(completed)
        XCTAssertNil(completionDate)
        XCTAssertEqual(rollbacks, 1)
        let result = try CalendarMutationPolicy.performWithRollback(write: { "real-id" }, rollback: { rollbacks += 1 })
        XCTAssertEqual(result, "real-id")
        XCTAssertEqual(rollbacks, 1)
    }

    private func panelSession(
        service: CalendarInteractionMemoryService,
        save: ((CalendarEventInput, String?) async throws -> EventModel)? = nil,
        create: ((String, Date, String?) async throws -> EventModel)? = nil,
        complete: ((String, Bool) async throws -> EventModel)? = nil
    ) -> CalendarPanelSession {
        CalendarPanelSession(
            selectedDate: date(day: 11), calendar: testCalendar, now: { self.date(day: 11, hour: 12) },
            saveEvent: save ?? { try await service.saveEvent(input: $0, eventID: $1) },
            createReminder: create ?? { try await service.createReminderRecord(title: $0, due: $1, listID: $2) },
            deleteEvent: { try await service.deleteEvent(id: $0) },
            completeReminder: complete ?? { try await service.completeReminder(id: $0, completed: $1) },
            event: { service.event(withID: $0) },
            openSystemEvent: { service.recordSystemOpen($0.id) }
        )
    }

    /// 切条目的三种情形（2026-10-16 上屏反馈）：**只有真的会丢东西才拦人**——
    /// ① 点当前那一条 → 什么都不做；② 稿没改过 → 静默换；③ 稿改过 → 才弹三选一。
    func testSwitchingItemsOnlyPromptsWhenTheDraftHasUnsavedChanges() throws {
        let backend = panelBackend()
        let event = try XCTUnwrap(backend.event(withID: "fixture-event-01"))
        let session = panelSession(service: backend)

        // ① 点当前那一条：同一个 id → 静默（`resumeDraft`），不进任何确认态。
        session.beginEdit(event)
        let identity = session.draftIdentity
        session.beginEdit(event)
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draftIdentity, identity, "同一条重复点：稿与身份都不动")
        XCTAssertNil(session.pendingConfirmation)

        // ② 稿没改过（`draft == baseline`）→ 点别处直接换稿，不弹框。
        XCTAssertFalse(session.hasDirtyDraft, "前提：刚开出来的稿与基线一致")
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        XCTAssertNil(session.pendingConfirmation, "没改过就不该弹「已有未保存草稿」")
        XCTAssertEqual(session.route, .editor)
        XCTAssertNil(session.draft?.eventID, "已经换成了新建稿")

        // ③ 稿改过（`draft != baseline`）→ 才拦人：三选一。
        session.beginEdit(event)
        session.draft?.title = "改过的标题"
        XCTAssertTrue(session.hasDirtyDraft, "前提：这条稿确实有改动")
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        XCTAssertEqual(session.pendingConfirmation, .draftConflict, "有改动才弹三选一")
        // 取消 → 什么都不动（还停在原来那条）。
        session.resolveDraftConflict(.cancel)
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draft?.eventID, event.id, "取消 = 留在原稿")
        // 继续旧草稿同样留在原稿；放弃后开始才换。
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.resolveDraftConflict(.resume)
        XCTAssertEqual(session.draft?.eventID, event.id, "继续旧草稿 = 回原稿")
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.resolveDraftConflict(.discardAndStart)
        XCTAssertNil(session.draft?.eventID, "放弃后开始 = 换成新稿")
        XCTAssertNil(session.pendingConfirmation)
    }

    /// 2026-10-16（用户）：**编辑 / 新增档整个期间都抑制自动收起**——不是只有「有焦点 / 有菜单 /
    /// 有日期弹层」时才抑制；离开编辑档（保存 / 取消 / 挂起）保护随之释放。
    func testEditorSessionProtectsAutoCloseUntilItIsLeft() throws {
        let backend = panelBackend()
        let event = try XCTUnwrap(backend.event(withID: "fixture-event-01"))
        let session = panelSession(service: backend)
        let owner = UUID()

        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        XCTAssertEqual(session.route, .editor)
        XCTAssertTrue(session.shouldProtectAutoClose, "新建档一开出来就保护（不看焦点/菜单/弹层）")
        XCTAssertFalse(session.editorHasFocus)
        XCTAssertEqual(session.ownedMenuCount, 0)
        XCTAssertFalse(session.datePopoverPresented)

        // 有焦点、有菜单、有弹层都仍然保护（老口径是新口径的子集）。
        session.setEditorFocus(true, ownerID: owner)
        XCTAssertTrue(session.shouldProtectAutoClose)
        session.setEditorFocus(false, ownerID: owner)
        session.setOwnedMenuCount(1, ownerID: owner)
        XCTAssertTrue(session.shouldProtectAutoClose)
        session.setOwnedMenuCount(0, ownerID: owner)
        session.setDatePopoverPresented(true, ownerID: owner)
        XCTAssertTrue(session.shouldProtectAutoClose)
        session.setDatePopoverPresented(false, ownerID: owner)
        XCTAssertTrue(session.shouldProtectAutoClose, "全清掉之后仍在编辑档 → 仍保护")

        // 撤销/取消（`requestCancel` 的两条出口之一：无改动直接撤）→ 回列表 → 释放。
        session.requestCancel()
        XCTAssertEqual(session.route, .list)
        XCTAssertFalse(session.shouldProtectAutoClose, "离开编辑档 = 释放保护")

        // 编辑档同样保护；`suspend()`（点面板外 / 切页）也释放。
        session.beginEdit(event)
        XCTAssertTrue(session.shouldProtectAutoClose)
        session.suspend()
        XCTAssertEqual(session.route, .list)
        XCTAssertFalse(session.shouldProtectAutoClose)

        // 提交期间也保护（既有口径）。
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.requestCancel()
        XCTAssertFalse(session.shouldProtectAutoClose)
    }

    private func panelBackend(count: Int = 9) -> CalendarInteractionMemoryService {
        CalendarInteractionFixtures.makeBackend(count: count, on: date(day: 11), calendar: testCalendar)
    }

    func testPanelDraftBaselineSuspensionAndBrowsingKeepOriginalTarget() throws {
        let backend = panelBackend()
        let event = try XCTUnwrap(backend.event(withID: "fixture-event-01"))
        let session = panelSession(service: backend)
        session.showList(on: date(day: 11), anchor: event.id)
        session.beginEdit(event)
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draft, session.baseline)
        XCTAssertFalse(session.hasDirtyDraft)
        session.draft?.title = "Changed draft"
        session.draft?.location = "Changed room"
        XCTAssertTrue(session.hasDirtyDraft)
        XCTAssertEqual(session.baseline?.title, event.title)
        XCTAssertEqual(backend.event(withID: event.id), event)
        let draft = session.draft
        session.setEditorFocus(true, ownerID: UUID())
        session.suspend()
        XCTAssertEqual(session.route, .list)
        XCTAssertFalse(session.editorHasFocus)
        XCTAssertFalse(session.shouldProtectAutoClose)
        session.showList(on: date(day: 19), anchor: "other-day")
        session.resumeDraft()
        XCTAssertEqual(session.draft, draft)
        XCTAssertEqual(session.draft?.eventID, event.id)
        XCTAssertEqual(session.draft?.calendarID, event.calendar.id)
        XCTAssertEqual(session.draft?.originalDate, event.start)
        XCTAssertEqual(session.returnSource, .calendar(date: date(day: 11), anchor: event.id))
        XCTAssertEqual(session.selectedDate, date(day: 19), "恢复草稿不改当前浏览日，草稿独立保存原日")
        XCTAssertEqual(backend.writeAttempts, 0)
    }

    /// T6（D-11）：详情档退休后 `back()` 只有「回列表并把来源交回」一种语义——不再有中间那一档。
    func testPanelBackRestoresTheListAnchor() throws {
        let backend = panelBackend()
        let event = try XCTUnwrap(backend.event(withID: "fixture-event-01"))
        let session = panelSession(service: backend)
        session.showList(on: date(day: 11), anchor: "calendar-tail")
        session.beginEdit(event)
        session.draft?.notes = "Retained"
        XCTAssertEqual(session.back(), .calendar(date: date(day: 11), anchor: "calendar-tail"))
        XCTAssertEqual(session.route, .list)
        XCTAssertEqual(session.calendarScrollAnchor, "calendar-tail")
        XCTAssertEqual(session.draft?.notes, "Retained")
        session.discardDraft()
        session.showList(on: date(day: 14), anchor: "calendar-tail")
        session.beginCreate(kind: .event, on: date(day: 14), calendarID: "fixture-events")
        XCTAssertEqual(session.back(), .calendar(date: date(day: 14), anchor: "calendar-tail"))
        XCTAssertEqual(session.calendarScrollAnchor, "calendar-tail")
        XCTAssertEqual(session.route, .list)
    }

    func testPanelCancelAndAllDraftConflictChoicesNeverSilentlyReplaceDraft() throws {
        let backend = panelBackend()
        let session = panelSession(service: backend)
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.requestCancel()
        XCTAssertNil(session.draft)
        XCTAssertEqual(session.route, .list)
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Keep this draft"
        let original = session.draft
        session.requestCancel()
        XCTAssertEqual(session.pendingConfirmation, .discardDraft)
        XCTAssertEqual(session.draft, original)
        session.dismissConfirmation()
        session.beginCreate(kind: .reminder, on: date(day: 14), calendarID: "fixture-reminders")
        XCTAssertEqual(session.pendingConfirmation, .draftConflict)
        XCTAssertEqual(session.draft, original)
        session.resolveDraftConflict(.cancel)
        XCTAssertEqual(session.draft, original)
        session.suspend()
        session.beginEdit(try XCTUnwrap(backend.event(withID: "fixture-event-01")))
        session.resolveDraftConflict(.resume)
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draft, original)
        session.beginCreate(kind: .reminder, on: date(day: 14), calendarID: "fixture-reminders")
        session.resolveDraftConflict(.discardAndStart)
        XCTAssertEqual(session.draft?.kind, .reminder)
        XCTAssertEqual(session.draft?.originalDate, date(day: 14))
        XCTAssertEqual(session.draft?.calendarID, "fixture-reminders")
        XCTAssertEqual(session.draft, session.baseline)
        XCTAssertNil(session.pendingConfirmation)
        XCTAssertEqual(backend.writeAttempts, 0)
    }

    func testPanelRepeatedOwnershipValuesAndMissingOwnerCleanupDoNotPublish() {
        let session = panelSession(service: panelBackend())
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        let owner = UUID()
        var publications = 0
        let subscription = session.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }

        session.setEditorFocus(false, ownerID: owner)
        session.setOwnedMenuCount(-1, ownerID: owner)
        session.setDatePopoverPresented(false, ownerID: owner)
        session.clearOwnership(UUID())
        session.clearOwnership(owner)
        session.clearOwnership(owner)
        XCTAssertEqual(publications, 0)

        session.setEditorFocus(true, ownerID: owner)
        XCTAssertEqual(publications, 1)
        XCTAssertTrue(session.editorHasFocus)
        XCTAssertTrue(session.shouldProtectAutoClose)
        session.setOwnedMenuCount(2, ownerID: owner)
        XCTAssertEqual(publications, 2)
        XCTAssertEqual(session.ownedMenuCount, 2)
        session.setDatePopoverPresented(true, ownerID: owner)
        XCTAssertEqual(publications, 3)
        XCTAssertTrue(session.datePopoverPresented)
        session.setEditorFocus(true, ownerID: owner)
        session.setOwnedMenuCount(2, ownerID: owner)
        session.setDatePopoverPresented(true, ownerID: owner)
        session.clearOwnership(UUID())
        XCTAssertEqual(publications, 3, "同值 setter 与不存在 owner 的清理不应通知订阅者")
    }

    func testPanelReleasingOneOfTwoInputOwnersDoesNotPublishUntilAggregateChanges() {
        let session = panelSession(service: panelBackend())
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Shared input survives one owner"
        let draft = session.draft
        let ownerA = UUID(), ownerB = UUID()
        session.setEditorFocus(true, ownerID: ownerA)
        session.setDatePopoverPresented(true, ownerID: ownerA)
        var publications = 0
        let subscription = session.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }

        session.setEditorFocus(true, ownerID: ownerB)
        session.setDatePopoverPresented(true, ownerID: ownerB)
        session.clearOwnership(ownerA)
        XCTAssertEqual(publications, 0)
        XCTAssertTrue(session.editorHasFocus)
        XCTAssertTrue(session.datePopoverPresented)
        XCTAssertTrue(session.shouldProtectAutoClose)
        XCTAssertEqual(session.draft, draft)

        session.clearOwnership(ownerB)
        XCTAssertEqual(publications, 2, "最后 owner 释放时立即发布两项真实变化")
        XCTAssertFalse(session.editorHasFocus)
        XCTAssertFalse(session.datePopoverPresented)
        // 2026-10-16 起：保护窗口 = 整个编辑档（不再是「有焦点 / 有菜单 / 有弹层」）——
        // 这里仍停在编辑档，所以保护照旧；ownership 的账本才是本用例的主体。
        XCTAssertTrue(session.shouldProtectAutoClose)
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draft, draft)
    }

    func testPanelMenuCountChangesPublishSynchronouslyAcrossOwners() {
        let session = panelSession(service: panelBackend())
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        let ownerA = UUID(), ownerB = UUID()
        var publications = 0
        let subscription = session.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }

        session.setOwnedMenuCount(2, ownerID: ownerA)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(session.ownedMenuCount, 2)
        session.setOwnedMenuCount(1, ownerID: ownerB)
        XCTAssertEqual(publications, 2)
        XCTAssertEqual(session.ownedMenuCount, 3)
        session.clearOwnership(ownerA)
        XCTAssertEqual(publications, 3)
        XCTAssertEqual(session.ownedMenuCount, 1)
        XCTAssertTrue(session.shouldProtectAutoClose)
        session.setOwnedMenuCount(-1, ownerID: ownerB)
        XCTAssertEqual(publications, 4)
        XCTAssertEqual(session.ownedMenuCount, 0)
        XCTAssertTrue(session.shouldProtectAutoClose, "菜单归零也在编辑档里 → 保护不撤")
        session.clearOwnership(ownerB)
        XCTAssertEqual(publications, 4)
    }

    func testLifecycleCleanupAfterBackDoesNotRepublishClearedOwnership() throws {
        let backend = panelBackend()
        let event = try XCTUnwrap(backend.event(withID: "fixture-event-01"))
        let session = panelSession(service: backend)
        session.showList(on: date(day: 11), anchor: "calendar-tail")
        session.beginEdit(event)
        let lifecycle = CalendarEditorLifecycle(session: session)
        lifecycle.setEditorFocus(true)
        lifecycle.setOwnedMenuCount(1)
        lifecycle.setDatePopoverPresented(true)
        XCTAssertEqual(session.back(), .calendar(date: date(day: 11), anchor: "calendar-tail"))
        XCTAssertFalse(session.editorHasFocus)
        XCTAssertEqual(session.ownedMenuCount, 0)
        XCTAssertFalse(session.datePopoverPresented)
        var publications = 0
        let subscription = session.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }

        lifecycle.setOwnedMenuCount(0)
        lifecycle.clearLocalInput()
        lifecycle.stop()
        lifecycle.stop()
        session.clearOwnership(lifecycle.ownerID)
        XCTAssertEqual(publications, 0, "返回已清 ownership 后，菜单拆卸与生命周期清理不能重复发布")
        XCTAssertEqual(session.route, .list)
        XCTAssertEqual(session.calendarScrollAnchor, "calendar-tail")
        XCTAssertFalse(session.shouldProtectAutoClose)
    }

    func testPanelOwnerAggregationKeepsOtherWindowProtectionUntilGlobalSuspend() {
        let session = panelSession(service: panelBackend())
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        let ownerA = UUID(), ownerB = UUID()
        session.setEditorFocus(true, ownerID: ownerA)
        session.setEditorFocus(true, ownerID: ownerB)
        session.setOwnedMenuCount(2, ownerID: ownerA)
        session.setOwnedMenuCount(1, ownerID: ownerB)
        session.setDatePopoverPresented(true, ownerID: ownerB)
        XCTAssertEqual(session.ownedMenuCount, 3)
        session.clearOwnership(ownerA)
        XCTAssertTrue(session.editorHasFocus)
        XCTAssertEqual(session.ownedMenuCount, 1)
        XCTAssertTrue(session.datePopoverPresented)
        XCTAssertTrue(session.shouldProtectAutoClose)
        session.setOwnedMenuCount(-1, ownerID: ownerB)
        XCTAssertEqual(session.ownedMenuCount, 0)
        session.suspend()
        XCTAssertFalse(session.editorHasFocus)
        XCTAssertFalse(session.datePopoverPresented)
        XCTAssertEqual(session.ownedMenuCount, 0)
        XCTAssertFalse(session.shouldProtectAutoClose)
        XCTAssertNotNil(session.draft)
    }

    func testPanelValidationRestrictedEditAndFailurePreserveDraftWithoutWrites() async throws {
        let backend = panelBackend()
        let session = panelSession(service: backend)
        for id in ["fixture-event-04", "fixture-event-07"] {
            session.beginEdit(try XCTUnwrap(backend.event(withID: id)))
            XCTAssertNil(session.draft)
            XCTAssertNotNil(session.error)
        }
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: nil)
        session.draft?.title = "Draft"
        let invalidResult = await session.save()
        XCTAssertFalse(invalidResult)
        XCTAssertEqual(backend.writeAttempts, 0)
        XCTAssertNotNil(session.draft)
        session.draft?.calendarID = "fixture-events"
        backend.writeFailure = .readOnlyCalendar
        let submitted = session.draft
        let failedResult = await session.save()
        XCTAssertFalse(failedResult)
        XCTAssertEqual(session.draft, submitted)
        XCTAssertEqual(session.route, .editor)
        XCTAssertNotNil(session.error)
        XCTAssertFalse(session.isSubmitting)
        session.suspend()
        session.resumeDraft()
        XCTAssertNotNil(session.error, "失败信息随原稿恢复")
        XCTAssertEqual(session.draft, submitted)
        backend.writeFailure = nil
        let savedResult = await session.save()
        XCTAssertTrue(savedResult)
        XCTAssertEqual(session.route, .list, "保存成功后回列表（T6：详情档退休）")
        XCTAssertEqual(backend.event(withID: "fixture-created-1")?.title, "Draft")
        XCTAssertNil(session.draft)
        XCTAssertNil(session.baseline)
        XCTAssertNil(session.error)
        XCTAssertEqual(backend.writeAttempts, 2)
    }

    func testPanelReminderSaveUsesStableListAndDateAndSystemOpenIsInjected() async throws {
        let backend = panelBackend()
        let session = panelSession(service: backend)
        session.beginCreate(kind: .reminder, on: date(day: 14), calendarID: "fixture-reminders")
        session.draft?.title = "  Reminder  "
        session.selectedDate = date(day: 20)
        let savedResult = await session.save()
        XCTAssertTrue(savedResult)
        let saved = try XCTUnwrap(backend.event(withID: "fixture-created-1"))
        XCTAssertEqual(saved.start, date(day: 14))
        XCTAssertEqual(saved.calendar.id, "fixture-reminders")
        XCTAssertEqual(saved.title, "Reminder")
        XCTAssertEqual(session.route, .list, "保存成功后回列表（T6：详情档退休）")
        session.openInSystemApp(saved)
        XCTAssertEqual(backend.systemOpenedIDs, [saved.id])
    }

    func testPanelLateSaveDoesNotReplaceNewNavigationOrStartAnotherWrite() async throws {
        let backend = panelBackend()
        let started = expectation(description: "save started")
        var continuation: CheckedContinuation<EventModel, Error>?
        var writes = 0
        let session = panelSession(service: backend, save: { _, _ in
            writes += 1
            return try await withCheckedThrowingContinuation {
                continuation = $0
                started.fulfill()
            }
        })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Submitted"
        let saving = Task { await session.save() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(session.isSubmitting)
        XCTAssertTrue(session.shouldProtectAutoClose)
        let second = await session.save()
        XCTAssertFalse(second)
        session.showList(on: date(day: 11), anchor: "new-tail")
        continuation?.resume(returning: record("saved-real-id"))
        let savedResult = await saving.value
        XCTAssertTrue(savedResult)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(session.route, .list, "迟到的保存不许把用户后来切到的档位换掉")
        XCTAssertEqual(session.calendarScrollAnchor, "new-tail")
        XCTAssertEqual(session.returnSource, .calendar(date: date(day: 11), anchor: "new-tail"))
        XCTAssertNil(session.draft)
        XCTAssertFalse(session.isSubmitting)
    }

    func testPanelResumingTheSameInFlightDraftShowsTheSavedRecordInsteadOfEmptyEditor() async {
        let backend = panelBackend()
        let started = expectation(description: "save started")
        var continuation: CheckedContinuation<EventModel, Error>?
        let session = panelSession(service: backend, save: { _, _ in
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Submitted draft"
        let saving = Task { await session.save() }
        await fulfillment(of: [started], timeout: 2)
        session.suspend()
        session.resumeDraft()
        XCTAssertEqual(session.route, .editor)
        continuation?.resume(returning: record("saved-real-id"))
        let saved = await saving.value
        XCTAssertTrue(saved)
        XCTAssertNil(session.draft)
        // T6：保存成功后回列表；会话不再持有「刚存的记录」这种引用（详情档退休，记录改由列表渲染它）。
        XCTAssertEqual(session.route, .list, "保存成功后回列表")
    }

    func testPanelLateFailureRetainsOldDraftAndDoesNotPolluteNewPage() async throws {
        let backend = panelBackend()
        let started = expectation(description: "save started")
        var continuation: CheckedContinuation<EventModel, Error>?
        let session = panelSession(service: backend, save: { _, _ in
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Retained after failure"
        let submitted = session.draft
        let saving = Task { await session.save() }
        await fulfillment(of: [started], timeout: 2)
        session.suspend()
        session.showList(on: date(day: 18), anchor: "fresh-page")
        continuation?.resume(throwing: CalendarMutationError.readOnlyCalendar)
        let savedResult = await saving.value
        XCTAssertFalse(savedResult)
        XCTAssertEqual(session.route, .list)
        XCTAssertEqual(session.selectedDate, date(day: 18))
        XCTAssertNil(session.error)
        XCTAssertEqual(session.draft, submitted)
        session.resumeDraft()
        XCTAssertNotNil(session.error)
    }

    func testPanelSavePreservesEditsMadeWhileOriginalSubmissionIsInFlight() async {
        let backend = panelBackend()
        let started = expectation(description: "save started")
        var continuation: CheckedContinuation<EventModel, Error>?
        let session = panelSession(service: backend, save: { _, _ in
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Submitted title"
        let saving = Task { await session.save() }
        await fulfillment(of: [started], timeout: 2)
        session.draft?.title = "Newer input"
        continuation?.resume(returning: record("saved-real-id"))
        let savedResult = await saving.value
        XCTAssertTrue(savedResult)
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draft?.title, "Newer input")
        XCTAssertEqual(session.baseline?.title, "Submitted title")
        XCTAssertEqual(session.draft?.eventID, "saved-real-id")
        XCTAssertEqual(session.baseline?.eventID, "saved-real-id")
        XCTAssertTrue(session.hasDirtyDraft)
    }

    func testPanelCompletionFailureKeepsReminderAndListCompletionDoesNotNavigate() async throws {
        let backend = panelBackend()
        let reminder = try XCTUnwrap(backend.event(withID: "fixture-reminder-03"))
        let session = panelSession(service: backend)
        session.showList(on: date(day: 11), anchor: reminder.id)
        backend.writeFailure = .readOnlyCalendar
        let failed = await session.complete(reminder, completed: true)
        XCTAssertFalse(failed)
        XCTAssertEqual(session.calendarScrollAnchor, reminder.id)
        XCTAssertEqual(backend.event(withID: reminder.id), reminder)
        backend.writeFailure = nil
        session.suspend()
        let completed = await session.complete(reminder, completed: true)
        XCTAssertTrue(completed)
        XCTAssertEqual(session.route, .list)
        XCTAssertEqual(backend.event(withID: reminder.id)?.type, .reminder(completed: true))
        XCTAssertTrue(backend.event(withID: reminder.id)?.hasRecurrenceRules == true)
    }

    func testPanelLateCompletionDoesNotUpdateAnotherNavigation() async throws {
        let backend = panelBackend()
        let reminder = try XCTUnwrap(backend.event(withID: "fixture-reminder-02"))
        let started = expectation(description: "completion started")
        var continuation: CheckedContinuation<EventModel, Error>?
        let session = panelSession(service: backend, complete: { _, _ in
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        })
        session.showList(on: date(day: 11), anchor: reminder.id)
        let completing = Task { await session.complete(reminder, completed: true) }
        await fulfillment(of: [started], timeout: 2)
        let other = try XCTUnwrap(backend.event(withID: "fixture-event-01"))
        session.showList(on: date(day: 11), anchor: other.id)
        continuation?.resume(returning: record(reminder.id, type: .reminder(completed: true)))
        let completed = await completing.value
        XCTAssertTrue(completed)
        XCTAssertEqual(session.calendarScrollAnchor, other.id)
        XCTAssertEqual(session.returnSource, .calendar(date: date(day: 11), anchor: other.id))
    }

    func testPanelDeleteFailureKeepsRecordAndSuccessKeepsListAnchor() async throws {
        let backend = panelBackend()
        let event = try XCTUnwrap(backend.event(withID: "fixture-event-01"))
        let session = panelSession(service: backend)
        session.showList(on: date(day: 11), anchor: "neighbor")
        backend.writeFailure = .readOnlyCalendar
        let failed = await session.delete(event)
        XCTAssertFalse(failed)
        XCTAssertNotNil(session.error)
        XCTAssertNotNil(backend.event(withID: event.id))
        backend.writeFailure = nil
        let deleted = await session.delete(event)
        XCTAssertTrue(deleted)
        XCTAssertEqual(session.route, .list)
        XCTAssertEqual(session.calendarScrollAnchor, "neighbor")
        XCTAssertEqual(session.returnSource, .calendar(date: date(day: 11), anchor: "neighbor"))
        XCTAssertNil(backend.event(withID: event.id))
        let readOnly = try XCTUnwrap(backend.event(withID: "fixture-event-04"))
        let restricted = await session.delete(readOnly)
        XCTAssertFalse(restricted)
        XCTAssertEqual(backend.writeAttempts, 2)
    }

    func testPanelTerminationChoicesSaveDiscardCancelAndRejectFailedSave() async {
        let backend = panelBackend()
        let session = panelSession(service: backend)
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Do not exit"
        let cancelled = await session.resolveTermination(.cancel)
        XCTAssertFalse(cancelled)
        XCTAssertNotNil(session.draft)
        backend.writeFailure = .readOnlyCalendar
        let failed = await session.resolveTermination(.save)
        XCTAssertFalse(failed)
        XCTAssertNotNil(session.draft)
        let discarded = await session.resolveTermination(.discard)
        XCTAssertTrue(discarded)
        XCTAssertNil(session.draft)
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Save before exit"
        backend.writeFailure = nil
        let saved = await session.resolveTermination(.save)
        XCTAssertTrue(saved)
        XCTAssertNil(session.draft)
        XCTAssertEqual(backend.writeAttempts, 2)
    }

    func testPanelTerminationWaitsForExistingSubmissionOnceAndFailureCancelsExit() async {
        for shouldFail in [false, true] {
            let backend = panelBackend()
            let started = expectation(description: "submission started")
            var continuation: CheckedContinuation<EventModel, Error>?
            var writes = 0
            let session = panelSession(service: backend, save: { _, _ in
                writes += 1
                return try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
            })
            session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
            session.draft?.title = "One submission"
            let saving = Task { await session.save() }
            await fulfillment(of: [started], timeout: 2)
            session.suspend()
            XCTAssertTrue(session.shouldProtectAutoClose, "切页仍保在途提交保护")
            let quitting = Task { await session.resolveTermination(.discard) }
            let waiting = Task { await session.waitForSubmission() }
            await Task.yield()
            XCTAssertEqual(writes, 1)
            XCTAssertTrue(session.isSubmitting)
            let cancelled = await session.resolveTermination(.cancel)
            XCTAssertFalse(cancelled)
            if shouldFail { continuation?.resume(throwing: CalendarMutationError.readOnlyCalendar) }
            else { continuation?.resume(returning: record("stable-saved-id")) }
            let result = await saving.value
            let allowedToQuit = await quitting.value
            let waited = await waiting.value
            XCTAssertEqual(result, !shouldFail)
            XCTAssertEqual(allowedToQuit, !shouldFail)
            XCTAssertEqual(waited, !shouldFail)
            XCTAssertEqual(writes, 1)
            XCTAssertFalse(session.isSubmitting)
            XCTAssertEqual(session.draft != nil, shouldFail)
        }
    }

    func testPanelResumedInFlightDraftFailurePublishesErrorImmediately() async {
        let backend = panelBackend()
        let started = expectation(description: "save started")
        var continuation: CheckedContinuation<EventModel, Error>?
        let session = panelSession(service: backend, save: { _, _ in
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Keep failed input"
        let submitted = session.draft
        let baseline = session.baseline
        let saving = Task { await session.save() }
        await fulfillment(of: [started], timeout: 2)
        session.suspend()
        session.resumeDraft()
        XCTAssertNil(session.error)
        continuation?.resume(throwing: CalendarMutationError.readOnlyCalendar)
        let saved = await saving.value
        XCTAssertFalse(saved)
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draft, submitted)
        XCTAssertEqual(session.baseline, baseline)
        XCTAssertEqual(session.error, CalendarMutationError.readOnlyCalendar.localizedDescription)
    }

    func testPanelOldFailedSaveDoesNotPublishErrorIntoReplacementEditor() async {
        let backend = panelBackend()
        let started = expectation(description: "save started")
        var continuation: CheckedContinuation<EventModel, Error>?
        let session = panelSession(service: backend, save: { _, _ in
            try await withCheckedThrowingContinuation { continuation = $0; started.fulfill() }
        })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Old input"
        let saving = Task { await session.save() }
        await fulfillment(of: [started], timeout: 2)
        session.beginCreate(kind: .reminder, on: date(day: 15), calendarID: "fixture-reminders")
        session.resolveDraftConflict(.discardAndStart)
        session.draft?.title = "New input"
        let newDraft = session.draft
        continuation?.resume(throwing: CalendarMutationError.readOnlyCalendar)
        let saved = await saving.value
        XCTAssertFalse(saved)
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draft, newDraft)
        XCTAssertNil(session.error)
    }

    func testPanelConcurrentSaveExitAfterUnrelatedCompletionSavesRemainingDraftOnce() async throws {
        for failSave in [false, true] {
            let backend = panelBackend()
            let completionStarted = expectation(description: "completion started")
            let saveStarted = expectation(description: "remaining draft save started")
            var completionGate: CheckedContinuation<Void, Error>?
            var saveGate: CheckedContinuation<Void, Error>?
            var savedInputs: [CalendarEventInput] = []
            let session = panelSession(service: backend, save: { input, id in
                savedInputs.append(input)
                try await withCheckedThrowingContinuation { saveGate = $0; saveStarted.fulfill() }
                return try await backend.saveEvent(input: input, eventID: id)
            }, complete: { id, completed in
                try await withCheckedThrowingContinuation { completionGate = $0; completionStarted.fulfill() }
                return try await backend.completeReminder(id: id, completed: completed)
            })
            session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
            session.draft?.title = "Save retained draft before exit"
            session.suspend()
            let reminder = try XCTUnwrap(backend.event(withID: "fixture-reminder-02"))
            let completing = Task { await session.complete(reminder, completed: true) }
            await fulfillment(of: [completionStarted], timeout: 2)
            let firstExit = Task { await session.resolveTermination(.save) }
            let secondExit = Task { await session.resolveTermination(.save) }
            await Task.yield()
            XCTAssertTrue(savedInputs.isEmpty)
            completionGate?.resume(returning: ())
            await fulfillment(of: [saveStarted], timeout: 2)
            XCTAssertTrue(session.isSubmitting)
            XCTAssertNotNil(session.draft)
            XCTAssertEqual(savedInputs.count, 1)
            XCTAssertEqual(backend.writeAttempts, 1, "这里只完成提醒，草稿保存仍等待")
            if failSave { backend.writeFailure = .readOnlyCalendar }
            saveGate?.resume(returning: ())
            let completed = await completing.value
            let firstAllowed = await firstExit.value
            let secondAllowed = await secondExit.value
            XCTAssertTrue(completed)
            XCTAssertEqual(firstAllowed, !failSave)
            XCTAssertEqual(secondAllowed, !failSave)
            XCTAssertEqual(savedInputs.count, 1)
            XCTAssertEqual(backend.writeAttempts, 2, "一份提醒提交加一份草稿提交，不重复保存")
            XCTAssertEqual(session.draft != nil, failSave)
            XCTAssertEqual(backend.event(withID: "fixture-created-1")?.title, failSave ? nil : "Save retained draft before exit")
        }
    }

    func testPanelDiscardExitAfterUnrelatedCompletionClearsDraftOnlyOnSuccess() async throws {
        for failCompletion in [false, true] {
            let backend = panelBackend()
            let started = expectation(description: "completion started")
            var completionGate: CheckedContinuation<Void, Error>?
            let session = panelSession(service: backend, complete: { id, completed in
                try await withCheckedThrowingContinuation { completionGate = $0; started.fulfill() }
                return try await backend.completeReminder(id: id, completed: completed)
            })
            session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
            session.draft?.title = "Discard this retained draft"
            session.suspend()
            let reminder = try XCTUnwrap(backend.event(withID: "fixture-reminder-02"))
            let completing = Task { await session.complete(reminder, completed: true) }
            await fulfillment(of: [started], timeout: 2)
            let quitting = Task { await session.resolveTermination(.discard) }
            await Task.yield()
            let cancelled = await session.resolveTermination(.cancel)
            XCTAssertFalse(cancelled)
            XCTAssertNotNil(session.draft)
            if failCompletion { backend.writeFailure = .readOnlyCalendar }
            completionGate?.resume(returning: ())
            let completed = await completing.value
            let allowed = await quitting.value
            XCTAssertEqual(completed, !failCompletion)
            XCTAssertEqual(allowed, !failCompletion)
            XCTAssertEqual(session.draft != nil, failCompletion)
            XCTAssertEqual(session.baseline != nil, failCompletion)
            XCTAssertEqual(backend.writeAttempts, 1, "放弃退出不会新增草稿写入")
            XCTAssertNil(backend.event(withID: "fixture-created-1"))
        }
    }

    func testPanelSaveExitAfterOlderSnapshotSavesNewerInputToSameActualRecordOnce() async {
        let backend = panelBackend()
        let started = expectation(description: "original save started")
        var gate: CheckedContinuation<Void, Error>?
        var titles: [String] = []
        var eventIDs: [String?] = []
        let session = panelSession(service: backend, save: { input, id in
            titles.append(input.title)
            eventIDs.append(id)
            if titles.count == 1 {
                try await withCheckedThrowingContinuation { gate = $0; started.fulfill() }
            }
            return try await backend.saveEvent(input: input, eventID: id)
        })
        session.beginCreate(kind: .event, on: date(day: 11), calendarID: "fixture-events")
        session.draft?.title = "Original submitted snapshot"
        let originalSave = Task { await session.save() }
        await fulfillment(of: [started], timeout: 2)
        session.draft?.title = "Newer retained input"
        let firstExit = Task { await session.resolveTermination(.save) }
        let secondExit = Task { await session.resolveTermination(.save) }
        await Task.yield()
        gate?.resume(returning: ())
        let originalSaved = await originalSave.value
        let firstAllowed = await firstExit.value
        let secondAllowed = await secondExit.value
        XCTAssertTrue(originalSaved)
        XCTAssertTrue(firstAllowed)
        XCTAssertTrue(secondAllowed)
        XCTAssertEqual(titles, ["Original submitted snapshot", "Newer retained input"])
        XCTAssertEqual(eventIDs, [nil, "fixture-created-1"])
        XCTAssertEqual(backend.writeAttempts, 2)
        XCTAssertEqual(backend.allRecords().filter { $0.id.hasPrefix("fixture-created-") }.count, 1)
        XCTAssertEqual(backend.event(withID: "fixture-created-1")?.title, "Newer retained input")
        XCTAssertFalse(session.hasDirtyDraft)
        XCTAssertNil(session.draft)
    }

    func testPanelSaveExitRejectsEditingReminderCreatedByOlderSnapshotWithoutDuplicatingIt() async {
        let backend = panelBackend()
        let started = expectation(description: "reminder creation started")
        var gate: CheckedContinuation<Void, Error>?
        var creations = 0
        let session = panelSession(service: backend, create: { title, due, id in
            creations += 1
            try await withCheckedThrowingContinuation { gate = $0; started.fulfill() }
            return try await backend.createReminderRecord(title: title, due: due, listID: id)
        })
        session.beginCreate(kind: .reminder, on: date(day: 11), calendarID: "fixture-reminders")
        session.draft?.title = "Original reminder snapshot"
        let originalSave = Task { await session.save() }
        await fulfillment(of: [started], timeout: 2)
        session.draft?.title = "Newer reminder input"
        let quitting = Task { await session.resolveTermination(.save) }
        await Task.yield()
        gate?.resume(returning: ())
        let originalSaved = await originalSave.value
        let allowedToQuit = await quitting.value
        XCTAssertTrue(originalSaved)
        XCTAssertFalse(allowedToQuit)
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(backend.writeAttempts, 1)
        XCTAssertEqual(backend.event(withID: "fixture-created-1")?.title, "Original reminder snapshot")
        XCTAssertEqual(session.draft?.eventID, "fixture-created-1")
        XCTAssertEqual(session.baseline?.eventID, "fixture-created-1")
        XCTAssertEqual(session.draft?.title, "Newer reminder input")
        XCTAssertTrue(session.hasDirtyDraft)
        XCTAssertEqual(session.error, String(localized: "Edit saved reminders in the system app."))
        let retried = await session.save()
        XCTAssertFalse(retried)
        XCTAssertEqual(creations, 1)
        let discarded = await session.resolveTermination(.discard)
        XCTAssertTrue(discarded)
        XCTAssertNil(session.draft)
        XCTAssertEqual(backend.allRecords().filter { $0.id.hasPrefix("fixture-created-") }.count, 1)
    }

    func testFixtureCountsLongNotesRestrictionsAndStableGlobalTail() async throws {
        for count in [9, 30] {
            let backend = panelBackend(count: count)
            let records = await backend.events(from: date(day: 11), to: date(day: 12), calendars: [])
            XCTAssertEqual(records.count, count)
            XCTAssertEqual(records.filter { !$0.type.isReminder }.count, count / 3)
            XCTAssertEqual(records.filter { $0.type.isReminder }.count, count * 2 / 3)
            XCTAssertTrue(records.contains { $0.id == String(format: "fixture-reminder-%02d", count) })
            XCTAssertEqual(records.filter { !$0.type.isReminder && $0.canModifyInIsland }.first?.id, "fixture-event-01")
            let readOnly = try XCTUnwrap(backend.event(withID: "fixture-event-04"))
            XCTAssertFalse(readOnly.canModifyInIsland)
            let notes = try XCTUnwrap(backend.event(withID: "fixture-event-01")?.notes)
            XCTAssertTrue(notes.hasSuffix("END OF NOTES fixture-event-01"))
            XCTAssertTrue(notes.split(separator: "\n").count > 40)
        }
    }

    func testFixtureEveryMutationUsesTheSameMemoryRecordsAndFailureIsAtomic() async throws {
        let backend = panelBackend()
        let input = CalendarEventInput(title: "Created", start: date(day: 14, hour: 9), end: date(day: 14, hour: 10), isAllDay: false, calendarID: "fixture-events")
        let created = try await backend.saveEvent(input: input, eventID: nil)
        XCTAssertEqual(backend.event(withID: created.id), created)
        var edit = input
        edit.title = "Edited"
        let updated = try await backend.saveEvent(input: edit, eventID: created.id)
        XCTAssertEqual(updated.id, created.id)
        XCTAssertEqual(backend.event(withID: created.id)?.title, "Edited")
        let reminder = try await backend.createReminderRecord(title: "Created reminder", due: date(day: 14), listID: "fixture-reminders")
        await backend.setReminderCompleted(reminderID: reminder.id, completed: true)
        XCTAssertEqual(backend.event(withID: reminder.id)?.type, .reminder(completed: true))
        let priority = await backend.setReminderPriority(reminderID: "fixture-reminder-03", priority: 1)
        XCTAssertTrue(priority)
        XCTAssertNotNil(backend.event(withID: "fixture-reminder-03")?.priority)
        backend.writeFailure = .readOnlyCalendar
        do { _ = try await backend.completeReminder(id: reminder.id, completed: false); XCTFail("Expected injected failure") }
        catch { XCTAssertEqual(error as? CalendarMutationError, .readOnlyCalendar) }
        XCTAssertEqual(backend.event(withID: reminder.id)?.type, .reminder(completed: true))
        do { try await backend.deleteEvent(id: created.id); XCTFail("Expected injected failure") }
        catch { XCTAssertEqual(error as? CalendarMutationError, .readOnlyCalendar) }
        XCTAssertEqual(backend.event(withID: created.id), updated)
        backend.writeFailure = nil
        try await backend.deleteEvent(id: created.id)
        XCTAssertNil(backend.event(withID: created.id))
        XCTAssertNotNil(backend.event(withID: reminder.id))
    }

    func testReminderComponentsKeepPreciseTimeSourceZoneAndExplicitAllDayAcrossDST() throws {
        var source = Calendar(identifier: .gregorian)
        source.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let due = try XCTUnwrap(source.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 17, minute: 45, second: 12)))
        let input = CalendarReminderInput(title: "Timed", due: due, isAllDay: false, timeZoneIdentifier: source.timeZone.identifier)
        let components = try XCTUnwrap(input.dueDateComponents(calendar: testCalendar))
        XCTAssertEqual(components.hour, 17)
        XCTAssertEqual(components.minute, 45)
        XCTAssertEqual(components.second, 12)
        XCTAssertEqual(components.timeZone, source.timeZone)
        XCTAssertEqual(CalendarRecordDates.absoluteDate(from: components, fallback: testCalendar), due)
        var dateOnly = input
        dateOnly.isAllDay = true
        let dayComponents = try XCTUnwrap(dateOnly.dueDateComponents(calendar: testCalendar))
        XCTAssertNil(dayComponents.hour)
        XCTAssertNil(dayComponents.minute)
        XCTAssertEqual(dayComponents.timeZone, source.timeZone)
        XCTAssertEqual(CalendarRecordDates.absoluteDate(from: dayComponents, fallback: testCalendar), source.startOfDay(for: due))
        let start = try XCTUnwrap(CalendarRecordDates.absoluteDate(from: dayComponents, fallback: testCalendar))
        XCTAssertEqual(source.date(byAdding: .day, value: 1, to: start)?.timeIntervalSince(start), 23 * 3600)
    }

    func testReminderReadUsesComponentsZoneWithoutDependingOnComponentsCalendar() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var components = DateComponents(year: 2026, month: 10, day: 13, hour: 17, minute: 25)
        components.timeZone = zone
        var fallback = testCalendar
        fallback.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var source = Calendar(identifier: .gregorian)
        source.timeZone = zone
        XCTAssertEqual(CalendarRecordDates.absoluteDate(from: components, fallback: fallback), source.date(from: components))
        components.calendar = fallback
        XCTAssertEqual(CalendarRecordDates.absoluteDate(from: components, fallback: fallback), source.date(from: components), "显式组件时区优先于所携日历与当前时区")
    }

    func testEventMetadataResolutionPreservesLegacyValuesAndUnknownZone() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/original?token=literal"))
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var input = CalendarEventInput(title: "Legacy", start: date(day: 14, hour: 9), end: date(day: 14, hour: 10), isAllDay: false)
        let legacy = try input.resolvedMetadata(existingURL: url, existingTimeZone: zone)
        XCTAssertEqual(legacy.url, url)
        XCTAssertEqual(legacy.timeZone, zone)
        XCTAssertNil(try input.resolvedMetadata(existingURL: url, existingTimeZone: nil).timeZone)
        input.url = URL(string: "https://example.com/replacement")
        input.timeZoneIdentifier = "Asia/Tokyo"
        let replaced = try input.resolvedMetadata(existingURL: url, existingTimeZone: zone)
        XCTAssertEqual(replaced.url, input.url)
        XCTAssertEqual(replaced.timeZone?.identifier, "Asia/Tokyo")
    }

    func testEventAllDayValidationUsesExplicitSourceZoneInsteadOfCurrentZone() throws {
        var source = testCalendar
        source.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let start = try XCTUnwrap(source.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let end = try XCTUnwrap(source.date(byAdding: .day, value: 1, to: start))
        let input = CalendarEventInput(title: "DST all day", start: start, end: end, isAllDay: true, timeZoneIdentifier: source.timeZone.identifier)
        XCTAssertNoThrow(try input.validated(calendar: testCalendar))
        XCTAssertEqual(end.timeIntervalSince(start), 23 * 3600)
    }

    func testInvalidExplicitTimeZoneRejectsBothInputsWithDistinctErrors() throws {
        let event = CalendarEventInput(title: "Event", start: date(day: 14, hour: 9), end: date(day: 14, hour: 10), isAllDay: false, timeZoneIdentifier: "Mars/Olympus")
        XCTAssertThrowsError(try event.validated(calendar: testCalendar)) { XCTAssertEqual($0 as? CalendarMutationError, .invalidTimeZone) }
        let reminder = CalendarReminderInput(title: "Task", due: date(day: 14), isAllDay: true, timeZoneIdentifier: "Mars/Olympus")
        XCTAssertThrowsError(try reminder.dueDateComponents(calendar: testCalendar)) { XCTAssertEqual($0 as? CalendarMutationError, .invalidTimeZone) }
        XCTAssertNotEqual(CalendarMutationError.invalidTimeZone.localizedDescription, CalendarMutationError.wrongRecordType.localizedDescription)
        XCTAssertNotEqual(CalendarMutationError.unsupportedReminderInput.localizedDescription, CalendarMutationError.wrongRecordType.localizedDescription)
    }

    func testManagerAndProductionPanelRichReminderWriteRetainsEveryField() async throws {
        let backend = panelBackend()
        let manager = CalendarManager(service: backend, now: { self.date(day: 11) }, calendar: testCalendar, startMonitoring: false)
        let session = CalendarPanelSession(manager: manager)
        session.beginCreate(kind: .reminder, on: date(day: 14), calendarID: "fixture-reminders")
        session.draft?.title = "  Precise task  "
        session.draft?.start = date(day: 14, hour: 17).addingTimeInterval(25 * 60)
        session.draft?.isAllDay = false
        session.draft?.notes = "Original invitation notes"
        session.draft?.url = URL(string: "https://example.com/invitation?source=literal")
        session.draft?.timeZoneIdentifier = "Asia/Shanghai"
        let submitted = try XCTUnwrap(session.draft)
        let success = await session.save()
        XCTAssertTrue(success)
        let saved = try XCTUnwrap(backend.allRecords().first { $0.id.hasPrefix("fixture-created-") })
        XCTAssertEqual(saved.title, "Precise task")
        XCTAssertEqual(saved.start, submitted.start)
        XCTAssertFalse(saved.isAllDay)
        XCTAssertEqual(saved.notes, submitted.notes)
        XCTAssertEqual(saved.url, submitted.url)
        XCTAssertEqual(saved.timeZone?.identifier, submitted.timeZoneIdentifier)
        XCTAssertNil(session.draft)
        XCTAssertEqual(backend.writeAttempts, 1)
    }

    func testRichAllDayReminderReadbackAndInvalidZoneFailurePreserveDraft() async throws {
        var source = testCalendar
        source.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let due = try XCTUnwrap(source.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 17)))
        let backend = panelBackend()
        let input = CalendarReminderInput(title: "Date only", due: due, isAllDay: true, notes: "Source notes", url: URL(string: "https://example.com/source"), listID: "fixture-reminders", timeZoneIdentifier: source.timeZone.identifier)
        let saved = try await backend.createReminderRecord(input: input)
        XCTAssertEqual(saved.start, source.startOfDay(for: due))
        XCTAssertEqual(saved.end.timeIntervalSince(saved.start), 23 * 3600)
        XCTAssertTrue(saved.isAllDay)
        XCTAssertEqual(saved.notes, input.notes)
        XCTAssertEqual(saved.url, input.url)
        XCTAssertEqual(saved.timeZone, source.timeZone)
        let manager = CalendarManager(service: backend, now: { self.date(day: 11) }, calendar: testCalendar, startMonitoring: false)
        let session = CalendarPanelSession(manager: manager)
        session.beginCreate(kind: .reminder, on: date(day: 14), calendarID: "fixture-reminders")
        session.draft?.title = "Reject invalid source zone"
        session.draft?.notes = "Keep all fields"
        session.draft?.url = input.url
        session.draft?.isAllDay = false
        session.draft?.timeZoneIdentifier = "Mars/Olympus"
        let draft = session.draft
        let before = backend.allRecords()
        let success = await session.save()
        XCTAssertFalse(success)
        XCTAssertEqual(session.error, CalendarMutationError.invalidTimeZone.localizedDescription)
        XCTAssertEqual(session.draft, draft)
        XCTAssertEqual(backend.allRecords(), before)
    }

    func testManagerRichReminderPassesEntireInputToProviderAndDoesNotRefreshAfterFailure() async throws {
        let service = CalendarInteractionServiceFake()
        service.reminderRecord = record("timed", type: .reminder(completed: false))
        let manager = CalendarManager(service: service, now: { self.date(day: 11) }, calendar: testCalendar, startMonitoring: false)
        let input = CalendarReminderInput(title: "Task", due: date(day: 14, hour: 17), isAllDay: false, notes: "Notes", url: URL(string: "https://example.com/task"), listID: "explicit-list", timeZoneIdentifier: "Asia/Tokyo")
        _ = try await manager.createReminderRecord(input: input)
        XCTAssertEqual(service.lastReminderInput, input)
        let fetches = service.fetchCount
        service.writeError = .readOnlyCalendar
        do { _ = try await manager.createReminderRecord(input: input); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? CalendarMutationError, .readOnlyCalendar) }
        XCTAssertEqual(service.fetchCount, fetches)
    }

    func testLegacyReminderWriterOnlyAcceptsLosslessDateOnlyInputAndLeavesRichDraftOnFailure() async throws {
        let backend = panelBackend()
        let legacy = try await backend.createReminderRecord(title: "Legacy", due: date(day: 14, hour: 17), listID: "fixture-reminders")
        XCTAssertEqual(legacy.start, date(day: 14))
        XCTAssertTrue(legacy.isAllDay)
        XCTAssertNil(legacy.notes)
        XCTAssertNil(legacy.url)
        let input = CalendarReminderInput(title: "Legacy", due: date(day: 14, hour: 17), isAllDay: true)
        let components = try XCTUnwrap(input.dueDateComponents(calendar: testCalendar))
        XCTAssertNil(components.hour)
        XCTAssertNil(components.timeZone)
        let variants: [CalendarReminderInput] = [
            CalendarReminderInput(title: "Rich", due: date(day: 14), isAllDay: false),
            CalendarReminderInput(title: "Rich", due: date(day: 14), isAllDay: true, notes: "Notes"),
            CalendarReminderInput(title: "Rich", due: date(day: 14), isAllDay: true, url: URL(string: "https://example.com")),
            CalendarReminderInput(title: "Rich", due: date(day: 14), isAllDay: true, timeZoneIdentifier: "Asia/Tokyo")
        ]
        for variant in variants {
            XCTAssertThrowsError(try variant.legacyArguments()) { XCTAssertEqual($0 as? CalendarMutationError, .unsupportedReminderInput) }
        }
        var calls = 0
        let session = panelSession(service: backend, create: { title, due, id in
            calls += 1
            return try await backend.createReminderRecord(title: title, due: due, listID: id)
        })
        session.beginCreate(kind: .reminder, on: date(day: 14), calendarID: "fixture-reminders")
        session.draft?.title = "Rich"
        session.draft?.notes = "Do not drop"
        let draft = session.draft
        let success = await session.save()
        XCTAssertFalse(success)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(session.draft, draft)
        XCTAssertTrue(session.hasDirtyDraft)
        XCTAssertEqual(session.error, CalendarMutationError.unsupportedReminderInput.localizedDescription)
    }

    func testEventPanelLoadsOriginalMetadataAndSavesReplacementWithoutClearingLegacyValues() async throws {
        let backend = panelBackend()
        var input = CalendarEventInput(title: "Original", start: date(day: 14, hour: 9), end: date(day: 14, hour: 10), isAllDay: false, notes: "Notes", calendarID: "fixture-events", url: URL(string: "https://example.com/original"), timeZoneIdentifier: "America/Los_Angeles")
        let original = try await backend.saveEvent(input: input, eventID: nil)
        let session = panelSession(service: backend)
        session.beginEdit(original)
        XCTAssertEqual(session.draft?.url, original.url)
        XCTAssertEqual(session.draft?.timeZoneIdentifier, original.timeZone?.identifier)
        session.draft?.title = "Edited"
        XCTAssertTrue(session.hasDirtyDraft)
        let success = await session.save()
        XCTAssertTrue(success)
        let edited = try XCTUnwrap(backend.event(withID: original.id))
        XCTAssertEqual(edited.url, original.url)
        XCTAssertEqual(edited.timeZone, original.timeZone)
        input.url = nil
        input.timeZoneIdentifier = nil
        let legacy = try await backend.saveEvent(input: input, eventID: original.id)
        XCTAssertEqual(legacy.url, original.url)
        XCTAssertEqual(legacy.timeZone, original.timeZone)
        input.url = URL(string: "https://example.com/replaced")
        input.timeZoneIdentifier = "Asia/Tokyo"
        let replaced = try await backend.saveEvent(input: input, eventID: original.id)
        XCTAssertEqual(replaced.url, input.url)
        XCTAssertEqual(replaced.timeZone?.identifier, "Asia/Tokyo")
    }

    func testLegacyEventEditKeepsUnknownOriginalTimeZoneAndMetadataFailureIsAtomic() async throws {
        let source = CalendarModel(accountName: "Fixture", id: "fixture-events", title: "Events", color: .systemBlue, isSubscribed: false, isReminder: false)
        let original = EventModel(id: "unknown-zone", start: date(day: 14, hour: 9), end: date(day: 14, hour: 10), title: "Original", location: nil, notes: "Original notes", url: URL(string: "https://example.com/original"), isAllDay: false, type: .event(.unknown), calendar: source, participants: [], timeZone: nil, hasRecurrenceRules: false, priority: nil, conferenceURL: nil)
        let backend = CalendarInteractionMemoryService(records: [original], calendars: [source], calendar: testCalendar)
        let input = CalendarEventInput(title: "Legacy edit", start: original.start, end: original.end, isAllDay: false, notes: original.notes)
        let saved = try await backend.saveEvent(input: input, eventID: original.id)
        XCTAssertNil(saved.timeZone)
        XCTAssertEqual(saved.url, original.url)
        var rich = input
        rich.url = URL(string: "https://example.com/replaced")
        rich.timeZoneIdentifier = "Asia/Tokyo"
        backend.writeFailure = .readOnlyCalendar
        do { _ = try await backend.saveEvent(input: rich, eventID: original.id); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? CalendarMutationError, .readOnlyCalendar) }
        XCTAssertEqual(backend.event(withID: original.id), saved)
    }

    func testRichMetadataDoesNotBypassRestrictedEventOrReminderWritesAndFailuresKeepRecords() async throws {
        let backend = panelBackend(count: 18)
        let input = CalendarEventInput(title: "Bypass", start: date(day: 14, hour: 9), end: date(day: 14, hour: 10), isAllDay: false, calendarID: "fixture-events", url: URL(string: "https://example.com"), timeZoneIdentifier: "Asia/Tokyo")
        for id in ["fixture-event-04", "fixture-event-07", "fixture-event-10", "fixture-event-13", "fixture-event-16"] {
            let original = try XCTUnwrap(backend.event(withID: id))
            do { _ = try await backend.saveEvent(input: input, eventID: id); XCTFail("Restricted record must reject") }
            catch { XCTAssertEqual(error as? CalendarMutationError, original.modificationRestriction) }
            XCTAssertEqual(backend.event(withID: id), original)
        }
        backend.setAuthorization(.denied, for: .reminder)
        let reminder = CalendarReminderInput(title: "Rich", due: date(day: 14), isAllDay: false, notes: "Notes", url: input.url, listID: "fixture-reminders", timeZoneIdentifier: "Asia/Tokyo")
        let before = backend.allRecords()
        do { _ = try await backend.createReminderRecord(input: reminder); XCTFail("Denied access must reject") }
        catch { XCTAssertEqual(error as? CalendarMutationError, .accessDenied) }
        XCTAssertEqual(backend.allRecords(), before)
        backend.setAuthorization(.fullAccess, for: .reminder)
        backend.writeFailure = .readOnlyCalendar
        do { _ = try await backend.createReminderRecord(input: reminder); XCTFail("Injected failure must propagate") }
        catch { XCTAssertEqual(error as? CalendarMutationError, .readOnlyCalendar) }
        XCTAssertEqual(backend.allRecords(), before)
    }

    func testSourceZoneEditorAllDayConversionsAndDateChangesRemainSavableAcrossDST() throws {
        var source = testCalendar
        source.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        for (month, day, hours) in [(3, 8, 23.0), (11, 1, 25.0)] {
            let start = try XCTUnwrap(source.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9)))
            let end = try XCTUnwrap(source.date(from: DateComponents(year: 2026, month: month, day: day, hour: 10)))
            let draft = CalendarDraft(kind: .event, eventID: nil, originalDate: start, title: "Source zone", start: start, end: end, isAllDay: false, notes: "Keep notes", calendarID: "fixture-events", url: URL(string: "https://example.com/source"), timeZoneIdentifier: source.timeZone.identifier)
            let allDay = CalendarPanelDates.settingAllDay(true, in: draft, calendar: testCalendar)
            XCTAssertEqual(allDay.start, source.startOfDay(for: start))
            XCTAssertEqual(allDay.end.timeIntervalSince(allDay.start), hours * 3600)
            XCTAssertEqual(CalendarPanelDates.includedEnd(of: allDay, calendar: testCalendar), allDay.start)
            XCTAssertNoThrow(try allDay.eventInput(calendar: testCalendar))
            let nextDay = try XCTUnwrap(source.date(byAdding: .day, value: 1, to: start))
            let extended = CalendarPanelDates.settingEnd(nextDay, in: allDay, calendar: testCalendar)
            let changed = CalendarPanelDates.settingStart(nextDay, in: extended, calendar: testCalendar)
            XCTAssertEqual(changed.start, source.startOfDay(for: nextDay))
            XCTAssertEqual(CalendarPanelDates.includedEnd(of: changed, calendar: testCalendar), changed.start)
            XCTAssertNoThrow(try changed.eventInput(calendar: testCalendar))
            let timed = CalendarPanelDates.settingAllDay(false, in: allDay, calendar: testCalendar)
            XCTAssertEqual(timed.start, start)
            XCTAssertEqual(timed.end, end)
            XCTAssertNoThrow(try timed.eventInput(calendar: testCalendar))
            let moved = CalendarPanelDates.changingDay(nextDay, preservingTimeOf: start, calendar: CalendarPanelDates.sourceCalendar(for: draft, fallback: testCalendar))
            XCTAssertEqual(moved, nextDay)
            XCTAssertEqual(changed.url, draft.url)
            XCTAssertEqual(changed.notes, draft.notes)
            XCTAssertEqual(changed.timeZoneIdentifier, draft.timeZoneIdentifier)
        }
    }

    func testEditorNilSourceZoneKeepsLegacyFallbackAndSourceFormattingIsConsistent() throws {
        let draft = pageDraft(start: date(day: 11, hour: 9), end: date(day: 11, hour: 10))
        XCTAssertEqual(CalendarPanelDates.sourceCalendar(for: draft, fallback: testCalendar).timeZone, testCalendar.timeZone)
        let allDay = CalendarPanelDates.settingAllDay(true, in: draft, calendar: testCalendar)
        XCTAssertEqual(allDay.start, date(day: 11))
        XCTAssertEqual(allDay.end, date(day: 12))
        let extended = CalendarPanelDates.settingEnd(date(day: 13, hour: 12), in: allDay, calendar: testCalendar)
        let moved = CalendarPanelDates.settingStart(date(day: 12, hour: 18), in: extended, calendar: testCalendar)
        XCTAssertEqual(moved.start, date(day: 12))
        XCTAssertEqual(CalendarPanelDates.includedEnd(of: moved, calendar: testCalendar), date(day: 13))
        XCTAssertNoThrow(try moved.eventInput(calendar: testCalendar))
        var zoned = draft
        zoned.timeZoneIdentifier = "America/Los_Angeles"
        let source = CalendarPanelDates.sourceCalendar(for: zoned, fallback: testCalendar)
        let midnight = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
        let sourceLabel = CalendarPanelDates.formatted(midnight, allDay: true, calendar: source)
        XCTAssertEqual(sourceLabel, midnight.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, calendar: source, timeZone: source.timeZone)))
        XCTAssertNotEqual(sourceLabel, CalendarPanelDates.formatted(midnight, allDay: true, calendar: testCalendar))
    }

    func testSourceZoneEditorSharedConversionsReachProductionSessionSave() async throws {
        let backend = panelBackend()
        let manager = CalendarManager(service: backend, now: { self.date(day: 11) }, calendar: testCalendar, startMonitoring: false)
        let session = CalendarPanelSession(manager: manager)
        session.beginCreate(kind: .event, on: date(day: 14), calendarID: "fixture-events")
        var draft = try XCTUnwrap(session.draft)
        draft.title = "Cross-zone all day"
        draft.timeZoneIdentifier = "America/Los_Angeles"
        let source = CalendarPanelDates.sourceCalendar(for: draft, fallback: testCalendar)
        draft.start = try XCTUnwrap(source.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9)))
        draft.end = draft.start.addingTimeInterval(3600)
        draft = CalendarPanelDates.settingAllDay(true, in: draft, calendar: testCalendar)
        let included = try XCTUnwrap(source.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)))
        draft = CalendarPanelDates.settingEnd(included, in: draft, calendar: testCalendar)
        draft = CalendarPanelDates.settingStart(included, in: draft, calendar: testCalendar)
        session.draft = draft
        let saved = await session.save()
        XCTAssertTrue(saved)
        let event = try XCTUnwrap(backend.allRecords().first { $0.id.hasPrefix("fixture-created-") })
        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(event.start, source.startOfDay(for: included))
        XCTAssertEqual(event.end, source.date(byAdding: .day, value: 1, to: event.start))
        XCTAssertEqual(event.timeZone?.identifier, draft.timeZoneIdentifier)
        XCTAssertNil(session.draft)
    }

    func testReminderFirstDSTFoldReadsBackExactlyAndSecondFoldIsRejected() throws {
        let formatter = ISO8601DateFormatter()
        let first = try XCTUnwrap(formatter.date(from: "2026-11-01T08:30:00Z"))
        let second = try XCTUnwrap(formatter.date(from: "2026-11-01T09:30:00Z"))
        var input = CalendarReminderInput(title: "DST first", due: first, isAllDay: false, timeZoneIdentifier: "America/Los_Angeles")
        let components = try XCTUnwrap(input.dueDateComponents(calendar: testCalendar))
        XCTAssertEqual(components.hour, 1)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.timeZone?.identifier, "America/Los_Angeles")
        XCTAssertEqual(CalendarRecordDates.absoluteDate(from: components, fallback: testCalendar), first)
        input.due = second
        XCTAssertThrowsError(try input.dueDateComponents(calendar: testCalendar)) { XCTAssertEqual($0 as? CalendarMutationError, .unrepresentableReminderTime) }
        input.isAllDay = true
        let allDay = try XCTUnwrap(input.dueDateComponents(calendar: testCalendar))
        XCTAssertNil(allDay.hour)
        XCTAssertEqual(allDay.timeZone?.identifier, "America/Los_Angeles")
    }

    func testTimedReminderNormalFractionalDatesPreserveWholeSecondWithoutFalseRejection() throws {
        let formatter = ISO8601DateFormatter()
        for literal in ["2026-10-13T16:20:45Z", "2026-11-01T08:30:00Z"] {
            let second = try XCTUnwrap(formatter.date(from: literal))
            let due = second.addingTimeInterval(0.875)
            let input = CalendarReminderInput(title: "Fractional", due: due, isAllDay: false, timeZoneIdentifier: "America/Los_Angeles")
            let components = try XCTUnwrap(input.dueDateComponents(calendar: testCalendar))
            let readback = try XCTUnwrap(CalendarRecordDates.absoluteDate(from: components, fallback: testCalendar))
            XCTAssertEqual(readback, second)
            XCTAssertEqual(readback.timeIntervalSince1970.rounded(.down), due.timeIntervalSince1970.rounded(.down))
            XCTAssertEqual(components.timeZone?.identifier, "America/Los_Angeles")
        }
    }

    func testUnrepresentableReminderFoldKeepsEntireDraftAndWritesNoRecordThenValidTimeCanSave() async throws {
        let formatter = ISO8601DateFormatter()
        let backend = panelBackend()
        let manager = CalendarManager(service: backend, now: { self.date(day: 11) }, calendar: testCalendar, startMonitoring: false)
        let session = CalendarPanelSession(manager: manager)
        session.beginCreate(kind: .reminder, on: date(day: 14), calendarID: "fixture-reminders")
        session.draft?.title = "Second fold"
        session.draft?.isAllDay = false
        session.draft?.start = try XCTUnwrap(formatter.date(from: "2026-11-01T09:30:00Z"))
        session.draft?.notes = "Original invitation"
        session.draft?.url = URL(string: "https://example.com/original")
        session.draft?.timeZoneIdentifier = "America/Los_Angeles"
        let before = backend.allRecords()
        let submitted = session.draft
        let rejected = await session.save()
        XCTAssertFalse(rejected)
        XCTAssertEqual(session.draft, submitted)
        XCTAssertTrue(session.hasDirtyDraft)
        XCTAssertEqual(session.error, CalendarMutationError.unrepresentableReminderTime.localizedDescription)
        XCTAssertEqual(backend.allRecords(), before)
        session.draft?.start = try XCTUnwrap(formatter.date(from: "2026-11-01T08:30:00Z"))
        let accepted = await session.save()
        XCTAssertTrue(accepted)
        let reminder = try XCTUnwrap(backend.allRecords().first { $0.id.hasPrefix("fixture-created-") })
        XCTAssertEqual(reminder.start, formatter.date(from: "2026-11-01T08:30:00Z"))
        XCTAssertEqual(reminder.notes, submitted?.notes)
        XCTAssertEqual(reminder.url, submitted?.url)
        XCTAssertEqual(reminder.timeZone?.identifier, submitted?.timeZoneIdentifier)
    }

    func testFixtureAuthorizationIsInMemoryAndSharedManagerChoosesFixtureBeforeStore() async throws {
        XCTAssertTrue(CalendarInteractionFixtures.isEnabled)
        XCTAssertEqual(CalendarManager.shared.liveCalendarAuthorization, .fullAccess)
        XCTAssertEqual(CalendarManager.shared.liveReminderAuthorization, .fullAccess)
        let sharedID = try XCTUnwrap(CalendarInteractionFixtures.backend.allRecords().first?.id)
        XCTAssertEqual(CalendarManager.shared.event(withID: sharedID)?.id, sharedID)
        let sharedEvent = try XCTUnwrap(CalendarManager.shared.event(withID: sharedID))
        let openedCount = CalendarInteractionFixtures.backend.systemOpenedIDs.count
        CalendarInteractionFixtures.openSystemEvent(sharedEvent)
        XCTAssertEqual(CalendarInteractionFixtures.backend.systemOpenedIDs.count, openedCount + 1)
        XCTAssertEqual(CalendarInteractionFixtures.backend.systemOpenedIDs.last, sharedID)
        let backend = panelBackend()
        backend.setAuthorization(.writeOnly, for: .event)
        backend.setAuthorization(.denied, for: .reminder)
        let calendars = await backend.calendars()
        XCTAssertTrue(calendars.isEmpty)
        XCTAssertEqual(backend.defaultEventCalendarID(), "fixture-events")
        XCTAssertTrue(backend.writableReminderCalendars().isEmpty)
        let input = CalendarEventInput(title: "Write only creation", start: date(day: 14, hour: 9), end: date(day: 14, hour: 10), isAllDay: false, calendarID: "fixture-events")
        let created = try await backend.saveEvent(input: input, eventID: nil)
        XCTAssertNil(backend.event(withID: created.id))
        do { try await backend.deleteEvent(id: created.id); XCTFail("Existing records require full access") }
        catch { XCTAssertEqual(error as? CalendarMutationError, .accessDenied) }
        backend.setAuthorization(.fullAccess, for: .event)
        XCTAssertEqual(backend.event(withID: created.id), created)
        let reminderAccess = await backend.requestAccess(to: .reminder)
        let eventAccess = await backend.requestAccess(to: .event)
        XCTAssertFalse(reminderAccess)
        XCTAssertTrue(eventAccess)
    }
}

/// 完整假服务：没有 EKEventStore，授权及写入全部是内存值，无法改动用户记录。
private final class CalendarInteractionServiceFake: CalendarServiceProviding {
    var fetch: (Date, Date, [String]) async -> [EventModel] = { _, _, _ in [] }
    var fetchCount = 0
    var accessRequests = 0
    var savedRecord: EventModel?
    var reminderRecord: EventModel?
    var writeError: CalendarMutationError?
    var lastEventID: String?
    var lastListID: String?
    var lastReminderInput: CalendarReminderInput?
    var deletedID: String?

    func requestAccess() async -> Bool { accessRequests += 1; return true }
    func requestAccess(to type: EKEntityType) async -> Bool { accessRequests += 1; return true }
    func calendars() async -> [CalendarModel] { [] }
    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel] {
        fetchCount += 1
        return await fetch(start, end, calendars)
    }
    func setReminderCompleted(reminderID: String, completed: Bool) async { }
    func saveEvent(input: CalendarEventInput, eventID: String?) async throws -> EventModel {
        if let writeError { throw writeError }
        lastEventID = eventID
        return try XCTUnwrap(savedRecord)
    }
    func createReminderRecord(input: CalendarReminderInput) async throws -> EventModel {
        if let writeError { throw writeError }
        lastReminderInput = input
        lastListID = input.listID
        return try XCTUnwrap(reminderRecord)
    }
    func createReminderRecord(title: String, due: Date, listID: String?) async throws -> EventModel {
        if let writeError { throw writeError }
        lastListID = listID
        return try XCTUnwrap(reminderRecord)
    }
    func deleteEvent(id: String) async throws {
        if let writeError { throw writeError }
        deletedID = id
    }
    func deleteReminder(id: String) async throws {
        if let writeError { throw writeError }
        deletedID = id
    }
    func completeReminder(id: String, completed: Bool) async throws -> EventModel {
        if let writeError { throw writeError }
        return try XCTUnwrap(reminderRecord)
    }
    func event(withID id: String) -> EventModel? { savedRecord?.id == id ? savedRecord : reminderRecord }
    func writableEventCalendars() -> [CalendarModel] { [] }
    func writableReminderCalendars() -> [CalendarModel] { [] }
    func defaultEventCalendarID() -> String? { nil }
    var preferredReminderCalendarID: String? { nil }
    func authorizationStatus(for type: EKEntityType) -> EKAuthorizationStatus { .fullAccess }
    func setReminderPriority(reminderID: String, priority: Int) async -> Bool { false }
}

// MARK: - 独立通用 AI（只用内存配置、假秘密、离线 transport）

@MainActor
private final class AIConfigurationMemory: AIConfigurationPersistence {
    var data: Data?
    var readFails = false
    var writeFails = false
    var writeCount = 0
    var failedWriteNumbers: Set<Int> = []
    var attemptedWrites: [Data] = []
    func read() throws -> Data? {
        if readFails { throw AIError.configurationReadFailed }
        return data
    }
    func write(_ data: Data) throws {
        writeCount += 1
        attemptedWrites.append(data)
        if writeFails || failedWriteNumbers.contains(writeCount) {
            throw NSError(domain: "fixture-secret original-text", code: 1)
        }
        self.data = data
    }
}

@MainActor
private final class AISecretMemory: AISecretStore {
    var values: [UUID: String] = [:]
    var readFails = false
    var writeFails = false
    var deleteFails = false
    var writtenReferences: [UUID] = []
    var deletedReferences: [UUID] = []
    var deleteFailures: [UUID: Set<Int>] = [:]
    var failedDeleteNumbers: Set<Int> = []
    var deleteCounts: [UUID: Int] = [:]
    func read(reference: UUID) throws -> String? {
        if readFails { throw AIError.secretReadFailed }
        return values[reference]
    }
    func write(_ secret: String, reference: UUID) throws {
        writtenReferences.append(reference)
        if writeFails { throw AIError.secretWriteFailed }
        values[reference] = secret
    }
    func delete(reference: UUID) throws {
        deletedReferences.append(reference)
        deleteCounts[reference, default: 0] += 1
        if deleteFails || failedDeleteNumbers.contains(deletedReferences.count) ||
            deleteFailures[reference]?.contains(deleteCounts[reference]!) == true {
            throw NSError(domain: "fixture-secret original-text", code: 2)
        }
        values.removeValue(forKey: reference)
    }
}

@MainActor
private final class AITransportFake: AIHTTPTransport {
    var requests: [URLRequest] = []
    var limits: [Int] = []
    var handler: (URLRequest) async throws -> AIHTTPResponse = { _ in
        AIHTTPResponse(statusCode: 200, body: Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8))
    }
    func send(_ request: URLRequest, responseLimit: Int) async throws -> AIHTTPResponse {
        requests.append(request)
        limits.append(responseLimit)
        return try await handler(request)
    }
}

@MainActor
final class AIConfigurationTests: XCTestCase {
    private func profile(_ apiProtocol: AIProtocol = .openAICompatible) -> AIModelProfile {
        AIModelProfile(displayName: "自定义连接", apiProtocol: apiProtocol, baseURL: "https://fixture.invalid/v1", modelID: "test-model")
    }

    func testProfilesDefaultsAndSecretReferencesRoundTripWithoutSecretEncoding() throws {
        let memory = AIConfigurationMemory()
        let secrets = AISecretMemory()
        let store = try AIConfigurationStore(persistence: memory, secretStore: secrets)
        let text = profile()
        var vision = profile(.anthropic)
        vision.capabilities = [.text, .vision]
        try store.save(text, apiKey: "fixture-secret-text")
        try store.save(vision, apiKey: "fixture-secret-vision")
        try store.setDefault(text.id, for: .text)
        try store.setDefault(vision.id, for: .vision)
        let references = try store.profiles.map { try XCTUnwrap($0.secretReference) }
        XCTAssertEqual(Set(references).count, 2)
        let data = try XCTUnwrap(memory.data)
        let encoded = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(encoded.contains("fixture-secret"))
        let restored = try AIConfigurationStore(persistence: memory, secretStore: secrets)
        XCTAssertEqual(restored.configuration, store.configuration)
        XCTAssertEqual(try restored.profile(for: AIRequest(purpose: "text", messages: [])).id, text.id)
        XCTAssertEqual(try restored.profile(for: AIRequest(purpose: "vision", messages: [], requiredCapability: .vision)).id, vision.id)
        XCTAssertEqual(try restored.credential(for: restored.profiles[0]), "fixture-secret-text")
        try restored.remove(profileID: text.id)
        XCTAssertNil(restored.configuration.defaultTextProfileID)
        XCTAssertNil(secrets.values[references[0]])
        XCTAssertEqual(restored.profiles.count, 1)
    }

    func testMissingDefaultsCapabilityAndInvalidEndpointsAreExplicit() throws {
        let store = try AIConfigurationStore(persistence: AIConfigurationMemory(), secretStore: AISecretMemory())
        XCTAssertThrowsError(try store.profile(for: AIRequest(purpose: "test", messages: []))) {
            XCTAssertEqual($0 as? AIError, .missingDefault(.text))
        }
        let text = profile()
        try store.save(text)
        XCTAssertThrowsError(try store.setDefault(text.id, for: .vision)) {
            XCTAssertEqual($0 as? AIError, .capabilityMismatch)
        }
        XCTAssertThrowsError(try store.setDefault(UUID(), for: .text)) {
            XCTAssertEqual($0 as? AIError, .profileNotFound)
        }
        for endpoint in ["http://example.com", "https://name:password@example.com", "https://example.com/#fragment", "https://example.com/?key=secret", "file:///tmp/model", "https://"] {
            var invalid = text
            invalid.baseURL = endpoint
            XCTAssertThrowsError(try store.save(invalid), endpoint) {
                XCTAssertEqual($0 as? AIError, .invalidEndpoint)
            }
        }
        for endpoint in ["http://127.0.0.1:8080", "http://localhost:8080", "http://[::1]:8080"] {
            var local = text
            local.baseURL = endpoint
            XCTAssertNoThrow(try AIEndpoint.url(for: local))
        }
    }

    func testWriteFailuresDoNotChangeConfigurationAndCredentialCleanupIsObservable() throws {
        let memory = AIConfigurationMemory()
        let secrets = AISecretMemory()
        let store = try AIConfigurationStore(persistence: memory, secretStore: secrets)
        let text = profile()
        secrets.writeFails = true
        XCTAssertThrowsError(try store.save(text, apiKey: "fixture-secret")) {
            XCTAssertEqual($0 as? AIError, .secretWriteFailed)
        }
        XCTAssertTrue(store.profiles.isEmpty)
        secrets.writeFails = false
        memory.writeFails = true
        XCTAssertThrowsError(try store.save(text, apiKey: "fixture-secret")) {
            XCTAssertEqual($0 as? AIError, .configurationWriteFailed)
        }
        XCTAssertTrue(secrets.values.isEmpty)
        XCTAssertTrue(store.profiles.isEmpty)
        memory.writeFails = false
        try store.save(text, apiKey: "fixture-secret")
        let original = store.configuration
        secrets.deleteFails = true
        XCTAssertThrowsError(try store.remove(profileID: text.id)) {
            XCTAssertEqual($0 as? AIError, .secretDeleteFailed)
        }
        XCTAssertEqual(store.configuration, original)
        XCTAssertEqual(try JSONDecoder().decode(AIConfiguration.self, from: XCTUnwrap(memory.data)), original)
        secrets.readFails = true
        XCTAssertThrowsError(try store.credential(for: store.profiles[0])) {
            XCTAssertEqual($0 as? AIError, .secretReadFailed)
        }
    }

    func testCredentialReplacementAndRemovalAreExplicit() throws {
        let memory = AIConfigurationMemory()
        let secrets = AISecretMemory()
        let store = try AIConfigurationStore(persistence: memory, secretStore: secrets)
        let text = profile()
        try store.save(text, apiKey: "first")
        let first = try XCTUnwrap(store.profiles[0].secretReference)
        try store.save(text)
        XCTAssertEqual(store.profiles[0].secretReference, first)
        try store.save(text, apiKey: "second")
        XCTAssertNil(secrets.values[first])
        XCTAssertEqual(secrets.values.count, 1)
        try store.save(text, apiKey: "")
        XCTAssertNil(store.profiles[0].secretReference)
        XCTAssertTrue(secrets.values.isEmpty)
    }

    private func assertReplacementFailure(recoveryWriteFails: Bool, newSecretCleanupFails: Bool,
                                          expectedError: AIError) throws {
        let memory = AIConfigurationMemory()
        let secrets = AISecretMemory()
        let store = try AIConfigurationStore(persistence: memory, secretStore: secrets)
        var connection = profile()
        try store.save(connection, apiKey: "old-fixture-secret")
        let original = store.configuration
        let oldReference = try XCTUnwrap(store.profiles[0].secretReference)
        secrets.deleteFailures[oldReference] = [1]
        if recoveryWriteFails { memory.failedWriteNumbers = [3] }
        if newSecretCleanupFails { secrets.failedDeleteNumbers = [2] }
        connection.displayName = "changed fixture"
        do { try store.save(connection, apiKey: "new-fixture-secret"); XCTFail("Replacement must fail") }
        catch {
            XCTAssertEqual(error as? AIError, expectedError)
            for privateText in ["original-text", "old-fixture-secret", "new-fixture-secret", "fixture-secret"] {
                XCTAssertFalse(error.localizedDescription.contains(privateText))
            }
        }
        XCTAssertEqual(secrets.writtenReferences.count, 2)
        let newReference = try XCTUnwrap(secrets.writtenReferences.last)
        XCTAssertNotEqual(oldReference, newReference)
        XCTAssertEqual(store.configuration, original)
        XCTAssertEqual(memory.writeCount, 3)
        XCTAssertEqual(try JSONDecoder().decode(AIConfiguration.self, from: memory.attemptedWrites[2]), original)
        let disk = try JSONDecoder().decode(AIConfiguration.self, from: XCTUnwrap(memory.data))
        XCTAssertEqual(disk.profiles[0].secretReference, recoveryWriteFails ? newReference : oldReference)
        XCTAssertEqual(disk.profiles[0].displayName, recoveryWriteFails ? "changed fixture" : original.profiles[0].displayName)
        XCTAssertEqual(secrets.values[oldReference], "old-fixture-secret")
        if recoveryWriteFails || newSecretCleanupFails {
            XCTAssertEqual(secrets.values[newReference], "new-fixture-secret")
            XCTAssertEqual(Set(secrets.values.keys), [oldReference, newReference])
        } else {
            XCTAssertNil(secrets.values[newReference])
            XCTAssertEqual(Set(secrets.values.keys), [oldReference])
        }
        XCTAssertEqual(secrets.deletedReferences, recoveryWriteFails ? [oldReference] : [oldReference, newReference])
        XCTAssertEqual(secrets.deleteCounts[oldReference], 1)
        XCTAssertEqual(secrets.deleteCounts[newReference, default: 0], recoveryWriteFails ? 0 : 1)
    }

    func testReplacementOldSecretDeleteFailureRestoresDiskAndCleansNewReference() throws {
        try assertReplacementFailure(recoveryWriteFails: false, newSecretCleanupFails: false,
                                     expectedError: .secretDeleteFailed)
    }

    func testReplacementConfigurationRestoreFailureLeavesBothSecretsAndReportsRollback() throws {
        try assertReplacementFailure(recoveryWriteFails: true, newSecretCleanupFails: false,
                                     expectedError: .rollbackFailed)
    }

    func testReplacementNewReferenceCleanupFailureKeepsOriginalConfigAndReportsRollback() throws {
        try assertReplacementFailure(recoveryWriteFails: false, newSecretCleanupFails: true,
                                     expectedError: .rollbackFailed)
    }

    func testCorruptAndUnreadableConfigurationNeverPretendToLoad() throws {
        let memory = AIConfigurationMemory()
        memory.data = Data("invalid".utf8)
        XCTAssertThrowsError(try AIConfigurationStore(persistence: memory, secretStore: AISecretMemory())) {
            XCTAssertEqual($0 as? AIError, .invalidConfiguration)
        }
        memory.readFails = true
        XCTAssertThrowsError(try AIConfigurationStore(persistence: memory, secretStore: AISecretMemory())) {
            XCTAssertEqual($0 as? AIError, .configurationReadFailed)
        }
    }
}

@MainActor
final class AIServiceTests: XCTestCase {
    private let prompt = AIRequest(purpose: "fixture", messages: [
        AIMessage(role: .system, text: "instruction"),
        AIMessage(role: .user, text: "question", images: [AIImage(data: Data([1, 2, 3]), mimeType: "image/png")]),
        AIMessage(role: .assistant, text: "previous")
    ], requiredCapability: .vision, maxOutputTokens: 17)

    private func profile(_ apiProtocol: AIProtocol) -> AIModelProfile {
        AIModelProfile(displayName: "fixture", apiProtocol: apiProtocol, baseURL: "https://fixture.invalid", modelID: "any-model", capabilities: [.text, .vision])
    }

    private func service(_ transport: AITransportFake? = nil) throws -> AIService {
        AIService(configurationStore: try AIConfigurationStore(persistence: AIConfigurationMemory(), secretStore: AISecretMemory()), transport: transport)
    }

    func testFourProtocolsEncodeRolesImagesLimitsHeadersAndDecodeText() async throws {
        let responses: [AIProtocol: String] = [
            .openAICompatible: #"{"choices":[{"message":{"content":"answer"}}]}"#,
            .anthropic: #"{"content":[{"type":"text","text":"answer"},{"type":"tool_use","name":"ignored"}]}"#,
            .gemini: #"{"candidates":[{"content":{"parts":[{"thought":true,"text":"private"},{"text":"answer"}]}}]}"#,
            .ollama: #"{"message":{"content":"answer"},"done":true}"#
        ]
        for apiProtocol in AIProtocol.allCases {
            let fake = AITransportFake()
            fake.handler = { _ in AIHTTPResponse(statusCode: 200, body: Data(responses[apiProtocol]!.utf8)) }
            let ai = try service(fake)
            let response = try await ai.complete(prompt, profile: profile(apiProtocol), apiKey: "fixture-key")
            XCTAssertEqual(response.text, "answer")
            let request = try XCTUnwrap(fake.requests.first)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 30)
            XCTAssertEqual(fake.limits, [1_048_576])
            XCTAssertNil(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.query)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("fixture-key"))
            switch apiProtocol {
            case .openAICompatible:
                XCTAssertEqual(request.url?.path, "/v1/chat/completions")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
                XCTAssertEqual(body["max_tokens"] as? Int, 17)
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user", "assistant"])
                let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
                XCTAssertEqual((content[1]["image_url"] as? [String: String])?["url"], "data:image/png;base64,AQID")
            case .anthropic:
                XCTAssertEqual(request.url?.path, "/v1/messages")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "fixture-key")
                XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
                XCTAssertEqual(body["system"] as? String, "instruction")
                XCTAssertEqual(body["max_tokens"] as? Int, 17)
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
                XCTAssertEqual((content[1]["source"] as? [String: String])?["data"], "AQID")
            case .gemini:
                XCTAssertEqual(request.url?.path, "/v1beta/models/any-model:generateContent")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fixture-key")
                XCTAssertNotNil(body["systemInstruction"])
                XCTAssertEqual((body["generationConfig"] as? [String: Int])?["maxOutputTokens"], 17)
                let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
                XCTAssertEqual(contents.map { $0["role"] as? String }, ["user", "model"])
                let parts = try XCTUnwrap(contents[0]["parts"] as? [[String: Any]])
                XCTAssertEqual((parts[1]["inlineData"] as? [String: String])?["mimeType"], "image/png")
            case .ollama:
                XCTAssertEqual(request.url?.path, "/api/chat")
                XCTAssertEqual(body["stream"] as? Bool, false)
                XCTAssertEqual((body["options"] as? [String: Int])?["num_predict"], 17)
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                XCTAssertEqual(messages[1]["images"] as? [String], ["AQID"])
            }
        }
    }

    func testEndpointNormalizationAndProtocolIndependentConnections() throws {
        for (apiProtocol, bases, path) in [
            (AIProtocol.openAICompatible, ["https://fixture.invalid", "https://fixture.invalid/v1/", "https://fixture.invalid/v1/chat/completions"], "/v1/chat/completions"),
            (.anthropic, ["https://fixture.invalid", "https://fixture.invalid/v1", "https://fixture.invalid/v1/messages"], "/v1/messages"),
            (.gemini, ["https://fixture.invalid", "https://fixture.invalid/v1beta", "https://fixture.invalid/v1beta/models/old:generateContent"], "/v1beta/models/any-model:generateContent"),
            (.ollama, ["https://fixture.invalid", "https://fixture.invalid/api/", "https://fixture.invalid/api/chat"], "/api/chat")
        ] {
            for base in bases {
                var connection = profile(apiProtocol)
                connection.baseURL = base
                XCTAssertEqual(try AIEndpoint.url(for: connection).path, path)
            }
        }
        var prefixed = profile(.openAICompatible)
        prefixed.baseURL = "https://fixture.invalid/proxy/v1"
        XCTAssertEqual(try AIEndpoint.url(for: prefixed).path, "/proxy/v1/chat/completions")
    }

    func testErrorsAreSanitizedAndOversizeResponsesAreRejected() async throws {
        let fake = AITransportFake()
        let ai = try service(fake)
        for (response, expected) in [
            (AIHTTPResponse(statusCode: 401, body: Data("fixture-key original-text".utf8)), AIError.httpStatus(401)),
            (AIHTTPResponse(statusCode: 200, body: Data("not-json original-text".utf8)), .invalidResponse),
            (AIHTTPResponse(statusCode: 200, body: Data(#"{"choices":[]}"#.utf8)), .invalidResponse),
            (AIHTTPResponse(statusCode: 200, body: Data(repeating: 0, count: 1_048_577)), .responseTooLarge)
        ] {
            fake.handler = { _ in response }
            do { _ = try await ai.complete(prompt, profile: profile(.openAICompatible), apiKey: "fixture-key"); XCTFail() }
            catch {
                XCTAssertEqual(error as? AIError, expected)
                XCTAssertFalse(error.localizedDescription.contains("fixture-key"))
                XCTAssertFalse(error.localizedDescription.contains("original-text"))
            }
        }
        fake.handler = { _ in throw URLError(.timedOut) }
        do { _ = try await ai.complete(prompt, profile: profile(.openAICompatible), apiKey: nil); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .timedOut) }
        fake.handler = { _ in throw NSError(domain: "fixture-key original-text", code: 7) }
        do { _ = try await ai.complete(prompt, profile: profile(.openAICompatible), apiKey: nil); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .transportFailed) }
    }

    func testSnapshotDoesNotPersistAndRequestValidationRunsBeforeTransport() async throws {
        let memory = AIConfigurationMemory()
        let secrets = AISecretMemory()
        let fake = AITransportFake()
        let store = try AIConfigurationStore(persistence: memory, secretStore: secrets)
        let ai = AIService(configurationStore: store, transport: fake)
        _ = try await ai.complete(prompt, profile: profile(.openAICompatible), apiKey: "unsaved-secret")
        XCTAssertNil(memory.data)
        XCTAssertTrue(secrets.values.isEmpty)
        XCTAssertTrue(store.profiles.isEmpty)
        var textOnly = profile(.openAICompatible)
        textOnly.capabilities = [.text]
        do { _ = try await ai.complete(prompt, profile: textOnly, apiKey: nil); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .capabilityMismatch) }
        do { _ = try await ai.complete(prompt, profile: profile(.anthropic), apiKey: nil); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .missingCredential) }
        XCTAssertEqual(fake.requests.count, 1)
    }

    func testPublicHandleResolvesDefaultAndSecretFailuresBeforeSending() async throws {
        let memory = AIConfigurationMemory()
        let secrets = AISecretMemory()
        let fake = AITransportFake()
        let store = try AIConfigurationStore(persistence: memory, secretStore: secrets)
        let handle: any AIHandle = AIService(configurationStore: store, transport: fake)
        let request = AIRequest(purpose: "default", messages: [AIMessage(role: .user, text: "fixture")])
        do { _ = try await handle.complete(request); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .missingDefault(.text)) }
        let connection = profile(.openAICompatible)
        try store.save(connection, apiKey: "fixture-key")
        try store.setDefault(connection.id, for: .text)
        let response = try await handle.complete(request)
        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(fake.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        secrets.readFails = true
        do { _ = try await handle.complete(request); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .secretReadFailed) }
        secrets.readFails = false
        secrets.values.removeAll()
        do { _ = try await handle.complete(request); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .missingCredential) }
        XCTAssertEqual(fake.requests.count, 1)
    }

    func testConcurrentRequestsAndCallerCancellationAreIndependent() async throws {
        let fake = AITransportFake()
        fake.handler = { request in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let model = body["model"] as? String
            if model == "cancelled" { try await Task.sleep(nanoseconds: 60_000_000_000) }
            else { await Task.yield() }
            return AIHTTPResponse(statusCode: 200, body: Data(#"{"choices":[{"message":{"content":"survived"}}]}"#.utf8))
        }
        let ai = try service(fake)
        var cancelledProfile = profile(.openAICompatible)
        cancelledProfile.modelID = "cancelled"
        let first = Task { try await ai.complete(prompt, profile: cancelledProfile, apiKey: nil) }
        let second = Task { try await ai.complete(prompt, profile: profile(.openAICompatible), apiKey: nil) }
        while fake.requests.count < 2 { await Task.yield() }
        first.cancel()
        do { _ = try await first.value; XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .cancelled) }
        let survivor = try await second.value
        XCTAssertEqual(survivor.text, "survived")
        XCTAssertEqual(fake.requests.count, 2)
    }
}

/// 捕获全部 URL 请求并在内存提供字节，无法访问真实网络。
private final class AIOfflineURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/redirect" {
            let redirected = URLRequest(url: URL(string: "https://other-fixture.invalid/destination")!)
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": redirected.url!.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
            return
        }
        let headers = url.path == "/announced" ? ["Content-Length": "9"] : [:]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("1234".utf8))
        client?.urlProtocol(self, didLoad: Data("56789".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@MainActor
final class AIHTTPTransportTests: XCTestCase {
    func testCrossOriginRedirectIsRejectedByOfflineTransport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIOfflineURLProtocol.self]
        let transport = AIURLSessionTransport(configuration: configuration)
        var request = URLRequest(url: URL(string: "https://fixture.invalid/redirect")!)
        request.setValue("Bearer fixture-key", forHTTPHeaderField: "Authorization")
        do { _ = try await transport.send(request, responseLimit: 1024); XCTFail() }
        catch { XCTAssertEqual(error as? AIError, .redirectRejected) }
    }

    func testReceivingLimitRejectsAnnouncedAndChunkedBodiesWithoutRealNetwork() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIOfflineURLProtocol.self]
        let transport = AIURLSessionTransport(configuration: configuration)
        for path in ["announced", "chunked"] {
            let request = URLRequest(url: URL(string: "https://fixture.invalid/\(path)")!)
            do { _ = try await transport.send(request, responseLimit: 8); XCTFail(path) }
            catch { XCTAssertEqual(error as? AIError, .responseTooLarge, path) }
        }
        let response = try await transport.send(URLRequest(url: URL(string: "https://fixture.invalid/exact")!), responseLimit: 9)
        XCTAssertEqual(response.body, Data("123456789".utf8))
    }
}

/// 只在测试内登记的URLProtocol实例；每个唯一URL独立暂停、完成和统计停止。
private final class AIPausedHTTPControl: @unchecked Sendable {
    let started = XCTestExpectation(description: "offline URLProtocol started")
    let stopped = XCTestExpectation(description: "offline URLProtocol stopped")
    private let lock = NSLock()
    private var instance: AIPausableURLProtocol?
    private var starts = 0
    private var stops = 0

    var startCount: Int { lock.lock(); defer { lock.unlock() }; return starts }
    var stopCount: Int { lock.lock(); defer { lock.unlock() }; return stops }

    func begin(_ instance: AIPausableURLProtocol) {
        lock.lock()
        starts += 1
        if stops == 0 { self.instance = instance }
        lock.unlock()
        started.fulfill()
    }

    func stop() {
        lock.lock()
        stops += 1
        let firstStop = stops == 1
        instance = nil
        lock.unlock()
        if firstStop { stopped.fulfill() }
    }

    func complete(body: Data = Data("survivor".utf8)) {
        lock.lock()
        let instance = self.instance
        self.instance = nil
        lock.unlock()
        guard let instance, let url = instance.request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        instance.client?.urlProtocol(instance, didReceive: response, cacheStoragePolicy: .notAllowed)
        instance.client?.urlProtocol(instance, didLoad: body)
        instance.client?.urlProtocolDidFinishLoading(instance)
    }
}

private final class AIPausedHTTPRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var controls: [String: AIPausedHTTPControl] = [:]

    func set(_ control: AIPausedHTTPControl?, for token: String) {
        lock.lock()
        controls[token] = control
        lock.unlock()
    }

    func get(_ token: String) -> AIPausedHTTPControl? {
        lock.lock()
        defer { lock.unlock() }
        return controls[token]
    }
}

private final class AIPausableURLProtocol: URLProtocol {
    static let registry = AIPausedHTTPRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let control = Self.registry.get(request.url!.lastPathComponent) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        control.begin(self)
    }
    override func stopLoading() {
        if let token = request.url?.lastPathComponent { Self.registry.get(token)?.stop() }
    }
}

@MainActor
final class AIHTTPTransportCancellationTests: XCTestCase {
    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIPausableURLProtocol.self]
        return configuration
    }

    private func fixture() -> (String, AIPausedHTTPControl, URLRequest) {
        let token = UUID().uuidString
        let control = AIPausedHTTPControl()
        AIPausableURLProtocol.registry.set(control, for: token)
        return (token, control, URLRequest(url: URL(string: "https://fixture.invalid/\(token)")!))
    }

    func testAlreadyCancelledTransportTaskDoesNotStartURLProtocol() async throws {
        let (token, control, request) = fixture()
        defer { AIPausableURLProtocol.registry.set(nil, for: token) }
        let transport = AIURLSessionTransport(configuration: configuration())
        let operation = Task { try await transport.send(request, responseLimit: 1024) }
        operation.cancel()
        let result = await operation.result
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? AIError, .cancelled) }
        XCTAssertEqual(control.startCount, 0)
    }

    func testReceiverCancelledBeforeStartKeepsFirstTerminalResult() async throws {
        let (token, control, request) = fixture()
        defer { AIPausableURLProtocol.registry.set(nil, for: token) }
        let receiver = AILimitedHTTPReceiver(limit: 1024, configuration: configuration())
        receiver.finish(.failure(AIError.cancelled))
        receiver.finish(.success(AIHTTPResponse(statusCode: 200, body: Data())))
        let operation = Task<AIHTTPResponse, Error> {
            try await withCheckedThrowingContinuation { receiver.start(request: request, continuation: $0) }
        }
        let result = await operation.result
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? AIError, .cancelled) }
        XCTAssertEqual(control.startCount, 0)
    }

    func testProductionTransportCancellationStopsOnePausedRequestAndOtherContinues() async throws {
        let (firstToken, firstControl, firstRequest) = fixture()
        let (secondToken, secondControl, secondRequest) = fixture()
        defer {
            AIPausableURLProtocol.registry.set(nil, for: firstToken)
            AIPausableURLProtocol.registry.set(nil, for: secondToken)
        }
        let transport = AIURLSessionTransport(configuration: configuration())
        let firstDone = XCTestExpectation(description: "cancelled transport continuation completes")
        let first = Task {
            defer { firstDone.fulfill() }
            return try await transport.send(firstRequest, responseLimit: 1024)
        }
        let second = Task { try await transport.send(secondRequest, responseLimit: 1024) }
        await fulfillment(of: [firstControl.started, secondControl.started], timeout: 2)
        first.cancel()
        await fulfillment(of: [firstDone], timeout: 2)
        // 若生产取消被删，释放假响应使测试退出；先前的超时和成功结果都会使断言失败。
        firstControl.complete()
        let firstResult = await first.result
        XCTAssertThrowsError(try firstResult.get()) { XCTAssertEqual($0 as? AIError, .cancelled) }
        await fulfillment(of: [firstControl.stopped], timeout: 2)
        XCTAssertEqual(firstControl.stopCount, 1)
        XCTAssertEqual(secondControl.stopCount, 0)
        secondControl.complete()
        let survivor = try await second.value
        XCTAssertEqual(survivor.body, Data("survivor".utf8))
        XCTAssertEqual(firstControl.startCount, 1)
        XCTAssertEqual(secondControl.startCount, 1)
    }

    func testReceiverOwnTerminationAndLateCancellationCompleteContinuationOnce() async throws {
        let (token, control, request) = fixture()
        defer { AIPausableURLProtocol.registry.set(nil, for: token) }
        let receiver = AILimitedHTTPReceiver(limit: 1024, configuration: configuration())
        let completed = XCTestExpectation(description: "receiver continuation completes once")
        completed.assertForOverFulfill = true
        let operation = Task<AIHTTPResponse, Error> {
            defer { completed.fulfill() }
            return try await withCheckedThrowingContinuation { receiver.start(request: request, continuation: $0) }
        }
        await fulfillment(of: [control.started], timeout: 2)
        receiver.finish(.failure(AIError.responseTooLarge))
        receiver.finish(.failure(AIError.cancelled))
        await fulfillment(of: [completed, control.stopped], timeout: 2)
        let result = await operation.result
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? AIError, .responseTooLarge) }
        XCTAssertEqual(control.startCount, 1)
        XCTAssertEqual(control.stopCount, 1)
        // 模拟完成回调之后再次出现取消，终态不变，也不重入已恢复的continuation。
        receiver.finish(.failure(AIError.cancelled))
        control.complete()
    }
}

// MARK: - 通用 AI 设置与内核注入（离线，不启动界面）

@MainActor
private final class SettingsAIHandleFake: AIHandle {
    var requests: [AIRequest] = []
    func complete(_ request: AIRequest) async throws -> AIResponse {
        requests.append(request)
        return AIResponse(text: "injected")
    }
}

@MainActor
final class GeneralAISettingsTests: XCTestCase {
    private func profile() -> AIModelProfile {
        AIModelProfile(displayName: "fixture", apiProtocol: .openAICompatible,
                       baseURL: "https://fixture.invalid", modelID: "before")
    }

    func testFactoryAndCompatibleInitializerAcceptInjectedHandle() async throws {
        let fake = SettingsAIHandleFake()
        let manifest = StubModule.manifest
        let factory = ModuleContextFactory.make(manifest: manifest, redraw: {}, ai: fake)
        let explicit = ModuleContext(moduleID: manifest.id, host: factory.host,
                                     config: factory.config, logger: factory.logger, ui: factory.ui, ai: fake)
        let request = AIRequest(purpose: "injection", messages: [AIMessage(role: .user, text: "fixture")])
        let first = try await factory.ai.complete(request)
        let second = try await explicit.ai.complete(request)
        XCTAssertEqual(first.text, "injected")
        XCTAssertEqual(second.text, "injected")
        XCTAssertEqual(fake.requests, [request, request])
    }

    func testSettingsSaveImmediatelyChangesExistingModuleHandleAndReload() async throws {
        let memory = AIConfigurationMemory()
        let store = try AIConfigurationStore(persistence: memory, secretStore: AISecretMemory())
        let transport = AITransportFake()
        let runtime = GeneralAIRuntime(store: store, transport: transport)
        let context = ModuleContextFactory.make(manifest: StubModule.manifest, redraw: {}, ai: runtime.handle)
        let settings = GeneralAISettingsModel(runtime: runtime)
        settings.select(profile())
        settings.save()
        settings.setDefault(settings.draft.id, for: .text)
        let request = AIRequest(purpose: "shared", messages: [AIMessage(role: .user, text: "fixture")])
        _ = try await context.ai.complete(request)
        settings.draft.modelID = "after"
        settings.save()
        _ = try await context.ai.complete(request)
        let body = try XCTUnwrap(transport.requests.last?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "after")
        let restored = try AIConfigurationStore(persistence: memory, secretStore: AISecretMemory())
        XCTAssertEqual(restored.configuration, store.configuration)
        XCTAssertEqual(restored.profiles.first?.modelID, "after")
    }

    func testBlankFormKeyPreservesSecretAndExplicitClearRemovesIt() throws {
        let secrets = AISecretMemory()
        let store = try AIConfigurationStore(persistence: AIConfigurationMemory(), secretStore: secrets)
        let original = profile()
        try store.save(original, apiKey: "fixture-key")
        let saved = try XCTUnwrap(store.profiles.first)
        secrets.readFails = true
        let settings = GeneralAISettingsModel(runtime: GeneralAIRuntime(store: store, transport: AITransportFake()))
        settings.draft.modelID = "edited"
        settings.save()
        XCTAssertEqual(store.profiles.first?.secretReference, saved.secretReference)
        XCTAssertEqual(secrets.values[saved.secretReference!], "fixture-key")
        settings.clearStoredKey = true
        settings.save()
        XCTAssertNil(store.profiles.first?.secretReference)
        XCTAssertTrue(secrets.values.isEmpty)
    }

    func testUnsavedConnectionUsesFormSnapshotAndDoesNotPersist() async throws {
        let memory = AIConfigurationMemory()
        let store = try AIConfigurationStore(persistence: memory, secretStore: AISecretMemory())
        let transport = AITransportFake()
        let settings = GeneralAISettingsModel(runtime: GeneralAIRuntime(store: store, transport: transport))
        settings.select(profile())
        settings.draft.modelID = "unsaved-model"
        settings.apiKey = "unsaved-key"
        settings.testConnection()
        await settings.connectionTask?.value
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer unsaved-key")
        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "unsaved-model")
        XCTAssertNil(memory.data)
        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertEqual(settings.connectionFeedback, String(localized: "ai.settings.testSucceeded"))
    }

    func testExplicitConnectionTestReadsPreservedFakeCredentialAndReportsReadFailure() async throws {
        let secrets = AISecretMemory()
        let store = try AIConfigurationStore(persistence: AIConfigurationMemory(), secretStore: secrets)
        try store.save(profile(), apiKey: "saved-fixture")
        let transport = AITransportFake()
        let settings = GeneralAISettingsModel(runtime: GeneralAIRuntime(store: store, transport: transport))
        settings.testConnection()
        await settings.connectionTask?.value
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer saved-fixture")
        secrets.readFails = true
        settings.testConnection()
        XCTAssertEqual(settings.connectionFeedback, AIError.secretReadFailed.localizedDescription)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testEditingSwitchingAndLeavingInvalidateLateConnectionResults() async throws {
        for action in 0..<3 {
            let store = try AIConfigurationStore(persistence: AIConfigurationMemory(), secretStore: AISecretMemory())
            let transport = AITransportFake()
            var release: CheckedContinuation<AIHTTPResponse, Never>?
            let settings = GeneralAISettingsModel(runtime: GeneralAIRuntime(store: store, transport: transport))
            settings.select(profile())
            await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
                transport.handler = { _ in
                    await withCheckedContinuation { response in
                        release = response
                        started.resume()
                    }
                }
                settings.testConnection()
            }
            let task = settings.connectionTask
            let continuation = try XCTUnwrap(release)
            switch action {
            case 0: settings.draft.modelID = "changed"
            case 1: settings.select(nil)
            default: settings.invalidateConnectionTest()
            }
            continuation.resume(returning: AIHTTPResponse(statusCode: 200, body: Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8)))
            await task?.value
            XCTAssertNil(settings.connectionFeedback)
            XCTAssertFalse(settings.isTesting)
        }
    }

    func testSaveFailureIsVisibleAndDoesNotReplaceSavedProfile() throws {
        let memory = AIConfigurationMemory()
        let store = try AIConfigurationStore(persistence: memory, secretStore: AISecretMemory())
        let settings = GeneralAISettingsModel(runtime: GeneralAIRuntime(store: store, transport: AITransportFake()))
        settings.select(profile())
        memory.writeFails = true
        settings.save()
        XCTAssertEqual(settings.feedback, AIError.configurationWriteFailed.localizedDescription)
        XCTAssertTrue(settings.configuration.profiles.isEmpty)
    }

    func testUnconfiguredRuntimeAndCorruptConfigurationExposeDifferentErrors() async throws {
        let suite = "gourd.settings-fixture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let request = AIRequest(purpose: "missing", messages: [AIMessage(role: .user, text: "fixture")])
        let empty = GeneralAIRuntime(defaults: defaults, secretStore: AISecretMemory(), transport: AITransportFake())
        XCTAssertNil(empty.loadError)
        do { _ = try await empty.handle.complete(request); XCTFail("Expected missing default") }
        catch { XCTAssertEqual(error as? AIError, .missingDefault(.text)) }
        defaults.set(Data("broken".utf8), forKey: AIDefaultsConfigurationPersistence.key)
        let broken = GeneralAIRuntime(defaults: defaults, secretStore: AISecretMemory(), transport: AITransportFake())
        XCTAssertEqual(broken.loadError, .invalidConfiguration)
        XCTAssertNil(broken.configurationStore)
        XCTAssertEqual(GeneralAISettingsModel(runtime: broken).loadError, .invalidConfiguration)
        do { _ = try await broken.handle.complete(request); XCTFail("Expected load error") }
        catch { XCTAssertEqual(error as? AIError, .invalidConfiguration) }
    }

    func testGeneralAITabIsIndependentAndGroupedWithIntegrations() {
        XCTAssertTrue(SettingsTab.allCases.contains(.generalAI))
        XCTAssertEqual(SettingsTab.generalAI.group, .integrations)
        XCTAssertEqual(SettingsTab.screenAssistant.group, .productivity)
        XCTAssertFalse(SettingsTab.generalAI.title.isEmpty)
        XCTAssertFalse(SettingsTab.generalAI.systemImage.isEmpty)
    }
}

// MARK: - AI calendar T3: deterministic meeting evidence and URL dispatch

private enum MeetingInvitationFixtures {
    static let huawei = """
    蔡锰 邀请您参加会议
    主题: 需求沟通会议
    时间: 2026-10-13 10:00-10:45(GMT+08:00) 北京, 重庆, 香港特别行政区, 乌鲁木齐, 台北
    点击链接加入会议：https://meeting.huaweicloud.com/#/j/960724861
    使用会议ID入会：会议ID：940 948 346
    无密码
    电话语音入会: 拨打0518-80148838（中文）或021-60381524（中英双语），按照语音提示，输入会议号940948346，7#静音8#解除静音
    """
    static let tencent = """
    蔡锰 邀请您参加腾讯会议
    会议主题：测试项沟通会议
    会议时间：2026/10/13 10:00-10:30 (GMT+08:00) 中国标准时间 - 北京
    点击链接入会，或添加至会议列表：https://meeting.tencent.com/dm/VUYtCU0Ssrfz
    #腾讯会议：817-450-376
    复制该信息，打开手机腾讯会议即可参与
    """
    static let feishu = """
    飞书会议邀请
    需求沟通，点击链接：https://vc.feishu.cn/j/384462190
    """
    static let native = "cloudlink://welinksoftclient/h5page?page=joinConfByLink&conf_id=960724861&name=Fixture&server_url=meeting.huaweicloud.com&port=443&enter_code=&open_mic=false&open_camera=false"
    static let minimalNative = "cloudlink://welinksoftclient/h5page?page=joinConfByLink&conf_id=960724861&name=Fixture"
    static let huaweiHTTPS = "https://meeting.huaweicloud.com/#/j/960724861"
}

final class MeetingLinkResolverTests: XCTestCase {
    private let resolver = MeetingLinkResolver()

    func testThreeOriginalInvitationsKeepURLsAndSeparateHuaweiIDs() throws {
        let huawei = try XCTUnwrap(resolver.uniqueOpenTarget(text: MeetingInvitationFixtures.huawei))
        XCTAssertEqual(huawei.provider, .huawei)
        XCTAssertEqual(huawei.sourceURL?.absoluteString, MeetingInvitationFixtures.huaweiHTTPS)
        XCTAssertEqual(huawei.httpsURL, huawei.sourceURL)
        XCTAssertNil(huawei.nativeURL)
        XCTAssertEqual(huawei.urlIdentifier, "960724861")
        XCTAssertEqual(huawei.meetingCodes.map(\.value), ["940948346"])
        XCTAssertFalse(huawei.meetingCodes.contains { ["051880148838", "02160381524"].contains($0.value) })
        let tencent = try XCTUnwrap(resolver.uniqueOpenTarget(text: MeetingInvitationFixtures.tencent))
        XCTAssertEqual(tencent.provider, .tencent)
        XCTAssertEqual(tencent.sourceURL?.absoluteString, "https://meeting.tencent.com/dm/VUYtCU0Ssrfz")
        XCTAssertEqual(tencent.meetingCodes.map(\.value), ["817450376"])
        XCTAssertNil(tencent.nativeURL)
        let feishu = try XCTUnwrap(resolver.uniqueOpenTarget(text: MeetingInvitationFixtures.feishu))
        XCTAssertEqual(feishu.provider, .feishu)
        XCTAssertEqual(feishu.sourceURL?.absoluteString, "https://vc.feishu.cn/j/384462190")
        XCTAssertNil(feishu.nativeURL)
    }

    func testStrictRulesPreserveExistingProviders() throws {
        let fixtures: [(String, MeetingProvider)] = [
            ("https://us02web.zoom.us/j/123456789?pwd=fixture", .zoom),
            ("https://zoom.us/my/fixture.room", .zoom),
            ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_fixture/0?context=fixture", .teams),
            ("https://meet.google.com/abc-defg-hij", .meet),
            ("https://fixture.webex.com/meet/fixture", .webex),
            ("https://fixture.webex.com/fixture/j.php?MTID=fixture", .webex),
            ("https://facetime.apple.com/join?v=fixture", .facetime),
            ("https://global.gotomeeting.com/join/123456789", .gotomeeting),
            ("https://bluejeans.com/123456789", .bluejeans),
            ("https://whereby.com/fixture-room", .whereby),
            ("https://meet.jit.si/fixture-room", .jitsi),
            ("https://discord.gg/fixture", .discord),
            ("https://discord.com/invite/fixture", .discord),
            ("https://discord.com/channels/123/456", .discord)
        ]
        for (source, provider) in fixtures {
            let target = try XCTUnwrap(resolver.uniqueOpenTarget(text: source), source)
            XCTAssertEqual(target.provider, provider, source)
            XCTAssertEqual(ConferenceProvider.detect(from: try XCTUnwrap(URL(string: source))), conferenceProvider(provider), source)
            XCTAssertNil(target.nativeURL, source)
        }
    }

    private func conferenceProvider(_ provider: MeetingProvider) -> ConferenceProvider {
        switch provider {
        case .zoom: return .zoom
        case .teams: return .teams
        case .meet: return .meet
        case .webex: return .webex
        case .facetime: return .facetime
        case .gotomeeting: return .gotomeeting
        case .bluejeans: return .bluejeans
        case .whereby: return .whereby
        case .jitsi: return .jitsi
        case .discord: return .discord
        case .huawei: return .huawei
        case .tencent: return .tencent
        case .feishu: return .feishu
        }
    }

    func testMaliciousDomainsSchemesPathsAndCredentialsAreRejected() {
        let invalid = [
            "https://zoom.us.attacker.example/j/123456789", "https://evilzoom.us/j/123456789",
            "https://meeting.tencent.com.attacker.example/dm/fixture", "https://vc.feishu.cn.attacker.example/j/123",
            "https://attacker.example/meeting.tencent.com/dm/fixture", "https://meeting.tencent.com@attacker.example/dm/fixture",
            "https://user:secret@meeting.tencent.com/dm/fixture", "http://meeting.tencent.com/dm/fixture",
            "file://meeting.tencent.com/dm/fixture", "javascript://meeting.tencent.com/dm/fixture",
            "https://meeting.tencent.com:8443/dm/fixture", "https://zoom.us/pricing",
            "https://meeting.tencent.com/download", "https://vc.feishu.cn/settings", "https://meet.jit.si.evil/room",
            "https://jitsi.evil/room", "msteams://teams.microsoft.com/l/meetup-join/fixture/0"
        ]
        for source in invalid {
            XCTAssertTrue(resolver.resolve(text: source).isEmpty, source)
            if let url = URL(string: source) { XCTAssertEqual(ConferenceProvider.detect(from: url), .generic, source) }
        }
    }

    func testOriginalURLQueryBytesArePreservedAndProsePunctuationIsExcluded() throws {
        let original = "https://zoom.us/j/123456789?pwd=fixture)"
        XCTAssertEqual(try XCTUnwrap(resolver.uniqueOpenTarget(text: original)).httpsURL?.absoluteString, original)
        let source = "Click https://meeting.tencent.com/dm/VUYtCU0Ssrfz."
        XCTAssertEqual(try XCTUnwrap(resolver.uniqueOpenTarget(text: source)).httpsURL?.absoluteString,
                       "https://meeting.tencent.com/dm/VUYtCU0Ssrfz")
        XCTAssertTrue(resolver.resolve(text: "https://zoom.us/j/123456789?pwd=fixture%0D%0Ainjected").isEmpty)
    }

    func testNativeRequiredAndOptionalFieldsValidateWithoutInventingParameters() throws {
        let minimal = try XCTUnwrap(resolver.uniqueOpenTarget(text: MeetingInvitationFixtures.minimalNative))
        XCTAssertEqual(minimal.nativeURL?.absoluteString, MeetingInvitationFixtures.minimalNative)
        XCTAssertNil(minimal.httpsURL)
        let full = try XCTUnwrap(resolver.uniqueOpenTarget(text: MeetingInvitationFixtures.native))
        XCTAssertEqual(full.nativeURL?.absoluteString, MeetingInvitationFixtures.native)
        XCTAssertNotNil(resolver.uniqueOpenTarget(text: MeetingInvitationFixtures.native.replacingOccurrences(of: "joinConfByLink", with: "joinTmpConfByLink")))
        let invalid = [
            MeetingInvitationFixtures.minimalNative.replacingOccurrences(of: "&name=Fixture", with: ""),
            MeetingInvitationFixtures.native + "&conf_id=999999999",
            MeetingInvitationFixtures.native.replacingOccurrences(of: "open_mic=false", with: "open_mic=1"),
            MeetingInvitationFixtures.native.replacingOccurrences(of: "server_url=meeting.huaweicloud.com", with: "server_url=attacker.example"),
            MeetingInvitationFixtures.native.replacingOccurrences(of: "server_url=meeting.huaweicloud.com", with: "server_url=https%3A%2F%2Fmeeting.huaweicloud.com"),
            MeetingInvitationFixtures.native.replacingOccurrences(of: "port=443", with: "port=0"),
            MeetingInvitationFixtures.native.replacingOccurrences(of: "name=Fixture", with: "name=Fixture%0D%0AInjected"),
            MeetingInvitationFixtures.native + "&unexpected=fixture"
        ]
        for source in invalid { XCTAssertTrue(resolver.resolve(text: source).isEmpty, source) }
    }

    func testMultipleCandidatesRemainExplicitAndCodesNeverBecomeURLs() throws {
        let source = MeetingInvitationFixtures.tencent + "\n" + MeetingInvitationFixtures.feishu
        XCTAssertEqual(resolver.resolve(text: source).count, 2)
        XCTAssertNil(resolver.uniqueOpenTarget(text: source))
        let code = try XCTUnwrap(resolver.resolve(text: "会议号：817-450-376\n联系电话：13800138000").first)
        XCTAssertEqual(code.meetingCodes.map(\.value), ["817450376"])
        XCTAssertNil(code.sourceURL)
        XCTAssertFalse(code.canOpen)
        XCTAssertTrue(resolver.resolve(text: "拨打0518-80148838 或021-60381524 联系13800138000").isEmpty)
        XCTAssertTrue(resolver.resolve(text: String(repeating: "x", count: 20_001)).isEmpty)
    }

    func testNativeFallbackPairsOnlyUnambiguousSameIdentityRegardlessOfOrder() throws {
        for source in [
            MeetingInvitationFixtures.native + "\n" + MeetingInvitationFixtures.huaweiHTTPS,
            MeetingInvitationFixtures.huaweiHTTPS + "\n" + MeetingInvitationFixtures.native
        ] {
            let target = try XCTUnwrap(resolver.uniqueOpenTarget(text: source))
            XCTAssertEqual(target.nativeURL?.absoluteString, MeetingInvitationFixtures.native)
            XCTAssertEqual(target.httpsURL?.absoluteString, MeetingInvitationFixtures.huaweiHTTPS)
        }
        let differing = MeetingInvitationFixtures.native + "\nhttps://meeting.huaweicloud.com/#/j/940948346"
        XCTAssertEqual(resolver.resolve(text: differing).count, 2)
        XCTAssertNil(resolver.uniqueOpenTarget(text: differing))
    }

    func testTwoNativeCandidatesDoNotConsumeAnHTTPSCandidateInEitherSourceOrder() throws {
        let nativeA = "cloudlink://welinksoftclient/h5page?page=joinConfByLink&conf_id=960724861&name=A"
        let nativeB = "cloudlink://welinksoftclient/h5page?page=joinConfByLink&conf_id=960724861&name=B"
        let https = "https://meeting.huaweicloud.com/#/j/960724861"
        for sources in [[nativeA, nativeB, https], [https, nativeA, nativeB]] {
            let source = sources.joined(separator: "\n")
            let targets = resolver.resolve(text: source)
            XCTAssertEqual(targets.count, 3)
            XCTAssertEqual(targets.compactMap { $0.sourceURL?.absoluteString }, sources)
            XCTAssertEqual(targets.filter { $0.nativeURL != nil }.count, 2)
            XCTAssertTrue(targets.filter { $0.nativeURL != nil }.allSatisfy { $0.httpsURL == nil })
            XCTAssertEqual(targets.filter { $0.httpsURL != nil }.count, 1)
            XCTAssertNil(resolver.uniqueOpenTarget(text: source))
        }
    }

    func testCalendarExtractionUsesSameRulesAndDoesNotPickFirstOfMany() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.url = URL(string: "https://zoom.us.attacker.example/j/123456789")
        event.notes = MeetingInvitationFixtures.huawei
        XCTAssertEqual(event.extractConferenceURL()?.absoluteString, MeetingInvitationFixtures.huaweiHTTPS)
        event.location = "https://vc.feishu.cn/j/384462190"
        XCTAssertNil(event.extractConferenceURL())
    }

    func testUnhashedTencentLabelIsRecognizedInBothRegularExpressionCopies() {
        // 两处同义正则（resolver 与 CalendarMeetingEvidence）都必须认不带井号的「腾讯会议：」。
        let resolution = CalendarMeetingEvidence.resolve(textFields: ["腾讯会议：939130533"])
        XCTAssertEqual(resolution.count, 1)
        XCTAssertEqual(resolution.first?.meetingCodes.map(\.value), ["939130533"])
        XCTAssertEqual(CalendarMeetingEvidence.resolve(textFields: ["联系电话：13800138000"]).count, 0)
        let direct = resolver.resolve(text: "腾讯会议：939130533")
        XCTAssertEqual(direct.first?.meetingCodes.map(\.value), ["939130533"])
        XCTAssertFalse(direct.first?.canOpen ?? true)
        XCTAssertTrue(resolver.resolve(text: "联系电话：13800138000").isEmpty)
    }

    func testPasscodeAcceptsOnlySupportedLabelsAndRejectsPhoneAndOverlongValues() {
        XCTAssertEqual(resolver.passcode(in: "化小易会议号：939130533\n入会密码：696294"), "696294")
        XCTAssertEqual(resolver.passcode(in: "会议密码：Ab12"), "Ab12")
        XCTAssertEqual(resolver.passcode(in: "PASSWORD: 9988"), "9988")
        XCTAssertNil(resolver.passcode(in: "mypassword：1234"))
        XCTAssertNil(resolver.passcode(in: "入会密码：696 294"))
        XCTAssertNil(resolver.passcode(in: "会议号：939130533"))
        XCTAssertNil(resolver.passcode(in: "联系电话：13800138000"))
        XCTAssertNil(resolver.passcode(in: "入会密码：13800138000"))
        XCTAssertNil(resolver.passcode(in: "入会密码：请输入密码"))
        XCTAssertNil(resolver.passcode(in: "入会密码：abcdefghi"))
    }

    func testWemeetNativeDeepLinkValidatesExactShapeAndRejectsExtrasOrForeignHosts() throws {
        let official = try XCTUnwrap(URL(string: "wemeet://page/inmeeting?meeting_code=939130533"))
        XCTAssertEqual(MeetingLinkResolver.provider(for: official), .tencent)
        let target = try XCTUnwrap(resolver.uniqueOpenTarget(text: official.absoluteString))
        XCTAssertEqual(target.provider, .tencent)
        XCTAssertEqual(target.nativeURL?.absoluteString, official.absoluteString)
        XCTAssertNil(target.httpsURL)
        for source in [
            "wemeet://page/inmeeting?meeting_code=939130533&x=1",
            "wemeet://evil.example/page/inmeeting?meeting_code=939130533",
            "wemeet://page/other?meeting_code=939130533",
            "wemeet://page/inmeeting?meeting_code=12345",
            "wemeet://page/inmeeting?meeting_code=939130533&meeting_code=123456789"
        ] {
            XCTAssertTrue(resolver.resolve(text: source).isEmpty, source)
            XCTAssertNil(URL(string: source).flatMap { MeetingLinkResolver.provider(for: $0) }, source)
        }
    }

    func testResolverNoLongerDeclaresAIRecognitionSymbolsOrDependsOnAIHandle() throws {
        // V6：删除「用 AI 识别会议」的解析侧后，resolver 源码里不得再有 recognize / MeetingRecognitionError / AIHandle。
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DynamicIsland/services/MeetingLinkResolver.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertFalse(source.contains("func recognize("))
        XCTAssertFalse(source.contains("MeetingRecognitionError"))
        XCTAssertFalse(source.contains("AIHandle"))
    }
}

@MainActor
private final class MeetingFakeOpener: MeetingURLOpening {
    var urls: [URL] = []
    var replies: [Bool]
    var beforeReply: (() -> Void)?
    init(_ replies: [Bool]) { self.replies = replies }
    func open(_ url: URL) async -> Bool {
        urls.append(url)
        beforeReply?()
        return replies.isEmpty ? false : replies.removeFirst()
    }
}

@MainActor
final class MeetingOpeningTests: XCTestCase {
    func testHTTPSAcceptedMeansDispatchOnly() async throws {
        let target = try XCTUnwrap(MeetingLinkResolver().uniqueOpenTarget(text: MeetingInvitationFixtures.tencent))
        let fake = MeetingFakeOpener([true])
        let result = await MeetingOpening(opener: fake).open(target)
        XCTAssertEqual(result, .accepted(try XCTUnwrap(target.httpsURL)))
        XCTAssertEqual(fake.urls, [try XCTUnwrap(target.httpsURL)])
    }

    func testNativeRefusedUsesExactOriginalHTTPSFallbackAndBothRefusedAreExplicit() async throws {
        let target = try XCTUnwrap(MeetingLinkResolver().uniqueOpenTarget(text: MeetingInvitationFixtures.native + "\n" + MeetingInvitationFixtures.huaweiHTTPS))
        let fallback = MeetingFakeOpener([false, true])
        let result = await MeetingOpening(opener: fallback).open(target)
        XCTAssertEqual(result, .fallback(try XCTUnwrap(target.httpsURL)))
        XCTAssertEqual(fallback.urls, [try XCTUnwrap(target.nativeURL), try XCTUnwrap(target.httpsURL)])
        let refused = MeetingFakeOpener([false, false])
        let refusedResult = await MeetingOpening(opener: refused).open(target)
        XCTAssertEqual(refusedResult, .refused(refused.urls))
        XCTAssertEqual(refused.urls.count, 2)
        let native = MeetingFakeOpener([true])
        let accepted = await MeetingOpening(opener: native).open(target)
        XCTAssertEqual(accepted, .accepted(try XCTUnwrap(target.nativeURL)))
        XCTAssertEqual(native.urls.count, 1)
    }

    func testCopyOnlyAndCancelledTargetsNeverOpenAndCancellationPreventsFallback() async throws {
        let target = try XCTUnwrap(MeetingLinkResolver().uniqueOpenTarget(text: MeetingInvitationFixtures.native + "\n" + MeetingInvitationFixtures.huaweiHTTPS))
        let fake = MeetingFakeOpener([false, true])
        let cancelled = Task { await MeetingOpening(opener: fake).open(target) }
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        XCTAssertEqual(cancelledResult, .cancelled)
        XCTAssertTrue(fake.urls.isEmpty)
        let code = try XCTUnwrap(MeetingLinkResolver().resolve(text: "会议ID：940 948 346").first)
        let unavailable = await MeetingOpening(opener: fake).open(code)
        XCTAssertEqual(unavailable, .unavailable)
        XCTAssertTrue(fake.urls.isEmpty)
        fake.beforeReply = { withUnsafeCurrentTask { $0?.cancel() } }
        let during = Task { await MeetingOpening(opener: fake).open(target) }
        let result = await during.value
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(fake.urls, [try XCTUnwrap(target.nativeURL)])
    }

    func testOpenByNumberBuildsDispatchesAndReportsUnavailableForNumbersWithoutADeepLink() async throws {
        let expectedHuawei = try XCTUnwrap(MeetingJoinURLBuilder.huawei(confID: "939130533", displayName: "蔡锰", passcode: "696294"))
        let accepted = MeetingFakeOpener([true])
        let opened = await MeetingOpening(opener: accepted).openByNumber(
            provider: .huawei, number: "939 130-533", displayName: "蔡锰", passcode: "696294")
        XCTAssertEqual(opened, .accepted(expectedHuawei))
        XCTAssertEqual(accepted.urls, [expectedHuawei])
        XCTAssertEqual(MeetingLinkResolver.provider(for: expectedHuawei), .huawei)

        let expectedTencent = try XCTUnwrap(MeetingJoinURLBuilder.tencent(meetingCode: "817450376", passcode: nil))
        let refused = MeetingFakeOpener([false])
        let rejected = await MeetingOpening(opener: refused).openByNumber(
            provider: .tencent, number: "817-450-376", displayName: "", passcode: "696294")
        XCTAssertEqual(rejected, .refused([expectedTencent]))
        XCTAssertEqual(refused.urls, [expectedTencent])

        let unsupported: [(MeetingProvider, String)] = [
            (.tencent, "12345"), (.huawei, "1234567890123"), (.feishu, "939130533"), (.zoom, "939130533")
        ]
        for (provider, number) in unsupported {
            let fake = MeetingFakeOpener([true])
            let result = await MeetingOpening(opener: fake).openByNumber(
                provider: provider, number: number, displayName: "蔡锰", passcode: nil)
            XCTAssertEqual(result, .unavailable, "\(provider) \(number)")
            XCTAssertTrue(fake.urls.isEmpty, number)
        }

        let cancellable = MeetingFakeOpener([true])
        let cancelledByNumber = Task {
            await MeetingOpening(opener: cancellable).openByNumber(
                provider: .huawei, number: "939130533", displayName: "蔡锰", passcode: nil)
        }
        cancelledByNumber.cancel()
        let cancelledResult = await cancelledByNumber.value
        XCTAssertEqual(cancelledResult, .cancelled)
        XCTAssertTrue(cancellable.urls.isEmpty)
    }
}

final class MeetingJoinURLBuilderTests: XCTestCase {
    func testDigitsAcceptsOnlyNineToTwelveAsciiDigitsAfterStrippingSpacesAndHyphens() {
        XCTAssertEqual(MeetingJoinURLBuilder.digits("939130533"), "939130533")
        XCTAssertEqual(MeetingJoinURLBuilder.digits("1234567890"), "1234567890")
        XCTAssertEqual(MeetingJoinURLBuilder.digits("123456789012"), "123456789012")
        XCTAssertEqual(MeetingJoinURLBuilder.digits("940 948 346"), "940948346")
        XCTAssertEqual(MeetingJoinURLBuilder.digits("817-450-376"), "817450376")
        XCTAssertNil(MeetingJoinURLBuilder.digits("12345678"))
        XCTAssertNil(MeetingJoinURLBuilder.digits("12345"))
        XCTAssertNil(MeetingJoinURLBuilder.digits("1234567890123"))
        XCTAssertNil(MeetingJoinURLBuilder.digits("93913053a"))
        XCTAssertNil(MeetingJoinURLBuilder.digits(""))
        XCTAssertNil(MeetingJoinURLBuilder.digits("９３９１３０５３３"))
        XCTAssertNil(MeetingJoinURLBuilder.digits("会议号：939130533"))
    }

    func testHuaweiDeepLinkPassesResolverValidationWithExactParameterSetAndFallbackName() throws {
        let url = try XCTUnwrap(MeetingJoinURLBuilder.huawei(confID: "939 130-533", displayName: "蔡锰", passcode: "696294"))
        XCTAssertEqual(MeetingLinkResolver.provider(for: url), .huawei)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.map(\.name), ["page", "conf_id", "name", "enter_code"])
        XCTAssertEqual(items.first { $0.name == "page" }?.value, "joinConfByLink")
        XCTAssertEqual(items.first { $0.name == "conf_id" }?.value, "939130533")
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "蔡锰")
        XCTAssertEqual(items.first { $0.name == "enter_code" }?.value, "696294")
        for forbidden in ["server_url", "port", "open_mic", "open_camera"] {
            XCTAssertFalse(items.contains { $0.name == forbidden }, forbidden)
        }
        // 号码为空缺凭据时只写三件套，且这条 URL 回到证据层仍是一个可打开的原生候选。
        let minimal = try XCTUnwrap(MeetingJoinURLBuilder.huawei(confID: "960724861", displayName: "Gourd", passcode: nil))
        XCTAssertEqual(MeetingLinkResolver.provider(for: minimal), .huawei)
        XCTAssertEqual(URLComponents(url: minimal, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name),
                       ["page", "conf_id", "name"])
        XCTAssertTrue(MeetingLinkResolver().resolve(text: minimal.absoluteString).contains { $0.nativeURL == minimal })

        for blank in ["", "   ", "\n"] {
            let fallback = try XCTUnwrap(MeetingJoinURLBuilder.huawei(confID: "939130533", displayName: blank, passcode: nil), blank)
            XCTAssertEqual(MeetingLinkResolver.provider(for: fallback), .huawei, blank)
            XCTAssertEqual(URLComponents(url: fallback, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "name" }?.value, MeetingJoinURLBuilder.fallbackDisplayName, blank)
        }

        for invalid in [
            (confID: "12345", name: "蔡锰", passcode: Optional("696294")),
            (confID: "1234567890123", name: "蔡锰", passcode: nil),
            (confID: "939130533", name: "蔡锰\r\nInjected", passcode: nil),
            (confID: "939130533", name: "蔡锰", passcode: Optional("696\u{0007}294"))
        ] {
            XCTAssertNil(MeetingJoinURLBuilder.huawei(confID: invalid.confID, displayName: invalid.name, passcode: invalid.passcode),
                         "\(invalid.confID) \(invalid.name)")
        }
    }

    func testPercentEncodingKeepsInjectedQueryDelimitersInsideOneValue() throws {
        // 判平台不足以证明编码集合安全：编码集合若放宽到 `.urlQueryAllowed`，`&` / `=` 会退出转义，
        // 于是被注入的串自己长成新的 query 项，而 `provider(for:)` 依旧判 `.huawei`。所以这里必须
        // 断言参数个数与解码值本身。
        let injectedName = try XCTUnwrap(MeetingJoinURLBuilder.huawei(
            confID: "939130533", displayName: "A&enter_code=1", passcode: nil))
        XCTAssertEqual(MeetingLinkResolver.provider(for: injectedName), .huawei)
        let nameItems = try XCTUnwrap(URLComponents(url: injectedName, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(nameItems.map(\.name), ["page", "conf_id", "name"])
        XCTAssertEqual(nameItems.first { $0.name == "name" }?.value, "A&enter_code=1")

        let injectedPasscode = try XCTUnwrap(MeetingJoinURLBuilder.huawei(
            confID: "939130533", displayName: "蔡锰", passcode: "a&b=c"))
        XCTAssertEqual(MeetingLinkResolver.provider(for: injectedPasscode), .huawei)
        let passcodeItems = try XCTUnwrap(URLComponents(url: injectedPasscode, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(passcodeItems.map(\.name), ["page", "conf_id", "name", "enter_code"])
        XCTAssertEqual(passcodeItems.first { $0.name == "enter_code" }?.value, "a&b=c")
    }

    func testTencentDeepLinkIsExactShapeAndNeverGainsExtraParametersOrForeignHosts() throws {
        let url = try XCTUnwrap(MeetingJoinURLBuilder.tencent(meetingCode: "817-450-376", passcode: "696294"))
        XCTAssertEqual(url.absoluteString, "wemeet://page/inmeeting?meeting_code=817450376")
        XCTAssertEqual(MeetingLinkResolver.provider(for: url), .tencent)
        // 腾讯密码没有依据可写：带密码与不带密码产出同一条 URL。
        XCTAssertEqual(MeetingJoinURLBuilder.tencent(meetingCode: "939130533", passcode: nil)?.absoluteString,
                       MeetingJoinURLBuilder.tencent(meetingCode: "939130533", passcode: "1234")?.absoluteString)
        XCTAssertNil(MeetingJoinURLBuilder.tencent(meetingCode: "12345", passcode: nil))
        XCTAssertNil(MeetingJoinURLBuilder.tencent(meetingCode: "1234567890123", passcode: nil))
        XCTAssertNil(MeetingJoinURLBuilder.tencent(meetingCode: "93913053a", passcode: nil))
        // 只有华为与腾讯有两处可查依据，其余平台一律不拼。
        XCTAssertEqual(MeetingJoinURLBuilder.url(provider: .huawei, number: "939130533", displayName: "蔡锰", passcode: nil)?.scheme, "cloudlink")
        XCTAssertEqual(MeetingJoinURLBuilder.url(provider: .tencent, number: "939130533", displayName: "蔡锰", passcode: nil)?.scheme, "wemeet")
        for provider in [MeetingProvider.zoom, .teams, .meet, .webex, .feishu, .facetime, .gotomeeting, .bluejeans, .whereby, .jitsi, .discord] {
            XCTAssertNil(MeetingJoinURLBuilder.url(provider: provider, number: "939130533", displayName: "蔡锰", passcode: nil), provider.rawValue)
        }
        for source in ["wemeet://page/inmeeting?meeting_code=939130533&x=1",
                       "wemeet://evil.com/page/inmeeting?meeting_code=939130533"] {
            XCTAssertTrue(MeetingLinkResolver().resolve(text: source).isEmpty, source)
            XCTAssertNil(URL(string: source).flatMap { MeetingLinkResolver.provider(for: $0) }, source)
        }
    }
}

// MARK: - AI schedule candidates and revision-isolated generation

@MainActor
private final class ScheduleAIStub: AIHandle {
    var requests: [AIRequest] = []
    var response: String
    var responseForRequest: ((AIRequest) throws -> [String: Any])?
    init(_ object: [String: Any]) {
        response = String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
    func complete(_ request: AIRequest) async throws -> AIResponse {
        requests.append(request)
        if let responseForRequest {
            let data = try JSONSerialization.data(withJSONObject: responseForRequest(request))
            return AIResponse(text: String(decoding: data, as: UTF8.self))
        }
        return AIResponse(text: response)
    }
}

@MainActor
private final class ControlledScheduleParser: ScheduleParser {
    var continuation: CheckedContinuation<ScheduleCandidate, Error>?
    var text: String?
    var reference: Date?
    func parse(text: String, referenceDate: Date, timeZone: TimeZone) async throws -> ScheduleCandidate {
        self.text = text
        reference = referenceDate
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ candidate: ScheduleCandidate) { continuation?.resume(returning: candidate); continuation = nil }
    func fail() { continuation?.resume(throwing: ScheduleParsingError.invalidResponse); continuation = nil }
}

@MainActor
final class ScheduleGenerationTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private func date(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func output(date: String? = "2026-10-13", evidence: String? = "明天", start: String? = "17:00", startEvidence: String? = "下午五点", end: String? = nil, endEvidence: String? = nil, url: String? = nil, zone: String = "Asia/Shanghai", allDay: Bool = false) -> [String: Any] {
        ["title": "周会", "date": date as Any? ?? NSNull(), "dateEvidence": evidence as Any? ?? NSNull(),
         "start": start as Any? ?? NSNull(), "startEvidence": startEvidence as Any? ?? NSNull(),
         "end": end as Any? ?? NSNull(), "endEvidence": endEvidence as Any? ?? NSNull(),
         "isAllDay": allDay, "location": "", "notes": "", "url": url as Any? ?? NSNull(), "timeZoneIdentifier": zone]
    }
    private func parse(_ text: String, output object: [String: Any], reference: Date? = nil) async throws -> (ScheduleCandidate, ScheduleAIStub) {
        let ai = ScheduleAIStub(object)
        let candidate = try await ScheduleParsing(ai: ai).parse(text: text, referenceDate: reference ?? date(12, hour: 12), timeZone: calendar.timeZone)
        XCTAssertEqual(ai.requests.count, 1)
        XCTAssertEqual(ai.requests[0].purpose, "schedule-draft")
        XCTAssertEqual(ai.requests[0].messages.last?.text, text)
        XCTAssertTrue(ai.requests[0].messages[0].text.contains("Asia/Shanghai"))
        return (candidate, ai)
    }
    private func candidate() -> ScheduleCandidate {
        ScheduleCandidate(title: "Generated", date: date(13), start: date(13, hour: 17), end: date(13, hour: 18), isAllDay: false, location: "Room", notes: "Summary", url: URL(string: "https://example.com/task"), timeZoneIdentifier: "Asia/Shanghai", confirmations: [])
    }
    private func session(_ backend: CalendarInteractionMemoryService) -> CalendarPanelSession {
        CalendarPanelSession(selectedDate: date(12), calendar: calendar, now: { self.date(12, hour: 12) },
                             saveEvent: { try await backend.saveEvent(input: $0, eventID: $1) },
                             createReminder: { try await backend.createReminderRecord(input: $0) },
                             deleteEvent: { try await backend.deleteEvent(id: $0) },
                             completeReminder: { try await backend.completeReminder(id: $0, completed: $1) },
                             event: { backend.event(withID: $0) })
    }
    private func backend() -> CalendarInteractionMemoryService {
        CalendarInteractionFixtures.makeBackend(count: 0, on: date(12), calendar: calendar)
    }
    private func wait(_ parser: ControlledScheduleParser) async {
        for _ in 0..<100 where parser.continuation == nil { await Task.yield() }
        XCTAssertNotNil(parser.continuation)
    }

    func testInitialManualDraftKeepsLegacySavePathAndInjectedCalendarModuleHandle() async throws {
        let backend = backend(), session = session(backend)
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        XCTAssertFalse(session.hasDirtyDraft)
        XCTAssertEqual(session.draft?.generationMode, .manual)
        session.draft?.title = "Manual"
        let saved = await session.save(); XCTAssertTrue(saved)
        let ai = ScheduleAIStub(output())
        let context = ModuleContextFactory.make(manifest: CalendarModule.manifest, redraw: {}, ai: ai)
        let module = CalendarModule(context: context, session: session)
        try await module.activate()
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        session.updateSourceText("明天下午五点进行周会")
        await session.parseSource()
        XCTAssertEqual(ai.requests.count, 1)
        XCTAssertEqual(session.generationState, .ready)
        await module.deactivate()
    }
    func testExplicitGMTContradictionAndInventedAllDayFail() async {
        for (text, object) in [
            ("明天下午五点 GMT+09:00", output()),
            ("明天进行周会", output(start: nil, startEvidence: nil, allDay: true))
        ] {
            do { _ = try await parse(text, output: object); XCTFail() }
            catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidEvidence) }
        }
    }
    func testExpiredSuccessCannotPopulateReplacementDraft() async {
        let backend = backend(), session = session(backend), parser = ControlledScheduleParser()
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        session.updateSourceText("old")
        let request = Task { await session.parseSource(using: parser) }; await wait(parser)
        session.discardDraft()
        session.beginCreate(kind: .reminder, on: date(14), calendarID: "fixture-reminders")
        parser.finish(candidate()); await request.value
        XCTAssertEqual(session.draft?.title, "")
        XCTAssertEqual(session.draft?.sourceText, "")
        XCTAssertEqual(session.draft?.start, date(14))
        XCTAssertEqual(session.generationState, .idle)
    }
    func testConfirmationStateIsDirtyAndGuardedOutsideSessionSave() async throws {
        let backend = backend(), session = session(backend)
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        session.draft?.title = "Manual"
        session.updateSourceText("unknown date")
        XCTAssertThrowsError(try XCTUnwrap(session.draft).eventInput(calendar: calendar)) {
            XCTAssertEqual($0 as? ScheduleParsingError, .confirmationRequired)
        }
        session.useManualEntry()
        session.confirmSource(.date)
        XCTAssertThrowsError(try XCTUnwrap(session.draft).eventInput(calendar: calendar))
        session.confirmSource(.time)
        XCTAssertNoThrow(try XCTUnwrap(session.draft).eventInput(calendar: calendar))
        XCTAssertTrue(session.hasDirtyDraft)
    }

    func testPreciseNaturalLanguageUsesAIAndDefaultsOneHourWithoutRecurrence() async throws {
        let (value, _) = try await parse("明天下午五点进行周会", output: output())
        XCTAssertEqual(value.start, date(13, hour: 17))
        XCTAssertEqual(value.end, date(13, hour: 18))
        XCTAssertTrue(value.confirmations.isEmpty)
    }
    func testWeekdayMorningHasDateButNoInventedClock() async throws {
        let (value, _) = try await parse("本周四上午开发xxx需求", output: output(date: "2026-10-15", evidence: "本周四", start: nil, startEvidence: nil))
        XCTAssertEqual(value.date, date(15))
        XCTAssertNil(value.start)
        XCTAssertNil(value.end)
        XCTAssertEqual(value.confirmations, [.time])
        do {
            _ = try await parse("本周四上午开发xxx需求", output: output(date: "2026-10-15", evidence: "本周四", start: "09:00", startEvidence: "上午"))
            XCTFail("A vague period must not substantiate 09:00")
        } catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidEvidence) }
    }
    func testMissingDateAndTimeRequireConfirmation() async throws {
        let (value, _) = try await parse("开发需求", output: output(date: nil, evidence: nil, start: nil, startEvidence: nil))
        XCTAssertNil(value.date)
        XCTAssertEqual(value.confirmations, [.date, .time])
    }
    func testHuaweiAndTencentInvitationsUseAIAndOriginalLinks() async throws {
        for (text, dateText, end, link) in [
            (MeetingInvitationFixtures.huawei, "2026-10-13", "10:45", MeetingInvitationFixtures.huaweiHTTPS),
            (MeetingInvitationFixtures.tencent, "2026/10/13", "10:30", "https://meeting.tencent.com/dm/VUYtCU0Ssrfz")
        ] {
            let (value, _) = try await parse(text, output: output(evidence: dateText, start: "10:00", startEvidence: "10:00", end: end, endEvidence: end, url: link))
            XCTAssertEqual(value.start, date(13, hour: 10))
            XCTAssertEqual(value.url?.absoluteString, link)
            XCTAssertTrue(value.confirmations.isEmpty)
            XCTAssertEqual(value.url, MeetingLinkResolver().uniqueOpenTarget(text: text)?.sourceURL)
        }
    }
    func testYearlessFeishuInvitationAndRelativeConflictRequireDateConfirmation() async throws {
        let text = """
        蔡锰邀请你加入飞书视频会议
        会议主题：AI先锋队项目汇报
        会议时间：10月13日 (明天) 15:00 - 16:30 (GMT+8)
        会议 ID：384 462 190
        会议链接：https://vc.feishu.cn/j/384462190
        手机拨号一键入会
        +862122504720,,384462190
        4008208888,,384462190
        """
        for reference in [date(12), date(13)] {
            let (value, _) = try await parse(text, output: output(evidence: "10月13日", start: "15:00", startEvidence: "15:00", end: "16:30", endEvidence: "16:30", url: "https://vc.feishu.cn/j/384462190"), reference: reference)
            XCTAssertEqual(value.start, date(13, hour: 15))
            XCTAssertEqual(value.confirmations, [.date])
        }
        let (conflict, _) = try await parse("2026-10-13 (明天) 15:00", output: output(evidence: "2026-10-13", start: "15:00", startEvidence: "15:00"), reference: date(13))
        XCTAssertEqual(conflict.confirmations, [.date])
    }
    func testModelChoosingRelativeDateCannotHideYearlessInvitationConflict() async throws {
        let (value, _) = try await parse("10月13日 (明天) 下午五点", output: output(date: "2026-10-14"), reference: date(13))
        XCTAssertEqual(value.date, date(14))
        XCTAssertEqual(value.confirmations, [.date])
    }
    func testURLPrefixAndFabricationAreRejected() async {
        for url in ["https://meeting.tencent.com/dm/VUYt", "https://meeting.tencent.com/dm/invented"] {
            do {
                _ = try await parse(MeetingInvitationFixtures.tencent, output: output(evidence: "2026/10/13", start: "10:00", startEvidence: "10:00", url: url))
                XCTFail("Only a complete original token is evidence")
            } catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidEvidence) }
        }
    }
    func testStrictSchemaAndInvalidDateRejected() async {
        var extra = output()
        extra["recurrence"] = "weekly"
        for object in [extra, output(date: "2026-02-30")] {
            do { _ = try await parse("明天下午五点进行周会", output: object); XCTFail() }
            catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidResponse) }
        }
    }
    func testSourceLimitFailsBeforeAI() async {
        let ai = ScheduleAIStub(output())
        do {
            _ = try await ScheduleParsing(ai: ai).parse(text: String(repeating: "字", count: 20_001), referenceDate: date(12), timeZone: calendar.timeZone)
            XCTFail()
        } catch { XCTAssertEqual(error as? ScheduleParsingError, .sourceTooLarge) }
        XCTAssertTrue(ai.requests.isEmpty)
    }
    func testExplicitZoneUsesAbsoluteTimeAndReferenceWeekCrossesMonth() async throws {
        let (value, _) = try await parse("明天 17:00 GMT+09:00", output: output(startEvidence: "17:00", zone: "Asia/Tokyo"))
        XCTAssertEqual(value.start, date(13, hour: 16))
        XCTAssertEqual(value.timeZoneIdentifier, "Asia/Tokyo")
        let (week, _) = try await parse("本周四上午开发需求", output: output(date: "2026-10-29", evidence: "本周四", start: nil, startEvidence: nil), reference: date(31))
        XCTAssertEqual(week.date, date(29))
    }
    func testInFlightEditsPreservedAndDepartureDoesNotReopenEditor() async throws {
        let backend = backend(), session = session(backend), parser = ControlledScheduleParser()
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        session.updateSourceText("明天下午五点进行周会")
        XCTAssertTrue(session.hasDirtyDraft)
        let request = Task { await session.parseSource(using: parser) }
        await wait(parser)
        XCTAssertEqual(parser.reference, date(12, hour: 12))
        session.draft?.title = "Manual title"
        session.draft?.notes = "Manual notes"
        session.draft?.start = date(14, hour: 11)
        session.suspend()
        XCTAssertFalse(session.shouldProtectAutoClose)
        parser.finish(candidate())
        await request.value
        XCTAssertEqual(session.route, .list)
        XCTAssertEqual(session.draft?.title, "Manual title")
        XCTAssertEqual(session.draft?.notes, "Manual notes")
        XCTAssertEqual(session.draft?.start, date(14, hour: 11))
        XCTAssertEqual(session.draft?.confirmations, [.date, .time])
    }
    func testSourceChangeImmediatelyBlocksSaveAndStaleSuccessCannotClearIt() async {
        let backend = backend(), session = session(backend), parser = ControlledScheduleParser()
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        session.draft?.title = "Initial"
        session.updateSourceText("明天下午五点进行周会")
        let request = Task { await session.parseSource(using: parser) }
        await wait(parser)
        session.updateSourceText("本周四上午开发需求")
        XCTAssertEqual(session.generationState, .debouncing)
        let saved = await session.save()
        XCTAssertFalse(saved)
        parser.finish(candidate())
        await request.value
        XCTAssertEqual(session.draft?.title, "Initial")
        XCTAssertEqual(session.draft?.generationMode, .required)
    }
    func testConfirmedCandidateSourceRevisionBlocksDuringDebounceFailureAndClear() async {
        let backend = backend(), session = session(backend), parser = ControlledScheduleParser()
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        session.updateSourceText("明天下午五点进行周会")
        let first = Task { await session.parseSource(using: parser) }; await wait(parser)
        var ambiguous = candidate(); ambiguous.confirmations = [.date]
        parser.finish(ambiguous); await first.value
        session.confirmSource(.date)
        XCTAssertTrue(session.draft?.confirmations.isEmpty == true)
        session.updateSourceText("上午开会")
        let debounceSave = await session.save(); XCTAssertFalse(debounceSave)
        let second = Task { await session.parseSource(using: parser) }; await wait(parser)
        parser.fail(); await second.value
        let failureSave = await session.save(); XCTAssertFalse(failureSave)
        session.updateSourceText("")
        let clearedSave = await session.save(); XCTAssertFalse(clearedSave)
        XCTAssertEqual(session.draft?.generationMode, .required)
    }
    func testCancelManualFallbackRequiresCurrentDateAndTimeConfirmation() async {
        let backend = backend(), session = session(backend), parser = ControlledScheduleParser()
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        session.draft?.title = "Manual"
        session.updateSourceText("上午开会")
        let request = Task { await session.parseSource(using: parser) }; await wait(parser)
        session.cancelSourceParsing()
        session.confirmSource(.date); session.confirmSource(.time)
        let cancelledSave = await session.save(); XCTAssertFalse(cancelledSave)
        session.useManualEntry()
        let unconfirmedSave = await session.save(); XCTAssertFalse(unconfirmedSave)
        session.confirmSource(.date); session.confirmSource(.time)
        parser.fail(); await request.value
        XCTAssertEqual(session.generationState, .idle)
        let saved = await session.save(); XCTAssertTrue(saved)
    }
    func testRetryAndNewDraftIsolateLateError() async {
        let backend = backend(), session = session(backend), first = ControlledScheduleParser(), second = ControlledScheduleParser()
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        session.updateSourceText("old")
        let old = Task { await session.parseSource(using: first) }; await wait(first)
        let retry = Task { await session.parseSource(using: second) }; await wait(second)
        second.finish(candidate()); await retry.value
        first.fail(); await old.value
        XCTAssertEqual(session.generationState, .ready)
        XCTAssertNil(session.generationError)
        let third = ControlledScheduleParser()
        let abandoned = Task { await session.parseSource(using: third) }; await wait(third)
        session.discardDraft()
        session.beginCreate(kind: .reminder, on: date(14), calendarID: "fixture-reminders")
        third.fail(); await abandoned.value
        XCTAssertEqual(session.draft?.kind, .reminder)
        XCTAssertEqual(session.generationState, .idle)
        XCTAssertNil(session.generationError)
    }
    func testGeneratedReminderPreservesFullMetadataAndOriginalNotes() async throws {
        let backend = backend(), session = session(backend), parser = ControlledScheduleParser()
        session.beginCreate(kind: .reminder, on: date(12), calendarID: "fixture-reminders")
        let source = "明天下午五点进行周会"
        session.updateSourceText(source)
        let request = Task { await session.parseSource(using: parser) }; await wait(parser)
        parser.finish(candidate()); await request.value
        let input = try XCTUnwrap(session.draft).reminderInput()
        XCTAssertEqual(input.due, date(13, hour: 17))
        XCTAssertFalse(input.isAllDay)
        XCTAssertEqual(input.timeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(input.notes, "Summary\n\n" + source)
        XCTAssertEqual(input.url, candidate().url)
        let saved = await session.save(); XCTAssertTrue(saved)
        XCTAssertEqual(session.route, .list, "保存成功后回列表（T6）")
        let savedRecord = try XCTUnwrap(backend.allRecords().last { $0.id.hasPrefix("fixture-created") })
        XCTAssertEqual(savedRecord.start, input.due)
        XCTAssertEqual(savedRecord.notes, input.notes)
        XCTAssertEqual(savedRecord.url, input.url)
        XCTAssertEqual(savedRecord.timeZone?.identifier, input.timeZoneIdentifier)
    }
    func testGeneratedReminderSecondDSTFoldRejectedBeforeWriter() async {
        let backend = backend(), session = session(backend), parser = ControlledScheduleParser()
        session.beginCreate(kind: .reminder, on: date(12), calendarID: "fixture-reminders")
        session.updateSourceText("2026-11-01 01:30 America/Los_Angeles")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let secondFold = utc.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9, minute: 30))!
        var value = candidate()
        value.start = secondFold; value.end = secondFold.addingTimeInterval(3600)
        value.timeZoneIdentifier = "America/Los_Angeles"
        let request = Task { await session.parseSource(using: parser) }; await wait(parser)
        parser.finish(value); await request.value
        let saved = await session.save(); XCTAssertFalse(saved)
        XCTAssertNotNil(session.draft)
        XCTAssertEqual(session.error, CalendarMutationError.unrepresentableReminderTime.localizedDescription)
    }

    func testUnicodeSourceDatesNeverIndexUnconvertedComponents() async throws {
        for evidence in ["２０２６-１０-１３", "٢٠٢٦-١٠-١٣", "2026年10月13日"] {
            let (value, _) = try await parse("明天下午五点，参考日期" + evidence, output: output())
            XCTAssertEqual(value.date, date(13))
            XCTAssertTrue(value.confirmations.isEmpty)
            let (selected, _) = try await parse(evidence + " 下午五点", output: output(evidence: evidence))
            XCTAssertEqual(selected.date, date(13))
        }
        let (conflict, _) = try await parse("明天下午五点，参考日期２０２６-１０-１４", output: output())
        XCTAssertEqual(conflict.confirmations, [.date])
    }
    func testInvalidSourceDateCannotNormalizeIntoConfirmedCandidate() async throws {
        for source in ["2026-02-30", "2026年02月30日", "2月30日", "2/30", "2026-13-02", "2026-00-13"] {
            let (value, _) = try await parse(source + " 17:00", output: output(date: "2026-03-02", evidence: source, startEvidence: "17:00"))
            XCTAssertTrue(value.confirmations.contains(.date), source)
        }
    }
    func testWholeSourceNumericMonthDayAndWeekdayConflictsCannotBeOmitted() async throws {
        for text in ["10/12（明天）下午五点", "10-12（明天）下午五点", "本周四（明天）下午五点", "１０/１２（明天）下午五点"] {
            let (value, _) = try await parse(text, output: output())
            XCTAssertTrue(value.confirmations.contains(.date), text)
        }
        let (same, _) = try await parse("10/13（明天）下午五点", output: output())
        XCTAssertTrue(same.confirmations.contains(.date), "The year is missing even when the hints agree")
    }
    func testRelativeDatesUseReferenceZoneBeforeConstructingSourceZone() async throws {
        let westReference = date(13, hour: 0, minute: 30)
        let (west, _) = try await parse("明天 17:00 America/New_York", output: output(date: "2026-10-14", startEvidence: "17:00", zone: "America/New_York"), reference: westReference)
        XCTAssertEqual(ISO8601DateFormatter().string(from: try XCTUnwrap(west.start)), "2026-10-14T21:00:00Z")
        XCTAssertTrue(west.confirmations.isEmpty)
        do {
            _ = try await parse("明天 17:00 America/New_York", output: output(startEvidence: "17:00", zone: "America/New_York"), reference: westReference)
            XCTFail("Source-zone yesterday must not shift the relative day")
        } catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidEvidence) }
        let eastReference = date(12, hour: 23, minute: 30)
        let (east, _) = try await parse("明天 17:00 Pacific/Auckland", output: output(startEvidence: "17:00", zone: "Pacific/Auckland"), reference: eastReference)
        XCTAssertEqual(ISO8601DateFormatter().string(from: try XCTUnwrap(east.start)), "2026-10-13T04:00:00Z")
        XCTAssertTrue(east.confirmations.isEmpty)
        let (week, _) = try await parse("本周四 17:00 America/New_York", output: output(date: "2026-10-15", evidence: "本周四", startEvidence: "17:00", zone: "America/New_York"), reference: westReference)
        XCTAssertEqual(ISO8601DateFormatter().string(from: try XCTUnwrap(week.start)), "2026-10-15T21:00:00Z")
    }
    func testExplicitOffsetUsesSourceClockAfterDSTTransition() async throws {
        let (value, _) = try await parse("2026-11-01 17:00 GMT-08:00 America/Los_Angeles", output: output(date: "2026-11-01", evidence: "2026-11-01", startEvidence: "17:00", zone: "America/Los_Angeles"))
        XCTAssertEqual(ISO8601DateFormatter().string(from: try XCTUnwrap(value.start)), "2026-11-02T01:00:00Z")
        XCTAssertTrue(value.confirmations.isEmpty)
    }
    func testPartialClockEvidenceCannotDiscardAfternoonContext() async throws {
        let (wrong, _) = try await parse("明天下午10:00开会", output: output(start: "10:00", startEvidence: "10:00"))
        XCTAssertTrue(wrong.confirmations.contains(.time))
        let (correct, _) = try await parse("明天下午10:00开会", output: output(start: "22:00", startEvidence: "10:00"))
        XCTAssertEqual(correct.start, date(13, hour: 22))
        XCTAssertTrue(correct.confirmations.isEmpty)
    }
    func testUnresolvedModifierOrApproximationRetainsTimeConfirmation() async throws {
        for text in ["明天下午约10:00开会", "明天10:00 PM开会", "明天10:00左右开会", "明天晚上3:00开会"] {
            let (value, _) = try await parse(text, output: output(start: text.contains("3:00") ? "03:00" : "10:00", startEvidence: text.contains("3:00") ? "3:00" : "10:00"))
            XCTAssertTrue(value.confirmations.contains(.time), text)
        }
    }
    func testExplicitEndOmissionDoesNotUseDefaultOneHour() async throws {
        for text in ["明天 10:00-12:00开会", "明天 10:00到12:00开会", "明天 10:00开始，12:00结束", "明天 10:00开会两小时"] {
            let (value, _) = try await parse(text, output: output(start: "10:00", startEvidence: "10:00"))
            XCTAssertNil(value.end, text)
            XCTAssertTrue(value.confirmations.contains(.time), text)
        }
        let (range, _) = try await parse("明天 10:00-12:00开会", output: output(start: "10:00", startEvidence: "10:00", end: "12:00", endEvidence: "12:00"))
        XCTAssertEqual(range.end, date(13, hour: 12))
        XCTAssertTrue(range.confirmations.isEmpty)
    }
    func testRangePeriodInheritanceAndMismatchedEndRequireConfirmation() async throws {
        let text = "明天下午10:00-11:00开会"
        let (correct, _) = try await parse(text, output: output(start: "22:00", startEvidence: "10:00", end: "23:00", endEvidence: "11:00"))
        XCTAssertEqual(correct.start, date(13, hour: 22))
        XCTAssertEqual(correct.end, date(13, hour: 23))
        XCTAssertTrue(correct.confirmations.isEmpty)
        let (wrong, _) = try await parse("明天 10:00-12:00开会", output: output(start: "10:00", startEvidence: "10:00", end: "11:00", endEvidence: "12:00"))
        XCTAssertTrue(wrong.confirmations.contains(.time))
    }
    func testWholeSourceIndependentClocksRequireConfirmationRegardlessOfSelectedStart() async throws {
        for (text, start) in [
            ("2026-10-14 17:00开会，改到18:00，19:00结束", "17:00"),
            ("2026-10-14 17:00开会，改到18:00，19:00结束", "18:00"),
            ("2026-10-14 17:00开始，19:00结束，20:00复盘", "17:00")
        ] {
            let (value, _) = try await parse(text, output: output(date: "2026-10-14", evidence: "2026-10-14", start: start, startEvidence: start, end: "19:00", endEvidence: "19:00"))
            XCTAssertEqual(value.confirmations, [.time], text + " selected " + start)
        }
        let (control, _) = try await parse("2026-10-14 17:00开会，19:00结束", output: output(date: "2026-10-14", evidence: "2026-10-14", startEvidence: "17:00", end: "19:00", endEvidence: "19:00"))
        XCTAssertEqual(control.start, date(14, hour: 17))
        XCTAssertEqual(control.end, date(14, hour: 19))
        XCTAssertTrue(control.confirmations.isEmpty)
    }
    func testInvitationNumericMetadataDoesNotBecomeIndependentClockConflict() async throws {
        let feishu = MeetingInvitationFixtures.feishu + """

        会议时间：2026-10-13 15:00 - 16:30 (GMT+08:00)
        会议 ID：384 462 190
        手机拨号一键入会：+862122504720,,384462190 或 4008208888,,384462190
        """
        for (text, evidence, start, end, url) in [
            (MeetingInvitationFixtures.huawei, "2026-10-13", "10:00", "10:45", MeetingInvitationFixtures.huaweiHTTPS),
            (MeetingInvitationFixtures.tencent, "2026/10/13", "10:00", "10:30", "https://meeting.tencent.com/dm/VUYtCU0Ssrfz"),
            (feishu, "2026-10-13", "15:00", "16:30", "https://vc.feishu.cn/j/384462190")
        ] {
            let (value, _) = try await parse(text, output: output(evidence: evidence, start: start, startEvidence: start, end: end, endEvidence: end, url: url))
            XCTAssertTrue(value.confirmations.isEmpty, text)
            XCTAssertEqual(value.url?.absoluteString, url)
        }
    }
    func testRealParserSessionBlocksConflictingClocksBeforeWriterUntilExplicitConfirmation() async {
        for (text, start, conflict) in [
            ("2026-10-14 17:00开会，改到18:00，19:00结束", "17:00", true),
            ("2026-10-14 17:00开会，改到18:00，19:00结束", "18:00", true),
            ("2026-10-14 17:00开始，19:00结束，20:00复盘", "17:00", true),
            ("2026-10-14 17:00开会，19:00结束", "17:00", false)
        ] {
            let backend = backend(), session = session(backend)
            session.configureAI(ScheduleAIStub(output(date: "2026-10-14", evidence: "2026-10-14", start: start, startEvidence: start, end: "19:00", endEvidence: "19:00")))
            session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
            session.updateSourceText(text)
            await session.parseSource()
            XCTAssertEqual(session.generationState, .ready)
            XCTAssertEqual(session.draft?.confirmations, conflict ? [.time] : [])
            XCTAssertEqual(backend.writeAttempts, 0)
            let saved = await session.save()
            XCTAssertEqual(saved, !conflict)
            XCTAssertEqual(backend.writeAttempts, conflict ? 0 : 1)
            if conflict {
                XCTAssertEqual(session.error, ScheduleParsingError.confirmationRequired.localizedDescription)
                XCTAssertNotNil(session.draft)
                session.confirmSource(.time)
                let confirmedSave = await session.save()
                XCTAssertTrue(confirmedSave)
                XCTAssertEqual(backend.writeAttempts, 1)
            }
        }
    }
    func testRealParserSessionFreezesReferenceInstantAndZoneAcrossRetryAndCancellation() async throws {
        let backend = backend()
        let firstInstant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-12T16:30:00Z"))
        var clockNow = firstInstant
        let session = CalendarPanelSession(selectedDate: firstInstant, calendar: calendar, now: { clockNow },
            saveEvent: { try await backend.saveEvent(input: $0, eventID: $1) },
            createReminder: { try await backend.createReminderRecord(input: $0) },
            deleteEvent: { try await backend.deleteEvent(id: $0) },
            completeReminder: { try await backend.completeReminder(id: $0, completed: $1) },
            event: { backend.event(withID: $0) })
        let ai = ScheduleAIStub(output())
        // The fake follows each actual request's relative-date context, so a zone
        // change would reproduce the previous one-day drift through the real parser.
        ai.responseForRequest = { request in
            let prompt = try XCTUnwrap(request.messages.first?.text)
            let instantText = try XCTUnwrap(prompt.components(separatedBy: "Reference instant: ").last?.components(separatedBy: ". Reference IANA time zone: ").first)
            let zoneText = try XCTUnwrap(prompt.components(separatedBy: "Reference IANA time zone: ").last?.components(separatedBy: ".").first)
            let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: instantText))
            var referenceCalendar = Calendar(identifier: .gregorian)
            referenceCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: zoneText))
            let tomorrow = try XCTUnwrap(referenceCalendar.date(byAdding: .day, value: 1, to: instant))
            let formatter = DateFormatter()
            formatter.calendar = referenceCalendar
            formatter.timeZone = referenceCalendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return self.output(date: formatter.string(from: tomorrow), startEvidence: "17:00", zone: "America/New_York")
        }
        session.configureAI(ai)
        session.beginCreate(kind: .event, on: date(13), calendarID: "fixture-events")
        session.updateSourceText("明天 17:00 America/New_York")
        await session.parseSource()
        let expectedStart = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T21:00:00Z"))
        XCTAssertEqual(session.draft?.start, expectedStart)
        XCTAssertEqual(session.draft?.timeZoneIdentifier, "America/New_York")
        clockNow = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-14T16:30:00Z"))
        await session.parseSource()
        XCTAssertEqual(session.draft?.start, expectedStart)
        XCTAssertEqual(session.draft?.confirmations, [])
        XCTAssertEqual(session.generationState, .ready)
        XCTAssertEqual(ai.requests.count, 2)
        let frozenContext = "Reference instant: 2026-10-12T16:30:00Z. Reference IANA time zone: Asia/Shanghai."
        for request in ai.requests { XCTAssertTrue(request.messages[0].text.contains(frozenContext)) }
        XCTAssertEqual(try XCTUnwrap(session.draft).eventInput(calendar: calendar).timeZoneIdentifier, "America/New_York")
        session.cancelSourceParsing()
        await session.parseSource()
        XCTAssertTrue(ai.requests[2].messages[0].text.contains(frozenContext))
        XCTAssertEqual(session.draft?.start, expectedStart)
        // A new revision takes both parts again from the current draft/reference clock.
        session.updateSourceText("明天 17:00 America/New_York 开会")
        await session.parseSource()
        XCTAssertTrue(ai.requests[3].messages[0].text.contains("Reference instant: 2026-10-14T16:30:00Z. Reference IANA time zone: America/New_York."))
        XCTAssertEqual(session.draft?.start, ISO8601DateFormatter().date(from: "2026-10-15T21:00:00Z"))
        XCTAssertEqual(session.draft?.confirmations, [])
        session.discardDraft()
        session.beginCreate(kind: .event, on: date(15), calendarID: "fixture-events")
        session.updateSourceText("明天 17:00 America/New_York")
        await session.parseSource()
        XCTAssertTrue(ai.requests[4].messages[0].text.contains("Reference instant: 2026-10-14T16:30:00Z. Reference IANA time zone: Asia/Shanghai."))
        XCTAssertEqual(session.draft?.start, ISO8601DateFormatter().date(from: "2026-10-16T21:00:00Z"))
        XCTAssertEqual(session.draft?.timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(backend.writeAttempts, 0)
    }
    func testResolverApprovedSentencePunctuationAndRealQueryBytesStayDistinct() async throws {
        let plain = "https://meeting.tencent.com/dm/VUYtCU0Ssrfz"
        let (value, _) = try await parse("明天下午五点开会，链接：" + plain + "。", output: output(url: plain))
        XCTAssertEqual(value.url?.absoluteString, plain)
        let queried = plain + "?name=Fixture,."
        let (query, _) = try await parse("明天下午五点开会 " + queried, output: output(url: queried))
        XCTAssertEqual(query.url?.absoluteString, queried)
        for truncated in [plain, plain + "?name=Fixture,"] {
            do {
                _ = try await parse("明天下午五点开会 " + queried, output: output(url: truncated))
                XCTFail("Valid query punctuation must not be treated as removable prose")
            } catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidEvidence) }
        }
    }
    func testPairedHuaweiFallbackKeepsFullHTTPSWithSentencePunctuationAndQuery() async throws {
        let native = MeetingInvitationFixtures.native
        let https = MeetingInvitationFixtures.huaweiHTTPS
        for source in [native + "\n" + https + "。", https + "。\n" + native] {
            let text = "明天下午五点开会\n" + source
            let target = try XCTUnwrap(MeetingLinkResolver().uniqueOpenTarget(text: text))
            XCTAssertEqual(target.sourceText, native)
            XCTAssertEqual(target.httpsURL?.absoluteString, https)
            let (value, _) = try await parse(text, output: output(url: https))
            XCTAssertEqual(value.url?.absoluteString, https)
        }
        let query = "https://meeting.huaweicloud.com/?name=Fixture,.#/j/960724861"
        let text = "明天下午五点开会\n" + native + "\n" + query + "。"
        let target = try XCTUnwrap(MeetingLinkResolver().uniqueOpenTarget(text: text))
        XCTAssertEqual(target.httpsURL?.absoluteString, query)
        let (value, _) = try await parse(text, output: output(url: query))
        XCTAssertEqual(value.url?.absoluteString, query)
        for truncated in [https, query.replacingOccurrences(of: "Fixture,.", with: "Fixture,"), query.replacingOccurrences(of: "960724861", with: "960724")] {
            do {
                _ = try await parse(text, output: output(url: truncated))
                XCTFail("Paired fallback evidence must retain the complete original URL bytes")
            } catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidEvidence) }
        }
    }
    func testGenerationErrorsResolveActualBilingualCatalogValues() throws {
        let values: [(ScheduleParsingError, String, String)] = [
            (.sourceTooLarge, "Use no more than 20,000 characters.", "原文不能超过 20,000 个字符。"),
            (.emptySource, "Enter source text to generate a draft.", "请输入用于生成草稿的原文。"),
            (.invalidResponse, "The model returned an invalid schedule. Try again or enter it manually.", "模型返回的日程格式无效，请重试或改为手工填写。"),
            (.invalidEvidence, "The schedule could not be verified against the source.", "无法根据原文验证生成的日程。"),
            (.confirmationRequired, "Confirm the current date and time before saving.", "请确认当前日期和时间后再保存。"),
            (.failed, "Generation failed. Try again or enter it manually.", "生成失败，请重试或改为手工填写。")
        ]
        for language in ["en", "zh-Hans"] {
            let resource = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"))
            let bundle = try XCTUnwrap(Bundle(url: resource))
            for (error, english, chinese) in values {
                XCTAssertEqual(error.localizedDescription(bundle: bundle, locale: Locale(identifier: language)), language == "en" ? english : chinese)
            }
        }
    }

    func testManualNotesRemainAcrossSubsequentReparse() async {
        let backend = backend(), session = session(backend), parser = ControlledScheduleParser()
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        session.updateSourceText("first")
        let first = Task { await session.parseSource(using: parser) }; await wait(parser)
        parser.finish(candidate()); await first.value
        session.draft?.notes = "User owns these notes"
        session.updateSourceText("second")
        let second = Task { await session.parseSource(using: parser) }; await wait(parser)
        parser.finish(candidate()); await second.value
        XCTAssertEqual(session.draft?.notes, "User owns these notes")
    }

    // MARK: - T1 显式「生成」取代自动解析（docs/48 D-06）

    /// 输入先落视图本地 state：打字不写草稿、不排解析；点「生成」/⌘↩ 才写回并解析一次。
    func testTypingSourceOnlyChangesLocalInputAndExplicitGenerateParsesOnce() async {
        let backend = backend(), session = session(backend)
        let ai = ScheduleAIStub(output())
        session.configureAI(ai)
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        XCTAssertFalse(session.hasDirtyDraft)
        // 视图本地 @State（这里用局部变量代表）：打字阶段草稿与生成状态都不动。
        let localInput = "明天下午五点进行周会"
        XCTAssertEqual(session.draft?.sourceText, "")
        XCTAssertEqual(session.generationState, .idle)
        XCTAssertEqual(session.draft?.generationMode, .manual)
        XCTAssertTrue(ai.requests.isEmpty)
        session.draft?.title = "手写标题"
        // 点「生成」的第一步是唯一写回点：同步进 `.parsing`（不经过 `.debouncing`），再由显式入口解析一次。
        session.commitSourceForGeneration(localInput)
        XCTAssertEqual(session.draft?.sourceText, localInput)
        XCTAssertEqual(session.generationState, .parsing)
        XCTAssertEqual(session.draft?.generationMode, .required)
        await session.generateDraft()
        XCTAssertEqual(ai.requests.count, 1, "显式生成只触发一次解析")
        XCTAssertEqual(session.draft?.sourceText, localInput)
        XCTAssertEqual(session.generationState, .ready)
        XCTAssertNil(session.generationError)
        XCTAssertEqual(session.draft?.title, "周会")
        XCTAssertEqual(session.draft?.start, date(13, hour: 17))
        XCTAssertEqual(session.draft?.confirmations, [])
        // 草稿已就绪时同一个入口仍可重新生成，每次点击同样只解析一次。
        await session.generateDraft()
        XCTAssertEqual(ai.requests.count, 2)
        XCTAssertEqual(session.generationState, .ready)
    }

    /// 冲突页「放弃并新建」：换稿换身份；草稿**真的带过原文**，新稿仍不带上一份原文。
    func testDiscardAndStartRebindsSourceInputIdentityAndDropsLocalInput() async {
        let backend = backend(), session = session(backend)
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        let firstIdentity = session.draftIdentity
        XCTAssertNotNil(firstIdentity)
        // 第一份稿先真的带上原文（同一个写回口径）：否则「新稿为空」是恒真的。
        session.updateSourceText("旧原文")
        XCTAssertEqual(session.draft?.sourceText, "旧原文")
        session.beginCreate(kind: .reminder, on: date(14), calendarID: "fixture-reminders")
        XCTAssertEqual(session.pendingConfirmation, .draftConflict)
        session.resolveDraftConflict(.discardAndStart)
        XCTAssertEqual(session.route, .editor)
        XCTAssertNotNil(session.draftIdentity)
        XCTAssertNotEqual(session.draftIdentity, firstIdentity, "换稿必须换身份")
        XCTAssertEqual(session.draft?.kind, .reminder)
        XCTAssertEqual(session.draft?.sourceText, "", "新稿不带上一份原文")
        XCTAssertEqual(session.draft?.generationMode, .manual, "新稿也不需要重新生成")
    }

    /// 冲突页「继续草稿」是同 route 同稿：身份不变；输入框按 `draft.sourceText`（="旧原文"）重新起头。
    func testConflictResumeKeepsIdentityAndRebuildsInputFromCommittedDraftOnly() async {
        let backend = backend(), session = session(backend)
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        let identity = session.draftIdentity
        session.draft?.title = "保留标题"
        // 先真的生成一份原文：去掉这行，下面「按旧原文起头」的断言就是恒真的。
        session.updateSourceText("旧原文")
        session.beginCreate(kind: .reminder, on: date(14), calendarID: "fixture-reminders")
        XCTAssertEqual(session.pendingConfirmation, .draftConflict)
        session.resolveDraftConflict(.resume)
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draftIdentity, identity, "继续草稿仍是同一份稿、同一身份")
        XCTAssertEqual(session.draft?.title, "保留标题")
        XCTAssertEqual(session.draft?.sourceText, "旧原文", "输入框按草稿原文（而非空）重新起头")
        session.suspend()
        session.resumeDraft()
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draftIdentity, identity)
        XCTAssertEqual(session.draft?.sourceText, "旧原文")
    }

    /// 切档/取消后再进编辑页：重建的输入框是空的，而不是上一份本地原文。
    func testLeavingAndDiscardingDraftReentersEditorWithEmptySourceInput() async {
        let backend = backend(), session = session(backend)
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        let identity = session.draftIdentity
        // 本地打过字但没点「生成」：会话里没有原文，所以重新进编辑页的初值仍是空。
        XCTAssertEqual(session.draft?.sourceText, "")
        session.suspend()
        XCTAssertEqual(session.route, .list)
        XCTAssertNotNil(session.draft, "暂停不丢草稿，只换页面")
        session.resumeDraft()
        XCTAssertEqual(session.route, .editor)
        XCTAssertEqual(session.draftIdentity, identity)
        XCTAssertEqual(session.draft?.sourceText, "", "回到编辑页的输入框初值仍是空")
        session.discardDraft()
        XCTAssertEqual(session.route, .list)
        XCTAssertNil(session.draft)
        XCTAssertNil(session.draftIdentity, "取消后没有稿，就没有身份")
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        XCTAssertNotNil(session.draftIdentity)
        XCTAssertNotEqual(session.draftIdentity, identity, "新建的编辑页拿到全新身份")
        XCTAssertEqual(session.draft?.sourceText, "")
    }

    /// I3：换稿时真正复位输入框的是**编辑页子树被卸载**，不是 `.id(session.draftIdentity)`。
    /// 今天不存在「不卸载编辑页的同 route 换稿」路径——两条换稿路径都先经过编辑页不渲染的状态
    /// （冲突页占位 / `suspend()` 把 route 切走），所以 `.id` 只是二次保险、未被独立验证。
    func testDraftSwapsNeverChangeIdentityWhileTheEditorSubtreeStaysMounted() async {
        let backend = backend(), session = session(backend)
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        let identity = session.draftIdentity
        session.updateSourceText("旧原文")
        // 路径一：冲突页占位（`pendingConfirmation != nil` 时 body 走别的分支，编辑页不渲染）。
        session.beginCreate(kind: .reminder, on: date(14), calendarID: "fixture-reminders")
        XCTAssertEqual(session.pendingConfirmation, .draftConflict)
        XCTAssertEqual(session.route, .editor)
        session.resolveDraftConflict(.discardAndStart)
        XCTAssertNotEqual(session.draftIdentity, identity, "换稿路径一：身份在编辑页不渲染期间才变")
        // 路径二：route 切走再回来（`suspend()` → `.list`），身份不变，靠卸载复位。
        let secondIdentity = session.draftIdentity
        session.suspend()
        XCTAssertEqual(session.route, .list, "切档期间编辑页不渲染")
        session.resumeDraft()
        XCTAssertEqual(session.draftIdentity, secondIdentity)
        // 清稿 → 身份为空；只有再新建才有新身份，而它必然伴随一次 route 切走。
        session.discardDraft()
        XCTAssertNil(session.draftIdentity)
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        XCTAssertNotEqual(session.draftIdentity, secondIdentity)
        XCTAssertNil(session.pendingConfirmation)
    }

    // MARK: - T1 显式「生成」：把生产编辑页挂进 `NSHostingView`（先例 PanelAutoHeightTests.mountPanelPage）

    /// 生产编辑页（`route = .editor`）挂进 `NSHostingView`：真布局、真 `NSViewRepresentable`。
    private func mountEditorPage(session: CalendarPanelSession, manager: CalendarManager) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: CalendarPanelPages(session: session, manager: manager, onReturnSource: { _ in })
            .environmentObject(DynamicIslandViewModel())
            .frame(width: 437, height: 278))
        host.frame = CGRect(x: 0, y: 0, width: 437, height: 278)
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// SwiftUI 的失效是异步的：放一轮 runloop 再布局，宿主才会把 `session` 的新状态渲染出来。
    private func settleEditorPage(_ host: NSView) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        host.layoutSubtreeIfNeeded()
    }

    /// 编辑页上「用文字生成」的原生输入框。判据是 `CalendarGrowingTextEditor` 给 NSView 设的
    /// 无障碍标签（就是本地化后的 `calendar.generation.source`），不猜视图树顺序。
    private func sourceTextViews(in host: NSView) -> [CalendarEditableTextView] {
        let label = NSLocalizedString("calendar.generation.source", comment: "")
        var found: [CalendarEditableTextView] = []
        func walk(_ view: NSView) {
            if let text = view as? CalendarEditableTextView, text.accessibilityLabel() == label { found.append(text) }
            view.subviews.forEach(walk)
        }
        walk(host)
        return found
    }

    /// I1：真页面 + 真输入框——打字只落视图本地 state，草稿原文与生成状态一个都不动、没有解析请求。
    /// 这条对旧实现（输入框绑 `session.draft?.sourceText` + 视图里排解析）必红。
    func testHostedEditorPageKeepsTypingInLocalStateAndParsesOnlyOnExplicitGenerate() async throws {
        let backend = backend(), session = session(backend)
        let ai = ScheduleAIStub(output())
        session.configureAI(ai)
        let manager = CalendarManager(service: backend, now: { self.date(12, hour: 12) },
                                      calendar: calendar, startMonitoring: false)
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        let host = mountEditorPage(session: session, manager: manager)
        let field = try XCTUnwrap(sourceTextViews(in: host).first, "编辑页必须渲染出生成用输入框")
        let typed = "明天下午五点进行周会"
        field.insertText(typed, replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(field.string, typed, "输入确实进了生产控件")
        XCTAssertEqual(session.draft?.sourceText, "", "打字不得写草稿原文")
        XCTAssertEqual(session.generationState, .idle, "打字不得进入任何生成状态")
        XCTAssertEqual(session.draft?.generationMode, .manual)
        XCTAssertTrue(ai.requests.isEmpty, "打字不得排任何解析任务")
        // 显式入口（按钮动作的两步）仍然只解析一次。
        session.commitSourceForGeneration(field.string)
        XCTAssertEqual(session.generationState, .parsing, "同步进解析态，中间不闪 .debouncing")
        await session.generateDraft()
        XCTAssertEqual(ai.requests.count, 1, "显式生成只触发一次解析")
        XCTAssertEqual(session.draft?.sourceText, typed)
        XCTAssertEqual(session.generationState, .ready)
    }

    /// I1/I2 的端到端复核：挂载页面后打进去的原文，在两条换稿路径之后都不会留在输入框里。
    func testHostedEditorPageRebuildsSourceInputAfterDraftSwapAndReentry() async throws {
        let backend = backend(), session = session(backend)
        let manager = CalendarManager(service: backend, now: { self.date(12, hour: 12) },
                                      calendar: calendar, startMonitoring: false)
        session.beginCreate(kind: .event, on: date(12), calendarID: "fixture-events")
        let host = mountEditorPage(session: session, manager: manager)
        let typed = "只打进去没点生成"
        try XCTUnwrap(sourceTextViews(in: host).first).insertText(typed, replacementRange: NSRange(location: 0, length: 0))

        // 路径一：冲突页 → 放弃并新建。新稿的输入框必须是空的。
        session.beginCreate(kind: .reminder, on: date(14), calendarID: "fixture-reminders")
        settleEditorPage(host)
        session.resolveDraftConflict(.discardAndStart)
        settleEditorPage(host)
        let rebuilt = try XCTUnwrap(sourceTextViews(in: host).first, "放弃并新建后编辑页仍要有输入框")
        XCTAssertEqual(rebuilt.string, "", "新稿的输入框不得带上旧原文")
        XCTAssertTrue(sourceTextViews(in: host).allSatisfy { $0.string != typed })

        // 路径二：切档（suspend）后回来。本地未提交的输入同样不留下。
        rebuilt.insertText(typed, replacementRange: NSRange(location: 0, length: 0))
        session.suspend()
        settleEditorPage(host)
        XCTAssertEqual(session.route, .list)
        session.resumeDraft()
        settleEditorPage(host)
        let resumed = try XCTUnwrap(sourceTextViews(in: host).first, "恢复草稿后编辑页仍要有输入框")
        XCTAssertEqual(resumed.string, "", "切档回来看不到上一份本地原文")
        XCTAssertEqual(session.draft?.sourceText, "")
    }

    /// I1 的源码证据（与挂载用例互补）：编辑页里没有任何自动调度，输入的写回只走显式入口。
    func testEditorPageSourceSchedulesNothingAndCommitsOnlyThroughTheExplicitEntry() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertFalse(source.contains("CalendarSourceDebouncer"), "编辑页不得再持有调度器")
        XCTAssertFalse(source.contains("sourceDebouncer"))
        XCTAssertFalse(source.contains("retrySourceParsing"))
        XCTAssertFalse(source.contains("updateSourceText"), "输入的写回只走显式入口")
        XCTAssertTrue(source.contains("text: $sourceDraft"), "输入框绑视图本地 state")
        XCTAssertTrue(source.contains("session.commitSourceForGeneration(sourceDraft)"))
        XCTAssertTrue(source.contains("await session.generateDraft()"))
        XCTAssertTrue(source.contains(".keyboardShortcut(.return, modifiers: .command)"))
    }

    // MARK: - T1 解析层：半点/点分解码与生成失败回归（docs/49 做法 1）

    /// T1 主回归：原文同时含「X点半」钟点与「时长一个点」。半小时必须解得开，
    /// 时长说法落回应用既有的「默认一小时」，而不是抛 invalidEvidence。
    func testHalfHourClockWithDurationFallsBackToDefaultHourInsteadOfFailing() async throws {
        let text = "精准维修云平台周会，今天下午三点半，会议时长一个点"
        let (value, _) = try await parse(text, output: output(date: "2026-10-12", evidence: "今天", start: "15:30", startEvidence: "下午三点半"))
        XCTAssertEqual(value.start, date(12, hour: 15, minute: 30))
        XCTAssertEqual(value.end, date(12, hour: 16, minute: 30), "只有时长说法时应用默认补一小时")
        XCTAssertTrue(value.confirmations.isEmpty)
    }

    /// T1：「三点十五分」「三点一刻」与「三点半」同类可解——修好之前它们会被判无效。
    func testChineseMinuteAndQuarterClockFormsDecode() async throws {
        for (evidence, clock) in [("下午三点十五分", "15:15"), ("下午三点一刻", "15:15")] {
            let (value, _) = try await parse("今天\(evidence)开会", output: output(date: "2026-10-12", evidence: "今天", start: clock, startEvidence: evidence))
            XCTAssertEqual(value.start, date(12, hour: 15, minute: 15), evidence)
            XCTAssertTrue(value.confirmations.isEmpty, evidence)
        }
    }

    /// T1：模型把证据归一化成原文里没有的 `15:30`，证据校验仍必须确定性拒绝（不静默放行）。
    func testNormalizedClockEvidenceAbsentFromSourceIsStillRejected() async {
        let text = "精准维修云平台周会，今天下午三点半，会议时长一个点"
        do {
            _ = try await parse(text, output: output(date: "2026-10-12", evidence: "今天", start: "15:30", startEvidence: "15:30"))
            XCTFail("原文里没有 15:30，证据必须是原文片段")
        } catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidEvidence) }
    }

    /// T1 不变量：`timePattern` 认得的每一种词形，`clockEvidence` 都要解得开。
    /// 逐一走真实解析器——两边漏一侧都会红：缺 pattern 会落时间确认，缺解码会抛 invalidEvidence。
    func testEverySupportedClockFormDecodesWithoutConfirmation() async throws {
        let forms: [(String, String, Date)] = [
            ("15:30", "15:30", date(12, hour: 15, minute: 30)),
            ("15:30:45", "15:30:45", date(12, hour: 15, minute: 30).addingTimeInterval(45)),
            ("三点", "03:00", date(12, hour: 3)),
            ("三点半", "03:30", date(12, hour: 3, minute: 30)),
            ("三点十五分", "03:15", date(12, hour: 3, minute: 15)),
            ("三点一刻", "03:15", date(12, hour: 3, minute: 15))
        ]
        for (evidence, clock, expected) in forms {
            let (value, _) = try await parse("今天\(evidence)开会", output: output(date: "2026-10-12", evidence: "今天", start: clock, startEvidence: evidence))
            XCTAssertEqual(value.start, expected, evidence)
            XCTAssertTrue(value.confirmations.isEmpty, "词形 \(evidence) 不该再要求时间确认")
        }
    }

    /// T1：支持集合之外的词形（如「三点三刻半」）仍确定性拒绝，不静默放行。
    func testUnsupportedClockWordingsStayDeterministicallyRejected() async {
        for evidence in ["三点三刻半", "三点半半"] {
            do {
                _ = try await parse("今天\(evidence)开会", output: output(date: "2026-10-12", evidence: "今天", start: "03:45", startEvidence: evidence))
                XCTFail("不支持的词形必须拒绝：" + evidence)
            } catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidEvidence, evidence) }
        }
    }

    /// T1：分钟的中文数词要真能认 0–59（「三点二十五分」「三点四十五分」这类必须可用）。
    func testChineseMinuteNumeralsZeroThroughFiftyNineDecode() async throws {
        let pairs: [(String, Int)] = [
            ("零", 0), ("一", 1), ("九", 9), ("十", 10), ("十一", 11), ("十九", 19),
            ("二十", 20), ("二十五", 25), ("二十九", 29), ("三十", 30), ("三十五", 35),
            ("四十", 40), ("四十五", 45), ("五十", 50), ("五十五", 55), ("五十九", 59)
        ]
        for (numeral, minute) in pairs {
            let (value, _) = try await parse("今天三点\(numeral)分开会", output: output(date: "2026-10-12", evidence: "今天", start: String(format: "%02d:%02d", 3, minute), startEvidence: "三点\(numeral)分"))
            XCTAssertEqual(value.start, date(12, hour: 3, minute: minute), numeral)
            XCTAssertTrue(value.confirmations.isEmpty, numeral)
        }
    }

    /// V2：新 prompt 要求模型在「只有时长说法」时把 end 与 endEvidence 一起留空。
    /// 这条钉的是**万一模型没照做**——把时长短语当 endEvidence 喂回来，也必须确定性拒绝、
    /// 不能静默接受（否则等于放行了一条原文里没有钟点的「结束时间」）。
    func testDurationPhraseAsEndEvidenceIsStillRejected() async {
        let text = "精准维修云平台周会，今天下午三点半，会议时长一个点"
        do {
            _ = try await parse(text, output: output(date: "2026-10-12", evidence: "今天", start: "15:30", startEvidence: "下午三点半", end: "16:30", endEvidence: "会议时长一个点"))
            XCTFail("时长短语不是钟点证据，必须拒绝")
        } catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidEvidence) }
    }

    /// 审查 I1：小时也走 0–59 词法后，合法的「十三点 / 二十三点 / 三点零零分」解得开
    /// （旧实现只到「十二」且不认「零零」，模型逐字引用它们会恒被 invalidEvidence 拒绝）。
    func testLegalExtendedChineseClockWordingsDecode() async throws {
        for (evidence, clock, expected) in [
            ("十三点", "13:00", date(12, hour: 13)),
            ("二十三点", "23:00", date(12, hour: 23)),
            ("三点零零分", "03:00", date(12, hour: 3))
        ] {
            let (value, _) = try await parse("今天\(evidence)开会", output: output(date: "2026-10-12", evidence: "今天", start: clock, startEvidence: evidence))
            XCTAssertEqual(value.start, expected, evidence)
            XCTAssertTrue(value.confirmations.isEmpty, evidence)
        }
    }

    /// 审查 I1/I3/I4：越界取值（时 >23、分 >59）与畸形词法（`十零`/`一十`/阿拉伯「刻」）
    /// 仍按原路径确定性拒绝——小时走同一词法、但范围守卫与「刻只认一二三」两侧口径保持不变。
    func testOutOfRangeAndMalformedClockWordingsAreRejected() async {
        for evidence in ["二十五点", "三点六十分", "三点十零分", "三点一十分", "三点3刻"] {
            do {
                _ = try await parse("今天\(evidence)开会", output: output(date: "2026-10-12", evidence: "今天", start: "03:00", startEvidence: evidence))
                XCTFail("必须确定性拒绝：" + evidence)
            } catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidEvidence, evidence) }
        }
    }

    /// 审查二：`零X` 读法（「三点零五分」「零点零五分」是极常见的口语写法）——解得开，
    /// 且 `timeHints` 与证据同值，不落时间确认。
    func testLeadingZeroReadingDecodesWithoutConfirmation() async throws {
        for (evidence, clock, expected) in [
            ("三点零五分", "03:05", date(12, hour: 3, minute: 5)),
            ("三点零一分", "03:01", date(12, hour: 3, minute: 1)),
            ("零点零五分", "00:05", date(12, hour: 0, minute: 5))
        ] {
            let (value, _) = try await parse("今天\(evidence)开会", output: output(date: "2026-10-12", evidence: "今天", start: clock, startEvidence: evidence))
            XCTAssertEqual(value.start, expected, evidence)
            XCTAssertTrue(value.confirmations.isEmpty, evidence)
        }
    }

    /// 审查二：`零X` 只认「零 + 单个个位数」——`零十`、三位「零」前缀仍是 nil。
    func testMalformedLeadingZeroWordingsAreRejected() async {
        for evidence in ["三点零十", "三点零零五分"] {
            do {
                _ = try await parse("今天\(evidence)开会", output: output(date: "2026-10-12", evidence: "今天", start: "03:05", startEvidence: evidence))
                XCTFail("必须确定性拒绝：" + evidence)
            } catch { XCTAssertEqual(error as? ScheduleParsingError, .invalidEvidence, evidence) }
        }
    }
}

// Native text regressions create production controls without a window or system input.
@MainActor
final class CalendarNativeTextSystemTests: XCTestCase {
    private func assertTextSystem(_ view: NSTextView, file: StaticString = #filePath, line: UInt = #line) throws {
        let storage = try XCTUnwrap(view.textStorage, file: file, line: line)
        let manager = try XCTUnwrap(view.layoutManager, file: file, line: line)
        let container = try XCTUnwrap(view.textContainer, file: file, line: line)
        XCTAssertTrue(manager.textStorage === storage, file: file, line: line)
        XCTAssertTrue(container.layoutManager === manager, file: file, line: line)
        XCTAssertTrue(manager.textContainers.contains { $0 === container }, file: file, line: line)
        XCTAssertTrue(container.textView === view, file: file, line: line)
        XCTAssertNil(view.window, file: file, line: line)
    }

    func testReadOnlyMakeNSViewArgumentsCreateCompleteTextSystem() throws {
        // Keep the production makeNSView's frame/container arguments, including .zero and nil.
        let view = CalendarReadOnlyTextView(frame: .zero, textContainer: nil)
        defer { view.stop() }
        try assertTextSystem(view)
        XCTAssertFalse(view.isEditable)
        XCTAssertTrue(view.isSelectable)
        XCTAssertFalse(view.isRichText)
        XCTAssertFalse(view.drawsBackground)
        XCTAssertEqual(view.textContainerInset, .zero)
        XCTAssertEqual(view.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(view.textContainer?.widthTracksTextView, true)
        XCTAssertFalse(view.isHorizontallyResizable)
        XCTAssertFalse(view.isVerticallyResizable, "SwiftUI owns height; native text must not grow across neighboring controls")
    }

    func testReadOnlyConfigureProducesTitleGlyphsAndMeasuredMultilineHeight() throws {
        let view = CalendarReadOnlyTextView(frame: .zero, textContainer: nil)
        defer { view.stop() }
        let title = "项目评审会议\n第二行议题\n第三行备注"
        let font = NSFont.systemFont(ofSize: 14)
        view.configure(text: title, font: font, color: .white, maximumLines: 0, strikethrough: true)
        view.setFrameSize(NSSize(width: 220, height: view.measuredSize(width: 220).height))
        let size = view.measuredSize(width: 220)
        try assertTextSystem(view)
        XCTAssertEqual(view.string, title)
        let manager = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        XCTAssertGreaterThan(manager.numberOfGlyphs, 0)
        let used = manager.usedRect(for: container)
        XCTAssertGreaterThan(used.width, 0)
        XCTAssertGreaterThan(used.height, font.boundingRectForFont.height)
        XCTAssertGreaterThanOrEqual(size.height, ceil(used.height))
        XCTAssertEqual(size.width, 220)
        let storage = try XCTUnwrap(view.textStorage)
        // AppKit can substitute a CJK fallback face; the configured size must survive layout.
        let renderedFont = try XCTUnwrap(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(renderedFont.pointSize, font.pointSize)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .white)
        XCTAssertEqual(storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int,
                       NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(container.lineBreakMode, .byWordWrapping)
    }

    func testReadOnlyRepeatedConfigureKeepsSelectionAndChangedTextUpdatesLayout() throws {
        let view = CalendarReadOnlyTextView(frame: .zero, textContainer: nil)
        defer { view.stop() }
        let title = "评审会议完整标题"
        view.configure(text: title, font: .systemFont(ofSize: 14), color: .white,
                       maximumLines: 2, strikethrough: false)
        _ = view.measuredSize(width: 80)
        let selection = NSRange(location: 2, length: 4)
        view.setSelectedRange(selection)
        let ranges = view.selectedRanges
        view.configure(text: title, font: .systemFont(ofSize: 14), color: .white,
                       maximumLines: 2, strikethrough: false)
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(view.selectedRanges, ranges)
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "会议完整")
        view.configure(text: title, font: .systemFont(ofSize: 16), color: .white,
                       maximumLines: 2, strikethrough: true)
        XCTAssertEqual(view.selectedRanges, ranges, "Same-text styling updates also preserve the native selection")
        XCTAssertEqual(view.textContainer?.maximumNumberOfLines, 2)
        XCTAssertEqual(view.textContainer?.lineBreakMode, .byTruncatingTail)
        view.configure(text: "更新标题\n附加说明", font: .systemFont(ofSize: 14), color: .white,
                       maximumLines: 0, strikethrough: false)
        _ = view.measuredSize(width: 220)
        XCTAssertEqual(view.string, "更新标题\n附加说明")
        XCTAssertGreaterThan(try XCTUnwrap(view.layoutManager).numberOfGlyphs, 0)
    }

    func testReadOnlyCanonicalEquivalentUTF16ChangesDoNotRestoreOldSelectionCoordinates() throws {
        let decomposed = "e\u{0301}XYZ"
        let composed = "\u{00e9}XYZ"
        XCTAssertEqual(decomposed, composed, "Swift equality includes canonical equivalence")
        XCTAssertFalse(decomposed.utf16.elementsEqual(composed.utf16))
        for (old, new) in [(decomposed, composed), (composed, decomposed)] {
            let view = CalendarReadOnlyTextView(frame: .zero, textContainer: nil)
            defer { view.stop() }
            try assertTextSystem(view)
            view.configure(text: old, font: .systemFont(ofSize: 14), color: .white,
                           maximumLines: 0, strikethrough: false)
            let oldSelection = (old as NSString).range(of: "X")
            view.setSelectedRange(oldSelection)
            XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "X")
            view.configure(text: new, font: .systemFont(ofSize: 14), color: .white,
                           maximumLines: 0, strikethrough: false)
            XCTAssertTrue(view.string.utf16.elementsEqual(new.utf16))
            XCTAssertFalse(view.selectedRange() == oldSelection,
                           "Different UTF-16 coordinates must use AppKit's content-replacement selection")
            XCTAssertTrue(NSMaxRange(view.selectedRange()) <= (new as NSString).length)
            // A stale old offset would now select Y or a standalone combining mark.
            XCTAssertEqual(view.selectedRange().length, 0)
        }
    }

    func testEditableMakeNSViewArgumentsSupportActualMultilineInsertionAndBinding() throws {
        let view = CalendarEditableTextView(frame: .zero, textContainer: nil)
        defer { view.stop() }
        try assertTextSystem(view)
        XCTAssertTrue(view.isEditable)
        XCTAssertTrue(view.isSelectable)
        XCTAssertFalse(view.isRichText)
        XCTAssertTrue(view.allowsUndo)
        XCTAssertFalse(view.isHorizontallyResizable)
        XCTAssertFalse(view.isVerticallyResizable, "SwiftUI owns height; native text must not grow across neighboring controls")
        XCTAssertEqual(view.textContainerInset, NSSize(width: 4, height: 4))
        XCTAssertEqual(view.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(view.textContainer?.widthTracksTextView, true)
        var bound = ""
        let editor = CalendarGrowingTextEditor(text: Binding(get: { bound }, set: { bound = $0 }),
                                               label: "calendar.editor.source", onFocus: { _ in })
        let coordinator = editor.makeCoordinator()
        view.delegate = coordinator
        let input = "明天上午评审\n讨论架构与计划"
        view.insertText(input, replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(view.string, input)
        XCTAssertEqual(bound, input, "Actual insertText must notify the production Coordinator, not a manual callback")
        let container = try XCTUnwrap(view.textContainer)
        container.containerSize = NSSize(width: 220, height: CGFloat.greatestFiniteMagnitude)
        let manager = try XCTUnwrap(view.layoutManager)
        manager.ensureLayout(for: container)
        XCTAssertGreaterThan(manager.numberOfGlyphs, 0)
        XCTAssertGreaterThan(manager.usedRect(for: container).height,
                             try XCTUnwrap(view.font).boundingRectForFont.height)
    }

    /// 显式生成（docs/48 D-06）后原文先落在视图本地 state：同一个控件对「本地输入」与「草稿备注」都写穿。
    func testEditableCoordinatorWritesActualInputToLocalSourceAndNotesDraftBindings() throws {
        let reference = Date(timeIntervalSince1970: 1_792_000_000)
        let session = CalendarPanelSession(selectedDate: reference, now: { reference },
                                          saveEvent: { _, _ in throw CalendarMutationError.readOnlyCalendar },
                                          createReminder: { _ in throw CalendarMutationError.readOnlyCalendar },
                                          deleteEvent: { _ in },
                                          completeReminder: { _, _ in throw CalendarMutationError.readOnlyCalendar },
                                          event: { _ in nil })
        session.beginCreate(kind: .event, on: reference, calendarID: "fixture-events")
        let source = "明天上午评审\n讨论架构"
        let notes = "用户备注\n第二行说明"
        var localSource = ""
        let bindings = [
            Binding<String>(get: { localSource }, set: { localSource = $0 }),
            Binding<String>(get: { session.draft?.notes ?? "" }, set: { session.draft?.notes = $0 })
        ]
        for (binding, input) in zip(bindings, [source, notes]) {
            let view = CalendarEditableTextView(frame: .zero, textContainer: nil)
            defer { view.stop() }
            try assertTextSystem(view)
            let editor = CalendarGrowingTextEditor(text: binding, label: "fixture", onFocus: { _ in })
            let coordinator = editor.makeCoordinator()
            view.delegate = coordinator
            view.insertText(input, replacementRange: NSRange(location: 0, length: 0))
            XCTAssertEqual(view.string, input)
            XCTAssertEqual(binding.wrappedValue, input)
        }
        XCTAssertEqual(localSource, source)
        XCTAssertEqual(session.draft?.sourceText, "", "打字阶段不写草稿原文，只有点「生成」才写")
        XCTAssertEqual(session.draft?.notes, notes)
        XCTAssertTrue(session.hasDirtyDraft)
        XCTAssertEqual(session.draft?.generationMode, .manual)
        XCTAssertEqual(session.route, .editor)
    }

    func testEditableRebindingAndSelectionReplacementUseCurrentCoordinatorParent() throws {
        let view = CalendarEditableTextView(frame: .zero, textContainer: nil)
        defer { view.stop() }
        try assertTextSystem(view)
        var first = "", second = ""
        let editor = CalendarGrowingTextEditor(text: Binding(get: { first }, set: { first = $0 }),
                                               label: "fixture", onFocus: { _ in })
        let coordinator = editor.makeCoordinator()
        view.delegate = coordinator
        view.insertText("第一行\n第二行", replacementRange: NSRange(location: 0, length: 0))
        let selection = NSRange(location: 4, length: 3)
        view.setSelectedRange(selection)
        // updateNSView refreshes this parent before accepting subsequent native edits.
        coordinator.parent = CalendarGrowingTextEditor(text: Binding(get: { second }, set: { second = $0 }),
                                                       label: "fixture", onFocus: { _ in })
        XCTAssertEqual(view.selectedRange(), selection)
        view.insertText("修订行", replacementRange: view.selectedRange())
        XCTAssertEqual(first, "第一行\n第二行")
        XCTAssertEqual(view.string, "第一行\n修订行")
        XCTAssertEqual(second, view.string)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 7, length: 0))
    }

    func testValidSuppliedTextContainersAndTheirExistingStorageAreRetained() throws {
        for editable in [false, true] {
            let storage = NSTextStorage(string: "已有文字")
            let manager = NSLayoutManager()
            let container = NSTextContainer(containerSize: NSSize(width: 180, height: CGFloat.greatestFiniteMagnitude))
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            let view: NSTextView = editable
                ? CalendarEditableTextView(frame: .zero, textContainer: container)
                : CalendarReadOnlyTextView(frame: .zero, textContainer: container)
            defer {
                (view as? CalendarEditableTextView)?.stop()
                (view as? CalendarReadOnlyTextView)?.stop()
            }
            try assertTextSystem(view)
            XCTAssertTrue(view.textStorage === storage)
            XCTAssertTrue(view.layoutManager === manager)
            XCTAssertTrue(view.textContainer === container)
            XCTAssertEqual(view.string, "已有文字")
            manager.ensureLayout(for: container)
            XCTAssertGreaterThan(manager.numberOfGlyphs, 0)
            XCTAssertGreaterThan(manager.usedRect(for: container).width, 0)
            if editable {
                view.insertText("追加", replacementRange: NSRange(location: storage.length, length: 0))
                XCTAssertEqual(storage.string, "已有文字追加")
            }
        }
    }
}

// T6 callbacks are offline: no NSTextView/NSWindow construction, clipboard or system data.
@MainActor
final class CalendarCopyInteractionTests: XCTestCase {
    private func session() -> CalendarPanelSession {
        CalendarPanelSession(saveEvent: { _, _ in throw CalendarMutationError.readOnlyCalendar },
                             createReminder: { _ in throw CalendarMutationError.readOnlyCalendar },
                             deleteEvent: { _ in }, completeReminder: { _, _ in throw CalendarMutationError.readOnlyCalendar },
                             event: { _ in nil })
    }

    func testMouseUpAndTrackingReturnReleaseOnceWithoutSelectionProtection() {
        var changes: [Bool] = [], rechecks = 0
        let owner = CalendarTextInteraction(setProtection: { active, _ in changes.append(active) },
                                            recheckHover: { rechecks += 1 })
        owner.mouseDown()
        owner.mouseUp()
        owner.trackingReturned()
        owner.mouseUp()
        XCTAssertEqual(changes, [true, false])
        XCTAssertEqual(rechecks, 1, "保持选区不常驻保护；重复 mouseUp/内部 tracking 返回幂等")
    }

    func testTrackingReturnReleasesWhenAppKitConsumesMouseUp() {
        var protected = false, rechecks = 0
        let owner = CalendarTextInteraction(setProtection: { active, _ in protected = active },
                                            recheckHover: { rechecks += 1 })
        owner.mouseDown()
        owner.trackingReturned()
        XCTAssertFalse(protected)
        XCTAssertEqual(rechecks, 1)
    }

    func testMenuCloseWaitsForEveryOwnMenuAndDrag() {
        var changes: [Bool] = [], rechecks = 0
        let owner = CalendarTextInteraction(setProtection: { active, _ in changes.append(active) },
                                            recheckHover: { rechecks += 1 })
        let first = NSObject(), second = NSObject()
        owner.menuWillOpen(first)
        owner.menuWillOpen(second)
        owner.mouseDown()
        owner.menuDidClose(first)
        owner.mouseUp()
        XCTAssertEqual(changes, [true])
        owner.menuDidClose(second)
        owner.menuDidClose(second)
        XCTAssertEqual(changes, [true, false])
        XCTAssertEqual(rechecks, 1)
    }

    func testMouseUpCannotClearAnOpenMenuAndMenuCloseCannotClearDrag() {
        var protected = false
        let owner = CalendarTextInteraction(setProtection: { active, _ in protected = active }, recheckHover: {})
        let menu = NSObject()
        owner.mouseDown(); owner.menuWillOpen(menu); owner.mouseUp()
        XCTAssertTrue(protected)
        owner.mouseDown(); owner.menuDidClose(menu)
        XCTAssertTrue(protected)
        owner.trackingReturned()
        XCTAssertFalse(protected)
    }

    func testIndependentOwnersReleaseOnlyTheirTokenAndRecheckHover() {
        let unrelated = UUID()
        var tokens: Set<UUID> = [unrelated], rechecks = 0
        let change: (Bool, UUID) -> Void = { active, token in
            if active { tokens.insert(token) } else { tokens.remove(token) }
        }
        let first = CalendarTextInteraction(setProtection: change, recheckHover: { rechecks += 1 })
        let second = CalendarTextInteraction(setProtection: change, recheckHover: { rechecks += 1 })
        let menu = NSObject()
        first.mouseDown(); second.menuWillOpen(menu)
        first.stop(); first.stop()
        XCTAssertEqual(tokens, [unrelated, second.token])
        second.menuDidClose(menu)
        XCTAssertEqual(tokens, [unrelated])
        XCTAssertEqual(rechecks, 2)
    }

    func testExternalDepartureAndLeavingWindowReleaseBothStatesAndAllowNewInteraction() {
        for _ in 0..<2 { // App departure and view leaving its window use the same cleanup.
            var protected = false, rechecks = 0
            let owner = CalendarTextInteraction(setProtection: { active, _ in protected = active },
                                                recheckHover: { rechecks += 1 })
            let menu = NSObject()
            owner.mouseDown(); owner.menuWillOpen(menu)
            owner.depart(); owner.depart(); owner.trackingReturned(); owner.menuDidClose(menu)
            XCTAssertFalse(protected)
            XCTAssertEqual(rechecks, 1)
            owner.mouseDown()
            XCTAssertTrue(protected)
            owner.mouseUp()
            XCTAssertEqual(rechecks, 2)
        }
    }

    func testDismantledOwnerRejectsLateMouseAndMenuCallbacks() {
        var changes: [Bool] = []
        let owner = CalendarTextInteraction(setProtection: { active, _ in changes.append(active) }, recheckHover: {})
        let menu = NSObject()
        owner.menuWillOpen(menu); owner.stop(); owner.stop()
        owner.mouseDown(); owner.menuWillOpen(menu); owner.menuDidClose(menu); owner.trackingReturned()
        XCTAssertEqual(changes, [true, false])
    }

    func testCapturedScreenProtectionCancelsOldTimerEvenAfterRelease() async {
        let session = session(), selectedScreen = CurrentValueSubject<Bool, Never>(false)
        let closed = expectation(description: "stale shortcut deadline must stay cancelled")
        closed.isInverted = true
        let timer = DispatchWorkItem { closed.fulfill() }
        let protection = CalendarShortcutCloseProtection(session: session) { timer.cancel() }
        protection.observeSuppression(selectedScreen.eraseToAnyPublisher())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: timer)
        selectedScreen.send(true); selectedScreen.send(false)
        XCTAssertTrue(timer.isCancelled)
        XCTAssertTrue(CalendarShortcutCloseProtection.permitsDeadline(session: session, suppressed: false))
        await fulfillment(of: [closed], timeout: 0.08)
        withExtendedLifetime(protection) {}
    }

    func testObserverReplacementStopAndInitialActiveProtection() {
        let session = session()
        let oldScreen = CurrentValueSubject<Bool, Never>(false), newScreen = CurrentValueSubject<Bool, Never>(true)
        var cancellations = 0
        let protection = CalendarShortcutCloseProtection(session: session) { cancellations += 1 }
        protection.observeSuppression(oldScreen.eraseToAnyPublisher())
        protection.observeSuppression(newScreen.eraseToAnyPublisher())
        XCTAssertEqual(cancellations, 1, "新捕获屏幕已有保护时立即取消")
        oldScreen.send(true)
        XCTAssertEqual(cancellations, 1, "旧屏幕订阅已解除")
        newScreen.send(false); newScreen.send(true)
        XCTAssertEqual(cancellations, 2)
        protection.stop(); protection.stop()
        newScreen.send(false); newScreen.send(true)
        session.beginCreate(kind: .event, on: Date(), calendarID: nil)
        XCTAssertEqual(cancellations, 2, "销毁解除 session 与 VM 的所有订阅")
    }

    func testDeadlineReadsCapturedSuppressionAndLiveSessionProtection() {
        let session = session()
        XCTAssertTrue(CalendarShortcutCloseProtection.permitsDeadline(session: session, suppressed: false))
        XCTAssertFalse(CalendarShortcutCloseProtection.permitsDeadline(session: session, suppressed: true))
        session.beginCreate(kind: .event, on: Date(), calendarID: nil)
        XCTAssertFalse(CalendarShortcutCloseProtection.permitsDeadline(session: session, suppressed: false))
    }

    func testMeetingCopyPreservesSeparateSourceCodesAndDoesNotInventLinks() {
        let source = "邀请 https://meeting.huaweicloud.com/#/j/123456789 会议ID：987654321"
        let payload = CalendarCopyPayload(title: "Review", fullInformation: source, meetingSource: source)
        XCTAssertTrue(payload.meetingInformation.contains("https://meeting.huaweicloud.com/#/j/123456789"))
        XCTAssertTrue(payload.meetingInformation.contains("987654321"))
        XCTAssertFalse(payload.meetingInformation.contains("hwmeeting://"))
        let noMeeting = CalendarCopyPayload(title: "Read", fullInformation: "Call 13800138000", meetingSource: "Call 13800138000")
        XCTAssertEqual(noMeeting.meetingInformation, "")
    }

    func testTodoFallbackCopyKeepsTitleListAndDueWithoutCalendarNavigation() {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let item = TodoBucketing.Item(id: "offline", title: "Read proposal", dueDate: due, isCompleted: false, listName: "Inbox")
        let payload = CalendarCopyPayload(item: item)
        XCTAssertEqual(payload.title, "Read proposal")
        XCTAssertTrue(payload.fullInformation.contains("Inbox"))
        XCTAssertTrue(payload.fullInformation.contains(due.formatted()))
    }
}

@MainActor
final class CalendarCopyReviewRegressionTests: XCTestCase {
    private func session() -> CalendarPanelSession {
        CalendarPanelSession(saveEvent: { _, _ in throw CalendarMutationError.readOnlyCalendar },
                             createReminder: { _ in throw CalendarMutationError.readOnlyCalendar },
                             deleteEvent: { _ in }, completeReminder: { _, _ in throw CalendarMutationError.readOnlyCalendar },
                             event: { _ in nil })
    }

    private func record(notes: String, url: URL? = nil, conferenceURL: URL? = nil) -> EventModel {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return EventModel(id: "long-copy", start: date, end: date.addingTimeInterval(3600), title: "Review",
                          location: "Room", notes: notes, url: url, isAllDay: false, type: .event(.unknown),
                          calendar: CalendarModel(accountName: "Fixture", id: "fixture-events", title: "Fixture", color: .systemBlue,
                                                  isSubscribed: false, isReminder: false), participants: [], timeZone: nil,
                          hasRecurrenceRules: false, priority: nil, conferenceURL: conferenceURL)
    }

    func testLongNotesDoNotHideIndependentStructuredURLsAndFullText() {
        let notes = String(repeating: "长🙂", count: 12_000)
        let huawei = URL(string: "https://meeting.huaweicloud.com/#/j/123456789")!
        let tencent = URL(string: "https://meeting.tencent.com/dm/fixture")!
        let payload = CalendarCopyPayload(event: record(notes: notes, url: huawei, conferenceURL: tencent))
        XCTAssertTrue(payload.fullInformation.contains(notes))
        XCTAssertTrue(payload.meetingInformation.contains(huawei.absoluteString))
        XCTAssertTrue(payload.meetingInformation.contains(tencent.absoluteString))
    }

    func testLongNotesKeepCompleteEmbeddedLinkAndSeparateMeetingCodeAtLimitBoundary() {
        let link = "https://meeting.huaweicloud.com/#/j/123456789"
        let notes = String(repeating: "a", count: 19_990) + "\n" + link + "\n会议ID：987654321\n" + String(repeating: "tail", count: 1_000)
        let payload = CalendarCopyPayload(event: record(notes: notes))
        XCTAssertTrue(payload.fullInformation.contains(notes))
        XCTAssertTrue(payload.meetingInformation.contains(link))
        XCTAssertTrue(payload.meetingInformation.contains("会议ID：987654321"))
        XCTAssertFalse(payload.meetingInformation.contains("cloudlink://"))
    }

    func testOversizedURLTokenNeverCreatesAValidTruncatedPrefix() {
        let prefix = "https://meeting.huaweicloud.com/#/j/123456789"
        let malformed = prefix + String(repeating: "x", count: 20_001)
        let targets = CalendarMeetingEvidence.resolve(textFields: [malformed], structuredURLs: [URL(string: "https://meeting.huaweicloud.com.evil.example/#/j/123456789")!])
        XCTAssertTrue(targets.isEmpty)
        let payload = CalendarCopyPayload(title: "Read", fullInformation: malformed, meetingSource: malformed)
        XCTAssertEqual(payload.fullInformation, malformed)
        XCTAssertEqual(payload.meetingInformation, "")
    }

    func testLongFieldHelperKeepsNativePairingDifferentCodesAndAllCandidates() {
        let notes = String(repeating: "padding\n", count: 4_000) + "会议ID：987654321\n" + MeetingInvitationFixtures.native
        let targets = CalendarMeetingEvidence.resolve(textFields: [notes], structuredURLs: [URL(string: MeetingInvitationFixtures.huaweiHTTPS)!])
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.nativeURL?.absoluteString, MeetingInvitationFixtures.native)
        XCTAssertEqual(targets.first?.httpsURL?.absoluteString, MeetingInvitationFixtures.huaweiHTTPS)
        XCTAssertEqual(targets.first?.meetingCodes.map(\.value), ["987654321"])
        let extra = CalendarMeetingEvidence.resolve(textFields: [notes], structuredURLs: [
            URL(string: MeetingInvitationFixtures.huaweiHTTPS)!, URL(string: "https://meeting.huaweicloud.com/#/j/123456789")!
        ])
        XCTAssertEqual(extra.filter(\.canOpen).count, 2)
    }

    func testEvidenceExceedingSingleBatchPreservesEveryCompleteURL() {
        let urls = (0..<650).map { URL(string: "https://meeting.huaweicloud.com/#/j/\(123456789 + $0)")! }
        let text = urls.map(\.absoluteString).joined(separator: "\n")
        XCTAssertGreaterThan(text.count, MeetingLinkResolver.maximumSourceCharacters)
        let targets = CalendarMeetingEvidence.resolve(textFields: [text])
        XCTAssertEqual(Set(targets.compactMap(\.sourceURL)), Set(urls))
    }

    func testOversizedEvidenceSetNeverPairsAnAmbiguousFallbackWithinPartialBatch() {
        let extras = (0..<650).map { "https://meeting.huaweicloud.com/#/j/\(123456789 + $0)" }
        let first = "https://meeting.huaweicloud.com/?first=1#/j/960724861"
        let second = "https://meeting.huaweicloud.com/?second=2#/j/960724861"
        let text = ([MeetingInvitationFixtures.native, first] + extras + [second]).joined(separator: "\n")
        let targets = CalendarMeetingEvidence.resolve(textFields: [text])
        XCTAssertEqual(targets.filter(\.canOpen).count, 653)
        XCTAssertNil(targets.first(where: { $0.nativeURL != nil })?.httpsURL,
                     "不能按部分证据把全局不唯一的 HTTPS 候选配给原生入口")
    }

    func testSynchronousInitialProtectionStopDoesNotReinstallReturnedSubscription() {
        let publisher = CurrentValueSubject<Bool, Never>(true)
        var calls = 0
        var protection: CalendarShortcutCloseProtection?
        protection = CalendarShortcutCloseProtection(session: session()) {
            calls += 1
            protection?.stopObservingSuppression() // Matches AppDelegate.cancelPendingNotchAutoClose.
        }
        protection?.observeSuppression(publisher.eraseToAnyPublisher())
        XCTAssertEqual(calls, 1)
        publisher.send(false); publisher.send(true)
        XCTAssertEqual(calls, 1, "sink 同步重入停止后不得在返回时重新安装")
        protection?.observeSuppression(publisher.eraseToAnyPublisher())
        XCTAssertEqual(calls, 2)
        publisher.send(false); publisher.send(true)
        XCTAssertEqual(calls, 2)
        protection?.stop(); protection = nil
    }

    func testSynchronousInitialProtectionFullStopRejectsLaterBinding() {
        let publisher = CurrentValueSubject<Bool, Never>(true)
        var calls = 0
        var protection: CalendarShortcutCloseProtection?
        protection = CalendarShortcutCloseProtection(session: session()) {
            calls += 1
            protection?.stop()
        }
        protection?.observeSuppression(publisher.eraseToAnyPublisher())
        publisher.send(false); publisher.send(true)
        protection?.observeSuppression(publisher.eraseToAnyPublisher())
        XCTAssertEqual(calls, 1)
        protection = nil
    }

    func testSynchronousReplacementRetainsNewBindingAndRejectsOldBinding() {
        let old = CurrentValueSubject<Bool, Never>(true), replacement = CurrentValueSubject<Bool, Never>(false)
        var calls = 0
        var protection: CalendarShortcutCloseProtection?
        protection = CalendarShortcutCloseProtection(session: session()) {
            calls += 1
            if calls == 1 { protection?.observeSuppression(replacement.eraseToAnyPublisher()) }
        }
        protection?.observeSuppression(old.eraseToAnyPublisher())
        old.send(false); old.send(true)
        XCTAssertEqual(calls, 1)
        replacement.send(true)
        XCTAssertEqual(calls, 2)
        protection?.stop(); protection = nil
    }

    func testHomeFullRecordSnapshotRefreshAndPermissionLossAvoidEventKit() async throws {
        let backend = CalendarInteractionFixtures.makeBackend(count: 3, on: Date())
        let store = TodoStore(logger: ModuleLogger(moduleID: "com.cmeng.gourd.todos", shortID: "todos"), fixtureBackend: backend)
        await store.refresh()
        XCTAssertEqual(Set(store.reminderRecords.keys), Set(store.items.map(\.id)))
        let record = try XCTUnwrap(store.reminderRecords["fixture-reminder-02"])
        XCTAssertEqual(record.notes, backend.event(withID: record.id)?.notes)
        XCTAssertTrue(CalendarCopyPayload(event: record).fullInformation.contains(record.notes!))
        XCTAssertFalse(store.hasInitializedEventStore)
        try await backend.deleteReminder(id: record.id)
        await store.refresh()
        XCTAssertNil(store.reminderRecords[record.id])
        backend.setAuthorization(.denied, for: .reminder)
        await store.refresh()
        XCTAssertTrue(store.reminderRecords.isEmpty)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.hasInitializedEventStore)
    }
}

// MARK: - T7 injected generation scheduling and meeting actions (no host UI or real services)
// T1（docs/48 D-06）后 `CalendarSourceDebouncer` 已从编辑页摘除自动调度、类本身保留；下面两条只验证
// 这个类自己的「最迟一次 / 取消不重放」语义，不再代表面板的输入流程（面板改为显式「生成」）。

@MainActor
private final class CalendarDebounceGate {
    var waits: [CheckedContinuation<Void, Error>?] = []
    func delay() async throws {
        try await withCheckedThrowingContinuation { waits.append($0) }
    }
    func release(_ index: Int) { waits[index]?.resume(); waits[index] = nil }
}

@MainActor
final class CalendarGenerationAndMeetingActionTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_792_000_000)

    /// 「记住的客户端」（docs/47 D-09）落开发机真实域，用例之间不能串味。
    override func setUp() async throws {
        try await super.setUp()
        Defaults.reset(Defaults.Keys.meetingCodeOpener.name)
    }

    override func tearDown() async throws {
        Defaults.reset(Defaults.Keys.meetingCodeOpener.name)
        try await super.tearDown()
    }

    private func makeSession() -> CalendarPanelSession {
        let backend = CalendarInteractionFixtures.makeBackend(count: 0, on: reference)
        let session = CalendarPanelSession(selectedDate: reference, now: { self.reference },
                                           saveEvent: { try await backend.saveEvent(input: $0, eventID: $1) },
                                           createReminder: { try await backend.createReminderRecord(input: $0) },
                                           deleteEvent: { try await backend.deleteEvent(id: $0) },
                                           completeReminder: { try await backend.completeReminder(id: $0, completed: $1) },
                                           event: { backend.event(withID: $0) })
        session.beginCreate(kind: .event, on: reference, calendarID: "fixture-events")
        return session
    }
    private func event(notes: String, start: Date? = nil) -> EventModel {
        let backend = CalendarInteractionFixtures.makeBackend(count: 1, on: reference)
        let template = backend.event(withID: "fixture-event-01")!
        return EventModel(id: template.id, start: start ?? reference, end: (start ?? reference).addingTimeInterval(3_600),
                          title: template.title, location: nil, notes: notes, url: nil, isAllDay: false,
                          type: template.type, calendar: template.calendar, participants: [], timeZone: template.timeZone,
                          hasRecurrenceRules: false, priority: nil, conferenceURL: nil, isDetached: false)
    }
    private func drain(until condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition())
    }

    func testDebounceOnlySubmitsLatestSourceAndDoesNotSubmitTitleOrConfirmationChanges() async {
        let session = makeSession(), gate = CalendarDebounceGate()
        let debouncer = CalendarSourceDebouncer(delay: { try await gate.delay() })
        var calls: [String] = []
        session.updateSourceText("first")
        debouncer.schedule(session: session, parse: { calls.append(session.draft!.sourceText) })
        await drain { gate.waits.count == 1 }
        session.updateSourceText("latest")
        debouncer.schedule(session: session, parse: { calls.append(session.draft!.sourceText) })
        await drain { gate.waits.count == 2 }
        session.draft?.title = "Hand edited"
        gate.release(0)
        await Task.yield()
        XCTAssertTrue(calls.isEmpty)
        gate.release(1)
        await drain { calls.count == 1 }
        XCTAssertEqual(calls, ["latest"])
        session.useManualEntry()
        session.confirmSource(.date)
        session.confirmSource(.time)
        debouncer.schedule(session: session, parse: { calls.append("unexpected") })
        await Task.yield()
        XCTAssertEqual(gate.waits.count, 2)
        XCTAssertEqual(calls.count, 1)
    }

    func testCancelBeforeDelayDoesNotAutoResendOnRestoreAndManualRequiresBothConfirmations() async throws {
        let session = makeSession(), gate = CalendarDebounceGate()
        let debouncer = CalendarSourceDebouncer(delay: { try await gate.delay() })
        var calls = 0
        session.updateSourceText("retain original")
        debouncer.schedule(session: session, parse: { calls += 1 })
        await drain { gate.waits.count == 1 }
        debouncer.cancel()
        session.cancelSourceParsing()
        gate.release(0)
        session.suspend()
        session.resumeDraft()
        debouncer.schedule(session: session, parse: { calls += 1 })
        await Task.yield()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(session.draft?.sourceText, "retain original")
        XCTAssertThrowsError(try session.draft!.eventInput())
        session.useManualEntry()
        session.draft?.title = "Manual"
        session.confirmSource(.date)
        XCTAssertThrowsError(try session.draft!.eventInput())
        session.confirmSource(.time)
        XCTAssertNoThrow(try session.draft!.eventInput())
    }

    func testMissingAIAndSourceChangesBlockSaveUntilManualConfirmation() async {
        let session = makeSession()
        session.draft?.title = "Manual title"
        session.updateSourceText("new invitation")
        await session.parseSource()
        XCTAssertEqual(session.generationState, .failed)
        XCTAssertNotNil(session.generationError)
        let saved = await session.save()
        XCTAssertFalse(saved)
        session.useManualEntry()
        session.confirmSource(.date)
        session.confirmSource(.time)
        session.updateSourceText("another revision")
        XCTAssertEqual(session.draft?.generationMode, .required)
        XCTAssertEqual(session.draft?.confirmations, Set(ScheduleConfirmation.allCases))
    }

    func testFutureMeetingStillOffersOpenBecauseTheTimeGateIsGone() async throws {
        let session = makeSession()
        let opener = MeetingFakeOpener([true])
        var copied: [String] = []
        let model = MeetingActionModel(event: event(notes: MeetingInvitationFixtures.huawei, start: reference.addingTimeInterval(3_600)),
                                      session: session, opener: opener, copyText: { copied.append($0) })
        let target = try XCTUnwrap(model.targets.first(where: \.canOpen))
        XCTAssertEqual(model.primary, .open(target, .huawei),
                       "docs/47 D-02：开始前 15 分钟的时间闸门已删，未来日程的主动作仍是打开")
        model.copy(target.sourceURL!.absoluteString)
        model.copySource()
        XCTAssertEqual(copied.count, 2)
        XCTAssertTrue(copied[1].contains(MeetingInvitationFixtures.huaweiHTTPS))
        model.performPrimary()
        await drain { !model.isOpening }
        XCTAssertEqual(opener.urls.count, 1, "时间闸门删除后未来日程同样派发打开请求")
        XCTAssertEqual(model.feedback, .opened)
    }

    func testRefusedThenExplicitRetryDoesNotClaimJoinedAndFallsBackToCopyingTheCode() async throws {
        let session = makeSession(), opener = MeetingFakeOpener([false, true])
        var copied: [String] = []
        let model = MeetingActionModel(event: event(notes: MeetingInvitationFixtures.tencent, start: reference),
                                      session: session, opener: opener, copyText: { copied.append($0) })
        let target = try XCTUnwrap(model.targets.first(where: \.canOpen))
        model.open(target)
        await drain { !model.isOpening }
        // 系统拒绝打开且证据里有会议号 → 退回复制号码（docs/47 §做法 3），不谎称已加入。
        XCTAssertEqual(model.feedback, .copied)
        XCTAssertEqual(copied, ["817450376"])
        model.open(target)
        await drain { !model.isOpening }
        XCTAssertEqual(model.feedback, .opened)
        XCTAssertEqual(copied.count, 1, "打开成功不再复制")
        XCTAssertEqual(opener.urls.count, 2)
    }

    func testPrimaryPrefersLinkedCandidateThenRememberedOpenerThenCopyingTheNumber() throws {
        let session = makeSession()
        let linked = MeetingActionModel(event: event(notes: MeetingInvitationFixtures.huawei), session: session,
                                       opener: MeetingFakeOpener([]), copyText: { _ in })
        let target = try XCTUnwrap(linked.targets.first(where: \.canOpen))
        XCTAssertEqual(linked.primary, .open(target, .huawei), "带链接的候选优先打开")
        XCTAssertNil(linked.rememberedProvider)

        let numberOnly = MeetingActionModel(event: event(notes: "会议ID：939130533"), session: session,
                                           opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(numberOnly.primary, .copyCode("939130533"), "只有会议号且没有记忆时复制号码")
        numberOnly.openByNumber(provider: .huawei)
        XCTAssertEqual(numberOnly.rememberedProvider, .huawei, "选过的客户端要记住（docs/47 D-09）")
        XCTAssertEqual(numberOnly.primary, .open(try XCTUnwrap(numberOnly.targets.first), .huawei),
                       "同一输入下主动作改用记住的客户端打开")
    }

    func testPrimaryCopyBranchSendsTheNumberThroughTheInjectedClipboard() throws {
        let session = makeSession()
        var copied: [String] = []
        let model = MeetingActionModel(event: event(notes: "会议ID：939130533"), session: session,
                                      opener: MeetingFakeOpener([]), copyText: { copied.append($0) })
        XCTAssertEqual(model.primary, .copyCode("939130533"))
        model.performPrimary()
        XCTAssertEqual(copied, ["939130533"])
        XCTAssertEqual(model.feedback, .copied)
        XCTAssertEqual(MeetingActionGlyph.symbol(for: model.feedback), "checkmark")
    }

    func testPrimaryIsNoneWithoutAnyOpenableCandidateOrCode() throws {
        let session = makeSession()
        let model = MeetingActionModel(event: event(notes: "请参加会议并做好准备"), session: session,
                                      opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(model.primary, .none)
        model.performPrimary()
        XCTAssertEqual(model.feedback, .failed, "连号码都没有时才算失败")
        XCTAssertEqual(MeetingActionGlyph.symbol(for: model.feedback), "exclamationmark.triangle")
    }

    func testOpenByNumberFeedsThePasscodeOnlyToTheHuaweiDeepLink() async throws {
        let session = makeSession()
        let notes = "会议ID：939130533\n入会密码：696294"
        let huawei = MeetingFakeOpener([true])
        let model = MeetingActionModel(event: event(notes: notes), session: session,
                                      opener: huawei, copyText: { _ in })
        model.openByNumber(provider: .huawei)
        await drain { !model.isOpening }
        let items = try XCTUnwrap(URLComponents(url: try XCTUnwrap(huawei.urls.first),
                                                resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "enter_code" }?.value, "696294")
        XCTAssertEqual(items.first { $0.name == "conf_id" }?.value, "939130533")
        XCTAssertEqual(model.feedback, .opened)

        let tencent = MeetingFakeOpener([true])
        let other = MeetingActionModel(event: event(notes: notes), session: session,
                                      opener: tencent, copyText: { _ in })
        other.openByNumber(provider: .tencent)
        await drain { !other.isOpening }
        // 腾讯分支没有可查依据写密码（docs/47 D-07）——只带会议号。
        XCTAssertEqual(try XCTUnwrap(tencent.urls.first).absoluteString,
                       "wemeet://page/inmeeting?meeting_code=939130533")
    }

    /// 记住的客户端只保证「换个客户端打开」，不保证号码一定拼得出深链：位数不合法时仍退回复制。
    func testRememberedOpenerFallsBackToCopyingWhenTheNumberIsTooShortForADeepLink() async throws {
        let session = makeSession()
        var copied: [String] = []
        let opener = MeetingFakeOpener([true])
        let model = MeetingActionModel(event: event(notes: "会议ID：93913053"), session: session,
                                      opener: opener, copyText: { copied.append($0) })
        XCTAssertEqual(model.primary, .copyCode("93913053"), "8 位号码仍在证据层（6–12 位），但还没有记忆")
        model.openByNumber(provider: .huawei)
        await drain { !model.isOpening }
        XCTAssertEqual(model.primary, .open(try XCTUnwrap(model.targets.first), .huawei))
        model.performPrimary()
        await drain { !model.isOpening }
        // builder 只认 9–12 位 → `.unavailable` → 退回复制，且一次 URL 都没派发过。
        XCTAssertEqual(model.feedback, .copied)
        XCTAssertEqual(copied, ["93913053", "93913053"])
        XCTAssertTrue(opener.urls.isEmpty)
    }

    /// 记住的客户端只认有深链依据的华为 / 腾讯（审查 M-3）：盘上写成别的值等于没记住。
    func testRememberedProviderIgnoresProvidersWithoutADocumentedDeepLink() throws {
        let session = makeSession()
        let model = MeetingActionModel(event: event(notes: "会议ID：939130533"), session: session,
                                      opener: MeetingFakeOpener([]), copyText: { _ in })
        for raw in ["feishu", "zoom", "nonsense"] {
            Defaults[.meetingCodeOpener] = raw
            XCTAssertNil(model.rememberedProvider, raw)
            XCTAssertEqual(model.primary, .copyCode("939130533"), raw)
        }
        for provider in [MeetingProvider.huawei, .tencent] {
            Defaults[.meetingCodeOpener] = provider.rawValue
            XCTAssertEqual(model.rememberedProvider, provider)
            XCTAssertEqual(model.primary, .open(try XCTUnwrap(model.targets.first), provider))
        }
    }

    func testDisplayNameFallsBackToGourdForBlankUserNames() {
        XCTAssertEqual(MeetingActionModel.resolvedDisplayName("蔡锰"), "蔡锰")
        for blank in ["", "   ", "\n", "\u{00A0}", "\u{00A0}\u{3000}"] {
            XCTAssertEqual(MeetingActionModel.resolvedDisplayName(blank),
                           MeetingJoinURLBuilder.fallbackDisplayName, blank.debugDescription)
        }
    }

    func testGlyphMapsEveryFeedbackState() {
        XCTAssertEqual(MeetingActionGlyph.symbol(for: .idle), "video.fill")
        XCTAssertEqual(MeetingActionGlyph.symbol(for: .opening), "arrow.triangle.2.circlepath")
        XCTAssertEqual(MeetingActionGlyph.symbol(for: .opened), "checkmark")
        XCTAssertEqual(MeetingActionGlyph.symbol(for: .copied), "checkmark")
        XCTAssertEqual(MeetingActionGlyph.symbol(for: .failed), "exclamationmark.triangle")
    }

    // MARK: - T4 视图与调用点：图标 chip / 一行两键 / 右键 4 项 / tooltip

    /// 会议入口新增的文案 key 在 **en 与 zh-Hans 两份**里都解析得出（都 `translated`），
    /// 且 tooltip 的拼接结果逐字等于设计图 ②。
    func testMeetingEntryLocalisationKeysResolveInBothLanguages() throws {
        let keys = ["calendar.meeting.openIn.tencent", "calendar.meeting.openIn.huawei",
                    "calendar.meeting.provider.tencent", "calendar.meeting.provider.huawei",
                    "calendar.meeting.tooltip.open", "calendar.meeting.tooltip.more",
                    "calendar.meeting.tooltip.multiple", "calendar.meeting.tooltip.copyValue",
                    "calendar.meeting.row.open", "calendar.meeting.row.copy", "calendar.meeting.row.choose"]
        for language in ["en", "zh-Hans"] {
            let bundle = try languageBundle(language)
            for key in keys {
                let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(localized, key, "\(key) 在 \(language) 里没解析出文案（catalog 未编进宿主 bundle？）")
                XCTAssertFalse(localized.isEmpty, "\(key) 在 \(language) 里解析为空串")
            }
        }
        let zh = try languageBundle("zh-Hans")
        func text(_ key: String) -> String { zh.localizedString(forKey: key, value: nil, table: nil) }
        XCTAssertEqual(String(format: text("calendar.meeting.tooltip.open"), text("calendar.meeting.provider.tencent")),
                       "打开腾讯会议")
        XCTAssertEqual(String(format: text("calendar.meeting.tooltip.more"), "939130533"),
                       "复制会议号 939130533 · 右键更多")
        XCTAssertEqual(text("calendar.meeting.tooltip.multiple"), "多个会议入口 · 右键选择")
        XCTAssertEqual(String(format: text("calendar.meeting.tooltip.copyValue"), "939130533"), "复制 939130533")
        XCTAssertEqual(text("calendar.meeting.row.open"), "打开")
        XCTAssertEqual(text("calendar.meeting.row.copy"), "复制")
        XCTAssertEqual(text("calendar.meeting.row.choose"), "选择入口")
        XCTAssertEqual(text("calendar.meeting.openIn.huawei"), "在华为云会议中打开")
        // 编辑页仍在用的两条键不许被本任务顺手删掉（失败信号：编辑页用例变红）。
        XCTAssertNotEqual(text("calendar.generation.generate"), "calendar.generation.generate")
        XCTAssertNotEqual(text("calendar.generation.settings"), "calendar.generation.settings")
        XCTAssertEqual(text("calendar.generation.generate"), "生成", "「生成」按钮的文案（T2 修掉「重新生成」错位）")
    }

    /// 右键菜单：只有会议号的邀请**恰好 4 项**（D-03），且没有任何 AI 兜底项。
    func testMeetingIconMenuKeepsExactlyFourEntriesWithoutAIRecognition() throws {
        let session = makeSession()
        let model = MeetingActionModel(event: event(notes: "会议ID：939130533"), session: session,
                                       opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(MeetingActionPresentation.menuEntries(for: model),
                       [.copyCode("939130533"), .openIn(.tencent), .openIn(.huawei), .copySource])
        XCTAssertEqual(MeetingActionPresentation.title(for: .copyCode("939130533")),
                       String(format: Bundle.main.localizedString(forKey: "calendar.meeting.copyCodeFormat",
                                                                  value: nil, table: nil), "939130533"),
                       "标题复用既有键，插进去的是号码本身（审查 C-1）")
    }

    /// 平台能判定时（带链接的邀请）两条「打开」合并成对应那一条。
    func testMeetingIconMenuCollapsesToTheDeterminedProvider() throws {
        let session = makeSession()
        let huawei = MeetingActionModel(event: event(notes: MeetingInvitationFixtures.huawei), session: session,
                                        opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(huawei.determinedProvider, .huawei)
        XCTAssertEqual(MeetingActionPresentation.menuEntries(for: huawei),
                       [.copyCode("940948346"), .openIn(.huawei), .copySource])
        let tencent = MeetingActionModel(event: event(notes: MeetingInvitationFixtures.tencent), session: session,
                                         opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(tencent.determinedProvider, .tencent)
        XCTAssertEqual(MeetingActionPresentation.menuEntries(for: tencent),
                       [.copyCode("817450376"), .openIn(.tencent), .copySource])
    }

    /// 菜单每一项都真的接上了动作：复制会议号（**号码本身**）/ 按号打开并记住客户端 / 复制邀请原文。
    func testMeetingIconMenuEntriesDispatchThroughTheInjectedSeams() async throws {
        let session = makeSession()
        let tencent = MeetingFakeOpener([true])
        var copied: [String] = []
        let codeOnly = MeetingActionModel(event: event(notes: "会议ID：939130533"), session: session,
                                          opener: tencent, copyText: { copied.append($0) })
        MeetingActionPresentation.perform(.copyCode("939130533"), on: codeOnly)
        XCTAssertEqual(copied, ["939130533"], "菜单这一项与主动作同口径：进剪贴板的是纯号码（审查 C-1）")
        MeetingActionPresentation.perform(.openIn(.tencent), on: codeOnly)
        await drain { !codeOnly.isOpening }
        XCTAssertEqual(try XCTUnwrap(tencent.urls.first).absoluteString,
                       "wemeet://page/inmeeting?meeting_code=939130533")
        XCTAssertEqual(Defaults[.meetingCodeOpener], MeetingProvider.tencent.rawValue, "从菜单选客户端同样要记住（D-09）")

        let huawei = MeetingFakeOpener([true])
        let linked = MeetingActionModel(event: event(notes: MeetingInvitationFixtures.huawei), session: session,
                                        opener: huawei, copyText: { _ in })
        MeetingActionPresentation.perform(.openIn(.huawei), on: linked)
        await drain { !linked.isOpening }
        XCTAssertEqual(try XCTUnwrap(huawei.urls.first).absoluteString, MeetingInvitationFixtures.huaweiHTTPS,
                       "证据里本条能直接打开时优先 open(target)，不是按号码拼深链")
    }

    /// 复制邀请原文（第 4 项）：整段来源进剪贴板。
    func testMeetingIconMenuCopySourceCopiesTheWholeInvitation() throws {
        let session = makeSession()
        var copied: [String] = []
        let model = MeetingActionModel(event: event(notes: MeetingInvitationFixtures.huawei), session: session,
                                       opener: MeetingFakeOpener([]), copyText: { copied.append($0) })
        MeetingActionPresentation.perform(.copySource, on: model)
        XCTAssertEqual(copied.count, 1)
        XCTAssertTrue(copied.first?.contains(MeetingInvitationFixtures.huaweiHTTPS) == true)
    }

    /// tooltip 由主动作决定（D-10）：打开 → 「打开<平台>」；只有会议号（复制）→ 「复制会议号 <号> · 右键更多」；
    /// 多个可打开候选 → 「多个会议入口 · 右键选择」；没有入口 → 无证据说明。
    func testMeetingTooltipFollowsThePrimaryAction() throws {
        let session = makeSession()
        let localized = { (key: String) in Bundle.main.localizedString(forKey: key, value: nil, table: nil) }
        let target = try XCTUnwrap(MeetingLinkResolver().uniqueOpenTarget(text: MeetingInvitationFixtures.huawei))
        XCTAssertEqual(MeetingActionPresentation.tooltip(primary: .open(target, .huawei)),
                       String(format: localized("calendar.meeting.tooltip.open"),
                              localized("calendar.meeting.provider.huawei")))
        // `.copyCode` 只会在没有任何可打开候选、也没记住客户端时产生 —— 一律「右键更多」（终审 M-1）。
        XCTAssertEqual(MeetingActionPresentation.tooltip(primary: .copyCode("939130533")),
                       String(format: localized("calendar.meeting.tooltip.more"), "939130533"))
        XCTAssertEqual(MeetingActionPresentation.tooltip(primary: .choose),
                       localized("calendar.meeting.tooltip.multiple"))
        XCTAssertEqual(MeetingActionPresentation.tooltip(primary: .none),
                       localized("calendar.meeting.noEvidence"))

        let linked = MeetingActionModel(event: event(notes: MeetingInvitationFixtures.huawei), session: session,
                                        opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(MeetingActionPresentation.tooltip(for: linked),
                       String(format: localized("calendar.meeting.tooltip.open"),
                              localized("calendar.meeting.provider.huawei")))
        let codeOnly = MeetingActionModel(event: event(notes: "会议ID：939130533"), session: session,
                                          opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(MeetingActionPresentation.tooltip(for: codeOnly),
                       String(format: localized("calendar.meeting.tooltip.more"), "939130533"))
    }

    /// 终审 I-1：`meetingCodeOpener` 是**全局**记忆，但本条链接的平台优先 —— 行标 / tooltip / 实际打开
    /// 三者必须都用**本条链接**的平台，不能被记住的另一家客户端带偏。
    func testRowBrandTooltipAndOpenStayOnTheLinksOwnProviderOverRememberedClient() async throws {
        let session = makeSession()
        let opener = MeetingFakeOpener([true])
        let localized = { (key: String) in Bundle.main.localizedString(forKey: key, value: nil, table: nil) }
        Defaults[.meetingCodeOpener] = MeetingProvider.tencent.rawValue   // 全局记忆 = 腾讯
        defer { Defaults.reset(Defaults.Keys.meetingCodeOpener.name) }
        let model = MeetingActionModel(event: event(notes: MeetingInvitationFixtures.huawei), session: session,
                                       opener: opener, copyText: { _ in })
        XCTAssertEqual(model.rememberedProvider, .tencent)
        XCTAssertEqual(model.determinedProvider, .huawei, "本条证据判出的是华为")
        XCTAssertEqual(MeetingActionPresentation.rowProviderName(for: model),
                       localized("calendar.meeting.provider.huawei"), "行标用本条链接的平台，不是记住的腾讯")
        XCTAssertEqual(MeetingActionPresentation.tooltip(for: model),
                       String(format: localized("calendar.meeting.tooltip.open"),
                              localized("calendar.meeting.provider.huawei")))
        guard case let .open(_, provider) = model.primary else { return XCTFail("带链接的邀请应直接打开") }
        XCTAssertEqual(provider, .huawei)
        model.performPrimary()
        await drain { !model.isOpening }
        XCTAssertEqual(try XCTUnwrap(opener.urls.first).absoluteString, MeetingInvitationFixtures.huaweiHTTPS,
                       "实际打开的仍是本条链接（华为 HTTPS），不是记住的腾讯")
    }

    /// `.row`（设计图 ④）：provider 名 + 号码；没有会议号时退回入口链接。
    func testMeetingRowPresentationShowsProviderAndNumber() throws {
        let session = makeSession()
        let localized = { (key: String) in Bundle.main.localizedString(forKey: key, value: nil, table: nil) }
        let codeOnly = MeetingActionModel(event: event(notes: "会议ID：939130533"), session: session,
                                          opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertNil(MeetingActionPresentation.rowProviderName(for: codeOnly), "判不出平台就不显示 provider 名")
        XCTAssertEqual(MeetingActionPresentation.rowValue(for: codeOnly), "939130533", ".row 显示纯数字")
        Defaults[.meetingCodeOpener] = MeetingProvider.tencent.rawValue
        XCTAssertEqual(MeetingActionPresentation.rowProviderName(for: codeOnly),
                       localized("calendar.meeting.provider.tencent"), "记住的客户端进 provider 名（D-09）")

        Defaults.reset(Defaults.Keys.meetingCodeOpener.name)
        let linked = MeetingActionModel(event: event(notes: MeetingInvitationFixtures.feishu), session: session,
                                        opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(MeetingActionPresentation.rowProviderName(for: linked), "Feishu", "没有记忆时 provider 名回到证据平台")
        XCTAssertEqual(MeetingActionPresentation.rowValue(for: linked), "https://vc.feishu.cn/j/384462190",
                       "没有会议号时显示入口链接")
    }

    /// `.row` 的退化态（审查 I-1）：键名必须与行为一致 —— 判不出平台（主动作是复制）时只有「复制」；
    /// 只有邀请提示词、没有任何入口（`.none`）时两个键都不画（也不会有反馈出口）。
    func testMeetingRowHidesKeysThatCannotAct() throws {
        let session = makeSession()
        let model = MeetingActionModel(event: event(notes: "请参加会议并做好准备"), session: session,
                                       opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(model.primary, .none)
        XCTAssertTrue(MeetingActionPresentation.rowKeys(for: model).isEmpty, "没有任何入口时不许画键")
        XCTAssertNil(MeetingActionPresentation.rowProviderName(for: model))
        XCTAssertNil(MeetingActionPresentation.rowValue(for: model))

        let codeOnly = MeetingActionModel(event: event(notes: "会议ID：939130533"), session: session,
                                          opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(codeOnly.primary, .copyCode("939130533"))
        XCTAssertEqual(MeetingActionPresentation.rowKeys(for: codeOnly), [.copy],
                       "主动作是复制时不许出现「打开」（键名与行为不符）")

        Defaults[.meetingCodeOpener] = MeetingProvider.tencent.rawValue
        XCTAssertEqual(codeOnly.primary, .open(try XCTUnwrap(codeOnly.targets.first), .tencent))
        XCTAssertEqual(MeetingActionPresentation.rowKeys(for: codeOnly), [.open, .copy], "能打开时两个键都在")
    }

    /// `.row` 的反馈出口（审查 I-4）：`.idle` 不占位，其余四态复用图标口径（D-10）。
    func testMeetingRowStatusSymbolMirrorsTheIconFeedback() {
        XCTAssertNil(MeetingActionPresentation.rowStatusSymbol(for: .idle))
        for feedback in [MeetingActionFeedback.opening, .opened, .copied, .failed] {
            XCTAssertEqual(MeetingActionPresentation.rowStatusSymbol(for: feedback),
                           MeetingActionGlyph.symbol(for: feedback), "\(feedback) 必须复用图标口径")
        }
        XCTAssertEqual(MeetingActionPresentation.rowStatusSymbol(for: .copied), "checkmark")
        XCTAssertEqual(MeetingActionPresentation.rowStatusSymbol(for: .opening), "arrow.triangle.2.circlepath")
    }

    // MARK: - 审查 I-2：多个可打开候选必须让用户选，不许静默取第一个

    /// **两个**可打开候选不猜：主动作既不直接打开、也不复制，而是交给菜单；tooltip 提示右键选择。
    func testMultipleOpenableCandidatesAskForAChoiceInsteadOfOpeningTheFirst() throws {
        let session = makeSession()
        let opener = MeetingFakeOpener([true, true])
        var copied: [String] = []
        let model = MeetingActionModel(
            event: event(notes: MeetingInvitationFixtures.huawei + "\n" + MeetingInvitationFixtures.tencent),
            session: session, opener: opener, copyText: { copied.append($0) })
        XCTAssertEqual(model.openTargets.count, 2, "华为链接与腾讯链接都该是可打开候选")
        XCTAssertEqual(model.primary, .choose, "≥2 可打开候选：主动作不许直接打开（不猜）")
        // 主动作点一下什么都不做：再交给菜单，一次 URL 都不派发、也不复制。
        model.performPrimary()
        XCTAssertTrue(opener.urls.isEmpty, "主动作不许静默打开第一个候选")
        XCTAssertTrue(copied.isEmpty, "有可打开候选时不该退化成复制")
        XCTAssertEqual(MeetingActionPresentation.tooltip(for: model),
                       Bundle.main.localizedString(forKey: "calendar.meeting.tooltip.multiple", value: nil, table: nil))

        // 菜单逐条列出每个候选（不折叠），加上复制会议号与复制原文。
        let entries = MeetingActionPresentation.menuEntries(for: model)
        let candidateEntries = entries.compactMap { entry -> MeetingJoinTarget? in
            if case let .openTarget(target) = entry { return target }
            return nil
        }
        XCTAssertEqual(candidateEntries, model.openTargets, "菜单必须逐个候选列一条，不再折叠")
        XCTAssertEqual(entries.count, 4, "复制会议号 + 2 个候选 + 复制原文")
        XCTAssertEqual(entries.first, .copyCode("940948346"))
        XCTAssertEqual(entries.last, .copySource)
        XCTAssertEqual(MeetingActionPresentation.rowKeys(for: model), [.choose],
                       ".row 在 ≥2 候选时只留一个「选择入口」键，点了弹菜单")
    }

    /// 菜单里那条候选真的打开它自己（不是按号码拼深链）。
    func testMultipleCandidateMenuEntriesDispatchToTheirOwnTarget() async throws {
        let session = makeSession()
        let opener = MeetingFakeOpener([true])
        let model = MeetingActionModel(
            event: event(notes: MeetingInvitationFixtures.huawei + "\n" + MeetingInvitationFixtures.tencent),
            session: session, opener: opener, copyText: { _ in })
        let candidate = try XCTUnwrap(model.openTargets.first { $0.provider == .huawei })
        MeetingActionPresentation.perform(.openTarget(candidate), on: model)
        await drain { !model.isOpening }
        XCTAssertEqual(try XCTUnwrap(opener.urls.first).absoluteString, MeetingInvitationFixtures.huaweiHTTPS,
                       "逐条候选项打开的是它自己的 URL")
    }

    /// **恰好一个**可打开候选仍然直接打开（防止「≥2 才不猜」把单候选改坏）。
    func testSingleOpenableCandidateStillOpensDirectly() throws {
        let session = makeSession()
        let model = MeetingActionModel(event: event(notes: MeetingInvitationFixtures.huawei), session: session,
                                       opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(model.openTargets.count, 1)
        guard case let .open(target, provider) = model.primary else {
            return XCTFail("1 个可打开候选必须直接打开，主动作是 \(model.primary)")
        }
        XCTAssertEqual(provider, .huawei)
        XCTAssertEqual(target.sourceURL?.absoluteString, MeetingInvitationFixtures.huaweiHTTPS)
        XCTAssertEqual(MeetingActionPresentation.rowKeys(for: model), [.open, .copy])
    }

    /// 首页那两处调用点的入口几何宽高都是 **22**（不是 187），且旧形态在视图文件里彻底消失。
    func testHomeMeetingIconKeepsAFixed22PointGeometry() throws {
        XCTAssertEqual(MeetingActionPresentation.iconSide, 22)
        let button = MeetingActionIconButton()
        XCTAssertEqual(button.intrinsicContentSize, NSSize(width: 22, height: 22), "固有尺寸必须钉在 22，别被 SwiftUI 拉伸")
        let source = try repositorySource("DynamicIsland/components/Calendar/MeetingActionView.swift")
        XCTAssertTrue(source.contains("width: MeetingActionPresentation.iconSide, height: MeetingActionPresentation.iconSide"))
        // 自绘 NSView 默认不是无障碍元素，必须显式声明 + 角色（审查 I-3）
        XCTAssertTrue(source.contains("setAccessibilityElement(true)"))
        XCTAssertTrue(source.contains("setAccessibilityRole(.button)"))
        XCTAssertTrue(source.contains(#"NSLocalizedString("calendar.meeting.actions""#),
                      "图标按钮的无障碍标签仍复用 calendar.meeting.actions")
        // 旧形态：整栏宽的文字按钮 + 最多 15 项的系统菜单 + AI 兜底 + 时间闸门/发送范围说明
        for gone in ["NSButton(title:", "candidate.submenu", "calendar.meeting.recognize", "calendar.meeting.choose",
                               "calendar.meeting.copyLink", "calendar.meeting.tooEarly", "calendar.meeting.menuHelp",
                               "calendar.meeting.sendingScope", "calendar.generation.settings", "isJoinable"] {
            XCTAssertFalse(source.contains(gone), "\(gone) 不应再出现在会议入口视图里")
        }
    }

    /// 形态分派：首页两处走默认 `.icon`，面板与详情显式要 `.row`（设计图 ④）。
    func testMeetingActionStylesDispatchIconOnHomeAndRowInThePanel() throws {
        let session = makeSession()
        let source = CalendarMeetingSource(event: event(notes: MeetingInvitationFixtures.huawei))
        XCTAssertEqual(MeetingActionView(source: source, session: session).style, .icon)
        XCTAssertEqual(MeetingActionView(event: event(notes: MeetingInvitationFixtures.huawei), session: session).style, .icon)
        XCTAssertEqual(MeetingActionView(source: source, session: session, style: .row).style, .row)

        let panel = try repositorySource("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        // docs/49 D-19（2026-10-15）：面板列表行的会议入口与首页同款——一枚 22×22 图标按钮
        // （点 = 打开 / 复制、右键 = 菜单），不再是 `.row` 的两枚文字键；「平台名 + 会议号」留作文字信息。
        XCTAssertTrue(panel.contains("MeetingActionView(event: event, session: session)"))
        XCTAssertFalse(panel.contains("style: .row"), "面板行不许再用 `.row` 形态")
        let detail = try repositorySource("DynamicIsland/components/Calendar/DynamicIslandCalendar.swift")
        XCTAssertTrue(detail.contains("style: .row"))
        let todos = try repositorySource("DynamicIsland/Modules/TodosModule.swift")
        XCTAssertTrue(todos.contains("MeetingActionView(source: source, session: session)"))
        XCTAssertFalse(todos.contains("style: .row"), "首页不许被改成 .row")
        // 编辑页本体仍在（T2 只重排两列网格与清理文案：模型说明行已删、设置按钮降级为齿轮）
        XCTAssertTrue(panel.contains("private var editorPage: some View"))
        XCTAssertTrue(panel.contains(#".help(Text("calendar.generation.settings"))"#))
        XCTAssertTrue(panel.contains(#"label: { Image(systemName: "gearshape") }"#))
    }

    private func languageBundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"),
                                 "宿主 bundle 里找不到 \(language).lproj")
        return try XCTUnwrap(Bundle(path: path))
    }

    private func repositorySource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testCodeOnlyMeetingCopiesExactEvidenceWithoutConstructingURL() async throws {
        let session = makeSession(), opener = MeetingFakeOpener([true])
        var copied: [String] = []
        let model = MeetingActionModel(event: event(notes: "会议ID：987654321"), session: session,
                                      opener: opener, copyText: { copied.append($0) })
        let target = try XCTUnwrap(model.targets.first)
        XCTAssertFalse(target.canOpen)
        model.copy(target.meetingCodes[0].sourceText)
        model.open(target)
        XCTAssertEqual(copied, ["会议ID：987654321"])
        XCTAssertTrue(opener.urls.isEmpty)
    }

    func testSettingsRequestPersistsBeforeAppearanceAndRepeatClearsSearch() {
        let navigation = CalendarAISettingsNavigation()
        var tab = SettingsTab.general
        var search = "old filter"
        navigation.request()
        XCTAssertNotNil(navigation.pendingRequest)
        navigation.consume(selectedTab: &tab, searchText: &search)
        XCTAssertEqual(tab, .generalAI)
        XCTAssertEqual(search, "")
        XCTAssertNil(navigation.pendingRequest)
        tab = .calendar
        search = "new filter"
        navigation.request()
        navigation.request()
        navigation.consume(selectedTab: &tab, searchText: &search)
        XCTAssertEqual(tab, .generalAI)
        XCTAssertEqual(search, "")
        tab = .general
        search = "keep without request"
        navigation.consume(selectedTab: &tab, searchText: &search)
        XCTAssertEqual(tab, .general)
        XCTAssertEqual(search, "keep without request")
    }

    func testCalendarActualContentSurfaceKeepsOwnedSessionThroughPanelMeetingAction() async throws {
        let owned = makeSession()
        let backend = CalendarInteractionFixtures.makeBackend(count: 0, on: reference)
        let manager = CalendarManager(service: backend, now: { self.reference }, startMonitoring: false)
        let context = ModuleContextFactory.make(manifest: CalendarModule.manifest, redraw: {})
        let module = CalendarModule(context: context, session: owned, manager: manager)
        try await module.activate()
        let request = ContentRequest(surface: .expanded, phase: .expanded, reason: .initial)
        guard case .view = module.content(for: request) else { return XCTFail("Actual calendar content must create its expanded surface") }
        let surface = module.expandedSurface()
        XCTAssertTrue(surface.session === owned)
        XCTAssertTrue(surface.calendarManager === manager)
        let panel = surface.panelPages(onReturnSource: { _ in })
        XCTAssertTrue(panel.session === owned)
        let action = panel.meetingAction(event(notes: MeetingInvitationFixtures.huawei))
        XCTAssertTrue(action.session === owned)
        let opener = MeetingFakeOpener([])
        let model = MeetingActionModel(source: action.source, session: action.session, opener: opener, copyText: { _ in })
        XCTAssertFalse(model.targets.isEmpty)
        XCTAssertTrue(opener.urls.isEmpty)
        await module.deactivate()
    }

    func testTodosActualHomeSurfaceRowsKeepOwnedSessionWithoutCalendarNavigation() async throws {
        let owned = makeSession()
        let backend = CalendarInteractionFixtures.makeBackend(count: 0, on: reference)
        let manager = CalendarManager(service: backend, now: { self.reference }, startMonitoring: false)
        let context = ModuleContextFactory.make(manifest: TodosModule.manifest, redraw: {})
        let store = TodoStore(logger: context.logger, fixtureBackend: backend)
        let module = TodosModule(context: context, session: owned, manager: manager, store: store)
        try await module.activate()
        guard case .view = module.content(for: ContentRequest(surface: .home, phase: .expanded, reason: .initial)) else {
            return XCTFail("Actual todos content must create its home surface")
        }
        let surface = module.homeSurface()
        XCTAssertTrue(surface.session === owned)
        XCTAssertTrue(surface.calendarManager === manager)
        XCTAssertTrue(surface.store === store)
        let list = surface.listContent.withTier(.full)
        XCTAssertTrue(list.session === owned)
        // No registry activation is required for the meeting branch. Navigation is separately disabled.
        let unavailableCalendarList = TodoHomeTodayList(entries: [], reminderRecords: [:], tier: .full, session: list.session,
                                                        details: CalendarEventDetailsModel(),
                                                        canOpenDetail: false, isSubmitting: false,
                                                        openEvent: { _ in XCTFail("Must not navigate") },
                                                        openTodo: { _ in XCTFail("Must not navigate") }, completeTodo: { _ in },
                                                        editEvent: { _ in }, deleteEvent: { _ in }, deleteItem: { _ in })
        let row = unavailableCalendarList.eventRow(event(notes: MeetingInvitationFixtures.huawei))
        XCTAssertFalse(row.canOpenDetail)
        let action = try XCTUnwrap(row.meetingAction)
        XCTAssertTrue(action.session === owned)
        let opener = MeetingFakeOpener([])
        let model = MeetingActionModel(source: action.source, session: action.session, opener: opener, copyText: { _ in })
        XCTAssertFalse(model.targets.isEmpty)
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertFalse(store.hasInitializedEventStore)
        await module.deactivate()
    }

    /// T5：今日块分组标题带**本组过滤后**的条目数（`日程 · 2` / `待办 · 2`），
    /// 且「条目为空的分组不渲染」（只有待办时不会画出空的「日程 · 0」）。
    /// 断言全部落在返回值上（`TodoText.groupHeaders` 是视图与单测共用的纯函数）。
    func testTodayBlockGroupHeadersCarryPerGroupCountsWithoutEmptyGroups() throws {
        let zh = try languageBundle("zh-Hans"), en = try languageBundle("en")
        XCTAssertEqual(TodoText.groupHeaderTitle(TodoText.kindEventKey, count: 2, bundle: zh), "日程 · 2")
        XCTAssertEqual(TodoText.groupHeaderTitle(TodoText.kindReminderKey, count: 2, bundle: zh), "待办 · 2")
        XCTAssertEqual(TodoText.groupHeaderTitle(TodoText.kindEventKey, count: 1, bundle: en), "Event · 1")
        XCTAssertEqual(TodoText.groupHeaderTitle(TodoText.kindReminderKey, count: 3, bundle: en), "To-do · 3")

        let eventKey = TodoText.kindEventKey, reminderKey = TodoText.kindReminderKey
        // 2 日程 + 2 待办 → 两组，各带**本组**的条数（不是总数、也不是未过滤集合）
        XCTAssertEqual(todayBlockGroups(events: 2, todos: 2),
                       [TodoText.Group(key: eventKey, count: 2), TodoText.Group(key: reminderKey, count: 2)])
        // 只有待办 → 不出现空的「日程 · 0」
        XCTAssertEqual(todayBlockGroups(events: 0, todos: 2), [TodoText.Group(key: reminderKey, count: 2)])
        // 只有日程 → 同理不出现「待办 · 0」
        XCTAssertEqual(todayBlockGroups(events: 3, todos: 0), [TodoText.Group(key: eventKey, count: 3)])
        XCTAssertEqual(todayBlockGroups(events: 0, todos: 0), [])
        // 计数是过滤后的剩余条数：3 条待办里 1 条已完成（默认隐藏已完成）→ 「待办 · 2」
        XCTAssertEqual(todayBlockGroups(events: 0, todos: 3, completed: 1), [TodoText.Group(key: reminderKey, count: 2)])
        // 未授权时待办侧不给条目（`listedEntries` 口径）→ 只剩日程组
        XCTAssertEqual(todayBlockGroups(events: 2, todos: 2, hasFullAccess: false), [TodoText.Group(key: eventKey, count: 2)])
    }

    /// 用生产口径造今日块条目（`TodoHomeBlockLayout.listedEntries`：日程按时间在前、待办去重接后、
    /// 已完成的提醒按默认开启的「隐藏已完成」剔掉），再取分组标题方案。
    private func todayBlockGroups(events: Int, todos: Int, completed: Int = 0,
                                  hasFullAccess: Bool = true) -> [TodoText.Group] {
        let template = CalendarInteractionFixtures.makeBackend(count: 1, on: reference).event(withID: "fixture-event-01")!
        let eventList = (0..<events).map { index in
            EventModel(id: "today-event-\(index)", start: reference, end: reference.addingTimeInterval(3_600),
                       title: "日程 \(index)", location: nil, notes: nil, url: nil, isAllDay: false,
                       type: template.type, calendar: template.calendar, participants: [], timeZone: template.timeZone,
                       hasRecurrenceRules: false, priority: nil, conferenceURL: nil, isDetached: false)
        }
        let todoList = (0..<todos).map { index in
            TodoBucketing.Item(id: "today-todo-\(index)", title: "待办 \(index)", dueDate: reference,
                               isCompleted: index < completed, completionDate: nil, listName: "Fixture")
        }
        return TodoText.groupHeaders(for: TodosHomeBlockLayout.listedEntries(
            events: eventList, todos: todoList, hasFullAccess: hasFullAccess, hideCompletedReminders: true))
    }

    func testSourceAwareHomeEntryIncludesAmbiguousLongCodeAndInvitationButHidesOrdinaryItems() throws {
        let owned = makeSession()
        let list = TodoHomeTodayList(entries: [], reminderRecords: [:], tier: .full, session: owned,
                                     details: CalendarEventDetailsModel(),
                                    canOpenDetail: false, isSubmitting: false, openEvent: { _ in }, openTodo: { _ in },
                                    completeTodo: { _ in }, editEvent: { _ in }, deleteEvent: { _ in }, deleteItem: { _ in })
        for notes in [MeetingInvitationFixtures.huaweiHTTPS,
                      MeetingInvitationFixtures.huaweiHTTPS + "\n" + MeetingInvitationFixtures.tencent,
                      String(repeating: "长备注\n", count: 5_000) + MeetingInvitationFixtures.huaweiHTTPS,
                      "会议ID：987654321", "会议邀请：请加入会议，入口稍后通知"] {
            let row = list.eventRow(event(notes: notes))
            XCTAssertNotNil(row.meetingAction, notes)
            XCTAssertTrue(row.meetingAction?.session === owned)
        }
        XCTAssertNil(list.eventRow(event(notes: "整理会议室，准备投影仪")).meetingAction)
        let item = TodoBucketing.Item(id: "fallback", title: "会议邀请：请参加会议", dueDate: nil, isCompleted: false,
                                     completionDate: nil, listName: "Fixture")
        let fallback = list.todoRow(item)
        let action = try XCTUnwrap(fallback.meetingAction)
        XCTAssertTrue(action.session === owned)
        XCTAssertNil(action.source.start)
        XCTAssertTrue(action.source.targets.isEmpty)
        let model = MeetingActionModel(source: action.source, session: owned, opener: MeetingFakeOpener([]), copyText: { _ in })
        XCTAssertEqual(model.primary, .none, "没有可打开候选也没有会议号时不臆造动作（时间闸门不再挡路）")
        let undated = EventModel(id: "undated", start: .distantFuture, end: .distantFuture, title: "会议ID：987654321",
                                 location: nil, notes: nil, url: nil, isAllDay: true, type: .reminder(completed: false),
                                 calendar: event(notes: "").calendar, participants: [], timeZone: nil, hasRecurrenceRules: false,
                                 priority: nil, conferenceURL: nil)
        XCTAssertNil(CalendarMeetingSource(event: undated).start)
        XCTAssertNotNil(list.eventRow(undated).meetingAction)
        XCTAssertEqual(CalendarMeetingSource(event: event(notes: MeetingInvitationFixtures.huaweiHTTPS,
                                                         start: reference.addingTimeInterval(10_000_000))).start,
                       reference.addingTimeInterval(10_000_000))
    }

    func testInvitationIntentExcludesPlaceAndMaterialNounsWhileKeepingFollowUpActions() async {
        let owned = makeSession()
        let list = TodoHomeTodayList(entries: [], reminderRecords: [:], tier: .full, session: owned,
                                     details: CalendarEventDetailsModel(),
                                    canOpenDetail: false, isSubmitting: false, openEvent: { _ in }, openTodo: { _ in },
                                    completeTodo: { _ in }, editEvent: { _ in }, deleteEvent: { _ in }, deleteItem: { _ in })
        for notes in ["请参加会议室保洁工作", "欢迎加入会议室保洁工作", "邀请你参加会议室保洁工作",
                      "请参加会议记录整理", "请加入会议材料准备", "制作会议邀请函模板",
                      "Please join the meetingroom cleaning task", "Please join the meeting room cleaning task",
                      "You are invited to a conference room cleaning task", "请参加会议纪要整理", "请加入会议资料归档",
                      "Please join the meeting notes preparation task", "Please join the meeting-room cleaning task",
                      "You are invited to a conference-room cleaning task", "Please join the meeting rooms cleaning task",
                      "You are invited to the conference-rooms cleaning task", "Please join the meeting-rooms cleaning task",
                      "You are invited to the conference rooms cleaning task", "https://meeting.tencent.com.evil/dm/fixture",
                      "https://evil.example/meeting.tencent.com/dm/fixture"] {
            let source = CalendarMeetingSource(event: event(notes: notes))
            XCTAssertTrue(source.targets.isEmpty, notes)
            XCTAssertFalse(source.hasMeetingInformation, notes)
            XCTAssertNil(list.eventRow(event(notes: notes)).meetingAction, notes)
        }
        for notes in ["请参加会议", "请参加年度总结会议。", "邀请你加入会议：年度计划讨论", "欢迎参加会议！",
                      "会议邀请：请加入会议，入口稍后通知", "会议主题：年度计划", "会议链接：稍后提供",
                      "Meeting invitation: annual planning", "Please join the meeting.", "You are invited to a conference.",
                      "会议ID：987654321", MeetingInvitationFixtures.huawei, MeetingInvitationFixtures.tencent,
                      MeetingInvitationFixtures.feishu, "请参加会议并做好准备", "欢迎加入会议进行讨论"] {
            XCTAssertTrue(CalendarMeetingSource(event: event(notes: notes)).hasMeetingInformation, notes)
            XCTAssertNotNil(list.eventRow(event(notes: notes)).meetingAction, notes)
        }
        let opener = MeetingFakeOpener([])
        let emptyInvitation = MeetingActionModel(event: event(notes: "请参加会议并做好准备"), session: owned,
                                                 opener: opener, copyText: { _ in })
        let unrelatedTarget = MeetingLinkResolver().resolve(text: MeetingInvitationFixtures.huaweiHTTPS)[0]
        XCTAssertEqual(emptyInvitation.primary, .none, "邀请意图本身不带会议号，主动作不臆造")
        XCTAssertTrue(unrelatedTarget.canOpen)
        emptyInvitation.open(unrelatedTarget)
        XCTAssertFalse(emptyInvitation.isOpening, "Invitation intent must not authorize another source's URL")
        XCTAssertTrue(opener.urls.isEmpty)
    }

    // MARK: - T2 统一表单：两列网格 + 文案清理（挂载取证，先例 PanelAutoHeightTests.mountPanelPage）

    /// 编辑页四个入口的会话：新建日程 / 新建待办 / 编辑日程（真 `beginEdit`）/ 编辑待办
    /// （当前代码里 `beginEdit` 硬编码 `.event`，这条只能按注入草稿覆盖，且它不可保存）。
    private func editorSession(kind: CalendarDraft.Kind, editing: Bool) -> (CalendarPanelSession, CalendarManager) {
        let backend = CalendarInteractionFixtures.makeBackend(count: 1, on: reference)
        let session = CalendarPanelSession(selectedDate: reference, now: { self.reference },
                                           saveEvent: { try await backend.saveEvent(input: $0, eventID: $1) },
                                           createReminder: { try await backend.createReminderRecord(input: $0) },
                                           deleteEvent: { try await backend.deleteEvent(id: $0) },
                                           completeReminder: { try await backend.completeReminder(id: $0, completed: $1) },
                                           event: { backend.event(withID: $0) })
        let manager = CalendarManager(service: backend, now: { self.reference }, startMonitoring: false)
        let calendarID = kind == .event ? "fixture-events" : "fixture-reminders"
        if editing, kind == .event, let event = backend.event(withID: "fixture-event-01") {
            session.beginEdit(event)
        } else if editing {
            session.beginCreate(kind: kind, on: reference, calendarID: calendarID)
            session.draft?.eventID = "fixture-reminder-01"
        } else {
            session.beginCreate(kind: kind, on: reference, calendarID: calendarID)
        }
        return (session, manager)
    }

    /// 生产编辑页挂进 `NSHostingView`（真布局、真 `NSViewRepresentable`）。
    private func mountEditor(_ session: CalendarPanelSession, manager: CalendarManager) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: CalendarPanelPages(session: session, manager: manager, onReturnSource: { _ in })
            .environmentObject(DynamicIslandViewModel())
            .frame(width: 437, height: 400))
        host.frame = CGRect(x: 0, y: 0, width: 437, height: 400)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func settle(_ host: NSView) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
    }

    /// 把真两栏的 `StandaloneCalendarView` 挂在给定宽度（T3 / D-09：编辑档宽度的**关系式**取证）。
    private func mountStandaloneCalendar(session: CalendarPanelSession, manager: CalendarManager,
                                         width: CGFloat, height: CGFloat = 400) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: StandaloneCalendarView(session: session, manager: manager)
            .environmentObject(DynamicIslandViewModel())
            .frame(width: width, height: height))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// 把 `CalendarPanelPages` 单独挂在给定宽度（T3：借它量「右栏自身的内边距」，用来把编辑区宽度写成关系式）。
    private func mountPanelPages(session: CalendarPanelSession, manager: CalendarManager,
                                 width: CGFloat, height: CGFloat = 400) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: CalendarPanelPages(session: session, manager: manager, onReturnSource: { _ in })
            .environmentObject(DynamicIslandViewModel())
            .frame(width: width, height: height))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// 固定日历（格里高利 + GMT + `en_US_POSIX` + `firstWeekday`，与 `MonthGridLayoutTests` 同式）。
    private func fixedGridCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    /// 固定月份的首日零点。
    private func fixedMonth(_ year: Int, _ month: Int) -> Date {
        fixedGridCalendar(firstWeekday: 1).date(from: DateComponents(year: year, month: month, day: 1))!
    }

    private func collectViews(_ host: NSView, where match: (NSView) -> Bool) -> [NSView] {
        var found: [NSView] = []
        func walk(_ view: NSView) {
            if match(view) { found.append(view) }
            view.subviews.forEach(walk)
        }
        walk(host)
        return found
    }

    private func sourceEditors(in host: NSView) -> [CalendarEditableTextView] {
        let label = NSLocalizedString("calendar.generation.source", comment: "")
        return collectViews(host) { ($0 as? CalendarEditableTextView)?.accessibilityLabel() == label }
            .compactMap { $0 as? CalendarEditableTextView }
    }

    private func notesEditors(in host: NSView) -> [CalendarEditableTextView] {
        let label = NSLocalizedString("calendar.panel.notes", comment: "")
        return collectViews(host) { ($0 as? CalendarEditableTextView)?.accessibilityLabel() == label }
            .compactMap { $0 as? CalendarEditableTextView }
    }

    /// 挂载后能直接观察到的字段签名：`NSViewRepresentable` 撑起的本地控件 + SwiftUI `TextField`
    /// 背后的 `NSTextField` / `DatePicker` 背后的 `NSDatePicker`。
    private struct EditorFieldSignature: Equatable {
        var sourceEditors: Int
        var notesEditors: Int
        var notesWidth: CGFloat
        var popups: Int
        var targetWidth: CGFloat
        var targetTitles: [String]
        var textFields: Int
        var datePickers: Int
    }

    private func editorSignature(_ session: CalendarPanelSession, manager: CalendarManager) -> EditorFieldSignature {
        let host = mountEditor(session, manager: manager)
        settle(host)
        let notes = notesEditors(in: host)
        let popups = collectViews(host) { $0 is NSPopUpButton }.compactMap { $0 as? NSPopUpButton }
        return EditorFieldSignature(
            sourceEditors: sourceEditors(in: host).count,
            notesEditors: notes.count,
            notesWidth: notes.first?.bounds.width ?? -1,
            popups: popups.count,
            targetWidth: popups.first?.bounds.width ?? -1,
            targetTitles: popups.first?.itemTitles ?? [],
            textFields: collectViews(host) { $0 is NSTextField }.count,
            datePickers: collectViews(host) { $0 is NSDatePicker }.count
        )
    }

    /// T2 / D-01·D-02·D-05：四种入口渲染出**同一套字段**，差异只有三处 —— 类型控件可点 / 锁定、
    /// 生成行有无、时间块两格 / 一格 + 地点有无。取证分两半：
    /// ① 挂载：能观察到的本地控件给出**数量与几何**（备注整宽、目标占半格、生成行只在新建、
    ///    日程比待办多一个时刻控件与一个地点输入框）；
    /// ② 源码检索：SwiftUI 原生 `HStack`/`Text` 在宿主里不是 `NSView`，因此「目标｜全天」「地点｜链接」
    ///    的并排关系与类型控件的 `disabled` 只能按源码取证。
    func testUnifiedEditorFormPairsFieldsAndHidesBoilerplate() throws {
        for (name, kind, editing) in [("newEvent", CalendarDraft.Kind.event, false),
                                      ("newReminder", CalendarDraft.Kind.reminder, false),
                                      ("editEvent", CalendarDraft.Kind.event, true),
                                      ("editReminder", CalendarDraft.Kind.reminder, true)] {
            let (session, manager) = editorSession(kind: kind, editing: editing)
            XCTAssertEqual(session.route, .editor, name)
            XCTAssertEqual(session.draft?.eventID == nil, !editing, name)
            // 待办默认全天：关掉它，才能观察「截止」那一格的时刻控件（时间块一格）。
            if kind == .reminder { session.draft?.isAllDay = false }
            let signature = editorSignature(session, manager: manager)
            let isEvent = kind == .event

            // 备注整宽：它的原生编辑器宽度就是页面内容宽。
            XCTAssertEqual(signature.notesEditors, 1, name)
            XCTAssertEqual(signature.notesWidth, 433, accuracy: 0.5, "\(name)：备注占满整宽")
            // 目标占左半格：宽度 = (内容宽 − 8) / 2 —— 右格就是同一行的「全天」。
            XCTAssertEqual(signature.popups, 1, name)
            XCTAssertEqual(signature.targetTitles.count, 1, name)
            XCTAssertEqual(signature.targetWidth, (signature.notesWidth - 8) / 2, accuracy: 1,
                           "\(name)：目标与「全天」并排各占半宽")
            // 生成行只有新建有。
            XCTAssertEqual(signature.sourceEditors, editing ? 0 : 1, name)
            // 时间两格 / 一格：日程多一个时刻控件（开始 + 结束，待办只有「截止」）。
            XCTAssertEqual(signature.datePickers, isEvent ? 2 : 1, "\(name)：时间块 \(isEvent ? "两格" : "一格")")
            // 地点有无：日程多一个输入框（标题 + 地点 + 链接 / 标题 + 链接）。
            XCTAssertEqual(signature.textFields, isEvent ? 3 : 2, "\(name)：\(isEvent ? "有地点" : "无地点")")
        }

        let panel = try repositorySource("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        // 抽出的「一格」helper：标签在上、控件在下。
        XCTAssertTrue(panel.contains(
            "private func fieldRow(_ label: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View"))
        XCTAssertEqual(panel.components(separatedBy: "fieldRow(").count - 1, 5,
                       "1 处声明 + 4 处调用（标题 / 全天 / 地点 / 链接）——备注改由框自身承担落点（T2 本轮）")
        // 三组并排：目标｜全天、开始｜结束（待办一格）、地点｜链接（待办无地点）。
        XCTAssertTrue(panel.contains("targetPicker(draft).frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(panel.contains(#"fieldRow("All-day")"#))
        XCTAssertTrue(panel.contains(#"dateRow("calendar.panel.start""#))
        XCTAssertTrue(panel.contains(#"dateRow("calendar.panel.end""#))
        XCTAssertTrue(panel.contains(#"dateRow("calendar.panel.dueDate""#))
        XCTAssertTrue(panel.contains(#"fieldRow("calendar.panel.location")"#))
        XCTAssertTrue(panel.contains(#"fieldRow("calendar.panel.url")"#))
        XCTAssertTrue(panel.contains(#"placeholder: "calendar.panel.notes""#),
                      "备注的落点在框内（占位文字复用既有键，T2 本轮）")
        // 类型控件新建可点、编辑锁定（`disabled` 而不是整段不渲染）。
        XCTAssertTrue(panel.contains(#".accessibilityIdentifier("calendar-kind")"#))
        XCTAssertTrue(panel.contains(".disabled(draft.eventID != nil)"))
        // 常驻文案已删（失败信号：页面上还能看到任一句）。
        for gone in [#"Text("calendar.generation.sendingScope")"#, #"Text("calendar.generation.model")"#,
                     #"Text("calendar.panel.additional")"#, #"Button("calendar.generation.settings")"#] {
            XCTAssertFalse(panel.contains(gone), "\(gone) 不应再出现在编辑页")
        }
        XCTAssertTrue(panel.contains(#"case .ready: "calendar.generation.generate""#), "「生成」按钮用新键（三态共用一枚，见 T3）")
    }

    /// T2 / D-03·D-04：AI 模型设置只以齿轮出现；失败时只留一行「生成失败：<原因>」+ 重试。
    func testEditorFailureShowsASingleLineAndGearOpensAISettings() async throws {
        let (session, manager) = editorSession(kind: .event, editing: false)
        let host = mountEditor(session, manager: manager)
        settle(host)
        XCTAssertNil(session.configuredAI, "这条用例走「没有 AI 句柄」的失败路径")
        // 点「生成」＝ commitSourceForGeneration + generateDraft（没有 AI 就同步进失败态）。
        session.commitSourceForGeneration("明天下午五点周会")
        await session.generateDraft()
        settle(host)
        XCTAssertEqual(session.generationState, .failed)
        XCTAssertNotNil(session.generationError, "那一行红字取的就是 generationError")
        XCTAssertEqual(sourceEditors(in: host).count, 1, "失败后编辑页仍在，生成行的输入框不消失")

        let panel = try repositorySource("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        // 失败只保留一行：状态词 + 错误原因 + 重试（旧的状态词一行 + 独立红字一行已合并）。
        XCTAssertTrue(panel.contains(#"Text("calendar.generation.state.failed")"#))
        XCTAssertTrue(panel.contains(#"case .failed: "calendar.generation.retry""#),
                      "重试文案挂在三态共用的那枚按钮上（不再是失败行里的第二个入口）")
        XCTAssertFalse(panel.contains(#"Button("calendar.generation.retry")"#), "失败行不许再出现第二个重试入口")
        XCTAssertFalse(panel.contains(#".accessibilityIdentifier("calendar-generation-state")"#),
                       "状态词不再单独占一行")
        XCTAssertFalse(panel.contains("generationState.labelKey"), "成功 / 等待不占行")
        XCTAssertFalse(panel.contains(#".accessibilityIdentifier("calendar-generation-error")"#),
                       "失败红字已并进那一行")
        // AI 模型设置：按钮降级为生成行右端的齿轮，文案仍走既有键（`.help` 与无障碍标签）。
        XCTAssertTrue(panel.contains(#"label: { Image(systemName: "gearshape") }"#))
        XCTAssertTrue(panel.contains(#".help(Text("calendar.generation.settings"))"#))
        XCTAssertTrue(panel.contains(#".accessibilityLabel(Text("calendar.generation.settings"))"#))
        XCTAssertTrue(panel.contains("CalendarAISettingsNavigation.open()"), "齿轮仍接 AI 设置页的入口")
    }

    /// T3 / V5（D-07·D-09）：日历页**按档报自然高**——编辑档列高 400（账本 = 400 + 表头 − 16）、列表档仍是
    /// `monthGridHeight`（2026-10 = 278）；编辑档左栏宽 260、两栏高 400、编辑区宽 = 宿主内容宽 −
    /// 260 − 栏间距 12 − 该栏自身内边距（**关系式，不写死 615**）。三层判据照
    /// `PanelAutoHeightTests.testCalendarIsAMeasuredTab`：① 键字面量 ② 名单含它 ③ 账本行为。
    func testCalendarPageReportsEditorModeNaturalHeight() throws {
        // ① 键：编辑档 = 页键；列表 / 详情档 = 模块 id（**现键不变**）。
        XCTAssertEqual(PanelContentHeight.calendarEditorTab, "calendarEditor")
        XCTAssertEqual(calendarPanelTabKey(route: .editor), PanelContentHeight.calendarEditorTab)
        XCTAssertEqual(calendarPanelTabKey(route: .list), CalendarModule.moduleID)
        XCTAssertEqual(calendarPanelTabKey(route: .list), CalendarModule.moduleID,
                       "T6：详情档退休，非编辑档只有列表这一档")

        // ② 名单：编辑档有自然高 400，因此在名单里（探针据此进门）。
        XCTAssertTrue(PanelContentHeight.measuredTabs.contains(PanelContentHeight.calendarEditorTab))
        XCTAssertTrue(PanelContentHeight.isMeasuredTab(PanelContentHeight.calendarEditorTab))

        // ③ 账本行为：编辑档自然高 448 → 448 + 表头 28 − 16 = 460；切回列表档**回落**当月自然高。
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }
        // 先量列表档：2026-10 = 5 周 → 278（`43 × 5 + 63`）→ 账本口径 290。
        let listNatural = MonthGridLayout.monthGridHeight(
            forMonth: fixedMonth(2026, 10), calendar: fixedGridCalendar(firstWeekday: 1)
        )
        XCTAssertEqual(listNatural, 278, accuracy: 1e-9, "前提：2026-10 = 5 周 → 43 × 5 + 63")
        ledger.selectTab(CalendarModule.moduleID)
        // 账本口径不手抄算式：走唯一真源换算（`PanelAutoHeight.measuredContentHeight`，docs/29 D-38），表头取测试桩 28。
        ledger.report(PanelAutoHeight.measuredContentHeight(naturalHeight: listNatural, headerHeight: 28),
                      for: CalendarModule.moduleID)
        XCTAssertEqual(ledger.current ?? 0, 290, accuracy: 1e-9,
                       "列表档：当月自然高 278 → 账本 290（表头取测试桩 28）")

        // 编辑档：两栏都钉 448（视图声明的常量，2026-10-16 由 400 抬高），账本口径走真实换算 → 460。
        XCTAssertEqual(StandaloneCalendarView.editorPaneHeight, 448, "编辑档列高 = 448（视图声明）")
        ledger.selectTab(PanelContentHeight.calendarEditorTab)
        XCTAssertEqual(ledger.activeTab, PanelContentHeight.calendarEditorTab)
        ledger.report(PanelAutoHeight.measuredContentHeight(
            naturalHeight: StandaloneCalendarView.editorPaneHeight, headerHeight: 28
        ), for: PanelContentHeight.calendarEditorTab)
        XCTAssertEqual(ledger.current ?? 0, 460, accuracy: 1e-9,
                       "编辑档：账本值 = measuredContentHeight(列高 448, 表头取测试桩 28) = 460")
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(contentHeight: 460, mode: PanelAutoHeight.modeAuto,
                                        manualHeight: 682, screenVisibleHeight: nil),
            500, accuracy: 1e-9,
            "auto 档：面板高 = 账本值 + homeVerticalPadding(40)；账本值 460 = 448 + 表头(测试桩 28) − 16"
                + "；真机表头 32 → 真机面板 504（448 + 32 − 16 + 40）——抬高编辑器高度后（2026-10-16 方案一）"
                + "面板比列表档那档高约 48pt（manual 档面板高由 openNotchHeight 决定）"
        )

        // 切回列表档：读缓存一步回落（不是停在编辑档的 412）——失败信号「切回列表档后高度没回落」的反证。
        ledger.selectTab(CalendarModule.moduleID)
        XCTAssertEqual(ledger.current ?? 0, 290, accuracy: 1e-9,
                       "切回列表档 → 回落当月自然高（编辑档的 460 不留在列表档）")

        // 几何：编辑档挂进 `NSHostingView`——编辑区内容宽随宿主宽**线性**变化（左栏 260 与栏间距 12
        // 在两次里都固定）。**两个不同宿主宽**各挂一次，断言两次读数的差 = 宿主宽之差：
        // 「把编辑区宽写死 615」这种改法必红（写死时两次读数相同、差为 0）。
        let (session, manager) = editorSession(kind: .event, editing: false)
        XCTAssertEqual(session.route, .editor)
        func editorPaneContentWidth(hostWidth: CGFloat) -> CGFloat {
            let host = mountStandaloneCalendar(session: session, manager: manager, width: hostWidth)
            settle(host)
            return notesEditors(in: host).first?.bounds.width ?? -1
        }
        let narrowHostWidth: CGFloat = 700
        let wideHostWidth: CGFloat = 887
        let narrowEditorWidth = editorPaneContentWidth(hostWidth: narrowHostWidth)
        let wideEditorWidth = editorPaneContentWidth(hostWidth: wideHostWidth)
        XCTAssertGreaterThan(narrowEditorWidth, 0, "编辑档右栏应渲染出备注编辑器（窄宿主）")
        XCTAssertGreaterThan(wideEditorWidth, 0, "编辑档右栏应渲染出备注编辑器（宽宿主）")
        XCTAssertEqual(wideEditorWidth - narrowEditorWidth, wideHostWidth - narrowHostWidth, accuracy: 0.5,
                       "编辑区内容宽随宿主宽线性变化：Δ读数 = Δ宿主宽（左栏 260 与栏间距 12 固定）")
        // 关系式（单点校核）：编辑区内容宽 = 宿主内容宽 − 左栏 260 − 栏间距 12 − 该栏自身内边距。
        // 内边距不写死：把同一份 `CalendarPanelPages` 单独挂在「右栏应得宽」上，读到的备注编辑器宽即
        // 「右栏宽 → 该栏内容宽」的换算结果。
        let rightPaneWidth = wideHostWidth - StandaloneCalendarView.editorSidebarWidth
            - StandaloneCalendarView.paneSpacing
        let alone = mountPanelPages(session: session, manager: manager, width: rightPaneWidth)
        settle(alone)
        let aloneWidth = notesEditors(in: alone).first?.bounds.width ?? -1
        XCTAssertGreaterThan(aloneWidth, 0)
        XCTAssertEqual(wideEditorWidth, aloneWidth, accuracy: 0.5,
                       "编辑区内容宽 = 宿主内容宽 − 左栏 260 − 栏间距 12 − 该栏内边距（关系式，不写死 615）")
        // 左栏 260 / 两栏 400 是 SwiftUI 原生视图（不是 NSView），按源码取证（派发片段裁决 7 允许的降级）。
        let source = try repositorySource("DynamicIsland/components/Calendar/DynamicIslandCalendar.swift")
        XCTAssertTrue(source.contains("static let editorSidebarWidth: CGFloat = 260"), "左栏宽 260")
        XCTAssertTrue(source.contains("static let editorPaneHeight: CGFloat = 448"),
                      "两栏高 448（2026-10-16 由 400 抬高，见设计图 F2 方案一）")
        XCTAssertTrue(source.contains(".frame(width: Self.editorSidebarWidth, height: Self.editorPaneHeight"),
                      "编辑档左栏钉宽 260 + 钉高 448")
    }

    /// T3 / 失败信号反证：「选中日记录很多时编辑档自然高 > 400（左栏没钉高）」。
    ///
    /// 编辑档 + 选中日塞 **8+ 条**记录，量这一页的**理想高**（只钉宽、不钉高，读
    /// `NSHostingView.fittingSize.height`——与账本探针 `PanelNaturalHeightLayout` 的「宽给定、高留空」
    /// 同一口径）。左栏若被去掉钉高，ScrollView 的理想高会随卡片数长到 8 × 卡片高（数百 pt）→ 本断言红。
    /// 公差 1pt：吸收 `NSHostingView` 的量化与 AppKit 取整。
    func testEditorModeKeepsThePinnedPaneHeightWithManyDayRecords() async throws {
        let backend = CalendarInteractionFixtures.makeBackend(count: 8, on: reference)
        let session = CalendarPanelSession(selectedDate: reference, now: { self.reference },
                                           saveEvent: { try await backend.saveEvent(input: $0, eventID: $1) },
                                           createReminder: { try await backend.createReminderRecord(input: $0) },
                                           deleteEvent: { try await backend.deleteEvent(id: $0) },
                                           completeReminder: { try await backend.completeReminder(id: $0, completed: $1) },
                                           event: { backend.event(withID: $0) })
        let manager = CalendarManager(service: backend, now: { self.reference }, startMonitoring: false)
        session.beginCreate(kind: .event, on: reference, calendarID: "fixture-events")
        XCTAssertEqual(session.route, .editor)
        await manager.updateCurrentDate(reference)
        XCTAssertGreaterThanOrEqual(manager.events.count, 8, "前提：选中日有 8 条记录（左栏清单很长）")

        let host = NSHostingView(rootView: StandaloneCalendarView(session: session, manager: manager)
            .environmentObject(DynamicIslandViewModel())
            .frame(width: 887))
        host.frame = CGRect(x: 0, y: 0, width: 887, height: 400)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, StandaloneCalendarView.editorPaneHeight, accuracy: 1,
                       "编辑档左栏钉高 400：当日清单再长也顶不高整页理想高")

        // 对照（反证上面的 400 不是「量什么都是 400」）：同一份左栏**不钉高**时，8 条记录的清单
        // 理想高远大于 400。钉高一旦被去掉，上面那条断言就会读到这个更大的数而红。
        let looseSidebar = NSHostingView(rootView: CalendarEditorSidebar(session: session, manager: manager)
            .environmentObject(DynamicIslandViewModel()))
        looseSidebar.frame = CGRect(x: 0, y: 0, width: 260, height: 400)
        looseSidebar.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        looseSidebar.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(looseSidebar.fittingSize.height, StandaloneCalendarView.editorPaneHeight,
                             "对照：左栏不钉高时理想高 > 400（清单条目多）——证 400 是钉出来的")
    }

    // MARK: - T2（本轮 docs/49）：待办表单收口——并一行、备注落点、原文区收高（V3 / V4）

    /// 从某个视图往上数的所有 `NSScrollView` 祖先（最近的在最前）。
    private func ancestorScrollViews(of view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        var node: NSView? = view
        while let current = node {
            if let scroll = current as? NSScrollView { result.append(scroll) }
            node = current.superview
        }
        return result
    }

    /// 表单可视区 = 编辑档 400 减去表头与底部动作后留给表单的那一块（页级滚动视图，宿主侧矩形）。
    private func formRegion(in host: NSView) -> NSRect? {
        guard let notes = notesEditors(in: host).first else { return nil }
        return ancestorScrollViews(of: notes).last.map { $0.convert($0.bounds, to: host) }
    }

    /// V3 / D-03：待办表单不再留空半格——「截止」与「链接」并成一行，`Color.clear` 占位整条删掉；
    /// 挂载后能测到的两格仍是 (内容宽 − 8) / 2。
    func testReminderFormMergesDueDateAndLinkWithoutBlankHalfCells() throws {
        let panel = try repositorySource("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        XCTAssertFalse(panel.contains("Color.clear"), "空半格占位必须整条删掉（D-03）")
        XCTAssertTrue(panel.contains(
            #"dateRow("calendar.panel.dueDate", field: .start, date: draft.start, allDay: draft.isAllDay)"#),
                      "待办仍要有「截止」这一格")

        let (session, manager) = editorSession(kind: .reminder, editing: false)
        session.draft?.isAllDay = false
        let host = mountStandaloneCalendar(session: session, manager: manager, width: 887)
        settle(host)
        let notes = try XCTUnwrap(notesEditors(in: host).first)
        let content = notes.bounds.width
        let fields = collectViews(host) { ($0 as? NSTextField)?.isEditable == true }
            .compactMap { $0 as? NSTextField }
            .map { $0.bounds.width }
            .sorted()
        XCTAssertEqual(fields.count, 2, "待办只有「标题」与「链接」两个输入框（地点那格不渲染，也不留空占位）")
        XCTAssertEqual(fields[0], (content - 8) / 2, accuracy: 1.5, "「链接」与「截止」并排，各占半格")
        XCTAssertEqual(fields[1], content, accuracy: 1.5, "「标题」整宽")
    }

    /// V3 / D-04：备注有可见落点——编辑器住进带描边的框（白 18% 描边、圆角 6），空框时框内画占位文字
    /// （复用 `calendar.panel.notes` 键，不新增本地化键）。
    func testNotesEditorDrawsAVisibleBoxWithPlaceholderInsideIt() throws {
        let (session, manager) = editorSession(kind: .reminder, editing: false)
        let host = mountStandaloneCalendar(session: session, manager: manager, width: 887)
        settle(host)
        let notes = try XCTUnwrap(notesEditors(in: host).first)
        let box = try XCTUnwrap(notes.enclosingScrollView, "备注编辑器必须住在带框的框里（D-04）")
        XCTAssertEqual(box.layer?.borderWidth, 1)
        XCTAssertEqual(box.layer?.cornerRadius, 6, "圆角 6（设计值，不镜像生产常量）")
        // `NSColor.components` 在非 RGB 色彩空间下长度不定（灰阶只有 2 个）——先转 sRGB 再读分量。
        let border = try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(box.layer?.borderColor))?
            .usingColorSpace(.sRGB))
        XCTAssertEqual(Double(border.redComponent), 1, accuracy: 0.01)
        XCTAssertEqual(Double(border.alphaComponent), 0.18, accuracy: 0.01,
                       "描边是白 18%（设计值；浅到不抢内容、又看得出落点）")
        // 框高 = 2 行（2026-10-16 上屏反馈第 7 条：3 → 2 行）：用布局管理器的行高**独立算**一遍。
        let lineHeight = try XCTUnwrap(notes.layoutManager).defaultLineHeight(
            for: try XCTUnwrap(notes.font))
        XCTAssertEqual(box.frame.height, ceil(lineHeight) * 2 + 2 * notes.textContainerInset.height,
                       accuracy: 0.5, "框高 = 2 行")
        XCTAssertTrue(notes.string.isEmpty)
        XCTAssertEqual(notes.placeholder, NSLocalizedString("calendar.panel.notes", comment: ""))
        // 生产形态：文档视图住在 clip view 里（不是裸放），纵向自增长只发生在框内。
        XCTAssertTrue(notes.isVerticallyResizable, "框内容器要能自己长（否则长备注没法滚）")
        XCTAssertTrue(box.documentView === notes, "文本视图是滚动框的文档视图")
        // 内容更长时框不再长高（封住无限长高），多出来的部分靠框内滚动到达。
        let pageHeightBefore = host.fittingSize.height
        session.draft?.notes = (1...20).map { "第\($0)行" }.joined(separator: "\n")
        settle(host)
        XCTAssertEqual(try XCTUnwrap(notes.enclosingScrollView).frame.height,
                       ceil(lineHeight) * 2 + 2 * notes.textContainerInset.height, accuracy: 0.5,
                       "20 行备注也不能把框顶高")
        XCTAssertGreaterThan(notes.frame.height, box.frame.height, "文档视图比框高 → 框内可滚动")
        XCTAssertEqual(box.hasVerticalScroller, true)
        XCTAssertEqual(host.fittingSize.height, pageHeightBefore, accuracy: 1,
                       "长内容不许把整页顶高（旧形态「编辑框随内容在页内长高」的护栏）")
    }

    // MARK: - T5（本轮 docs/49）：列表行整行点开详情浮层 + 行内编辑/删除（V7 / V8 / V9）

    /// 行带 → 行内按钮：按标题文本框的位置切出每一行的竖直带，再数落在带里的焦点环
    /// （SwiftUI `Button` 会留下一枚 `_FocusRingView`；会议按钮是 NSView，不算在里面）。
    private func rowButtonSlots(in host: NSView) -> [(string: String, title: NSRect, buttons: [NSRect])] {
        let titles = collectViews(host) { ($0 as? CalendarReadOnlyTextView)?.string.isEmpty == false }
            .compactMap { $0 as? CalendarReadOnlyTextView }
            .map { ($0.string, $0.convert($0.bounds, to: host)) }
            .filter { $0.1.width > 40 && $0.1.height > 0 }
        let rings = collectViews(host) { String(describing: type(of: $0)).contains("FocusRing") }
            .map { $0.convert($0.bounds, to: host) }
        // 行带只取**列表列**（左栏月历里也有焦点环，混进来就会把每个行带都数成十几枚）。
        let column = titles.map(\.1.minX).min() ?? 0
        return titles.map { string, title in
            let band = NSRect(x: max(0, column - 40), y: title.midY - 20,
                              width: host.bounds.width - max(0, column - 40), height: 40)
            return (string, title, rings.filter { $0.intersects(band) && $0.midX > column - 40 })
        }
    }

    /// V7 / D-07·D-12·D-19：行内动作键按「可写性 + 记录类型」给——可写日程两枚（✎ / 🗑）、
    /// 只读记录一枚都不给、待办只有 🗑（完成圈在左边，不算动作键）。
    func testListRowActionsFollowWritabilityAndKind() async throws {
        let backend = CalendarInteractionFixtures.makeBackend(count: 4, on: reference)
        let session = CalendarPanelSession(selectedDate: reference, now: { self.reference },
                                          saveEvent: { try await backend.saveEvent(input: $0, eventID: $1) },
                                          createReminder: { try await backend.createReminderRecord(input: $0) },
                                          deleteEvent: { try await backend.deleteEvent(id: $0) },
                                          completeReminder: { try await backend.completeReminder(id: $0, completed: $1) },
                                          event: { backend.event(withID: $0) })
        let manager = CalendarManager(service: backend, now: { self.reference }, startMonitoring: false)
        session.showList(on: reference)
        await manager.updateCurrentDate(reference)
        let host = mountStandaloneCalendar(session: session, manager: manager, width: 887)
        settle(host)

        let rows = rowButtonSlots(in: host)
        func actions(_ needle: String) -> (right: Int, left: Int) {
            guard let row = rows.first(where: { $0.string.contains(needle) }) else { return (-1, -1) }
            return (row.buttons.filter { $0.minX > row.title.maxX }.count,
                    row.buttons.filter { $0.maxX < row.title.minX }.count)
        }
        XCTAssertGreaterThanOrEqual(rows.count, 4, "前提：当日渲染出 4 行（\(rows.map(\.string))）")
        XCTAssertEqual(actions("01 ·").right, 2, "可写日程：右端 ✎ + 🗑 两枚")
        XCTAssertEqual(actions("02 ·").right, 1, "待办：右端只有 🗑（本批不给编辑，D-10）")
        XCTAssertEqual(actions("02 ·").left, 1, "待办左端那枚是完成圈")
        XCTAssertEqual(actions("04 ·").right, 0, "只读记录（fixture-event-04）：一枚动作键都不给（D-12）")
        XCTAssertEqual(actions("04 ·").left, 0)

        let panel = try repositorySource("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        // 行内动作的可见性判据（源码口径与上面实测同源）。
        XCTAssertTrue(panel.contains("if event.canModifyInIsland, !event.type.isReminder {"))
        XCTAssertTrue(panel.contains("if canDelete {\n                    rowIconButton(\"calendar.panel.delete\""))
        // 会议入口走与首页同款的一枚按钮（D-19），不再用 `.row` 的两枚文字键；平台名 + 会议号仍作文字信息。
        XCTAssertTrue(panel.contains("MeetingActionView(event: event, session: session)"))
        XCTAssertFalse(panel.contains("MeetingActionView(event: event, session: session, style: .row)"))
        XCTAssertTrue(panel.contains("MeetingActionInfoText(event: event, session: session)"))
        // 整行可点 + 锚点上报（浮层定位靠它）。
        XCTAssertTrue(panel.contains(".onTapGesture { details.togglePin(event.id) }"))
        XCTAssertTrue(panel.contains(".anchorPreference(key: CalendarEventAnchorKey.self, value: .bounds)"))
        // 浮层**不在**滚动视口里：宿主挂在 listPage 的列级（`calendar-list-scroll` 之外）。
        XCTAssertTrue(panel.contains(".calendarEventDetails(model: details, actions: detailActions)"))
        // 浮层必须是面板内自绘：不许出现 NSPopover / sheet（限定在浮层与列表行代码里）。
        let detail = try repositorySource("DynamicIsland/components/Calendar/CalendarEventDetail.swift")
        for banned in ["NSPopover", ".sheet(", ".popover("] {
            XCTAssertFalse(detail.contains(banned), "\(banned) 不许出现在详情浮层里（D-08）")
        }
        // 动作行是图标形态（D-20）：动作集里没有文字按钮构造，只有 iconAction。
        XCTAssertTrue(detail.contains("private func iconAction("))
        XCTAssertFalse(detail.contains("Label(\"Open in Calendar\""))
    }

    /// V8 / D-23：钉住**不**抑制自动收起（该标志恒 false，本轮无写入点）；浮窗状态在
    /// 切页 / 收面板 / 卸载三处收口，Esc 先收浮窗（源码 + 模型两半取证）。
    func testDetailsPopupNeverSuppressesAutoCloseAndClearsOnEveryExit() throws {
        let model = CalendarEventDetailsModel()
        XCTAssertFalse(model.isPinRenderable)
        model.togglePin("a")
        XCTAssertEqual(model.pinnedID, "a")
        XCTAssertEqual(model.activeID, "a", "钉住优先于悬停")
        model.hover("b")
        XCTAssertEqual(model.activeID, "a", "悬停不许抢走钉住档")
        model.togglePin("a")
        XCTAssertEqual(model.activeID, "b", "再点同一行取消钉住 → 回落到仍然悬停的那一条")
        model.hover(nil)
        XCTAssertNil(model.activeID, "悬停也走了就什么都不显示")
        model.togglePin("b")
        model.clear()
        XCTAssertNil(model.pinnedID)
        XCTAssertNil(model.hoveredID)
        XCTAssertFalse(model.isPinRenderable)

        let panel = try repositorySource("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        // 三处收口 + Esc 第一步。
        XCTAssertEqual(panel.components(separatedBy: "details.clear()").count - 1, 5,
                       "Esc / **切页** / 收面板 / 视图卸载 / 叫确认条前各一处")
        // 切页那一处要在 route 变化的回调里（只数总次数会被别的调用点凑齐——审查抓到过）。
        let routeChange = try XCTUnwrap(panel.range(of: ".onChange(of: session.route) { _, _ in"))
        let routeBlock = String(panel[routeChange.lowerBound...].prefix(400))
        XCTAssertTrue(routeBlock.contains("details.clear()"), "切页必须收浮窗（C2「切页 → 自动复位」）")
        XCTAssertTrue(routeBlock.contains("deleteTargetID = nil"), "切页也要清确认条")
        XCTAssertTrue(panel.contains("else if datePopover != nil { datePopover = nil }"),
                      "Esc 链仍要先处理日期弹层（C2 的顺序）")
        XCTAssertTrue(panel.contains("if state != .open { details.clear(); deleteTargetID = nil }"))
        XCTAssertTrue(panel.contains("if details.activeID != nil { details.clear() }"))
        // D-23：不写 `vm.isCalendarDetailsPinned`（该标志恒 false，浮窗不抑制自动收起）。
        for file in ["CalendarPanelPages.swift", "CalendarEventDetail.swift",
                     "CalendarEditorLifecycle.swift", "DynamicIslandCalendar.swift"] {
            let text = try repositorySource("DynamicIsland/components/Calendar/" + file)
            XCTAssertFalse(text.contains("isCalendarDetailsPinned ="),
                           "\(file) 不许写收起抑制标志（D-23）")
        }
    }

    /// V9 / D-10：删除走**会话层**同一条路（列表档也要能用），唯一判据是 `canModifyInIsland`；
    /// 行内先出就地确认条、确认后才调删除（源码口径 + 会话行为两半）。
    func testDeleteWorksFromTheListAndStaysConfirmedFirst() async throws {
        let backend = CalendarInteractionFixtures.makeBackend(count: 4, on: reference)
        let session = CalendarPanelSession(selectedDate: reference, now: { self.reference },
                                          saveEvent: { try await backend.saveEvent(input: $0, eventID: $1) },
                                          createReminder: { try await backend.createReminderRecord(input: $0) },
                                          deleteEvent: { try await backend.deleteEvent(id: $0) },
                                          completeReminder: { try await backend.completeReminder(id: $0, completed: $1) },
                                          event: { backend.event(withID: $0) },
                                          deleteReminder: { try await backend.deleteReminder(id: $0) })
        session.showList(on: reference)
        let reminder = try XCTUnwrap(backend.event(withID: "fixture-reminder-02"))
        XCTAssertFalse(reminder.canModifyInIsland, "'岛内可编辑'对提醒恒 false（它的写入判据是另一条）")
        XCTAssertTrue(CalendarPanelSession.canDeleteInIsland(reminder), "但可写待办在岛内可删（D-10）")
        XCTAssertEqual(session.route, .list)
        let deletedReminder = await session.delete(reminder)
        XCTAssertTrue(deletedReminder, "列表档删待办必须能走通（改前 guard 是 route == .detail，T6 已删掉那一档）")
        XCTAssertNil(backend.event(withID: "fixture-reminder-02"))
        let readOnly = try XCTUnwrap(backend.event(withID: "fixture-event-04"))
        XCTAssertFalse(CalendarPanelSession.canDeleteInIsland(readOnly))
        // 重复记录一律不给删（提醒在 EventKit 里删的是整串；与「重复日程交给系统应用」同一条边界）。
        // fixture-reminder-03 就是 fixtures 里带重复规则的那条（index == 3）。
        let recurring = try XCTUnwrap(backend.event(withID: "fixture-reminder-03"))
        XCTAssertTrue(recurring.hasRecurrenceRules, "前提：这条 fixture 带重复规则")
        XCTAssertFalse(CalendarPanelSession.canDeleteInIsland(recurring), "重复待办不给岛内删")
        let refusedSeries = await session.delete(recurring)
        XCTAssertFalse(refusedSeries, "会话层也不许删整串")
        let deletedReadOnly = await session.delete(readOnly)
        XCTAssertFalse(deletedReadOnly, "只读记录：会话层也不许删（D-12 的第二道门）")

        let panel = try repositorySource("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        XCTAssertTrue(panel.contains("CalendarDeleteConfirmation("),
                      "删除确认改成**弹框**（2026-10-16 第 6 条）")
        XCTAssertFalse(panel.contains("deleteConfirmationBar"),
                       "行下方确认条已退休")
        XCTAssertTrue(panel.contains("private func requestDelete(_ event: EventModel)"),
                      "行内 🗑 只叫确认条")
        XCTAssertTrue(panel.contains("guard await session.delete(event) else { return }"),
                      "确认后才真的删，删成功再把锚点挪到邻近条目")
        let detailSource = try repositorySource("DynamicIsland/components/Calendar/CalendarEventDetail.swift")
        XCTAssertTrue(detailSource.contains("calendar.panel.deleteReminderConsequence")
                      && detailSource.contains("calendar.panel.deleteEventConsequence"),
                      "弹框里写清后果（C2 硬规则②）")
        XCTAssertTrue(detailSource.contains(".accessibilityIdentifier(\"calendar-delete-scrim\")"),
                      "遮罩（点它 = 取消）")
        let sessionSource = try repositorySource("DynamicIsland/models/CalendarPanelSession.swift")
        XCTAssertTrue(sessionSource.contains("guard !isSubmitting, Self.canDeleteInIsland(event) else { return false }"),
                      "删除的唯一判据是 canDeleteInIsland（不再卡 route == .detail）")
        XCTAssertTrue(sessionSource.contains("if event.type.isReminder {"), "待办走 deleteReminder 那条注入")
        let provider = try repositorySource("DynamicIsland/Providers/CalendarServiceProviding.swift")
        XCTAssertTrue(provider.contains("func deleteReminder(id: String) async throws"),
                      "服务层补上了删待办（原 deleteEvent 只吃 EKEvent，会抛 wrongRecordType）")
    }

    // MARK: - T6（本轮 docs/49）：详情档退休 + 列表档分栏 40/60（V10 / V16）

    /// V10 / D-11·D-13：详情档退休——`CalendarPanelRoute` 只两种档位、`showDetail` / `detailEvent`
    /// 全仓绝迹、保存成功后回列表；既有引用该页的用例同批改成列表口径。
    func testDetailRouteIsRetiredAcrossTheApp() async throws {
        XCTAssertEqual(String(describing: CalendarPanelRoute.list), "list")
        let sessionSource = try repositorySource("DynamicIsland/models/CalendarPanelSession.swift")
        XCTAssertTrue(sessionSource.contains("enum CalendarPanelRoute: Equatable { case list, editor }"),
                      "只剩列表 / 编辑两档")
        XCTAssertFalse(sessionSource.contains("showDetail"), "入口已删")
        XCTAssertFalse(sessionSource.contains("detailEvent"), "会话不再持有「详情记录」这一状态")
        for file in ["DynamicIsland/components/Calendar/CalendarPanelPages.swift",
                     "DynamicIsland/components/Calendar/DynamicIslandCalendar.swift",
                     "DynamicIsland/Modules/TodosModule.swift",
                     "DynamicIsland/ContentView.swift",
                     "DynamicIslandTests/PanelAutoHeightTests.swift"] {
            XCTAssertFalse(try repositorySource(file).contains("showDetail"), "\(file) 不许再有 showDetail 调用")
        }
        // 行为：保存成功后回列表（不是旧的详情档）。
        let backend = CalendarInteractionFixtures.makeBackend(count: 0, on: reference)
        let session = CalendarPanelSession(selectedDate: reference, now: { self.reference },
                                          saveEvent: { try await backend.saveEvent(input: $0, eventID: $1) },
                                          createReminder: { try await backend.createReminderRecord(input: $0) },
                                          deleteEvent: { try await backend.deleteEvent(id: $0) },
                                          completeReminder: { try await backend.completeReminder(id: $0, completed: $1) },
                                          event: { backend.event(withID: $0) })
        session.beginCreate(kind: .event, on: reference, calendarID: "fixture-events")
        session.draft?.title = "Saved"
        let saved = await session.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(session.route, .list, "保存成功后回列表（T6）")
    }

    /// V15 / D-15·D-18：首页今日条目点击 = 就地弹同一个浮窗（不切页、不写别的会话状态）；
    /// 浮层宿主挂在**滚动视口之外**；行形态不动（会议仍一枚 `.icon` 图标、行内不加 ✎ / 🗑）。
    func testHomeTodayRowsOpenTheSharedPopupInPlace() throws {
        let todos = try repositorySource("DynamicIsland/Modules/TodosModule.swift")
        // 点击：写自己那份 `details`，不再切模块 / 不再走旧详情路径。
        XCTAssertTrue(todos.contains("details.togglePin(event.id)"), "今日条目点击 = 钉住浮窗")
        XCTAssertTrue(todos.contains(".calendarEventDetails(model: details, actions: homeDetailActions, lookup: homeDetailLookup)"),
                      "浮层由**块**持有并画（并带上取数兜底）")
        XCTAssertFalse(todos.contains("selectModule(CalendarModule.moduleID)\n    }\n\n    private func openTodo"),
                       "openDetail 不再切页（编辑那一枚仍会切，属 Actions 内部）")
        XCTAssertFalse(todos.contains("showDetail"))
        // 锚点：两种行都上报。
        XCTAssertEqual(todos.components(separatedBy: ".anchorPreference(key: CalendarEventAnchorKey.self, value: .bounds)").count - 1, 2,
                       "日程行与待办行各上报一次锚点")
        // 行形态（2026-10-16 第 1 条改口径）：首页行**加了** ✎ / 🗑，并去掉旧详情档留下的 ›；
        // 会议入口仍是默认 `.icon` 那一枚。
        XCTAssertTrue(todos.contains("struct TodoHomeRowActions"), "首页行的右端动作组")
        XCTAssertTrue(todos.contains("home-edit-"), "可写日程给 ✎")
        XCTAssertTrue(todos.contains("home-delete-"), "可删记录给 🗑")
        XCTAssertTrue(todos.contains("CalendarPanelSession.canDeleteInIsland(event)"),
                      "🗑 与面板同一判据")
        XCTAssertFalse(todos.contains("chevron.right"), "首页行不再有 › 箭头（第 1 条）")
        let eventRow = try XCTUnwrap(todos.range(of: "struct TodoHomeEventRow"))
        let rowBody = String(todos[eventRow.lowerBound...].prefix(2600))
        XCTAssertTrue(rowBody.contains("MeetingActionView(source: source, session: session)"),
                      "会议入口仍是那枚单图标（默认 .icon）")
        XCTAssertFalse(rowBody.contains("style: .row"))
        // 浮层挂在滚动视口之外：`home-today-scroll` 是滚动视图，浮层修饰符挂在块级（其后）。
        let scrollIndex = try XCTUnwrap(todos.range(of: #".accessibilityIdentifier("home-today-scroll")"#))
        let overlayIndex = try XCTUnwrap(todos.range(of: ".calendarEventDetails(model: details, actions: homeDetailActions, lookup:"))
        XCTAssertLessThan(scrollIndex.lowerBound, overlayIndex.lowerBound)
        // 删除仍先确认（C2 硬规则①）：浮窗里换成确认行，确认后才真删。
        XCTAssertTrue(todos.contains("CalendarDeleteConfirmation("),
                      "首页的删除也走**弹框**（第 6 条），遮罩 + 居中卡片")
        XCTAssertTrue(todos.contains("calendarEventDetails(model: details, actions: homeDetailActions, lookup: homeDetailLookup)")
                      && todos.contains(".overlay {"),
                      "弹框挂在浮层之上")
        XCTAssertTrue(todos.contains("if await session.delete(target) {"),
                      "确认后才调删除，且失败要在首页说出来（M-2）")
        let detail = try repositorySource("DynamicIsland/components/Calendar/CalendarEventDetail.swift")
        XCTAssertTrue(detail.contains("struct CalendarDeleteConfirmation"),
                      "确认弹框是共用组件（面板 / 首页同一份）")
        // 取数兜底：首页的行来自 todayEvents + store.reminderRecords（含**不在当日窗口**的过期条目），
        // 浮层必须用同一份数据查，否则那些行点了什么都不画（审查 I-2）。
        XCTAssertTrue(todos.contains("calendarEventDetails(model: details, actions: homeDetailActions, lookup: homeDetailLookup)"))
        XCTAssertTrue(todos.contains("calendarManager.todayEvents.first { $0.id == id } ?? store.reminderRecords[id]"))
        XCTAssertTrue(detail.contains("lookup: ((String) -> EventModel?)? = nil"))
        // 首页行整行可点（与面板同款；原来只有那枚 › 能点）。
        XCTAssertEqual(todos.components(separatedBy: "onTapGesture { if canOpenDetail").count - 1, 2,
                       "日程行与待办行都整行可点")
        // 列表行第二行按 C1：日程给「起–止」时段、待办给「截止 日期」。
        let panel = try repositorySource("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        XCTAssertTrue(panel.contains("+ CalendarPanelDates.formattedTime(event.end, calendar: calendar)"),
                      "日程行第二行是时段（C1）")
        XCTAssertTrue(panel.contains(#"String(localized: "calendar.panel.dueDate") + " ""#),
                      "待办行第二行带「截止」（C1）")
    }

    /// V16 / D-16·D-21：列表档左栏 = **内容宽 × 40%**——用「两个宿主宽下的右栏起点差」证**关系式**
    /// （写死常量时差会是 0 或线性错值），再按真机内容宽 1086 推日格宽是否 ≥ 56（3 字节日名门槛）。
    /// **为什么测斜率而不是绝对值**：右栏第一条目标题的 x 还要让开行内部偏移（色条 / 间距 / 行内边距），
    /// 拿绝对 x 反推左栏会把那些实现细节卷进来；两个宿主宽的差把这些常量全部约掉，剩下的就是斜率。
    func testListColumnTakesFortyPercentOfContentWidth() async throws {
        func titleOrigin(hostWidth: CGFloat) async throws -> CGFloat {
            let backend = CalendarInteractionFixtures.makeBackend(count: 4, on: reference)
            let session = CalendarPanelSession(selectedDate: reference, now: { self.reference },
                                              saveEvent: { try await backend.saveEvent(input: $0, eventID: $1) },
                                              createReminder: { try await backend.createReminderRecord(input: $0) },
                                              deleteEvent: { try await backend.deleteEvent(id: $0) },
                                              completeReminder: { try await backend.completeReminder(id: $0, completed: $1) },
                                              event: { backend.event(withID: $0) })
            let manager = CalendarManager(service: backend, now: { self.reference }, startMonitoring: false)
            session.showList(on: reference)
            await manager.updateCurrentDate(reference)
            let host = mountStandaloneCalendar(session: session, manager: manager, width: hostWidth)
            settle(host)
            let origin = rowButtonSlots(in: host).map(\.title.minX).min() ?? -1
            XCTAssertGreaterThan(origin, 0, "前提：\(hostWidth) 宿主下渲染出行标题")
            return origin
        }
        let narrow = try await titleOrigin(hostWidth: 887)
        let wide = try await titleOrigin(hostWidth: 1086)
        XCTAssertEqual(wide - narrow, (1086 - 887) * 0.4, accuracy: 1,
                       "右栏起点随宿主宽按 40% 走（斜率 = 1 − 0.4）——写死常量时这里必红")

        // 真机内容宽 1086 → 左栏 434.4 → 日格宽 (434.4 − 42) / 7 = 56.1（3 字节日名门槛 ≈55 放得下；
        // 初一那格只显月名的「九月」门槛 44 更宽裕，D-21）。
        let realLeft = 1086 * 0.4
        let cellWidth = (realLeft - MonthGridLayout.gridInset) / 7
        XCTAssertEqual(cellWidth, 56.1, accuracy: 0.2, "内容宽 1086 → 日格宽 56.1")
        XCTAssertGreaterThanOrEqual(cellWidth, 56)
        // 副标判据走实现自己的 `MonthCellSubtitle.fits`（D-21 就是这么定的）。
        XCTAssertTrue(MonthCellSubtitle.fits("九月", cellWidth: cellWidth), "初一那格只显月名 → 放得下")
        XCTAssertFalse(MonthCellSubtitle.fits("九月初一", cellWidth: cellWidth),
                       "4 字写不下——这正是 D-21 改成只显月名的原因")
        XCTAssertTrue(MonthCellSubtitle.fits("重阳节", cellWidth: cellWidth), "3 字节日名仍放得下")

        // 高度不动：页高仍是当月 `monthGridHeight`（43N + 63）。
        XCTAssertEqual(MonthGridLayout.monthGridHeight(forMonth: fixedMonth(2026, 10),
                                                       calendar: fixedGridCalendar(firstWeekday: 1)),
                       278, accuracy: 1e-9, "2026-10 五周 → 43 × 5 + 63")
        XCTAssertTrue(try repositorySource("DynamicIsland/components/Calendar/DynamicIslandCalendar.swift")
            .contains(".containerRelativeFrame(.horizontal, count: 5, span: 2, spacing: 0)"),
                      "分栏是「容器的 5 份取 2 份」的关系式，不是写死常量")
    }

    /// V6 / D-06：字号档只在一个常量里改——编辑页五类与列表卡片两类都引用具名常量，数值即设计值；
    /// 挂载后读**真实控件**的字号（SwiftUI `Text` 不是 NSView，标签那档靠常量 + 源码引用点取证）。
    func testEditorAndCardTypographyUsesTheNamedScale() throws {
        XCTAssertEqual(CalendarPanelTypography.fieldLabelPointSize, 13, "字段标签（原 .caption ≈ 10）")
        XCTAssertEqual(CalendarPanelTypography.fieldInputPointSize, 15, "输入框正文（原 12）")
        XCTAssertEqual(CalendarPanelTypography.actionPointSize, 13, "按钮与状态文字")
        XCTAssertEqual(CalendarPanelTypography.cardTitlePointSize, 15, "列表卡片标题（原 13）")
        XCTAssertEqual(CalendarPanelTypography.cardSecondaryPointSize, 13, "列表卡片次要（原 11 / 10）")
        XCTAssertEqual(CalendarPanelTypography.bigEditorPointSize, 16, "大文本编辑器（原 13）")
        XCTAssertEqual(CalendarEditableTextView.defaultFontSize, CalendarPanelTypography.bigEditorPointSize,
                       "AppKit 侧默认字号取自同一档")

        let (session, manager) = editorSession(kind: .event, editing: false)
        let host = mountStandaloneCalendar(session: session, manager: manager, width: 887)
        settle(host)
        let fields = collectViews(host) { ($0 as? NSTextField)?.isEditable == true }.compactMap { $0 as? NSTextField }
        XCTAssertFalse(fields.isEmpty, "前提：编辑页渲染出输入框")
        for field in fields { XCTAssertEqual(field.font?.pointSize, 15, "输入框正文 15") }
        // 日期控件 / 下拉的**字号**在 small 与 regular 下都是 13（实测），判据是 `controlSize` 与
        // 随之变化的固有高度（small 20 / regular 24）——用 font.pointSize 断言会假绿。
        let pickers = collectViews(host) { $0 is NSDatePicker }.compactMap { $0 as? NSDatePicker }
        XCTAssertFalse(pickers.isEmpty, "前提：编辑页渲染出日期控件")
        for picker in pickers {
            // 断言 `controlSize` 本身：`font.pointSize` 在 small / regular 下都是 13（实测），
            // 而 NSDatePicker 的固有高反而是 regular 更小（20 vs small 22）——只有档位才是判据。
            XCTAssertEqual(picker.controlSize, .regular, "日期控件跟到 regular 档")
        }
        let popups = collectViews(host) { $0 is NSPopUpButton }.compactMap { $0 as? NSPopUpButton }
        XCTAssertEqual(popups.first?.controlSize, .regular, "目标下拉跟到 regular 档")
        XCTAssertGreaterThanOrEqual(popups.first?.intrinsicContentSize.height ?? 0, 24,
                                    "regular NSPopUpButton 的固有高 = 24")
        for editor in [sourceEditors(in: host).first, notesEditors(in: host).first].compactMap({ $0 }) {
            XCTAssertEqual(editor.font?.pointSize, 16, "大文本编辑器 16")
        }

        // 源码：编辑页与列表卡片都引用具名常量（不再散落 `.caption` / `systemFontSize`）。
        let panel = try repositorySource("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        XCTAssertTrue(panel.contains("Text(label).font(CalendarPanelTypography.fieldLabel)"))
        XCTAssertTrue(panel.contains("Text(key).font(CalendarPanelTypography.fieldLabel)"))
        XCTAssertTrue(panel.contains(".textFieldStyle(.roundedBorder).font(CalendarPanelTypography.fieldInput)"))
        XCTAssertTrue(panel.contains(".pickerStyle(.segmented).controlSize(.regular)"))
        XCTAssertTrue(panel.contains(".labelsHidden().controlSize(.regular)"))
        XCTAssertTrue(panel.contains("button.controlSize = .regular"))
        let cards = try repositorySource("DynamicIsland/components/Calendar/CalendarEventCards.swift")
        XCTAssertEqual(cards.components(separatedBy: "CalendarPanelTypography.appKitTitle(").count - 1, 2,
                       "两张卡片的标题都取具名档")
        XCTAssertEqual(cards.components(separatedBy: "CalendarPanelTypography.appKitSecondary()").count - 1, 1,
                       "日程卡片的地点行取具名档")
        XCTAssertEqual(cards.components(separatedBy: "CalendarPanelTypography.cardSecondary").count - 1, 5,
                       "两张卡片的次要文字（全天 / 开始 / 结束）都取具名档")
    }

    /// 生成行右端的按钮槽（SwiftUI 画的 `Button` 会留下一枚 `_FocusRingView`，按它的宿主坐标取）：
    /// 主按钮是定尺寸 76×26，齿轮是 15×15 —— 三态里主按钮必须落在**同一格**。
    private func generationRowButtonSlots(in host: NSView) -> [NSRect] {
        guard let note = sourceEditors(in: host).first else { return [] }
        let noteFrame = note.convert(note.bounds, to: host)
        let band = NSRect(x: noteFrame.maxX, y: noteFrame.minY, width: 200, height: noteFrame.height)
        return collectViews(host) { String(describing: type(of: $0)).contains("FocusRing") }
            .map { $0.convert($0.bounds, to: host) }
            .filter { $0.intersects(band) }
            .sorted { $0.minX < $1.minX }
    }

    /// V5 / D-05：生成区三态共用同一枚主按钮——就绪「生成」/ 生成中「取消」/ 失败「重新生成」，
    /// 三种状态都渲染得出那枚按钮、且落在同一格；失败行只剩红字 + 改为手工填写（没有第二个重试入口）。
    func testGenerationPrimaryButtonExistsInEveryStateAlongOneSlot() async throws {
        // ① 纯函数：状态映射与文案键（设计图 C4 的三种状态逐字）。
        XCTAssertEqual(CalendarGenerationPrimary(.idle), .ready)
        XCTAssertEqual(CalendarGenerationPrimary(.ready), .ready)
        XCTAssertEqual(CalendarGenerationPrimary(.cancelled), .ready)
        XCTAssertEqual(CalendarGenerationPrimary(.debouncing), .busy)
        XCTAssertEqual(CalendarGenerationPrimary(.parsing), .busy)
        XCTAssertEqual(CalendarGenerationPrimary(.failed), .failed)
        XCTAssertEqual(CalendarGenerationPrimary(.ready).labelKey, "calendar.generation.generate")
        XCTAssertEqual(CalendarGenerationPrimary.busy.labelKey, "Cancel")
        XCTAssertEqual(CalendarGenerationPrimary(.failed).labelKey, "calendar.generation.retry")
        XCTAssertEqual(CalendarGenerationPrimary(.idle).identifier, "calendar-generation-generate")
        XCTAssertEqual(CalendarGenerationPrimary(.debouncing).identifier, "calendar-generation-cancel")
        XCTAssertEqual(CalendarGenerationPrimary(.failed).identifier, "calendar-generation-retry")

        // ② 挂载：三态各来一次，主按钮每次都渲染、且是同一格（用户报的「失败后按钮没了」）。
        let (session, manager) = editorSession(kind: .event, editing: false)
        let host = mountEditor(session, manager: manager)
        settle(host)
        session.commitSourceForGeneration("明天下午五点周会")
        session.cancelSourceParsing()
        var slots: [(CalendarGenerationState, NSRect)] = []
        for state in [CalendarGenerationState.cancelled, .parsing, .failed] {
            if state == .parsing { session.commitSourceForGeneration("明天下午五点周会") }
            if state == .failed { await session.generateDraft() }
            settle(host)
            XCTAssertEqual(session.generationState, state, "前提：会话确实在 \(state) 态")
            XCTAssertEqual(CalendarGenerationPrimary(state).identifier,
                           [CalendarGenerationState.cancelled: "calendar-generation-generate",
                            .parsing: "calendar-generation-cancel",
                            .failed: "calendar-generation-retry"][state])
            let buttons = generationRowButtonSlots(in: host)
            XCTAssertEqual(buttons.count, 2, "\(state)：生成行右端只有主按钮与齿轮，实得 \(buttons.map(\.debugDescription))")
            let primary = try XCTUnwrap(buttons.first)
            XCTAssertEqual(primary.width, 76, accuracy: 0.5, "\(state)：主按钮定宽 76")
            XCTAssertEqual(primary.height, 26, accuracy: 0.5, "\(state)：主按钮定高 26")
            slots.append((state, primary))
        }
        XCTAssertEqual(slots.count, 3)
        for (state, slot) in slots.dropFirst() {
            XCTAssertEqual(slot, slots[0].1, "\(state) 与就绪态必须是同一格（位置与尺寸都不变）")
        }

        // ③ 失败行只剩两样：一行红字 + 「改为手工填写」；重试不再是独立入口。
        // 失败行（生成行下方那一条）只放「改为手工填写」一枚按钮。
        let failureBand = NSRect(x: 0, y: slots[0].1.maxY + 1, width: slots[0].1.maxX + 76,
                                 height: 60)
        let failureRowButtons = collectViews(host) { String(describing: type(of: $0)).contains("FocusRing") }
            .map { $0.convert($0.bounds, to: host) }
            .filter { $0.intersects(failureBand) }
        XCTAssertEqual(failureRowButtons.count, 1,
                       "失败行只有「改为手工填写」一枚按钮（实得 \(failureRowButtons.map(\.debugDescription))）")
        let panel = try repositorySource("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        XCTAssertFalse(panel.contains("Button(\"calendar.generation.retry\")"), "不许再出现第二个重试入口")
        XCTAssertTrue(panel.contains("manualEntryButton"))
        // 只有生成中的「取消」无条件可点：其余两态都要有原文（清空原文后的重试没有意义）。
        XCTAssertTrue(panel.contains("let enabled = primary == .busy || hasSource"))
        // 生成中的 mini 指示器槽位**恒定**占宽，按钮三态才不会左右挪。
        XCTAssertTrue(panel.contains("ProgressView().controlSize(.mini)"),
                      "生成中要有进行中的提示（C4 ② 的小圈）")
    }

    /// V4 / D-03·D-04·D-17：新建待办的表单收进编辑档——**内容高 ≤ 400**（编辑档自然高，计划的 V4 口径），
    /// 行距 8（不再有多余的行距）。可视区（400 − 表头 30 − 底部动作 34 = 336）比 400 更小，
    /// 差额在这里**打印成实测读数**，正式开口记在 docs/49 已知限制 + 验收清单（编辑档高度待用户拍板）。
    func testNewReminderFormContentStaysWithinTheEditorPaneBudget() throws {
        let (session, manager) = editorSession(kind: .reminder, editing: false)
        session.draft?.isAllDay = false
        let host = mountStandaloneCalendar(session: session, manager: manager, width: 887)
        settle(host)
        let panel = try repositorySource("DynamicIsland/components/Calendar/CalendarPanelPages.swift")
        XCTAssertTrue(panel.contains("VStack(alignment: .leading, spacing: 8)"), "编辑页行距 = 8（D-17）")
        // 挂载用的宿主高就是编辑档高（`mountStandaloneCalendar` 按它钉框），所以这里断言**声明**本身：
        // 2026-10-16 由 400 抬到 448（设计图 F2 方案一），页面的自然高口径见 `PanelAutoHeightTests`。
        XCTAssertEqual(StandaloneCalendarView.editorPaneHeight, 448, "编辑档高 = 448")

        let notes = try XCTUnwrap(notesEditors(in: host).first)
        let box = try XCTUnwrap(notes.enclosingScrollView)
        let region = try XCTUnwrap(formRegion(in: host), "找不到表单可视区（页级滚动视图）")
        let content = box.convert(box.bounds, to: host).maxY - region.minY
        XCTAssertLessThanOrEqual(content, StandaloneCalendarView.editorPaneHeight,
                                 "表单内容高 \(content) 必须 ≤ 编辑档自然高 400")
        // 2026-10-16 起**待办表单连可视区也放得下**（大文本框 2 行 + 行距 7）→ 恢复严格断言：
        // 面板不该再为待办表单冒出一条滚动条（日程多一行「地点｜链接」，仍会滚，见 docs/49 已知限制）。
        XCTAssertLessThanOrEqual(content, region.height,
                                 "新建待办表单 \(content) 必须落在可视区 \(region.height) 之内")
        print("校准读数：新建待办表单内容高 \(content)，可视区 \(region.height) → 差额 \(content - region.height)")

        // 同一把尺子量**日程**（多一行「地点｜链接」，是这次抬高编辑档的理由）：
        // 2026-10-16 方案一把编辑档 400 → 448，日程表单因此也一屏放完（改前 378 > 336 会出滚动条）。
        let (eventSession, eventManager) = editorSession(kind: .event, editing: false)
        let eventHost = mountStandaloneCalendar(session: eventSession, manager: eventManager, width: 887)
        settle(eventHost)
        let eventNotes = try XCTUnwrap(notesEditors(in: eventHost).first)
        let eventBox = try XCTUnwrap(eventNotes.enclosingScrollView)
        let eventRegion = try XCTUnwrap(formRegion(in: eventHost))
        let eventContent = eventBox.convert(eventBox.bounds, to: eventHost).maxY - eventRegion.minY
        XCTAssertLessThanOrEqual(eventContent, eventRegion.height,
                                 "新建日程表单 \(eventContent) 必须落在可视区 \(eventRegion.height) 之内")
        print("校准读数：新建日程表单内容高 \(eventContent)，可视区 \(eventRegion.height) → 差额 \(eventContent - eventRegion.height)")
    }


}


// Proposal probes run after allocation: measuring must not mutate displayed or editable state.
@MainActor
final class CalendarPageLayoutTests: XCTestCase {
    func testReadOnlyMinimumIdealAndNormalMeasurementsPreserveLiveTextKit() throws {
        let view = CalendarReadOnlyTextView(frame: .zero, textContainer: nil)
        defer { view.stop() }
        view.configure(text: "项目评审完整标题\n第二行\n第三行", font: .systemFont(ofSize: 14),
                       color: .white, maximumLines: 0, strikethrough: false)
        view.setFrameSize(NSSize(width: 374, height: view.measuredSize(width: 374).height))
        view.setSelectedRange(NSRange(location: 2, length: 4))
        let frame = view.frame, ranges = view.selectedRanges
        let storage = NSAttributedString(attributedString: try XCTUnwrap(view.textStorage))
        let container = try XCTUnwrap(view.textContainer)
        for width: CGFloat in [0, 1, 200, 374, 80, .infinity, .nan, 374, 0] {
            let size = view.measuredSize(width: width)
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertEqual(view.frame, frame)
            XCTAssertEqual(container.containerSize.width, view.bounds.width, accuracy: 0.5)
            XCTAssertEqual(view.selectedRanges, ranges)
            XCTAssertTrue(try XCTUnwrap(view.textStorage).isEqual(to: storage))
        }
        view.setFrameSize(NSSize(width: 180, height: view.measuredSize(width: 180).height))
        XCTAssertEqual(container.containerSize.width, 180, accuracy: 0.5)
        XCTAssertEqual(view.selectedRanges, ranges)
    }

    func testTwoLinePreviewAndFullTitleHaveSeparateNaturalHeightsWithoutNativeGrowth() throws {
        let view = CalendarReadOnlyTextView(frame: .zero, textContainer: nil)
        defer { view.stop() }
        let text = (1...6).map { "第\($0)行完整标题" }.joined(separator: "\n")
        view.configure(text: text, font: .systemFont(ofSize: 14), color: .white,
                       maximumLines: 2, strikethrough: false)
        let preview = view.measuredSize(width: 220)
        view.setFrameSize(preview)
        try XCTUnwrap(view.layoutManager).ensureLayout(for: try XCTUnwrap(view.textContainer))
        XCTAssertLessThanOrEqual(try XCTUnwrap(view.layoutManager).usedRect(for: try XCTUnwrap(view.textContainer)).height,
                                 preview.height)
        view.configure(text: text, font: .systemFont(ofSize: 14), color: .white,
                       maximumLines: 0, strikethrough: false)
        let full = view.measuredSize(width: 220)
        XCTAssertGreaterThan(full.height, preview.height * 2)
        XCTAssertEqual(view.frame.size, preview, "AppKit must not grow outside the SwiftUI allocation")
        view.setFrameSize(full)
        XCTAssertEqual(view.string, text)
        XCTAssertEqual(view.frame.size, full)
    }

    func testEditorMeasurementsKeepInsetWidthSelectionAndActualBindingInput() throws {
        let view = CalendarEditableTextView(frame: .zero, textContainer: nil)
        defer { view.stop() }
        var bound = ""
        let editor = CalendarGrowingTextEditor(text: Binding(get: { bound }, set: { bound = $0 }),
                                               label: "fixture", onFocus: { _ in })
        let coordinator = editor.makeCoordinator()
        view.delegate = coordinator
        view.insertText("原文\n用户备注", replacementRange: NSRange(location: 0, length: 0))
        let boxHeight = view.cappedHeight()
        view.setFrameSize(NSSize(width: 374, height: boxHeight))
        view.setSelectedRange(NSRange(location: 0, length: 2))
        let frame = view.frame, ranges = view.selectedRanges, string = view.string
        // 框是**定高**：不再有「随内容量出不同高度」的路径（旧 `measuredSize` 已随 D-04 删除）。
        let lineHeight = try XCTUnwrap(view.layoutManager).defaultLineHeight(for: try XCTUnwrap(view.font))
        XCTAssertEqual(boxHeight, ceil(lineHeight) * 2 + 2 * view.textContainerInset.height, accuracy: 0.5,
                       "框高 = 2 行（2026-10-16 起；用行高独立算一遍，不镜像 cappedHeight 的实现）")
        for _ in 0..<4 {
            XCTAssertEqual(view.cappedHeight(), boxHeight, accuracy: 1e-9, "测量不许改框高、也不许有副作用")
            XCTAssertEqual(view.frame, frame)
            XCTAssertEqual(view.textContainer?.containerSize.width ?? 0, view.bounds.width - 8, accuracy: 0.5)
            XCTAssertEqual(view.selectedRanges, ranges)
            XCTAssertEqual(view.string, string)
            XCTAssertEqual(bound, string)
        }
        view.insertText("实际替换", replacementRange: view.selectedRange())
        XCTAssertEqual(bound, "实际替换\n用户备注")
        view.insertText(String(repeating: "\n新增完整内容", count: 20),
                        replacementRange: NSRange(location: (view.string as NSString).length, length: 0))
        XCTAssertEqual(view.cappedHeight(), boxHeight, accuracy: 1e-9, "20 行也不许把框顶高")
        XCTAssertEqual(view.frame, frame, "Native insertion cannot grow across adjacent controls")
        view.setFrameSize(NSSize(width: 220, height: boxHeight))
        XCTAssertEqual(view.textContainer?.containerSize.width ?? 0, 212, accuracy: 0.5)
        XCTAssertEqual(bound, view.string)
    }
}

// MARK: - 歌词取词的查询阶梯与失败分类（2026-10-16 / docs/50）

/// 用例的素材全部来自**本机实测**（2026-10-16：`mediaremote-adapter get` 读到 LX Music 的
/// `cn.toside.music.desktop` 会话，再直连 LRCLIB 对照返回）：
/// - 「慕夏」的歌手报成 `邓寓君(等什么君)`，词库里存的是 `等什么君`——**同样的歌，字面量差一个字就查不到**；
/// - 「我也可以是流浪诗人」的歌手报成 `好妹妹乐队`，词库里是 `好妹妹`；
/// - 「素颜」的歌手报成 `许嵩、何曼婷`，词库里是 `许嵩&何曼婷`（分隔符不同）；
/// - 「樱花(现场吉他版）」在词库里只有 `樱花` 这个名字，而且上游给的开括号是半角、闭括号是全角。
final class LyricsQueryPlannerTests: XCTestCase {

    // MARK: 阶梯

    func testExactQueryComesFirstAndOnlyOnce() {
        let queries = LyricsQueryPlanner.variants(title: "慕夏", artist: "邓寓君(等什么君)")
        XCTAssertEqual(queries.first?.isExact, true, "原样那条恒在第一——它承载既有的打分匹配")
        XCTAssertEqual(queries.first?.title, "慕夏")
        XCTAssertEqual(queries.first?.artist, "邓寓君(等什么君)")
        XCTAssertEqual(queries.filter(\.isExact).count, 1, "原样那条只许有一条")
    }

    func testArtistAliasInsideParenthesesIsQueried() {
        let queries = LyricsQueryPlanner.variants(title: "慕夏", artist: "邓寓君(等什么君)")
        XCTAssertTrue(queries.contains { $0.artist == "等什么君" && !$0.isExact },
                      "括号里的别名（词库里就是这个）要成为一条候选：\(queries.map(\.artist))")
        XCTAssertTrue(queries.contains { $0.artist == "邓寓君" }, "去掉括号的原名也是一条候选")
    }

    func testBandSuffixIsStripped() {
        let queries = LyricsQueryPlanner.variants(title: "我也可以是流浪诗人", artist: "好妹妹乐队")
        XCTAssertTrue(queries.contains { $0.artist == "好妹妹" && !$0.isExact },
                      "团体后缀（乐队）要去掉：\(queries.map(\.artist))")
    }

    func testCollaboratorsAreSplit() {
        let queries = LyricsQueryPlanner.variants(title: "素颜", artist: "许嵩、何曼婷")
        XCTAssertTrue(queries.contains { $0.artist == "许嵩" && !$0.isExact }, "多歌手要拆开各问一遍")
        XCTAssertTrue(queries.contains { $0.artist == "何曼婷" && !$0.isExact })
    }

    func testTitleVersionTagIsStripped() {
        let queries = LyricsQueryPlanner.variants(title: "樱花(现场吉他版）", artist: "茶季杨")
        XCTAssertTrue(queries.contains { $0.title == "樱花" && !$0.isExact },
                      "尾部版本标注要去掉（注意这里的闭括号是全角、开括号是半角）：\(queries.map(\.title))")
        XCTAssertFalse(queries.contains { $0.title.isEmpty })
    }

    func testVersionTagStrippingOnlyTouchesTheTail() {
        XCTAssertEqual(LyricsQueryPlanner.titleVariants("丢了幸福的猪 (烟嗓版)"), ["丢了幸福的猪"])
        XCTAssertEqual(LyricsQueryPlanner.titleVariants("不问ciaga (不问别离)").first, "不问ciaga")
        XCTAssertTrue(LyricsQueryPlanner.titleVariants("如果当时").isEmpty, "没有版本标注就不产变体")
        XCTAssertTrue(LyricsQueryPlanner.titleVariants("Rock (Live").isEmpty, "只有闭括号、没有开括号 → 不剥")
    }

    func testQueryCountIsCappedAndDeduplicated() {
        let queries = LyricsQueryPlanner.variants(title: "某首歌 (Live)", artist: "甲、乙、丙、丁乐队")
        XCTAssertLessThanOrEqual(queries.count, LyricsQueryPlanner.maximumQueryCount,
                                 "一次取词最多问这么多遍（公共免费词库，不许把重试当默认策略）")
        let keys = queries.map { LyricsQueryPlanner.normalizedKey($0.title) + "\u{1}" + LyricsQueryPlanner.normalizedKey($0.artist) }
        XCTAssertEqual(Set(keys).count, keys.count, "候选不许重复")
        XCTAssertTrue(queries.allSatisfy { !$0.title.isEmpty && !$0.artist.isEmpty })
    }

    func testMissingArtistOrTitleProducesNoQueries() {
        XCTAssertTrue(LyricsQueryPlanner.variants(title: "", artist: "茶季杨").isEmpty)
        XCTAssertTrue(LyricsQueryPlanner.variants(title: "樱花", artist: "  ").isEmpty,
                      "歌名与歌手都要有——没有歌手就只剩歌名，那会撞上同名不同曲")
    }

    // MARK: 归一化与接受闸

    func testNormalizedKeyIgnoresPunctuationWidthAndCase() {
        XCTAssertEqual(LyricsQueryPlanner.normalizedKey("许嵩、何曼婷"),
                       LyricsQueryPlanner.normalizedKey("许嵩&何曼婷"))
        XCTAssertEqual(LyricsQueryPlanner.normalizedKey("Show Me Love"),
                       LyricsQueryPlanner.normalizedKey("show me love"))
        XCTAssertEqual(LyricsQueryPlanner.normalizedKey("樱花（现场版）"),
                       LyricsQueryPlanner.normalizedKey("樱花(现场版)"))
        XCTAssertEqual(LyricsQueryPlanner.normalizedKey("a b\tc"), "abc")
    }

    func testVariantAcceptanceRequiresTheSameTitle() {
        let alias = LyricsQueryPlanner.Query(title: "可乐", artist: "赵紫骅", isExact: false)
        XCTAssertTrue(LyricsQueryPlanner.accepts(resultTitle: "可乐", resultArtist: "赵紫骅", query: alias))
        XCTAssertFalse(LyricsQueryPlanner.accepts(resultTitle: "可乐", resultArtist: "半吨兄弟", query: alias),
                       "同名不同歌手不许放行（「可乐」在词库里有半吨兄弟的版本）")
        XCTAssertFalse(LyricsQueryPlanner.accepts(resultTitle: "可乐 (烟嗓版)", resultArtist: "赵紫骅", query: alias),
                       "歌名要**相等**，不是包含——不然变体会越拿越远")
        XCTAssertFalse(LyricsQueryPlanner.accepts(resultTitle: "", resultArtist: "赵紫骅", query: alias))
    }

    func testVariantAcceptanceAllowsArtistContainment() {
        let alias = LyricsQueryPlanner.Query(title: "慕夏", artist: "等什么君", isExact: false)
        XCTAssertTrue(LyricsQueryPlanner.accepts(resultTitle: "慕夏", resultArtist: "等什么君", query: alias))
        XCTAssertTrue(LyricsQueryPlanner.accepts(resultTitle: "慕夏", resultArtist: "等什么君 & 伊格赛听", query: alias),
                      "歌手串互相包含即可（`&` / `、` 这类分隔符在归一化里被丢掉）")
        XCTAssertFalse(LyricsQueryPlanner.accepts(resultTitle: "慕夏", resultArtist: "伊格赛听", query: alias))
    }

    func testExactQueryIsNeverGated() {
        let exact = LyricsQueryPlanner.Query(title: "樱花(现场吉他版）", artist: "茶季杨", isExact: true)
        XCTAssertTrue(LyricsQueryPlanner.accepts(resultTitle: "樱花", resultArtist: "茶季杨", query: exact),
                      "原样那条沿用既有打分匹配，本次不加闸（行为零变化）")
        XCTAssertTrue(LyricsQueryPlanner.accepts(resultTitle: "完全不同的名字", resultArtist: "别人", query: exact))
    }

    // MARK: 失败分类

    func testTransientStatusCodesAreRetryable() {
        for status in [408, 425, 429, 500, 502, 503, 504] {
            XCTAssertEqual(LyricsFetchPolicy.classify(statusCode: status), .transient, "HTTP \(status) 值得重试")
        }
    }

    func testPermanentStatusCodesAreNot() {
        XCTAssertEqual(LyricsFetchPolicy.classify(statusCode: 200), .ok)
        for status in [400, 401, 403, 404, 422] {
            XCTAssertEqual(LyricsFetchPolicy.classify(statusCode: status), .permanent, "HTTP \(status) 重试没意义")
        }
    }

    func testRetryScheduleIsBounded() {
        XCTAssertEqual(LyricsFetchPolicy.retryDelaysMilliseconds.count, 2, "一次查询最多 1 + 2 = 3 次请求")
        XCTAssertTrue(LyricsFetchPolicy.retryDelaysMilliseconds.allSatisfy { $0 > 0 && $0 <= 5000 })
        XCTAssertGreaterThan(LyricsFetchPolicy.transientAutoRetryDelaySeconds, 0,
                             "瞬时故障后自动再试一次，但只一次（不是轮询）")
    }
}
