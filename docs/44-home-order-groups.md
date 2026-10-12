# 44 · 首页组件排序按「环境带 / 可变流」分组，只能组内移动

| 项 | 值 |
|---|---|
| 状态 | 已实现 |
| 最后更新 | 2026-10-12 |
| 关联来源 | 用户 2026-10-12 要求：「首页的排序设置要调整，现在分为两组，第一组音乐、前台应用、统计，这三个可以在第一排调整排序；第二组也是一样，两组之间不能跳着排序，现在的组件设置首页组件的时候也不能乱着调整」。承接 [38-home-v5-layout.md](38-home-v5-layout.md)（三带结构、`homeZone` 钩子 D-01~D-03、`homeBlockOrder` 的排序语义） |
| 工作流 | `.workflow/p20-home-order-groups/` |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是这场改动的判断依据；
> §接口与数据形状 是参考型小节（执行者与机器查考），人审可跳过；
> §已知限制 / §实际交付 是留给后来人的。

**读者分界**：§一句话方案 / §背景与目标 / §备选与取舍 / §明确不做 / §验收标准 / §决策摘要 给人读；§做法 / §接口与数据形状 是给执行者与模型的契约。

## 一句话方案

「设置 → 组件 → 首页组件」那一节**按首页的两个区拆成两节**——**环境带（第一排）**：音乐 / 前台应用 / 统计；**可变流**：其余块——每行只在本节内上下移动，**上/下按钮在本节首尾自动禁用，跨组移动不可能发生**。

## 背景与目标

**问题现状**：首页本来就有两个区（`homeZone` 钩子：三个模块申报 `.environment` 进环境带、其余缺省 `.flow` 进可变流，docs/38 D-01~D-03），但**设置页把它们当成一条扁平列表**：

- 列表按 `HomeBlockOrdering.sorted` 的输出整条排下来，环境带的块与可变流的块**混在一起**（用户截图里的顺序是 前台应用 / 通知 / 音乐 / 统计 / 待办——正是混着的）；
- 上/下按钮做的是**整条列表里的相邻交换**（`HomeBlockOrdering.moved`），而「是不是第一项/最后一项」也是按整条列表算的——于是**可以把音乐挪到待办下面**这种跨组乱序，用户原话：「两组之间不能跳着排序……也不能乱着调整」。

**预期结果**：设置页一眼能看出两个区，且只能组内调序；首页渲染结果与调整预期一致（组内顺序生效、分组不变）。

**关键约束**：**不改渲染侧的排序语义**（渲染仍是「按 `homeBlockOrder` 的 rank 排序 → 再按区劈开」，见 docs/38 D-03）；**不改面板那一节的排序**（`panelSectionRows` 保持扁平、行为不变）；不改任何块的内容/显隐，不动 `homeZone` 的归属本身。

## 做法

**① 设置页那一节按区拆成两节**：复用该页既有惯用法（`Form` + `Section { rows } header: {…} footer: {…}`），把现在那个 `.home` 单节换成 **两节**：环境带一节、可变流一节，各带自己的表头/表尾文案与**本节内**的「上/下」按钮与禁用边界。行视图本身（图标、名称、surface 芯片、配置行、开关）不变。

**② 移动逻辑改成组内相邻交换**：新增一个**纯函数**（`HomeBlockOrdering.movedInGroup(_ groups:moving:direction:)`），把「分组后的 id 列表」交给它，只在 id 所在的那一组里做相邻交换，越界返回 `nil`；调用方再把两组合并回**整表 rank**（`table(for:)`）落盘——**落盘仍是整表语义**，否则渲染侧的整表排序会把两区重新交织回去（`sorted` 按 `(rank, id)`，rank 缺省取模块默认名次）。

**③ 归一化（顺带的好处）**：因为写回时按「环境带 ++ 可变流」的规范顺序拼整表，用户此前被搞混的存储顺序会在**第一次调序后自动变成分组形式**；组内相对顺序全部保留，渲染结果不变（渲染本来就按区劈开）。

## 备选与取舍

| 选择 | 理由 |
|---|---|
| 保持一条列表，只在跨组时禁用按钮 | 不选：用户明确说「现在分为两组」——他要的是**看得见的两组**，不只是按钮变灰 |
| 在一条列表里插分组标题行 | 不选：该页现有惯用法是 `Section` + 表头/表尾；插标题行要自定义行样式与间距，反而更绕 |
| 把 `homeBlockOrder` 从 rank 表改成「每组一个数组」 | 不选：要改键的形状 + 迁移 + 渲染侧与 `DynamicIslandApp` 的重算链路；本轮用「组内交换 + 整表落盘」就够，零迁移 |
| 顺带把面板那一节也分组 | 不选：用户只说首页；面板那一节没有「区」的概念 |
| 借这次机会把被混掉的存储顺序重置成默认 | 不选：会丢掉用户已有的组内顺序偏好；规范化在第一次调序时自然发生 |

## 接口与数据形状

```swift
// Host/HomeBlockOrdering.swift —— 新增纯函数（无 SwiftUI / Defaults 依赖，单测直接钉）
extension HomeBlockOrdering {
    /// 在「分组后的 id 列表」里把 `id` 在本组内上/下移一格。
    /// - 越界（组首上移 / 组尾下移）或 id 不在任何组里 → nil（调用方据此禁用按钮，不改状态）
    /// - 返回新分组；组之间的顺序与各组的成员集合都不变
    static func movedInGroup(_ groups: [[String]], moving id: String, direction: MoveDirection) -> [[String]]?
}

// components/Settings/ModuleSettingsSection.swift
// .home 由「单节」拆成两节：环境带（registry.homeZone(for:) == .environment）/ 可变流（其余），
// 渲染走新的 homeSection(rows:titleKey:footerKey:)；每节的 isFirst / isLast 按**本节**算
// （不再按整条列表）。
// 分组算式（**内部 `static`**，分节渲染与移动落盘共用同一份拆分；两处各写一份 filter 就会漂）：
static func homeOrderGroups(_ ids: [String], environmentIDs: Set<String>) -> [[String]]
//   恒返回 [环境带, 可变流]（可能含空组），两组各自保持入参顺序——这就是落盘拼回整表的规范顺序。
// 移动：homeRows → homeOrderGroups → movedInGroup → 按规范顺序 flatMap → HomeBlockOrdering.table(for:)
//   → Defaults[.homeBlockOrder]；movedInGroup 返回 nil（越界 / id 不在任何组）时**什么都不写**。

// Localizable.xcstrings —— 两节各自的表头/表尾键（en + zh-Hans 齐）：
//   settings.modules.group.home.environment[.footer]（环境带）、settings.modules.group.home.flow[.footer]（可变流）
```

**不动的**：`HomeBlockOrdering.sorted` / `moved` / `table(for:)` 的既有语义与签名；`Defaults[.homeBlockOrder]` 的形状（仍是 `[String: Int]` rank 表）；渲染侧（`HomeBandCatalog.resolve` / `HomeStripView` 的按区劈开）；面板那一节（`panelSectionRows`）的扁平行为；`homeZone` 的归属。

## 明确不做

不改渲染排序语义与 `homeBlockOrder` 的键形状（零迁移）；不改面板那一节的排序；不改各块的内容/显隐/默认开关；不重排用户已有的组内顺序；不给「区」加设置项（区由模块自己申报，docs/38 D-03）；不动 `HomeTodayBand`（今天带不可排，不进本列表）。

## 实际交付

已实装。提交 `b01592fc`（`T1: 首页组件排序按区分组并约束组内移动`）。

**交付物**

- `DynamicIsland/Host/HomeBlockOrdering.swift`：新增纯函数 `movedInGroup(_:moving:direction:) -> [[String]]?`——只在 `id` 所在的那一组里做相邻交换；组首上移 / 组尾下移 / 单元素组两个方向 / `id` 不在任何组 → `nil`；非 `nil` 时组间顺序与各组员都不变。`sorted` / `table(for:)` / `moved` 逐字未改。
- `DynamicIsland/components/Settings/ModuleSettingsSection.swift`：`.home` 由单节拆成两节，渲染走新的 `homeSection(rows:titleKey:footerKey:)`；拆分算式提为**内部 `static`** `homeOrderGroups(_:environmentIDs:)`（分节渲染与 `moveHome` 共用）；`isFirst` / `isLast` 按**本节**算；移动链路 `moveHome` → `homeOrderGroups` → `movedInGroup` → 规范顺序 flatMap → `HomeBlockOrdering.table(for:)` → `Defaults[.homeBlockOrder]`，`nil` 时不写盘。旧 `surfaceSection(_:)` / `move(_:in:)` 窄化为 `panelSection` / `movePanel`（面板路径逐字等价）。
- `DynamicIsland/Localizable.xcstrings`：新增两节表头 / 表尾四键（`settings.modules.group.home.environment[.footer]`、`…home.flow[.footer]`），**en + zh-Hans 齐**。
- `DynamicIslandTests/ModuleKernelTests.swift`：新增三档用例钉 `movedInGroup` 的组内交换 / 三类越界 `nil`，以及 `homeOrderGroups` 的「环境带 ++ 可变流」规范顺序与回落整表 rank。

**交付机制**：设置页首页组件那一节按区一眼拆成两节——**环境带**（`homeZone == .environment`：音乐 / 前台应用 / 系统读数）在前、**可变流**（其余）在后；每行 ↑↓ 只在**本节内**相邻交换（`movedInGroup`，越界 `nil`），本节首项的上键 / 末项的下键按本节置灰，「跨组移动」在构造上不可能发生。落盘仍是**整表 rank**（`[String: Int]`，键形状与渲染语义一个字没改），合并顺序固定为**环境带 ++ 可变流**——用户此前被搞混的存储顺序因此在**第一次调序后**自动被规范（§做法③）。面板那一节仍是扁平行为（`moved` 仍服务它）。

**与计划的偏离**

1. **多出一个计划未命名的可测辅助 `homeOrderGroups`**：计划只说「取当次排序后的 home 列表 → 拆成 `[envIDs, flowIDs]`」。实现期把这份拆分提成 `ModuleSettingsSection.homeOrderGroups(_:environmentIDs:)`（内部 `static`，`environmentIDs` 由 `registry.homeZone(for:)` 现取），让**分节渲染**与**移动落盘**共用同一份判据，并让它可被单测直接钉（「环境带 ++ 可变流」与「另一组逐字不变」两条由它一处体现）。这是相较计划的**增量交付**，不是语义变化。
2. **指南那一句落在 `docs/guide/modules.md`（而非计划写的 `docs/guide/settings.md`）**：`settings.md` 是「设置参考」，**没有**「组件」那一节（组件页的说明在 `modules.md` §两节的分工 / §首页长什么样，前一批 calendar 的「指南一行」也落在 `modules.md`）。故这一句按同一惯例落进 `modules.md`。

**验证**：完整单元套件 **677 / 677、0 失败、exit 0**；`sh tools/build.sh` BUILD SUCCEEDED；独立审查 **PASS**。审查提出三条 Minor，**全部裁决为「保留」**：① 旧 `home` 组键与首页那条 `orderTable` 路径成死代码——无害（面板仍要 `moved`），见 §已知限制；② 空组仍画表头——今天不可达（三块环境带模块恒注册），见 §已知限制；③ 可再补一个直接钉「组内边界」的用例——现由 `XCTAssertNil` 三档间接覆盖，够用。

**遗留项**：两节的**表头 / 表尾文案、行间距与开关 / 箭头观感**，以及**在某一节内调序后首页是否只在该区（环境带或可变流）内重排**，需用户**上屏复核**（设计稿已确认，真机观感由用户判；自动化 UI 套件不在本轮验收门内）。

## 已知限制

- 实装后定稿（起草期先列，实现期踩到的已补入）：
  - **组归属由模块申报、用户改不了**：某个块属于哪一组是 `homeZone` 说了算（docs/38 D-03），设置页只呈现与约束顺序。想让用户自定义分组，是另一件事。
  - **存储顺序的规范化只发生在第一次调序**：在那之前，`homeBlockOrder` 里可能仍是混杂的名次（渲染不受影响，因为渲染按区劈开）。
  - **面板那一节仍是扁平列表**：它没有「区」的概念，本轮不动。
  - **旧单节 `home` 的文案键与「首页走 `ModuleSurfaceGroup.orderTable`」那条路已成死代码（无害残留）**：`settings.modules.group.home[.footer]` 两键、以及产出它们的 `ModuleSurfaceGroup.home.titleKey` / `.footerKey` 自 p20 起不再被任何渲染读到；组内翻转算式 `ModuleSurfaceGroup.orderTable`（内里是 `HomeBlockOrdering.moved`）现只剩面板那一节调用，首页已改走 `movedInGroup`。`moved` 不能删——面板仍靠它；`writeOrderTable` / `setHidden` 的 `.home` 分支也仍被 `moveHome` 与卡片开关用着。本轮不清理。
  - **空组仍会画出它的表头**：`homeSurfaceSections` 恒渲染两节（`homeOrderGroups` 返回恒为两段），某个区一个块都没有时，那一节的表头 / 表尾仍照画。今天不可达——环境带三块（音乐 / 前台应用 / 系统读数）在 `KernelBootstrap` 恒注册，环境带非空；可变流也非空。

## 验收标准

- 设置页「首页组件」呈现为**两节**：环境带（音乐 / 前台应用 / 统计）、可变流（其余申报首页的块）；每节有表头说明。
- 每行的上/下按钮**只在本节内**生效：本节第一项的上键禁用、最后一项的下键禁用；**任何操作都不能把块移到另一节**。
- 调序后首页渲染的组内顺序与设置页一致，分组不变（环境带恒为第一排）。
- 纯函数单测：`movedInGroup` 的组内上/下移、组首上移与组尾下移返回 nil、id 不在任何组返回 nil、多组时其它组逐字不变、单元素组两个方向都返回 nil。
- 面板那一节的排序行为与既有测试不变。
- Release 构建通过；上屏复核（需用户）。

## 决策摘要

| ID | 决策与来源 | 理由 |
|---|---|---|
| D-01 | 用户：首页组件排序分成两组（第一组=音乐/前台应用/统计），两组之间不能跨组排序 | 用户 2026-10-12 原话；现在是一条扁平列表，能跨组乱跳 |
| D-02 | agent：组的归属直接用既有 `homeZone` 钩子，**不新增设置项** | 区早就是模块自申报的（docs/38 D-03）；设置页只是第一次把它显示出来 |
| D-03 | agent：移动改为「组内相邻交换 + 整表 rank 落盘」，`homeBlockOrder` 的键形状与渲染语义都不动 | 零迁移、零渲染改动；若只改列表不改落盘语义，渲染的整表排序会把两区重新交织 |
| D-04 | agent：拆成两个 `Section`（复用该页既有 `Section + header/footer` 惯用法），非列表内插标题行 | 与页面既有结构一致，改动面最小；用户明确要「看得见的两组」 |
