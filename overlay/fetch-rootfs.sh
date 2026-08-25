#!/bin/bash
# ikshell rootfs 构建脚本（由 Xcode 构建阶段调用）
# 下载上游 Alpine rootfs -> 注入 ikshell overlay(ikpkg/横幅等) -> 重新打包
# 任何 overlay 环节失败都回退到上游原版 rootfs，绝不阻塞构建。
#
# 用法: fetch-rootfs.sh <输出路径 root.tar.gz>
set -uo pipefail

OUT="${1:?usage: fetch-rootfs.sh <output.tar.gz>}"
OVERLAY_DIR="$(cd "$(dirname "$0")" && pwd)/rootfs"

# 与上游 app/iSH.xcconfig 中默认 ROOTFS_URL 指向同一文件（含 apk 的 App Store 版 rootfs）
UPSTREAM_URL="https://github.com/ish-app/roots/releases/download/g00712ff0a54b2839c5aa1a8ed758003ca65357dc/appstore-apk.tar.gz"

work="$(mktemp -d "${TMPDIR:-/tmp}/ikshell-rootfs.XXXXXX")"
trap 'rm -rf "$work"' EXIT

echo "ikshell rootfs: 下载上游 rootfs ..."
if ! curl -fSL --retry 3 --retry-delay 5 -o "$work/orig.tar.gz" "$UPSTREAM_URL"; then
    echo "ikshell rootfs: ERROR 上游 rootfs 下载失败" >&2
    exit 1
fi

echo "ikshell rootfs: 注入 ikshell overlay ..."
mkdir -p "$work/root"
if [ -d "$OVERLAY_DIR" ] \
    && tar -xzf "$work/orig.tar.gz" -C "$work/root" 2>"$work/extract.err" \
    && cp -R "$OVERLAY_DIR/." "$work/root/"; then
    # 属主归一为 root(0:0) 后重打包；GNU tar 与 bsdtar 参数不同，逐级回退
    if tar -czf "$work/new.tar.gz" --uid 0 --gid 0 -C "$work/root" . 2>/dev/null \
        || tar -czf "$work/new.tar.gz" --owner=0 --group=0 -C "$work/root" . 2>/dev/null \
        || tar -czf "$work/new.tar.gz" -C "$work/root" . 2>/dev/null; then
        if [ -s "$work/new.tar.gz" ]; then
            mv "$work/new.tar.gz" "$OUT"
            echo "ikshell rootfs: 已生成含 overlay 的定制 rootfs -> $OUT"
            exit 0
        fi
    fi
fi

echo "ikshell rootfs: WARNING overlay 注入失败，回退到上游原版 rootfs" >&2
cp "$work/orig.tar.gz" "$OUT"
