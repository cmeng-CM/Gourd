#!/bin/bash
# Gourd 本地打包脚本（2026-09-27）
#
# 用法（在仓库内任意位置）：
#   sh tools/build.sh                # 构建 Release 的 Gourd.app，打印产物路径
#   sh tools/build.sh --install      # 构建后安装到 /Applications/壶中天.app（自动退出旧实例）
#   sh tools/build.sh --dmg          # 构建后在 dist/ 产出拖拽安装式 DMG
#   sh tools/build.sh --install --dmg
#   其余参数原样转给 xcodebuild（如 CODE_SIGN_IDENTITY=... 覆盖）。
#
# 说明：
#   - 构建产物（DerivedData 里）固定叫 Gourd.app，TEST_HOST 依赖该路径；
#     对外安装与 DMG staging 才改名为「壶中天.app」（见 --install / --dmg）；
#   - 签名优先用稳定身份 "Gourd Local"（tools/setup-signing.sh 生成），
#     TCC 授权跨构建保留；无则退回 ad-hoc；
#   - DerivedData 固定在 ~/Library/Developer/Xcode/Gourd（勿用 /tmp，Xcode 27 会挂起）；
#   - 打包全程本机完成，不依赖 GitHub。

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

derived="${GOURD_DERIVED_DATA:-$HOME/Library/Developer/Xcode/Gourd}"
# 构建产物名（PRODUCT_NAME=Gourd，TEST_HOST 依赖）——不要改
app="$derived/Build/Products/Release/Gourd.app"
# 安装落地名：对用户可见的产品名叫「壶中天」
installed_app="/Applications/壶中天.app"

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
  sign_identity="Gourd Local"
  echo "签名身份：Gourd Local（稳定，授权跨构建保留）"
else
  sign_args=(CODE_SIGN_IDENTITY="-")
  sign_identity="-"
  echo "签名身份：ad-hoc（提示：运行 tools/setup-signing.sh 生成稳定身份）"
fi

# 落地副本的产品名收尾：Info.plist 的 CFBundleName 由 PRODUCT_NAME 生成
# （INFOPLIST_KEY_CFBundleName 不生效），所以只能在落地副本上改，再按原身份重签。
# 重签用同一张证书 + 同一 bundle id + 原 entitlements，TCC 与登录项的「证书 + bundle id」记忆不变；
# 不改这里是不能只改 plist 的——改完不重签会让签名与 Info.plist 不匹配，应用起不来。
stamp_product_name() {
  target="$1"
  plutil -replace CFBundleName -string "壶中天" "$target/Contents/Info.plist" 2>/dev/null \
    || plutil -insert CFBundleName -string "壶中天" "$target/Contents/Info.plist"
  codesign --force --options runtime --preserve-metadata=identifier,entitlements \
    --sign "$sign_identity" "$target"
}

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
  # 两个历史落地名都查一遍（旧的 Gourd.app、新的 壶中天.app）；只删 bundle id 命中的，
  # 读到别人的 id 一律中止，不硬删非本工程应用
  for old in /Applications/Gourd.app "$installed_app"; do
    if [ -d "$old" ]; then
      installed_id="$(plutil -extract CFBundleIdentifier raw "$old/Contents/Info.plist" 2>/dev/null || true)"
      case "$installed_id" in
        com.cmeng.gourd|com.cmeng.gourd.dev) rm -rf "$old" ;;
        *) echo "中止：$old 存在但不是本工程产物（bundle id: ${installed_id:-未知}），请手动确认。"; exit 1 ;;
      esac
    fi
  done
  ditto "$app" "$installed_app"
  stamp_product_name "$installed_app"
  echo "===== 已安装到 $installed_app ====="
  # 刷新 LaunchServices，免得系统里留下重复/失效条目；失败不致命，只提示
  lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  if "$lsregister" -f "$installed_app" >/dev/null 2>&1; then
    echo "LaunchServices 已刷新：$installed_app"
  else
    echo "提示：LaunchServices 刷新失败（不影响使用）"
  fi
  # 构建期 xcodebuild 会把 DerivedData 里的产物也登记成 com.cmeng.gourd 的候选，
  # 两份同 id 会抢 `open -b`（实测会拉起 DerivedData 那份）；注销掉它，
  # 让 /Applications 的这支成为唯一候选。失败不致命。
  if "$lsregister" -u "$app" >/dev/null 2>&1; then
    echo "已注销 DerivedData 副本的 LaunchServices 登记（保 /Applications 唯一）"
  else
    echo "提示：未注销 DerivedData 副本（通常表示它本就没有登记，无需处理）"
  fi
fi

if [ "$do_dmg" = true ]; then
  ver="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
  out="$repo_root/dist"
  mkdir -p "$out"
  stage="$(mktemp -d)"
  ditto "$app" "$stage/壶中天.app"
  stamp_product_name "$stage/壶中天.app"
  ln -s /Applications "$stage/Applications"
  rm -f "$out/Gourd-$ver.dmg"
  hdiutil create -volname "壶中天" -srcfolder "$stage" -ov -format UDZO "$out/壶中天-$ver.dmg" >/dev/null
  rm -rf "$stage"
  echo "===== DMG ====="
  echo "$out/壶中天-$ver.dmg"
fi
