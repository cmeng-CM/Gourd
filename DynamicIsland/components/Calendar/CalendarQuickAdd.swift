// Modified for Gourd (2026-10-10)
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
//  CalendarQuickAdd.swift
//  Gourd 日历 · 快速新增的口径纯函数（P11 批次 / T5）
//
//  **为什么独立成文件**：两处日历的「+」内联表单（T6，`CalendarQuickAddBar.swift`）要做的
//  都是同一件事——把用户敲的 `HH:mm` 文本解析成**选中日**上的时刻、给日程算出默认起止、
//  给待办算出全天口径的到期组件。这些判断全是**无副作用的纯函数**，所以单独放在这里：
//  不读 `Defaults`、不碰 `EventKit`（因此可以直连单测，不依赖 TCC 授权与真日历库）。
//
//  **口径来源**：docs/36-calendar-cards-and-add.md §做法 机制三 与 §接口与数据形状·纯函数，
//  决策 D-11（宽松解析：`15:30` / `1530` / `9:5` 都收、首尾空白容忍、带秒秒归零、越界拒）与
//  D-08（待办只有日期 / 日程默认 09:00–10:00、选中日=今天取下一个整点、≥23:00 回退 09:00）。
//  解析规则的每个边界都由 `ModuleKernelTests.CalendarQuickAddTests` 逐条钉死——改行为先改那里。
//
//  **时区口径**：所有函数都要求调用方传入 `calendar`（单测传固定 `Asia/Shanghai` 的格里高利历）；
//  日历行与面板页的调用点传 `Calendar.current`（「选中日」本来就是用户本机日历里的那一天）。
//

import Foundation

/// 快速新增（待办 / 日程）的口径纯函数集合。
///
/// 六条函数与 docs/36 §接口与数据形状 逐字一致：
/// - 时间解析：`parseTime`（宽松，D-11）
/// - 日程默认时段：`defaultStart` / `defaultEnd`（D-08）
/// - 校验与全天口径：`isValidRange` / `allDayRange` / `reminderDueComponents`
enum CalendarQuickAdd {

    /// 宽松解析用户敲入的时间文本（D-11），返回**选中日 `day` 当天**该时分的 `Date`（秒 = 0）。
    ///
    /// 接受的写法（先剥首尾空白与换行；空串直接拒）：
    /// - `"H:mm"` / `"HH:mm"`：如 `"9:5"` → 09:05、`"15:30"` → 15:30；
    /// - `"H:mm:ss"` / `"HH:mm:ss"`：**秒一律归零**（`"15:30:45"` → 15:30:00），但秒仍要过 0…59 的界；
    /// - 纯数字 1–2 位 → **整点**（`"9"` → 09:00）；
    /// - 纯数字 3–4 位 → **时+分**（`"930"` → 09:30、`"1530"` → 15:30）。
    ///
    /// 拒绝（一律 `nil`，不做任何兜底猜测）：时 ∉ 0…23、分 ∉ 0…59、秒 ∉ 0…59、
    /// 任一段不是 1–2 位纯数字（含 `"abc"` / `"15:3a"` / `"-1:00"`）、纯数字 5 位及以上
    /// （`"15300"`）、空串与纯空白。
    ///
    /// 结果只落在 `day` 当天（时分已各在界内，**不可能滚动到次日**）。
    static func parseTime(_ text: String, on day: Date, calendar: Calendar) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hour: Int
        let minute: Int

        if trimmed.contains(":") {
            // 冒号档：2 段（时:分）或 3 段（时:分:秒，秒归零）。`omittingEmptySubsequences: false`
            // 让 `"15::30"` / `"15:"` 这类空段留在结果里、由下面的位数校验拒掉（而不是被静默合并）。
            let segments = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            guard segments.count == 2 || segments.count == 3 else { return nil }
            guard segments.allSatisfy(Self.isOneOrTwoASCIIDigits) else { return nil }
            guard let parsedHour = Int(segments[0]), let parsedMinute = Int(segments[1]) else { return nil }
            if segments.count == 3 {
                // 秒只做**越界合法性**校验（0…59），值本身归零——用户写不写秒，落库的都是分精度。
                guard let parsedSecond = Int(segments[2]), (0...59).contains(parsedSecond) else { return nil }
            }
            hour = parsedHour
            minute = parsedMinute
        } else {
            guard trimmed.allSatisfy(Self.isASCIIDigit) else { return nil }
            switch trimmed.count {
            case 1, 2:
                // 纯数字 1–2 位 = 整点（`"9"` → 09:00）。
                guard let parsedHour = Int(trimmed) else { return nil }
                hour = parsedHour
                minute = 0
            case 3, 4:
                // 纯数字 3–4 位 = 时+分：末两位是分（`"930"` → 09:30、`"1530"` → 15:30）。
                let digits = Array(trimmed)
                guard let parsedHour = Int(String(digits.dropLast(2))),
                      let parsedMinute = Int(String(digits.suffix(2))) else { return nil }
                hour = parsedHour
                minute = parsedMinute
            default:
                // 5 位及以上不是任何合法写法的子集（H 最多 2 位 + M 2 位）——拒，不猜。
                return nil
            }
        }

        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    /// 日程表单的默认开始时间（D-08）。
    ///
    /// - 选中日 = 今天，且 `now` 的小时 < 23 → **下一个整点**（分/秒归零；`now` 恰好落在整点上时
    ///   取当前这个整点，即「09:00:00 → 09:00」）；
    /// - 其余情况（选中日不是今天，或今天但已 23 点）→ `day` 的 **09:00**。
    ///
    /// 23 点后仍回当天 09:00（不跳到次日）：日期一律 = 月历选中日，表单不回写日期（D-07）。
    static func defaultStart(on day: Date, now: Date, calendar: Calendar) -> Date {
        if calendar.isDate(day, inSameDayAs: now), calendar.component(.hour, from: now) < 23 {
            let startOfHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let components = calendar.dateComponents([.minute, .second, .nanosecond], from: now)
            let isExactHour = (components.minute ?? 0) == 0
                && (components.second ?? 0) == 0
                && (components.nanosecond ?? 0) == 0
            return isExactHour ? startOfHour : startOfHour.addingTimeInterval(3600)
        }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = 9
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? day
    }

    /// 日程表单的默认结束时间 = 开始 + 1 小时（口径与 `defaultStart` 一起构成 09:00–10:00 的默认档）。
    static func defaultEnd(start: Date) -> Date {
        start.addingTimeInterval(3600)
    }

    /// 起止是否成一条合法日程：`end` 严格晚于 `start`，且两者落在**同一个自然日**。
    ///
    /// 跨日拒（`23:00 → 次日 00:30`）：本批的日程是「给选中日快速加一条」，跨日事件去系统 App 建；
    /// 相等 / 倒挂也拒（`EKEvent` 的零长度事件没有意义）。
    static func isValidRange(start: Date, end: Date, calendar: Calendar) -> Bool {
        end > start && calendar.isDate(start, inSameDayAs: end)
    }

    /// 「全天」开关的目标区间：`day` 当天 00:00 → **次日 00:00**（`EKEvent` 的全天口径）。
    static func allDayRange(on day: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(24 * 3600)
        return (start, end)
    }

    /// 待办的到期组件：**只带** `[.year, .month, .day]`（全天口径，D-08）。
    ///
    /// 刻意不带 `hour/minute/second`：`EventModel.init?(from: EKReminder)` 用
    /// `dueDateComponents.hour == nil` 判「全天待办」，带时刻会把快速新增的待办渲染成带时间的条目。
    /// 因此调用方可以传选中日上的**任意时刻**，这里只看它属于哪一天。
    static func reminderDueComponents(on day: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: day)
    }

    // MARK: - 私有

    /// 冒号档每一段的要求：1–2 位、全是 ASCII 数字（`"9"` / `"05"` 合法；`""` / `"123"` / `"a5"` 拒）。
    private static func isOneOrTwoASCIIDigits(_ segment: Substring) -> Bool {
        (1...2).contains(segment.count) && segment.allSatisfy(Self.isASCIIDigit)
    }

    /// 只认 ASCII 的 `0…9`：`Int("１")` / 阿拉伯-印度数字等一律不当数字收（宽松解析不等于乱收）。
    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}
