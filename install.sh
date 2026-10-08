#!/bin/bash
# 壶中天 / Gourd —— 命令行安装（2026-10-08）
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/cmeng-CM/Gourd/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- v0.1.0      # 指定版本
#
# 为什么有这条：从浏览器下载的 DMG 会被打上 com.apple.quarantine 隔离标记，
# 首次启动必被 Gatekeeper 拦一次（要手动去「系统设置 → 隐私与安全性」放行）。
# 本脚本改用 curl 取包——curl 落盘不带隔离标记，装完首启不会弹任何提示。
#
# 脚本只做五件事，不做别的：判断芯片架构 → 下载 → 校验 SHA256 → 挂载并拷进
# 「应用程序」→ 卸载清理。不写系统目录、不改系统设置、不装任何额外东西。
# 想核对再跑：本文件全文就在上面那个 URL，没有任何下载后才展开的逻辑。

set -euo pipefail

REPO="cmeng-CM/Gourd"
APP_NAME="壶中天"
BUNDLE_ID="com.cmeng.gourd"
DEST="/Applications/$APP_NAME.app"

say() { printf '%s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

# ---- 0. 前置检查 ----------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || die "这个脚本只用于 macOS。"
[ "$EUID" -ne 0 ] || die "请不要用 sudo 运行：装到「应用程序」不需要 root，用 root 装会让应用属主变成 root。"

# 应用只出 arm64 架构（Apple 芯片）。Intel 机器上装得上但跑不起来，先挡掉。
if [ "$(uname -m)" != "arm64" ]; then
  die "当前芯片是 $(uname -m)，而「${APP_NAME}」目前只提供 Apple 芯片（arm64）构建。"
fi

[ -w /Applications ] || die "当前用户对 /Applications 没有写权限，请改用 README 里的 DMG 方式安装。"

# ---- 1. 定版本 ------------------------------------------------------------

tag="${1:-}"
if [ -z "$tag" ]; then
  say "查询最新版本…"
  # 末尾 || true：curl 失败（断网 / 404）时不要因 pipefail 静默退出，交给下面那句报错
  tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" | sed 's#.*/tag/##' || true)"
fi
[ -n "$tag" ] || die "没能确定版本号，请显式指定，例如：bash -s -- v0.1.0"

ver="${tag#v}"
dmg_name="Gourd-$ver.dmg"
base="https://github.com/$REPO/releases/download/$tag"

# ---- 2. 下载 --------------------------------------------------------------

tmp="$(mktemp -d)"
mp=""
cleanup() {
  [ -n "$mp" ] && [ -d "$mp" ] && hdiutil detach "$mp" >/dev/null 2>&1
  [ -n "${tmp:-}" ] && [ -d "$tmp" ] && rm -rf "$tmp"
  return 0
}
trap cleanup EXIT

say "下载 ${dmg_name}（${tag}）…"
curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/$dmg_name" "$base/$dmg_name" \
  || die "下载失败：${base}/${dmg_name}（版本号写错？或该 Release 没有这个附件）"

# ---- 3. 校验完整性 --------------------------------------------------------
# Release 里附了 SHA256SUMS 就自动校验；没有则打印实测值，供手动比对 Release 正文。

if curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS" 2>/dev/null; then
  ( cd "$tmp" && shasum -a 256 -c SHA256SUMS --status ) \
    || die "SHA256 校验不通过——文件可能下载不全或被改过，已中止，什么都没装。"
  say "SHA256 校验通过。"
else
  say "提示：该 Release 未提供 SHA256SUMS，无法自动校验。"
  say "      实测 SHA256：$(shasum -a 256 "$tmp/$dmg_name" | awk '{print $1}')"
fi

# ---- 4. 挂载并安装 --------------------------------------------------------

mp="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$mp" "$tmp/$dmg_name" >/dev/null \
  || die "挂载 DMG 失败。"

# 末尾 || true：没找到 .app 时不要让 pipefail 静默退出，交给下面那句报错
src="$(ls -d "$mp"/*.app 2>/dev/null | head -1 || true)"
[ -n "$src" ] || die "DMG 里没找到 .app。"

# 先退出正在运行的实例，否则替换后旧实例还占着刘海位
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

# 覆盖安装：只删 bundle id 命中的那一支；读到别人的 id 就停下问人，绝不硬删
if [ -d "$DEST" ]; then
  installed_id="$(plutil -extract CFBundleIdentifier raw "$DEST/Contents/Info.plist" 2>/dev/null || true)"
  [ "$installed_id" = "$BUNDLE_ID" ] \
    || die "$DEST 已存在，但它的 bundle id 是「${installed_id:-未知}」，不是本应用——请手动确认后处理。"
  rm -rf "$DEST"
fi

ditto "$src" "$DEST"
# curl 下载本来就不带隔离标记，这里再兜一次：确保首启不弹 Gatekeeper
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
say "已安装到 $DEST"

# ---- 5. 收尾 --------------------------------------------------------------

hdiutil detach "$mp" >/dev/null 2>&1 || true
mp=""

say ""
say "装好了。"
say "· 应用是菜单栏小工具（没有 Dock 图标）：把鼠标移到屏幕顶部中间，悬停即展开；"
say "· 退出、设置都在菜单栏图标里；"
say "· 要读系统通知需要「完全磁盘访问」，要镜子需要摄像头——用到时按提示给，不给只是对应功能降级。"
say "· 升级：重新跑一遍本脚本；偏好、权限、登录项都不会丢。"
