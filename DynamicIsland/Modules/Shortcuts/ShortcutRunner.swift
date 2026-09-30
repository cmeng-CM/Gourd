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
//  ShortcutRunner.swift
//  Gourd 模块 · 快捷指令（p2-shortcuts-frontapp / T1）
//
//  docs/22-shortcuts-and-frontapp.md §接口与数据形状 1 的**两个注入点**（D-03）与它们的真实现：
//  取数与运行都从 T2 的 `ShortcutsModule.init` 注入（默认真实现，用例给假体），
//  于是单测不跑真命令、不依赖本机装了什么快捷指令。
//
//  子进程的四条口径（§做法 机制二 + §接口与数据形状 1 的「真实现的三条要点」）：
//  1. **限时**：`Task` 竞速——一个子任务等退出、一个子任务睡到点 `terminate()`；到点即结论
//     `timedOut`，**不重试**；
//  2. **不阻塞主 actor**：`waitUntilExit()` 只在竞速的子任务里调（子任务不在主 actor 上）；
//     这两个函数是 `async` 的 `@MainActor`，等的过程中主 actor 照常走别的活；
//  3. **退出之后再读 pipe**（照 `DynamicIsland/helpers/MediaChecker.swift:69-88` 的既有先例）：
//     `terminate()` 之后竞速组会把等退出那个子任务收完，两个 pipe 都不会再被写，
//     `readDataToEndOfFile()` 读到缓冲区内容后立刻 EOF，不靠「边跑边读」的读线程；
//  4. 边界（先例的既有代价，不做进程组管理）：子进程在退出前写满 64KB 管道会卡到超时——
//     本模块两条命令都不走这条路：`list` 每行约 60 字节，`run` 的输出走 `--output-path` 文件。
//
//  `--output-path` 是**统一契约**（§备选与取舍 ③）：`shortcuts run` 的标准输出只有「显示结果」类
//  动作才写，因此 `captureOutput` 为真时读回的是临时文件（读完即删）；没输出时文件不存在或为空。
//
//  §明确不做：Shelf 的输入文件联动（没有输入源）与文件夹分组（交互未定）——两者都不做，
//  连它们的命令行开关都不出现（docs/22 §明确不做 与 §验收标准 5 的 grep 判据）。
//

import Foundation
import os

// MARK: - 注入点

/// 取数的注入点（默认走真命令 `shortcutsListLines()`；单测给构造的行）。
typealias ShortcutsListing = @MainActor () async -> [String]

/// 运行的注入点（默认走真子进程 `shortcutsRun(identifier:timeout:captureOutput:)`；单测给构造的结果）。
typealias ShortcutsRunning = @MainActor (_ identifier: String, _ timeout: TimeInterval, _ captureOutput: Bool) async -> ShortcutRunResult

// MARK: - 常量

/// `/usr/bin/shortcuts`：系统自带的命令行入口（零私有 API，docs/22 §背景与目标）。
private let shortcutsExecutable = "/usr/bin/shortcuts"

/// 输出回显的行数上限（§已知限制 4：实现取 40 行）。
///
/// 截断在**产出结果的那一侧**做（`shortcutsRun` 读回文件时），视图直接显示 `output`、不重算行数；
/// 被截断时 `output` 末尾多一行截断提示（文案见 `module.shortcuts.outputTruncated`）。
extension ShortcutRunResult {
    static let maxOutputLines = 40
}

/// `shortcuts list` 的限时。
///
/// 不是 `timeoutSeconds`：那个旋钮（默认 30s）按 §接口与数据形状 2 是**运行**的限时。
/// 列一次清单同样不能无限等（卡住的是 tab），因此给一个同量级的固定上限——刷新是手动动作，
/// 超时的后果只是「缓存没更新」，不弹错、不写半张表。
private let shortcutsListTimeout: TimeInterval = 30

/// 写 `os.Logger`（**显式写 `os.`**：本模块里 `Logger` 这个名字被 `DynamicIsland/utils/Logger.swift`
/// 的结构体占着，同 `KernelBootstrap` 的写法）。
private let runnerLog = os.Logger(subsystem: "com.cmeng.gourd.module.shortcuts", category: "runner")

// MARK: - 真实现一：取数

/// `shortcuts list --show-identifiers` 的**原始行**（不解析——解析只有 `ShortcutListParser` 一份，
/// 读缓存与读命令走同一条路，§做法 机制一）。
///
/// 失败（起不来 / 非零退出 / 超时）返回 `[]` 并写 `os.Logger`：tab 于是显示「没有快捷指令（点刷新）」
/// 而不是半张表；原因在日志里（Console.app / `log stream` 按 subsystem
/// `com.cmeng.gourd.module.shortcuts` 过滤），不在 UI 上编一句系统没说过的话。
@MainActor
func shortcutsListLines() async -> [String] {
    switch await shortcutsProcess(arguments: ["list", "--show-identifiers"], timeout: shortcutsListTimeout) {
    case .launchFailed(let message):
        runnerLog.error("shortcuts list 起不来：\(message, privacy: .public)")
        return []
    case .finished(let finished):
        guard !finished.timedOut else {
            runnerLog.error("shortcuts list 超时（\(shortcutsListTimeout, privacy: .public)s）已终止")
            return []
        }
        guard finished.terminationStatus == 0 else {
            let status = finished.terminationStatus
            let stderr = finished.stderrText
            runnerLog.error("shortcuts list 退出码 \(status, privacy: .public)：\(stderr, privacy: .public)")
            return []
        }
        return finished.stdoutLines
    }
}

// MARK: - 真实现二：运行

/// `shortcuts run <identifier>`：限时、可读回输出、失败带系统原话。
///
/// - `timeout`: 秒（模块侧从 `timeoutSeconds` 读，默认 30）；到点 `terminate()` 并把结果记成
///   `.timedOut`（**不重试**）。`terminate()` 杀的是直接子进程，它内部再拉起的动作不保证一起结束
///   （§已知限制 3）。
/// - `captureOutput`: 为真时加 `--output-path <临时文件>`（读回后即删）；为假时 `output` 是空串
///   （**不是**「跑了但没输出」——那一档由空的临时文件表达）。
@MainActor
func shortcutsRun(identifier: String, timeout: TimeInterval, captureOutput: Bool) async -> ShortcutRunResult {
    var arguments = ["run", identifier]
    let outputURL: URL? = captureOutput
        ? FileManager.default.temporaryDirectory
            .appendingPathComponent("gourd-shortcut-output-\(UUID().uuidString)")
        : nil
    if let outputURL { arguments.append(contentsOf: ["--output-path", outputURL.path]) }
    // 读完即删：临时文件是本模块自己造的垃圾，不留（docs/22 §明确不做「大输出落盘」那一档）。
    defer { if let outputURL { try? FileManager.default.removeItem(at: outputURL) } }

    switch await shortcutsProcess(arguments: arguments, timeout: timeout) {
    case .launchFailed(let message):
        // 连进程都没起来：系统的原话（`Process.run()` 抛出的）就是唯一的原因，原样带出去。
        return ShortcutRunResult(outcome: .failure, output: "", failureMessage: message, duration: 0)

    case .finished(let finished):
        let output = outputURL.map(capturedOutput(at:)) ?? ""
        if finished.timedOut {
            return ShortcutRunResult(
                outcome: .timedOut,
                output: output,
                failureMessage: timeoutMessage(timeout),
                duration: finished.duration
            )
        }
        if finished.terminationStatus == 0 {
            return ShortcutRunResult(
                outcome: .success,
                output: output,
                failureMessage: "",
                duration: finished.duration
            )
        }
        return ShortcutRunResult(
            outcome: .failure,
            output: output,
            failureMessage: failureSummary(for: finished),
            duration: finished.duration
        )
    }
}

// MARK: - 读回输出

/// 读回 `--output-path` 写的临时文件：不存在 / 读不出 / 是空文件都是空串
/// （`--output-path` 的语义是「有输出才写」，见 `shortcuts run --help` 的 "if applicable"）。
private func capturedOutput(at url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { return "" }
    return truncatedOutput(String(decoding: data, as: UTF8.self))
}

/// 截到 `maxOutputLines` 行；超了就在末尾追加一行截断提示（§已知限制 4）。
private func truncatedOutput(_ text: String) -> String {
    // `omittingEmptySubsequences: false`：输出里的空行是内容，不能顺手删（删了行数就对不上）。
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    // 结尾的换行会切出一个空尾行：它不是第 N+1 行内容。
    if lines.last == "" { lines.removeLast() }
    guard lines.count > ShortcutRunResult.maxOutputLines else { return text }
    return lines.prefix(ShortcutRunResult.maxOutputLines).joined(separator: "\n")
        + "\n" + String(localized: "module.shortcuts.outputTruncated")
}

// MARK: - 失败 / 超时的那一句

/// 失败时给的是 **stderr 摘要**（§机制二：系统原话，不吞、不猜）：去空白、最多 3 行，多了加省略号。
/// 只截长度，不改字；系统没给 stderr 时**不留空串**——那一栏是「失败时把系统的原话摆出来」的载体，
/// 空着等于把失败说成「没有原因」，因此退到可核对的系统事实（退出码），不编一句像人说的话。
private func failureSummary(for finished: ShortcutProcessOutcome) -> String {
    let lines = finished.stderrText
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    guard !lines.isEmpty else { return "exit \(finished.terminationStatus)" }
    guard lines.count > 3 else { return lines.joined(separator: "\n") }
    return lines.prefix(3).joined(separator: "\n") + "…"
}

/// 超时的那一句说明：「超时」+ 这次用的限值（唯一能解释「为什么停在这儿」的信息）。
/// 文案走 catalog（`module.shortcuts.timedOut`，T2 落 key），不另造一条 key。
private func timeoutMessage(_ timeout: TimeInterval) -> String {
    "\(String(localized: "module.shortcuts.timedOut")) · \(Int(timeout.rounded()))s"
}

// MARK: - 子进程（唯一的 `Process` 落点）

/// 一次子进程跑完的形态。
private struct ShortcutProcessOutcome {
    /// 标准输出的**原始行**（按 `\n` 切、丢掉空行；未解析）。
    let stdoutLines: [String]
    /// 标准错误的原文（不裁剪，裁剪在拼消息时做）。
    let stderrText: String
    let terminationStatus: Int32
    /// 到点被 `terminate()` 终止（**不是**「退出码非零」）。
    let timedOut: Bool
    let duration: TimeInterval
}

private enum ShortcutProcessResult {
    case finished(ShortcutProcessOutcome)
    /// 连进程都没起来（`Process.run()` 抛错）：带系统原话（`error.localizedDescription`）。
    case launchFailed(String)
}

/// 起一个 `/usr/bin/shortcuts` 子进程并等它结束（限时见 `timeout`）。
///
/// 读法照 `DynamicIsland/helpers/MediaChecker.swift:69-88` 的既有先例：
/// **Task 竞速 + 超时 `terminate()`，且退出之后再读 pipe**（文件头第 3 条）。
@MainActor
private func shortcutsProcess(arguments: [String], timeout: TimeInterval) async -> ShortcutProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: shortcutsExecutable)
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let started = Date()
    do {
        try process.run()
    } catch {
        return .launchFailed(error.localizedDescription)
    }

    // 竞速：等退出（false）与 到点终止（true）各一个子任务，先回来的定结论。
    // 返回前 `withTaskGroup` 会把剩下的子任务收完——超时那一档因此保证「读 pipe 之前进程已死」。
    let timedOut = await withTaskGroup(of: Bool.self) { group -> Bool in
        group.addTask {
            process.waitUntilExit()
            return false
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(timeout))
            if process.isRunning { process.terminate() }
            return true
        }
        for await fired in group {
            group.cancelAll()
            return fired
        }
        return false
    }
    let duration = Date().timeIntervalSince(started)

    // 此刻子进程已退出（或已被终止），两个 pipe 不会再被写：读到缓冲区内容后立刻 EOF。
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    let stdoutText = String(decoding: stdoutData, as: UTF8.self)
    return .finished(
        ShortcutProcessOutcome(
            stdoutLines: stdoutText.split(separator: "\n", omittingEmptySubsequences: true).map(String.init),
            stderrText: String(decoding: stderrData, as: UTF8.self),
            terminationStatus: process.terminationStatus,
            timedOut: timedOut,
            duration: duration
        )
    )
}
