#!/bin/bash
# 用 XcodeGen 从 project.yml 生成 ikshell.xcodeproj
#
# 需要安装 xcodegen: brew install xcodegen
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "ERROR: xcodegen 未安装。请运行: brew install xcodegen" >&2
    exit 1
fi

# 确认引擎已编译 (静态库存在)
ENGINE_DIR="$REPO_ROOT/build/engine"
if [ ! -f "$ENGINE_DIR/libish.a" ]; then
    echo "ERROR: 引擎未编译。先运行 scripts/build-engine.sh" >&2
    exit 1
fi

echo "=== ikshell: 生成 Xcode 工程 ==="
xcodegen generate 2>&1

if [ -f "ikshell.xcodeproj/project.pbxproj" ]; then
    echo "  [ok] ikshell.xcodeproj 已生成"
else
    echo "  [FAIL] 生成失败" >&2
    exit 1
fi

echo "=== 下一步 ==="
echo "  xcodebuild -project ikshell.xcodeproj -scheme ikshell \\"
echo "    -arch arm64 -sdk iphoneos -configuration Release \\"
echo "    -derivedDataPath build CODE_SIGNING_ALLOWED=NO build"
