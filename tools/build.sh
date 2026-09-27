#!/bin/bash
# Gourd 本地打包脚本（2026-09-27）
#
# 用法（在仓库内任意位置）：
#   sh tools/build.sh                # 构建 Release 的 Gourd.app，打印产物路径
#   sh tools/build.sh --install      # 构建后安装到 /Applications（自动退出旧实例）
#   sh tools/build.sh --dmg          # 构建后在 dist/ 产出拖拽安装式 DMG
#   sh tools/build.sh --install --dmg
#   其余参数原样转给 xcodebuild（如 CODE_SIGN_IDENTITY=... 覆盖）。
#
# 说明：
#   - 签名优先用稳定身份 "Gourd Local"（tools/setup-signing.sh 生成），
#     TCC 授权跨构建保留；无则退回 ad-hoc；
#   - DerivedData 固定在 ~/Library/Developer/Xcode/Gourd（勿用 /tmp，Xcode 27 会挂起）；
#   - 打包全程本机完成，不依赖 GitHub。

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

derived="${GOURD_DERIVED_DATA:-$HOME/Library/Developer/Xcode/Gourd}"
app="$derived/Build/Products/Release/Gourd.app"

do_install=false
do_dmg=false
extra=()
for a in "$@"; do
  case "$a" in
    --install) do_install=true ;;
    --dmg) do_dmg=true ;;
    *) extra+=("$a") ;;
  esac
done

# 签名：app target 在工程里固定用稳定身份 "Gourd Local"（tools/setup-signing.sh 生成，
# TCC 授权按「证书 + Bundle ID」记忆，升级不重复弹授权）。本机没有该身份时，
# 整体退回 ad-hoc 兜底（每次构建授权重置）。SPM 依赖包不受工程内身份影响。
if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Gourd Local"'; then
  sign_args=()
  echo "签名身份：Gourd Local（稳定，授权跨构建保留）"
else
  sign_args=(CODE_SIGN_IDENTITY="-")
  echo "签名身份：ad-hoc（提示：运行 tools/setup-signing.sh 生成稳定身份）"
fi

xcodebuild build \
  -project DynamicIsland.xcodeproj \
  -scheme DynamicIsland \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$derived" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  ${extra[@]+"${extra[@]}"} \
  ${sign_args[@]+"${sign_args[@]}"}

echo
echo "===== 产物 ====="
echo "$app"
plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist"
plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist"

if [ "$do_install" = true ]; then
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

if [ "$do_dmg" = true ]; then
  ver="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
  out="$repo_root/dist"
  mkdir -p "$out"
  stage="$(mktemp -d)"
  ditto "$app" "$stage/Gourd.app"
  ln -s /Applications "$stage/Applications"
  rm -f "$out/Gourd-$ver.dmg"
  hdiutil create -volname "壶中天" -srcfolder "$stage" -ov -format UDZO "$out/Gourd-$ver.dmg" >/dev/null
  rm -rf "$stage"
  echo "===== DMG ====="
  echo "$out/Gourd-$ver.dmg"
fi
