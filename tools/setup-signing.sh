#!/bin/bash
# 壶中天/Gourd —— 本地稳定签名身份一次性配置（2026-09-27）
#
# 作用：生成自签代码签名证书 "Gourd Local"（10 年期）并导入登录钥匙串、
#       开启代码签名信任。此后 tools/build.sh 会自动用它签名：
#       TCC 授权（辅助功能、文件夹、相机…）按「证书 + Bundle ID」记忆，
#       重新构建等于升级——授权一次，后续不再弹窗。
#       （ad-hoc 签名没有稳定身份，系统按每次构建的哈希认应用，授权全部重置。）
#
# 用法：sh tools/setup-signing.sh
# 幂等：已有 "Gourd Local" 身份时什么都不做直接退出。
set -euo pipefail

if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Gourd Local"'; then
  echo "✅ 已存在 \"Gourd Local\" 签名身份，无需重复配置。"
  security find-identity -v -p codesigning | grep '"Gourd Local"'
  echo
  echo "提醒：这张身份的私钥做过离线备份了吗？没备份请补一次（钥匙串访问 → 该身份 → 右键 → 导出 .p12）。"
  echo "      私钥丢失后重建会生成同名新证书 = 换了签名身份，所有用户的 TCC 授权与登录项会整体重置。"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "① 生成自签代码签名证书（CN=Gourd Local，有效期 10 年）…"
openssl req -x509 -newkey rsa:2048 -keyout "$work/key.pem" -out "$work/cert.pem" -days 3650 -nodes \
  -subj "/CN=Gourd Local/O=cmeng/C=CN" \
  -addext "keyUsage=digitalSignature" \
  -addext "extendedKeyUsage=codeSigning,1.2.840.113635.100.6.1.13" 2>/dev/null
openssl pkcs12 -export -out "$work/identity.p12" -inkey "$work/key.pem" -in "$work/cert.pem" \
  -passout pass:gourd-local-import

echo "② 导入登录钥匙串（允许 codesign 使用私钥）…"
security import "$work/identity.p12" -k ~/Library/Keychains/login.keychain-db \
  -P gourd-local-import -T /usr/bin/codesign

echo "③ 开启代码签名信任（用户域，无需管理员密码）…"
security add-trusted-cert -r trustRoot -p codeSign "$work/cert.pem"

echo
security find-identity -v -p codesigning | grep '"Gourd Local"'
echo "✅ 完成。运行 sh tools/build.sh --install 安装一次，逐个授权后，后续升级不再弹授权。"
echo
echo "⚠️  请立刻离线备份这张证书的私钥（做一次就够，但千万别漏）："
echo "    钥匙串访问 → 选「Gourd Local」这条身份（含私钥）→ 右键 → 导出 → 存成 .p12，"
echo "    密码存进密码管理器，.p12 放密码管理器附件或加密备份里（不要进仓库）。"
echo "    原因：出厂包靠这张证书的「证书 + Bundle ID」记忆用户授权。私钥丢了、或本脚本在身份"
echo "    缺失时重新生成一张同名新证书，签名身份就变了——所有用户的 TCC 授权与登录项会整体重置。"
