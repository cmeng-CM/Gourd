# 发布流程（打包 → 上传 → Release）

| 项 | 值 |
|---|---|
| 状态 | **可用**（2026-10-08 首版；v0.1.0 之后的每次发布照这一页走） |
| 最后更新 | 2026-10-08 |
| 关联来源 | [00-decisions](00-decisions.md) ADR-0013（签名与分发路线）、[25-release-smoke](25-release-smoke.md)（发布前真机自检）、[24-release-freeze](24-release-freeze.md)（版本身份与许可口径）；脚本：[tools/build.sh](../tools/build.sh)、[install.sh](../install.sh) |

> **给谁看**：给**发布者**（我自己）。目标：任何一次发布照这一页走完，产出的包与说明都一致、可复现。
> **不涉及**：要不要付费公证（已定：不付费，见 ADR-0013）。

## 0. 既定事实（它们决定了流程长什么样）

| 事实 | 实测依据（2026-10-08） | 对流程的约束 |
|---|---|---|
| 应用用**自签证书** `Gourd Local` 签，**不公证** | 出厂包 `Authority=Gourd Local`、`TeamIdentifier=not set`；DMG 无公证票据 | 别人首次启动必被 Gatekeeper 拦一次 → 安装说明必须写对放行路径 |
| Gatekeeper 的首次启动拦截**只对带 `com.apple.quarantine` 标记的包生效** | `curl` 落盘只有 `com.apple.provenance`，无 quarantine；Homebrew cask 会主动打上（源码 `Quarantining ...`） | 「命令行安装」是零成本的无提示路径；DMG 路径必须保留放行说明 |
| **签名身份一变，全体用户的 TCC 授权与登录项会重置** | TCC 按「证书 + Bundle ID」记忆（见 tools/setup-signing.sh 注释） | 每次发布必须用同一张证书；私钥要备份 |
| 应用只出 **arm64** | 出厂包 `Mach-O thin (arm64)` | Intel 机器要提前挡掉；安装说明写明 |
| Release 附件用 **ASCII 名**，本地产物用中文名 | README「与 Atoll 的关系」段 | 上传前改名；`install.sh` 按 ASCII 名拼下载地址 |

**一次性准备（只做一次）**

1. 生成签名身份：`sh tools/setup-signing.sh`（已有则幂等跳过）。
2. **拿到并离线保存这张证书的私钥——漏了这一步，将来证书一丢，所有用户的授权都会重置。**
   `setup-signing.sh` 现在会把生成的 p12 留一份在
   `~/Library/Application Support/Gourd/signing/Gourd-Local-<日期>.p12`（权限 600），
   把它移到密码管理器附件或加密备份里，**绝不进仓库、别留在同步盘**。
   它的密码是脚本里的 `gourd-local-import`——只防随手读走，不是强保护。

   > **为什么不能事后从钥匙串导出**：`security import` 只把私钥的使用权限授给了 `/usr/bin/codesign`
   > （`-T` 参数），**导出**是另一种权限，任何进程想导出都会弹一次人工授权；实测在无人值守时
   > 直接返回 `SecKeychainItemExport: User canceled the operation`，钥匙串访问里的导出项也可能
   > 直接不可用。**所以那份落盘的 p12 才是你真正能带走的备份**，别指望临时从钥匙串抠出来。
   >
   > 早期身份（脚本还不落盘时生成的）想补救，只能人工授权导一次：
   >
   > ```bash
   > security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 \
   >   -P '<自己设的导出密码>' -o ~/Desktop/Gourd-Local.p12
   > ```
   >
   > 跑完会弹出授权框，**必须在框里输密码点允许**，命令行等不到人就会中止。
3. 验一下当前身份在位：`security find-identity -v -p codesigning | grep '"Gourd Local"'`。

## 1. 改版本号

| 位置 | 改什么 |
|---|---|
| `VERSION` | `x.y.z` |
| `DynamicIsland.xcodeproj/project.pbxproj` | `MARKETING_VERSION`（**Debug 与 Release 两处**）；可选：`CURRENT_PROJECT_VERSION` 递增（「关于」页显示的构建号） |
| `CHANGELOG.md` | 顶部新增 `## [x.y.z] - YYYY-MM-DD` 段，写本版自有变更 |
| `README.md` | 安装段里的 `Gourd-x.y.z.dmg` |
| `docs/guide/README.md` | 头部「适用版本」 |

> `docs/24`、`25`、`27`、`07` 等**历史设计记录里的版本号不要改**——那是当时的记录。

## 2. 门禁（两条都绿才继续）

```bash
xcodebuild test -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -destination "platform=macOS" -derivedDataPath ~/Library/Developer/Xcode/Gourd \
  -only-testing:DynamicIslandTests -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES

sh tools/build.sh          # 能出包即可
```

真机自检按 [25-release-smoke](25-release-smoke.md) 走一遍；**没跑到的条目要写进当次发布报告，不许留空。**

## 3. 打包

```bash
sh tools/build.sh --dmg
```

脚本自带两道发布门禁，任一不过会**直接中止**：

1. **身份门禁**：`--dmg` 的产物用于对外分发，签名身份必须是 `Gourd Local`；
   本机没有该身份时会退回 ad-hoc ——这时脚本拒绝出包（ad-hoc 在别人机器上更容易被判「已损坏」，
   且会重置老用户授权）。只装本机请用 `--install`。
2. **签名自校验**：对 staging 里的 app 跑 `codesign --verify --deep --strict`，
   查的是**嵌套代码**（Sparkle 的 `Updater.app` + 两个 XPC 服务、Lottie、helpers）。
   本机因为没有隔离标记，嵌套签名坏了照样能跑，**光在本机试是发现不了的**。

产物：`dist/壶中天-x.y.z.dmg`，脚本同时打印 **SHA256**。留用。

> 出厂包**不应带 `get-task-allow`**。它由 Release 配置的
> `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` 关掉（调试权限；也是将来公证的硬性拒收项）。
> 复核：`codesign -d --entitlements :- <app>` 里不应出现该键。

## 4. 改名 + 校验和

```bash
cd dist
cp 壶中天-x.y.z.dmg Gourd-x.y.z.dmg
shasum -a 256 Gourd-x.y.z.dmg > SHA256SUMS
cat SHA256SUMS
```

`SHA256SUMS` 必须按 ASCII 名写——[install.sh](../install.sh) 会下载它并 `shasum -c` 校验，
文件里名字对不上就校验失败、安装中止。

## 5. 打标签 + 建 Release

```bash
cd /Users/cm/workspace/github/gourd

git push origin main          # 日常提交是本地提交不推送；发布这一步才推
git tag -a vx.y.z -m "壶中天 vx.y.z"
git push origin vx.y.z

gh release create vx.y.z --repo cmeng-CM/Gourd \
  --title "壶中天 vx.y.z" \
  --notes-file .workflow/release-notes-vx.y.z.md \
  dist/Gourd-x.y.z.dmg dist/SHA256SUMS
```

**附件只有两个**：`Gourd-x.y.z.dmg` 与 `SHA256SUMS`。不加别的。

## 6. Release 正文模板

> 正文里的安装说明必须与 README 一致；下面是当前口径，发布时整段复制、替换版本号。
> 完整正文另见上一版的 Release（`gh release view --repo cmeng-CM/Gourd`）。

```markdown
壶中天（Gourd）是 macOS 上的**刘海工作台**……（保留上一版的介绍段）

## 安装

要求 **macOS 26（Tahoe）及以上**、**Apple 芯片（arm64）**。

**方式一 · DMG**：下载 `Gourd-x.y.z.dmg`，打开后把「壶中天」拖进「应用程序」。
应用**未公证**（本项目不付费走 Apple 开发者计划），第一次打开会被 Gatekeeper 拦下，**放行一次即可**：

1. 双击「壶中天」，出现「Apple 无法验证」这类提示时点**完成**；
2. **系统设置 → 隐私与安全性** → 往下滚到「安全性」一栏 → 点**仍要打开**；
3. 输入密码，再双击一次。
   （别跳第 1 步：先被拦一次，那个按钮才会出现。）

**方式二 · 命令行**（装完不弹任何提示）：

    curl -fsSL https://raw.githubusercontent.com/cmeng-CM/Gourd/main/install.sh | bash

**方式三 · 自己构建**（需要 Xcode）：`sh tools/build.sh --install`

## 校验

`SHA256SUMS` 里的值应与下面一致（即附件 DMG 的 SHA256）：

    <贴本次 shasum 输出>

## 这一版有什么

……（本次变更）

## 说明与已知限制

- **未公证**：首启需按上面第 2~3 步手动放行。
- **没有应用内更新**：升级用新 DMG 覆盖安装，或重跑命令行安装脚本；偏好、权限、登录项都不会丢。
- ……（其余保留上一版口径）
```

## 7. 发布后自检（别省）

`Gourd Local` 的信任写在**用户域**，所以**同一台 Mac 上新建一个用户账户就等价于一台干净机器**：

1. 在新账户里打开浏览器下载 DMG（**必须走浏览器**，`curl` 不带隔离标记，测不出拦截）；
2. 拖进「应用程序」，双击 → 应被拦下；
3. 按 Release 正文的第 2~3 步放行 → 应能打开；
4. 再跑一次命令行安装：`curl -fsSL .../install.sh | bash` → 应安装成功且**首启无任何提示**；
5. 顺带确认 `SHA256SUMS` 与 Release 正文里贴的值一致。

## 8. 仓库保护（`main` 的规则集）

`main` 上有一条 **ruleset `main-protection`**（2026-10-08 加，仓库设置 → Rules：

| 规则 | 含义 |
|---|---|
| `deletion` | **不能删 `main`** |
| `non_fast_forward` | **不能 force push**（历史不能被覆盖） |
| `pull_request` | **要改 `main` 得走 PR**（要求批准数 0 —— PR 可以直接合并，不必等 review） |

**bypass：仓库管理员角色（`RepositoryRole` id 5）× `always`。** 也就是**你自己照旧**能
`git push origin main`（第 5 步一个字不用改）；这条保护管的是**将来加进来的协作者**——
他们只能提 PR，推不动 `main`、也删不掉。

两条刻意的取舍：

- **tag 不在这条规则集里**：发版时「删旧 tag → 重打同一个 tag」是既定手法（第 5 步、以及 2026-10-08
  的 v0.1.0 重发），把 `refs/tags/*` 也保护起来会把那条路堵死。
- **不开 `required_status_checks`**：本仓库 Actions 是停用的（见下），没有可要求的检查。

> 自查：`gh api repos/cmeng-CM/Gourd/rulesets --jq '.[] | {name, enforcement}'`。
> 万一哪天这条规则把你自己拦住了（`current_user_can_bypass` 不是 `always`），
> 到 仓库设置 → Rules 里把 bypass 改成你的账号、或临时 disable 这条规则集。


## 已知限制 / 不做的事

- **做不到「下载双击就开」**：没有 Developer ID + 公证就没有这条路；零成本的上限就是上面两条。
- **不写「右键 → 打开」**：macOS 15 起 Apple 移除了这个绕过入口，而应用要求 macOS 26。
  本项目未在旧系统上逐版本复核，所以文档统一只给「系统设置 → 仍要打开」——
  那条路径在所有受支持版本上都成立。
- **不推荐 `xattr -dr com.apple.quarantine`** 作为对外的安装说明：那是绕过动作，
  对普通使用者不友好也不透明；命令行安装已经用「curl 不带标记」这个正当方式解决了同一问题。
- **Intel 机器当前不支持**（只出 arm64）。
