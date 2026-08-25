#!/bin/bash
# 将构建产物 .app 打包为未签名 IPA
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCTS_DIR="$REPO_ROOT/build/Build/Products/Release-iphoneos"
APP_PATH="$(find "$PRODUCTS_DIR" -maxdepth 1 -name '*.app' | head -1)"

if [ -z "$APP_PATH" ]; then
    echo "ERROR: 在 $PRODUCTS_DIR 下未找到 .app，请先构建" >&2
    exit 1
fi

DIST="$REPO_ROOT/dist"
rm -rf "$DIST"
mkdir -p "$DIST/Payload"

cp -R "$APP_PATH" "$DIST/Payload/ikshell.app"

# ad-hoc 签名（SideStore/AltStore 会重新签名）
codesign --force --deep --sign - "$DIST/Payload/ikshell.app" 2>/dev/null \
    && echo "package-ipa: ad-hoc 签名完成" \
    || echo "package-ipa: 跳过 ad-hoc 签名"

(cd "$DIST" && zip -qry ikshell.ipa Payload)

if command -v shasum >/dev/null 2>&1; then
    (cd "$DIST" && shasum -a 256 ikshell.ipa > ikshell.ipa.sha256)
fi

rm -rf "$DIST/Payload"
echo "package-ipa: $DIST/ikshell.ipa ($(du -h "$DIST/ikshell.ipa" | cut -f1))"
