#!/usr/bin/env python3
"""对 ios-linuxkit (ish-arm64) C 引擎代码应用 ikshell 适配补丁。

引擎来源: rcarmo/ios-linuxkit (Asbestos 解释器, ARM64 guest)

历史说明（旧版补丁已废弃）:
- rootfs 路径补丁: 上游已无 fs/roots.c / DEFAULT_ROOTFS,
  rootfs 路径由 ikshell 的 kernel_boot 桥接层直接传入 mount_root()
- MAX_TASKS 补丁: 上游改为动态 task 分配, 常量已不存在
- timezone 补丁: sys_gettimeofday 已透传宿主时区, 无需强制 UTC+8

本版补丁:
1. uname 品牌信息 (kernel/uname.c)
2. 引擎前置检查: 确认 ARM64 guest 支持的目录/文件齐全
"""
import sys
from pathlib import Path

REPO = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
KERNEL = REPO / "kernel"

failures = []
applied = []


def patch_file(rel_path, old, new, name):
    path = KERNEL / rel_path
    try:
        content = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        failures.append(f"{name}: 文件不存在 {rel_path}")
        return
    if new in content:
        applied.append(f"{name}: 已应用（跳过）")
        return
    if old not in content:
        failures.append(f"{name}: 未找到目标串 文件={rel_path}")
        return
    # 只替换第一次出现，避免误改其他位置
    count = content.count(old)
    if count > 1:
        print(f"  [WARN] {name}: 目标串在 {rel_path} 中出现 {count} 次，只替换第一次")
    path.write_text(content.replace(old, new, 1), encoding="utf-8")
    applied.append(f"{name}: 已应用")


def check_exists(rel_path, name):
    if (KERNEL / rel_path).exists():
        applied.append(f"{name}: 存在")
    else:
        failures.append(f"{name}: 缺失 {rel_path}")


# ---------------------------------------------------------------------------
# 0. 引擎前置检查: 确认提取到的是 ARM64 guest 引擎
#    （防止 fetch-kernel.sh 误指向纯 x86 的 ish-app/ish master）
# ---------------------------------------------------------------------------
check_exists("asbestos/guest-arm64/gen.c", "arm64-guest-decoder")
check_exists("asbestos/guest-arm64/gadgets-aarch64/entry.S", "arm64-host-gadgets")
check_exists("vdso/arm64", "arm64-vdso")
check_exists("emu/arch/arm64/fpu.c", "arm64-emu-fpu")

# ---------------------------------------------------------------------------
# 1. uname 品牌信息: 上游默认 "Block Emulation" / "4.20.69-linuxkit"
# ---------------------------------------------------------------------------
patch_file(
    "kernel/uname.c",
    'const char *uname_version = "Block Emulation";',
    'const char *uname_version = "ikshell (Asbestos ARM64)";',
    "uname-brand",
)

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------
for line in applied:
    print(f"  [ok] {line}")
if failures:
    for line in failures:
        print(f"  [FAIL] {line}", file=sys.stderr)
    sys.exit(1)
print("apply-patches: 全部补丁应用成功")
