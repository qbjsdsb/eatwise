#!/bin/bash
# M16 应用内更新：生成本地固定签名 keystore
#
# 用法：bash scripts/generate_keystore.sh
#
# 生成的文件：
# - android/app/eatwise-release.jks（keystore 文件，不进 repo）
# - android/app/key.properties（keystore 密码配置，不进 repo）
#
# 这两个文件都已在 .gitignore 中，提交时不会被包含。
# 首次生成后，本地 flutter build apk --release 会自动用此 keystore 签名。
# CI build 需要把 eatwise-release.jks base64 encode 后上传到 GitHub Secrets
# （详见 docs/superpowers/plans/2026-07-05-in-app-update.md Task G2）

set -e

KEYSTORE_PATH="android/app/eatwise-release.jks"
PROPERTIES_PATH="android/app/key.properties"

if [ -f "$KEYSTORE_PATH" ]; then
    echo "⚠️  $KEYSTORE_PATH 已存在"
    read -p "覆盖生成？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "取消"
        exit 0
    fi
    rm -f "$KEYSTORE_PATH" "$PROPERTIES_PATH"
fi

# 固定密码（个人自用项目，密码复杂度非关键，关键是 keystore 文件本身不泄露）
STORE_PASSWORD="eatwise_release_$(date +%s)"
KEY_PASSWORD="$STORE_PASSWORD"
KEY_ALIAS="eatwise-release"

echo "生成 keystore: $KEYSTORE_PATH"
keytool -genkeypair \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 36500 \
    -keystore "$KEYSTORE_PATH" \
    -storepass "$STORE_PASSWORD" \
    -keypass "$KEY_PASSWORD" \
    -dname "CN=EatWise, OU=Personal, O=Personal, L=Beijing, ST=Beijing, C=CN"

cat > "$PROPERTIES_PATH" <<EOF
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=eatwise-release.jks
EOF

echo ""
echo "✅ 生成完成："
echo "  keystore: $KEYSTORE_PATH"
echo "  properties: $PROPERTIES_PATH"
echo ""
echo "📦 上传到 GitHub Secrets（CI build 用）："
echo "  base64 $KEYSTORE_PATH | tr -d '\\n' | pbcopy  # macOS 复制到剪贴板"
echo "  然后在 GitHub repo Settings → Secrets and variables → Actions 加："
echo "    - ANDROID_KEYSTORE_BASE64"
echo "    - ANDROID_KEYSTORE_PASSWORD=$STORE_PASSWORD"
echo "    - ANDROID_KEY_ALIAS=$KEY_ALIAS"
echo "    - ANDROID_KEY_PASSWORD=$KEY_PASSWORD"
