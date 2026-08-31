#!/bin/bash
# 用 meson + ninja 编译 ios-linuxkit C 引擎为静态库
#
# 产出: build/engine/libish.a, libish_emu.a, libfakefs.a
#       build/engine/cpu-offsets.h
#
# 在 macOS 上运行 (CI runner 或本地)。需要 meson, ninja, clang (Xcode toolchain)。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_DIR="$REPO_ROOT/kernel"
BUILD_DIR="$REPO_ROOT/build/engine"

# 确认引擎源码已提取
if [ ! -d "$KERNEL_DIR/emu" ]; then
    echo "ERROR: kernel/ 目录不存在或不完整。先运行 scripts/fetch-kernel.sh" >&2
    exit 1
fi

# 确认 meson 和 ninja 可用
if ! command -v meson >/dev/null 2>&1; then
    echo "ERROR: meson 未安装。请运行: brew install meson" >&2
    exit 1
fi
if ! command -v ninja >/dev/null 2>&1; then
    echo "ERROR: ninja 未安装。请运行: brew install ninja" >&2
    exit 1
fi

# 用 Xcode 的 clang 作为编译器
export CC="${CC:-$(xcrun --find clang)}"
export CC_FOR_BUILD="$CC"

echo "=== ikshell: 编译 ARM64 引擎 (meson) ==="
echo "  CC: $CC"
echo "  kernel: $KERNEL_DIR"
echo "  output: $BUILD_DIR"

# 创建 meson 交叉编译配置 (iOS arm64)
CROSSFILE="$BUILD_DIR/cross.txt"
mkdir -p "$BUILD_DIR"

cat > "$CROSSFILE" <<EOF
[binaries]
c = '$CC'
ar = '$(xcrun --find ar)'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = ['-arch', 'arm64', '-isysroot', '$(xcrun --sdk iphoneos --show-sdk-path)', '-mios-version-min=15.0']
EOF

# meson setup (如果已配置则跳过)
if [ ! -f "$BUILD_DIR/build.ninja" ]; then
    echo "  meson setup..."
    (cd "$BUILD_DIR" && meson "$KERNEL_DIR" --crossfile "$CROSSFILE" \
        -Dguest_arch=arm64 \
        -Ddefault_library=static \
        --buildtype=release)
fi

# ninja 编译
echo "  ninja 编译..."
if ! ninja -C "$BUILD_DIR"; then
    echo "ERROR: ninja 编译失败" >&2
    exit 1
fi

# 确认产出
echo "  检查产出..."
for lib in libish.a libish_emu.a libfakefs.a; do
    if [ -f "$BUILD_DIR/$lib" ]; then
        echo "  [ok] $lib ($(du -h "$BUILD_DIR/$lib" | cut -f1))"
    else
        # meson 可能放在子目录
        FOUND=$(find "$BUILD_DIR" -name "$lib" -type f | head -1)
        if [ -n "$FOUND" ]; then
            cp "$FOUND" "$BUILD_DIR/$lib"
            echo "  [ok] $lib (从 $(dirname "$FOUND") 复制)"
        else
            echo "  [MISSING] $lib" >&2
            exit 1
        fi
    fi
done

# cpu-offsets.h
if [ -f "$BUILD_DIR/cpu-offsets.h" ]; then
    echo "  [ok] cpu-offsets.h"
else
    echo "  [WARN] cpu-offsets.h 未找到 (可能在子目录)" >&2
    find "$BUILD_DIR" -name "cpu-offsets.h" -exec cp {} "$BUILD_DIR/cpu-offsets.h" \; 2>/dev/null
fi

# vdso (可选——如果没有 aarch64 交叉链接器, 会是空占位)
VDSO=$(find "$BUILD_DIR" -name "libvdso.so.elf" | head -1)
if [ -n "$VDSO" ]; then
    cp "$VDSO" "$BUILD_DIR/libvdso.so.elf" 2>/dev/null || true
    echo "  [ok] libvdso.so.elf"
else
    echo "  [INFO] vdso 未构建 (可选, 不影响核心功能)"
fi

echo "=== 引擎编译完成 ==="
echo "  静态库: $BUILD_DIR/"
echo "  下一步: bash scripts/gen-xcode-project.sh && xcodebuild ..."
