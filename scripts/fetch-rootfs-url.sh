#!/bin/bash
# 获取最新 Alpine Linux aarch64 rootfs URL
# 用于 CI 构建时动态确定下载地址
#
# 架构说明: 引擎 (ios-linuxkit/Asbestos) 的 guest 是 aarch64,
# 必须使用 aarch64 minirootfs. ios-linuxkit v2.1.1 验证过的组合是
# Alpine 3.24 aarch64 minirootfs.
set -euo pipefail

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
ALPINE_VERSION="${ALPINE_VERSION:-v3.24}"
ARCH="aarch64"

# 获取最新 minirootfs 版本号
LATEST=$(curl -fsSL "${ALPINE_MIRROR}/${ALPINE_VERSION}/releases/${ARCH}/latest-releases.yaml" \
    | grep "minirootfs" | grep "tar.gz" | head -1 | awk '{print $NF}' | tr -d '"')

if [ -z "$LATEST" ]; then
    # Fallback：硬编码版本（与 ios-linuxkit app/GuestARM64.xcconfig 锁定的一致）
    LATEST="alpine-minirootfs-3.24.0-${ARCH}.tar.gz"
fi

URL="${ALPINE_MIRROR}/${ALPINE_VERSION}/releases/${ARCH}/${LATEST}"
echo "$URL"
