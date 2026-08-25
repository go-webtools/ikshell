#!/bin/bash
# 从 ios-linuxkit（iSH 的 ARM64 guest 分支）提取 C 模拟引擎代码到 ikshell/kernel/
# 只提取内核引擎，不包含 iOS 应用层代码
#
# 上游: https://github.com/rcarmo/ios-linuxkit (fork of ish-arm64)
# 引擎特性: Asbestos threaded-code 解释器, guest 架构 = aarch64, 无 JIT/RWX (App Store 兼容)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT_FILE="$REPO_ROOT/config/ish-commit.txt"
if [ ! -f "$COMMIT_FILE" ]; then
    echo "ERROR: $COMMIT_FILE 不存在" >&2
    exit 1
fi
ISH_COMMIT="$(cat "$COMMIT_FILE")"
if [ -z "$ISH_COMMIT" ]; then
    echo "ERROR: ISH_COMMIT 为空" >&2
    exit 1
fi
ISH_REPO="${ISH_REPO:-https://github.com/rcarmo/ios-linuxkit.git}"
KERNEL_DIR="$REPO_ROOT/kernel"

echo "=== ikshell: 提取 ARM64 Linux 模拟引擎 (ios-linuxkit) ==="
echo "  上游 commit: $ISH_COMMIT"

# 按 commit SHA 浅获取（git clone --branch 不支持 SHA，必须 init + fetch）
# 网络抖动时自动重试
fetch_retry() {
    local attempt
    for attempt in 1 2 3; do
        if "$@"; then return 0; fi
        echo "  第 ${attempt} 次失败，重试..."
        sleep 5
    done
    return 1
}

if [ -d "$KERNEL_DIR/.git" ] && [ -d "$KERNEL_DIR/emu" ]; then
    echo "  kernel/ 已存在且完整，跳过获取"
else
    echo "  获取 ios-linuxkit (commit $ISH_COMMIT)..."
    rm -rf "$KERNEL_DIR"
    mkdir -p "$KERNEL_DIR"
    # 注意: 用 cd 进目录操作，不用 git -C <绝对路径>（MSYS /c/ 路径转换在 -C 下不可靠）
    if ! (
        cd "$KERNEL_DIR"
        git init -q
        git remote add origin "$ISH_REPO"
        # GitHub 支持按任意 SHA fetch
        fetch_retry git fetch --depth 1 origin "$ISH_COMMIT" || exit 1
        git checkout -q FETCH_HEAD
        # 引擎依赖的子模块: deps/libapps, deps/libarchive
        # (deps/linux 被上游 .gitmodules 标记 update=none, 会自动跳过)
        echo "  拉取子模块..."
        fetch_retry git submodule update --init --depth 1 --recursive
    ); then
        echo "  获取失败，清理残留的 kernel/ ..." >&2
        rm -rf "$KERNEL_DIR"
        exit 1
    fi
fi

# 确认 commit
ACTUAL_COMMIT="$(git -C "$KERNEL_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$ACTUAL_COMMIT" != "$ISH_COMMIT" ]; then
    echo "  WARNING: 期望 $ISH_COMMIT，实际 $ACTUAL_COMMIT"
fi

# 只保留引擎代码，删除 iOS 应用层与无关文件
echo "  清理非引擎文件..."
cd "$REPO_ROOT"

# 删除上游的 iOS app 层、构建产物目录、CI、文档
rm -rf "$KERNEL_DIR/app"
rm -rf "$KERNEL_DIR/fastlane"
rm -rf "$KERNEL_DIR/tests"
rm -rf "$KERNEL_DIR/benchmark"
rm -rf "$KERNEL_DIR/docs"
rm -rf "$KERNEL_DIR/scripts"
rm -rf "$KERNEL_DIR/.pi"
rm -rf "$KERNEL_DIR/.github"
rm -rf "$KERNEL_DIR/iSH.xcodeproj"
rm -rf "$KERNEL_DIR/.git"

# 删除 CLI 驱动入口（ikshell 有自己的 kernel_boot 桥接层）
rm -f  "$KERNEL_DIR/main.c"
rm -f  "$KERNEL_DIR/xX_main_Xx.h"

# 删除文档 / 构建配置外文件
rm -f  "$KERNEL_DIR/Gemfile" "$KERNEL_DIR/Gemfile.lock"
rm -f  "$KERNEL_DIR/README.md" "$KERNEL_DIR/ISSUE_TEMPLATE.md"
rm -f  "$KERNEL_DIR/SECURITY.md"
rm -f  "$KERNEL_DIR/LICENSE.md" "$KERNEL_DIR/LICENSE.IOS"
rm -f  "$KERNEL_DIR/shell.nix" "$KERNEL_DIR/ish-gdb.gdb" "$KERNEL_DIR/ish-lldb.lldb"
rm -f  "$KERNEL_DIR/.editorconfig" "$KERNEL_DIR/.gitignore" "$KERNEL_DIR/.gitmodules"

# 注意: 以下文件是引擎编译必需，不能删——
#   debug.h / misc.h        : 全引擎使用的日志与工具头
#   meson.build / Makefile / tools/ : Linux 宿主构建 + cpu-offsets.h 生成 (tools/staticdefine.sh)
#   vdso/ (含 arm64)        : guest vdso
#   asbestos/ (含 guest-arm64) : ARM64 guest 指令解码 + aarch64 host gadgets
#   deps/                   : libarchive / linux 头文件子模块

echo "  引擎代码已提取到 kernel/"
echo "  保留: emu/ fs/ kernel/ platform/ linux/ util/ asbestos/ vdso/ deps/ tools/"
echo "  保留: debug.h misc.h meson.build meson_options.txt Makefile"
echo "=== 完成 ==="
