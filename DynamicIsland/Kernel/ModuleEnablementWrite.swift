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
//  ModuleEnablementWrite.swift
//  Gourd 模块内核 · 开关的写路径与回弹策略（P2 接管批次 / T1）
//
//  两个**纯函数式**的小类型，把「开关拨下去该写哪一份偏好」与「activate() 失败该写回什么」
//  收在一处（docs/20-component-page.md §接口与数据形状 3）：
//
//  - `ModuleEnablementWrite`：组件页写开关的**唯一入口**——接管模块写上游键，
//    非接管模块写 `moduleEnableOverrides`。逻辑从 `ModuleSettingsSection` 的
//    `ModuleSettingsCard.writeOverride` 搬来（T6 接线，本批先不动那个文件）。
//  - `ModuleEnablementRollback`：回弹策略（D-13）——**nil = 什么都不写**。
//
//  为什么要有这两个类型（而不是让组件页自己分支）：接管之后「同一个开关」有两个落点
//  （上游键 / overrides），分支散在视图里就会出现「某一处写错一份」的静默故障——
//  组件页说关、上游还开着。裁定收在这里，视图只调一次。
//
//  **本文件不订阅、不读状态、不碰注册表**：写偏好与改内存状态是两步（docs/17 §处理链路），
//  第二步永远是 `ModuleRegistry.setEnabled(_:for:)`，由调用方在写完偏好之后调。
//

import Defaults
import Foundation

/// 组件页写开关的**唯一入口**（docs/20 §接口与数据形状 3）。
enum ModuleEnablementWrite {

    /// 把用户的选择落到它该落的那一份偏好上。
    ///
    /// - **接管键非 nil**（接管模块）→ `Defaults[takeoverKey] = enabled`：写的**就是上游那个
    ///   总开关**（用户在组件页与在上游设置页拨的是同一个键，D-01）。
    /// - **接管键 nil**（非接管模块）→ 整字典读改写 `Defaults[.moduleEnableOverrides]`。
    ///   **缺键 = 用户未表达**（回落 manifest），因此这里只在用户真的动了开关时写键。
    ///
    /// 与既有的 `ModuleSettingsCard.writeOverride` 逐字同形（同一份读改写口径），搬过来是为了
    /// 让「写哪一份」在接管引入后仍只有一处判断——本方法**不**改注册表状态，
    /// 调用方拿到之后照旧 `await ModuleRegistry.setEnabled(_:for:)`。
    ///
    /// `@MainActor`：`Defaults` 的下标写是主线程口径（与设置页一致），
    /// 且这一路必然伴随一次 UI 动作。
    @MainActor
    static func write(_ enabled: Bool, for id: String, takeoverKey: Defaults.Key<Bool>?) {
        if let takeoverKey {
            Defaults[takeoverKey] = enabled
            return
        }

        var overrides = Defaults[.moduleEnableOverrides]
        overrides[id] = enabled
        Defaults[.moduleEnableOverrides] = overrides
    }
}

/// 回弹策略（D-13）：`activate()` 失败时应当写回的偏好值；**nil = 什么都不写**。
enum ModuleEnablementRollback {

    /// - **非接管模块**（`takeoverKey == nil`）→ `false`：把用户的开关拨回去（既有口径，
    ///   `ModuleSettingsCard` 的失败回弹）。
    /// - **接管模块** → `nil`：它的偏好就是上游总开关（`enableTimerFeature` /
    ///   `showStandardMediaControls` / `showMirror`），回弹等于「因为模块激活失败，
    ///   把用户的功能关了」——`showStandardMediaControls` 还会连带关掉 Home tab 的判据。
    ///   偏好本就等于用户表达，因此**什么都不写**，失败只由卡片显示失败态（D-13）。
    static func preferenceToWrite(takeoverKey: Defaults.Key<Bool>?) -> Bool? {
        takeoverKey == nil ? false : nil
    }
}
