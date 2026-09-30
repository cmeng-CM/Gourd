// Modified for Gourd (2026-10-01)
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
//  PanelLayoutDefaults.swift
//  Gourd 宿主内核 · 「恢复默认」的键清单与重置动作（p5-home-blocks / T8）
//
//  docs/29-home-blocks-and-panel.md §做法 机制七 / §接口与数据形状：外观页「面板布局」组的
//  「恢复默认」按下并确认后，走这里——**只重置布局与显示那一组键**，让首页/面板的排布与尺寸
//  回到出厂（未设置状态）；账号、授权、内容类设置一个不动。
//
//  **判据一条**（D-13）：**这个键丢了会不会让用户丢东西 / 要重新授权**——会，就不进清单。
//  按这条判据出局的两类（护栏用例 `PanelLayoutDefaultsTests` 逐个钉住，防止日后被顺手扫进来）：
//
//  - **功能入口类**：`enableScreenAssistant` / `quickShareProvider` / `enableLLMUsageFeature`
//    ——关掉它们是「让用户丢掉一个入口」，不是「排布回到出厂」；
//  - **内容与授权类**：提醒 / 日历来源（`calendarSelectionState` 等）、剪贴板历史与取色历史
//    （裸键 `ClipboardHistory` / `ClipboardPinnedItems` / `ColorPickerHistory`）、快捷指令清单与缓存
//    （模块 `shortcuts` 的 `pinnedShortcuts` / `cachedShortcuts`——它们在**模块自己的 suite**
//    `com.cmeng.gourd.module.shortcuts` 里，本清单连够都够不着）。
//
//  三条口径：
//  ① **唯一清单**：`resetKeys` 就是 §接口与数据形状 那一行（17 个键，顺序与文档一致）；
//     重置动作只有 `reset()` 一个出口，别处不要再抄第二份列表。
//  ② 每项**取自强类型键的 `.name`**（`Defaults.Keys.openNotchWidth.name`…）：键改名 / 被删时
//     编译期就断，清单不会与实现悄悄漂移；`resetKeys` 仍是文档里的形状（`[String]` 键名表）。
//  ③ **删掉，不是写默认值**：`Defaults.reset(_: [String])` 逐键 `removeObject`——「未设置」就是
//     出厂默认；而「写一个恰好等于默认值的值」会让「盘上有没有这个键」不可判（与用户的显式选择
//     同形，读法见 `TakeoverEnablementTests.persistedValue(of:)`：`object(forKey:)` 被注册域
//     污染，只有持久域答得出「盘上有没有」），重置必须让它重新变成**没有这个键**。
//
//  **按下之后的连锁**：逐键 `removeObject` 走 KVO，`DynamicIslandApp` / `DynamicIslandViewCoordinator`
//  那几条既有的 `Defaults.publisher` 订阅照常收到变化（面板尺寸 / tab 名单跟着重算）——不新开
//  第二条通知链；高度那一档另由外观页补一下既有 `notchHeightChanged`（与两个滑块同一条收尾）。
//

import Defaults
import Foundation

/// 「恢复默认」（外观页 · 面板布局组）的键清单与重置动作。
enum PanelLayoutDefaults {

    /// 重置的**唯一清单**（docs/29 §接口与数据形状 那一行，顺序与文档逐项一致）。
    ///
    /// 逐项取自强类型键的 `.name`：清单与 `Defaults.Keys` 同源，改名 / 删键时编译期就断。
    static let resetKeys: [String] = [
        Defaults.Keys.openNotchWidth.name,
        Defaults.Keys.openNotchHeight.name,
        Defaults.Keys.panelHeightMode.name,
        Defaults.Keys.homeBlockOrder.name,
        Defaults.Keys.panelOrder.name,
        Defaults.Keys.hiddenHomeModules.name,
        Defaults.Keys.hiddenPanelModules.name,
        Defaults.Keys.moduleEnableOverrides.name,
        Defaults.Keys.showCalendar.name,
        Defaults.Keys.enableStatsFeature.name,
        Defaults.Keys.dynamicShelf.name,
        Defaults.Keys.enableTerminalFeature.name,
        Defaults.Keys.enableClipboardManager.name,
        Defaults.Keys.enableColorPickerFeature.name,
        Defaults.Keys.showMirror.name,
        Defaults.Keys.showStandardMediaControls.name,
        Defaults.Keys.enableTimerFeature.name,
    ]

    /// 把 `resetKeys` 里的每一个键**删掉**（回到未设置状态 = 出厂默认）。
    ///
    /// - 不用 `removePersistentDomain`（那会连授权 / 历史 / 清单一起丢——备选 ⑦ 已否决）；
    /// - 不写默认值（「写一个等于默认值的值」= 盘上仍有一个键，与用户的显式选择同形）；
    /// - 逐键 `removeObject` 走 KVO，既有 `Defaults.publisher` 订阅照常收到变化。
    static func reset() {
        Defaults.reset(resetKeys)
    }

    /// 外观页「Notch Height」组那个**展开高度滑块**在这一档可不可用。
    ///
    /// 它写的 `openNotchHeight` 在自适应档**被内容高取代**（`PanelAutoHeight.panelHeight(...)`
    /// 在那一档不读手动值），留着能拖就是本仓明确规避的「拖了没用」——与右下角拖动把手
    /// `showsPanelResizeHandle(isOpen:isMinimalistic:heightMode:)` 同一条先例（D-16，T6）。
    /// 档名的判定与尺寸层共用 `PanelAutoHeight.isAuto`（未知值按默认档 auto），不另立一套。
    static func expandHeightSliderEnabled(heightMode: String) -> Bool {
        !PanelAutoHeight.isAuto(heightMode)
    }
}
