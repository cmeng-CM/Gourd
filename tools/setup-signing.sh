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
  echo "提醒：这份签名身份的私钥备份好了吗？"
  echo "      备份文件默认落在 ~/Library/Application Support/Gourd/signing/ 下（若你是早点生成的，"
  echo "      那里可能没有——因为当时脚本还不落盘）。"
  echo "      早期身份想补救：从钥匙串导出需要一次人工授权，跑下面这条，并在弹出的授权框里输密码允许："
  echo "        security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 \\"
  echo "          -P <自己设的导出密码> -o ~/Desktop/Gourd-Local.p12"
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

# 备份落盘：钥匙串里的私钥受 ACL 保护（上面的 -T 只授给了 codesign），
# 事后想从钥匙串导出需要一次人工授权，不可靠。所以生成时就把 p12 留一份出来。
backup_dir="$HOME/Library/Application Support/Gourd/signing"
mkdir -p "$backup_dir"
backup="$backup_dir/Gourd-Local-$(date +%Y%m%d).p12"
cp "$work/identity.p12" "$backup"
chmod 600 "$backup"

echo "③ 开启代码签名信任（用户域，无需管理员密码）…"
security add-trusted-cert -r trustRoot -p codeSign "$work/cert.pem"

echo
security find-identity -v -p codesigning | grep '"Gourd Local"'
echo "✅ 完成。运行 sh tools/build.sh --install 安装一次，逐个授权后，后续升级不再弹授权。"
echo
echo "⚠️  私钥备份已落在："
echo "    $backup"
echo "    它的密码是脚本用的那个：gourd-local-import（只是防随手读走，不是强保护）。"
echo "    请把它移到密码管理器附件或加密备份里，**不要留在同步盘、更不要进仓库**。"
echo "    原因：出厂包靠这张证书的「证书 + Bundle ID」记忆用户授权。私钥丢了、或本脚本在身份"
echo "    缺失时重新生成一张同名新证书，签名身份就变了——所有用户的 TCC 授权与登录项会整体重置。"
echo "    钥匙串里那份私钥受 ACL 保护（只授给了 codesign），事后想再从钥匙串导出需要一次人工"
echo "    授权、不一定成——所以上面这份文件才是你真正能带走的备份。"
