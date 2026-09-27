#!/bin/bash
# Gourd 本地打包脚本（2026-09-27）
#
# 用法（在仓库内任意位置）：
#   sh tools/build.sh             # 构建 Release 的 Gourd.app，打印产物路径
#   sh tools/build.sh --install   # 构建后安装到 /Applications（自动退出旧实例）
#
# 说明：
#   - 签名用工程内置的 ad-hoc（CODE_SIGN_IDENTITY = "-"），不依赖任何证书；
#   - DerivedData 固定在 ~/Library/Developer/Xcode/Gourd（勿用 /tmp，Xcode 27 会挂起）；
#   - 传给本脚本的其余参数原样转给 xcodebuild。

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

derived="${GOURD_DERIVED_DATA:-$HOME/Library/Developer/Xcode/Gourd}"
app="$derived/Build/Products/Release/Gourd.app"

xcodebuild build \
  -project DynamicIsland.xcodeproj \
  -scheme DynamicIsland \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$derived" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  "$@"

echo
echo "===== 产物 ====="
echo "$app"
plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist"
plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist"

if [ "${1:-}" = "--install" ]; then
  # 同名应用会抢刘海位，先退出正在运行的实例（按 bundle id，两个配置都试）
  osascript -e 'tell application id "com.cmeng.gourd" to quit' >/dev/null 2>&1 || true
  osascript -e 'tell application id "com.cmeng.gourd.dev" to quit' >/dev/null 2>&1 || true
  if [ -d /Applications/Gourd.app ]; then
    installed_id="$(plutil -extract CFBundleIdentifier raw /Applications/Gourd.app/Contents/Info.plist 2>/dev/null || true)"
    case "$installed_id" in
      com.cmeng.gourd|com.cmeng.gourd.dev) rm -rf /Applications/Gourd.app ;;
      *) echo "中止：/Applications/Gourd.app 存在但不是本工程产物（bundle id: ${installed_id:-未知}），请手动确认。"; exit 1 ;;
    esac
  fi
  ditto "$app" /Applications/Gourd.app
  echo "===== 已安装到 /Applications/Gourd.app ====="
fi
