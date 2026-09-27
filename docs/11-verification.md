# P0 实测验证报告

**日期**：2026-09-27 · **平台**：macOS 27.0（26A428）/ Xcode 27.0（27A266a）/ arm64 单屏 1512×982 逻辑（3024×1964 物理）
**对象**：P0 交付物 `Gourd.app`（[docs/10-p0-execution.md](10-p0-execution.md) 的「实际交付」）
**性质**：**本地验证**——不推送、不建远端、不跑真实 CI。所验证的提交为此报告提交前的 `HEAD`。

本报告只装证据。每条结论都附命令与输出；**间接证据一律显式标注**。

---

## 1. 单元测试（T1）

**命令**（注意：与计划里写的相比**允许了签名**——`CODE_SIGNING_ALLOWED=NO` 会让 arm64 上无法启动 TEST_HOST，这是 T6 在 CI 侧记录过的同一问题；此为对计划的必要偏离，已记录）：

```bash
xcodebuild test -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -destination "platform=macOS" -derivedDataPath ~/Library/Developer/Xcode/Gourd \
  -only-testing:DynamicIslandTests -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES
```

**结果**：退出码 **0**，`** TEST SUCCEEDED **`

```
Test Suite 'ExtensionRPCServerTests'    passed  Executed  9 tests, with 0 failures
Test Suite 'FlyoutFrameCalculatorTests'  passed  Executed  4 tests, with 0 failures
Test Suite 'JSONLUsageParserTests'       passed  Executed  6 tests, with 0 failures
Test Suite 'SpotifyLibraryTests'         passed  Executed  8 tests, with 0 failures
Test Suite 'DynamicIslandTests.xctest'   passed  Executed 27 tests, with 0 failures
xcresult: ~/Library/Developer/Xcode/Gourd/Logs/Test/Test-DynamicIsland-2026.09.27_19-50-03-+0800.xcresult
```

**结论**：改名后的工程**测试可跑且全绿**。这条比"能构建"强得多——它同时证明了 T2 的 `TEST_HOST` 与 `PRODUCT_MODULE_NAME = Atoll` 两处改动在真实测试路径上成立（否则 test host 起不来或 4 个 `@testable import Atoll` 编译失败）。

## 2. 上游自带测试（T2）

```bash
python3 -m unittest tests.test_privacy_configuration tests.test_timer_lifecycle
# Ran 7 tests in 2.160s
# OK        → 退出码 0
```

## 3. 运行时验证（T3）

### 3.1 启动与存活

```bash
open ~/Library/Developer/Xcode/Gourd/Build/Products/Debug/Gourd.app
pgrep -f "Gourd.app/Contents/MacOS/Gourd"      # → 37595（存活，观察 >2 分钟无崩溃）
```

### 3.2 面板窗口存在且层级/位置正确（间接证据）

用 CoreGraphics 按 **PID** 枚举窗口（`CGWindowListCopyWindowInfo`；注意属主名是显示名 `壶中天` 而非 `Gourd`）：

```
owner=壶中天 layer=27 alpha=1.0 bounds={X=436, Y=-4, W=640, H=222}   ← 刘海面板
owner=壶中天 layer=0  alpha=1.0 bounds={X=0,   Y=382, W=700, H=600}  ← 启动时出现的普通窗口（疑似首启引导）
```

- `layer=27` 恰为设计值 `.mainMenu + 3`（菜单栏之上、不抢焦点）✓
- 水平居中：`436 + 640/2 = 756 = 1512/2` ✓、贴顶 `Y=-4` ✓
- **间接性标注**：这是窗口元数据证据，说明"面板窗口存在且层级正确"，**不等于**"肉眼看到的折叠态渲染正确"（见 §3.6）。

### 3.3 资源基线

| 指标 | 实测 | 基线 | 判定 |
|---|---|---|---|
| CPU（折叠态，`top` 静置 6 次采样） | 0.0 / 4.4 / 0.3 / 0.3 / 0.4 / 0.2 % | <1% | **达标**（4.4% 为一次性瞬态） |
| CPU（重启后静置 3 次） | 0.0 / 0.1 / 0.2 % | <1% | **达标** |
| 内存（`vmmap` **Physical footprint**） | **129.0 MB**（峰值 218.2 MB） | <150MB | **达标** |
| 内存（`top` MEM） | 90–133 MB | — | 同上量级 |
| 内存（`ps` **RSS**） | 230–258 MB | — | **口径不同，不用于判定** |

> ⚠️ **口径提醒（重要，避免误判）**：`ps` 的 RSS 把**共享库页**也算进来，本机只读库常驻就有 650MB（全系统共享），所以它系统性高于真实占用。macOS 上与"内存占用"一致的口径是 **physical footprint**（活动监视器的"内存"列），实测 129MB，**在基线内**。以后验收请固定用 `vmmap -summary` 的 Physical footprint。

### 3.4 网络：没有连上游，但有 loopback 与局域网

```bash
lsof -a -p <pid> -i -n -P      # 注意必须带 -a：lsof 的 -p 与 -i 缺省是"或"关系，不带 -a 会打到别的进程（本报告初稿即踩此坑）
```

```
TCP 127.0.0.1:9020 (LISTEN)     ← 扩展 RPC（ADR-0008 冻结项，符合预期）
TCP [::1]:9020     (LISTEN)     ← 同上
TCP *:53317        (LISTEN)     ← LocalSend 服务（shelf 的局域网互传）
UDP *:64466 / *:53317
UDP 192.168.1.6:64466 -> 224.0.0.167:53317   ← LocalSend 多播发现
```

**结论**：**没有任何指向上游域名（`raw.githubusercontent.com` 等）的外部连接**，没有 `:443` 出站长连接 ✓。T9 关闭运行期 Sparkle feed 的效果在运行时得到验证。局域网多播是 LocalSend 的既定行为（上游功能，非本次改动引入）。

### 3.5 日志 subsystem —— **未能验证（不是失败）**

```bash
log show --last 5m --predicate 'subsystem == "com.cmeng.gourd"'   # 0 条
log show --last 6m --predicate 'process == "Gourd"'               # 0 条
```

两条都是 0 条。**这不是"旧 subsystem 还在"的证据**（旧 subsystem 查询同样是 0 条），而是**该应用在观察窗口内没有产生被持久化的 os_log 记录**（`debug`/`info` 级默认不落盘）。**结论：本项无法用 `log show` 验证**，需要改成"触发一个必定打日志的路径再看"，留作后续验证手段（不影响 P0 判定）。

### 3.6 GUI 交互（折叠/展开）—— **未能验证 + 记录一处异常**

**为什么验不了**（两条工具限制，均实测）：
1. 展开是**窗口内裁剪**而非窗口变大——`W/H` 在悬停前后恒为 `640×222`，所以"窗口尺寸变化"不能作为展开的判据；
2. 用 `CGEvent` 合成鼠标移动（沿路径逼近刘海 `(756, y)` 直至 `y=2`，每步 60ms）**触发了异常位移**：

```
[初始]        W=640 H=222 X=436   Y=-4
[悬停在刘海]  W=640 H=222 X=3242  Y=-4    ← 面板被移到屏幕外（本机单屏，宽仅 1512）
[移开后]      W=640 H=222 X=436   Y=-4    ← 自动复位
```

重启应用后窗口数为 2、面板回到 `X=436` 居中，**异常不复现**。

**对这条异常的诚实定性**：它在**合成输入**下出现、重启即复位，**不能**据此认定真实鼠标下也会发生；但也不能排除——**需要一次人工复核**（真实鼠标移到刘海，看面板是否正常展开、有没有被移位）。这是本报告唯一挂起的观察项。

**另外**：首启时会出现一个 `700×600` 的 `layer=0` 普通窗口（疑似欢迎/引导窗），每次启动都在。属上游既有行为，未见异常。

---

## 4. 未验证部分与判定

### 4.1 本次明确未验证（含原因）

| 项 | 原因 |
|---|---|
| 折叠/展开的视觉与交互行为 | 展开为窗口内裁剪、合成鼠标事件触发异常位移；**需人工复核一次** |
| 日志 subsystem 实际生效 | 观察窗口内无被持久化的 os_log 记录（debug/info 不落盘），`log show` 无法判定 |
| 真实 CI 绿灯 | 用户要求本地验证、不推送（D-01） |
| 分发链路（签名/公证/DMG/Sparkle 更新） | P5 范围 |
| 长时间稳定性（"连续使用 7 天"） | 本次只做短时采样（>2 分钟） |
| x86_64 / 多屏 / 合盖 | 本机 arm64 单屏；无外接显示器与合盖操作 |
| GUI 之外的"不投入"默认值（如 `enableScreenAssistant=false` 的效果） | 属 P2 接管范围 |

### 4.2 P0 验收判定

**达标（本地范围内）**：

| P0 验收（docs/02） | 判定 | 依据 |
|---|---|---|
| 本机能编译 | ✅ | 全量重建 `BUILD SUCCEEDED`，产物 119MB（P0-7 实测记录） |
| **单测可跑且全绿** | ✅ | 27 用例 0 失败（§1）—— 本次新增证据 |
| **运行不崩** | ✅ | 存活 >2 分钟、重启后资源在基线内（§3.1/3.3） |
| **性能基线（内存 <150MB、折叠态 CPU <1%）** | ✅ | 足迹 129MB / CPU 0.0–0.4%（§3.3） |
| **不再外连上游** | ✅ | 无外部连接（§3.4）—— 本次新增证据 |
| 刘海面板能折叠/展开 | ⚠️ **未验证** | 工具限制 + 一处待人工复核的异常（§3.6） |
| CI 绿灯 | ⚠️ 未验证 | 用户要求本地优先（D-01） |

**一句话结论**：P0 的"能构建"已推进到"**测试全绿 + 运行正常 + 资源达标 + 不外连上游**"；**唯一未闭环的是折叠/展开的视觉交互**，需要你花 10 秒用真实鼠标试一下（顺带看面板有没有被移位）。

### 4.3 未推送声明

本次验证全程**未推送、未建远端**：`git remote -v` 只有只读的 `atoll`。
