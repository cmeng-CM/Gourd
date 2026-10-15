#!/bin/bash
# 双击这个文件 = 把当前源码构建成 Release 并装到 /Applications/壶中天.app，然后启动它。
#
# 命令行等价用法：sh tools/install-local.sh        （--no-open 可只装不启动）
# 「给别人装」用的是仓库根的 install.sh（下载 GitHub Release 的 DMG），不是这个。
#
# 说明：双击后 Finder 会用「终端」跑本脚本，输出就在那个窗口里；跑完按任意键关闭。
# 构建约一两分钟，中途窗口没动静是正常的（xcodebuild 的输出很长）。

cd "$(dirname "$0")" || exit 1

sh tools/install-local.sh
status=$?

echo
if [ "$status" -eq 0 ]; then
  echo "装好了：/Applications/壶中天.app"
else
  echo "安装失败（退出码 ${status}）——上面的输出里有原因。"
fi

# 只在真正的终端里等按键（被脚本调用 / 管道里跑时不阻塞）
if [ -t 0 ]; then
  echo
  echo "按任意键关闭这个窗口…"
  read -n 1 -s
fi
exit "$status"
