#!/bin/bash
# 壶中天 / Gourd —— 本机一键安装（2026-10-15）
#
# 用法（在仓库内任意位置，或双击仓库根的 `install-local.command`）：
#   sh tools/install-local.sh              # 构建 Release → 装到 /Applications/壶中天.app → 启动
#   sh tools/install-local.sh --no-open    # 同上，但装完不自动启动
#   其余参数原样转给 tools/build.sh（如 CODE_SIGN_IDENTITY=...）
#
# 这条脚本**只管本机**：源码就地构建，不联网、不碰 GitHub。
# 「给别人装」的那条是仓库根的 `install.sh`（curl 下载 Release 里的 DMG）——两者别混。
#
# 为什么装完顺手启动一次：装完新版本就是要立刻看效果，这一步省掉一次鼠标。
# 2026-10-22 起，启动也归 tools/build.sh --install 管（它会在登记收尾之后 open，
# 并只在 Aqua 会话里启动）；本脚本只负责把 --no-open 原样转下去，不再自己 open 第二遍。

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

open_after=true
extra=()
for a in "$@"; do
  case "$a" in
    --no-open) open_after=false ;;
    *) extra+=("$a") ;;
  esac
done

forward=(--install)
if [ "$open_after" = false ]; then
  forward+=(--no-open)
fi

# 构建 + 安装 + 退出旧实例 + 刷新 LaunchServices + 启动：全部逻辑只有一份，住在 tools/build.sh 里。
sh "$repo_root/tools/build.sh" "${forward[@]}" ${extra[@]+"${extra[@]}"}
