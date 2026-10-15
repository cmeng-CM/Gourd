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
# 这里的 open 与你手点 Finder 等价——脚本在你自己的登录会话里跑（Terminal / 双击 .command）。
# 反例是**非交互 shell 里 `open -a`**：那会起出一个没有 UI 会话的实例（菜单栏无图标、
# 退不掉、主线程在 AppKit 约束循环里空转），只能手工 lsregister 补救——所以自动化里要么
# 传 --no-open，要么别从那种 shell 起它（见 tools/build.sh 末尾的登记收尾那一段）。

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
installed_app="/Applications/壶中天.app"

open_after=true
extra=()
for a in "$@"; do
  case "$a" in
    --no-open) open_after=false ;;
    *) extra+=("$a") ;;
  esac
done

# 构建 + 安装 + 退出旧实例 + 刷新 LaunchServices：全部逻辑只有一份，住在 tools/build.sh 里。
sh "$repo_root/tools/build.sh" --install ${extra[@]+"${extra[@]}"}

if [ "$open_after" = true ]; then
  if open "$installed_app" >/dev/null 2>&1; then
    echo "已启动 ${installed_app}"
  else
    echo "提示：自动启动失败，请手动打开 ${installed_app}"
  fi
fi
