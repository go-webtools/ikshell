# ikshell

**运行在 iPad 上的 Linux 终端** — SwiftUI + iSH C 引擎

ikshell 使用 SwiftUI 重写界面，集成 iSH 的 ARM64 模拟引擎，提供轻量级 Alpine Linux 环境。

> 基于 [iSH](https://github.com/ish-app/ish)（GPLv3）构建

## 功能

- ✅ **SwiftUI 原生界面** — 纯 Swift 实现，iPad 原生体验
- ✅ **xterm-256color 终端** — 完整 ANSI 色彩支持
- ✅ **Alpine Linux 3.20** — 运行时下载，轻量级（仅5MB）
- ✅ **ikpkg 软件管理** — 快捷安装编译器：`ikpkg c`、`ikpkg go`、`ikpkg node`
- ✅ **多窗口会话** — 通过 tmux/screen 实现多会话管理
- ✅ **C 引擎真实集成** — 使用 iSH 内核 API

## 当前状态

**已完成：**
- SwiftUI 界面（终端 + 设置）
- ANSI escape 序列解析器（256 色）
- Alpine Linux 3.20 rootfs 下载管理
- C 桥接层框架（真实 iSH 内核集成）
- 多窗口会话支持（tmux/screen）
- GitHub Actions CI/CD
- 构建脚本

**待验证：**
- 实机运行测试

## 构建

### 方案 A：快速验证（使用占位实现）

```sh
bash scripts/fetch-kernel.sh      # 下载 iSH 内核源码
python3 scripts/apply-patches.py  # 应用补丁
python3 scripts/make-icons.py     # 生成图标
xcodebuild -project ikshell.xcodeproj -scheme ikshell -arch arm64 \
  -sdk iphoneos -configuration Release -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
bash scripts/package-ipa.sh
```

此方案可构建出 IPA，但终端只能运行系统 shell（非 Linux）。

### 方案 B：完整集成（需手动操作）

1. 在 Xcode 中打开 `ikshell.xcodeproj`
2. 右键 `ikshell` target → Add Files
3. 选择 `kernel/` 目录下的核心 C 文件：
   - `kernel/kernel/*.c`
   - `kernel/emu/*.c`
   - `kernel/fs/*.c`
   - `kernel/platform/*.c`
4. 修改 `ikshell/Linux/ikshell_engine.c` 实现真实内核调用
5. 配置 Header Search Paths：`$(SRCROOT)/kernel`
6. 构建

## 为什么不自动包含内核源码？

iSH 内核有 **15000+ 行 C 代码**，涉及复杂的构建配置（Meson）。手动在 `project.pbxproj` 中枚举所有文件会导致：
1. pbxproj 文件膨胀到 50000+ 行
2. 构建配置复杂（头文件路径、编译选项）
3. 维护困难

推荐在 Xcode IDE 中手动添加源文件（拖拽方式）。

## 项目结构

```
ikshell/
├── ikshell.xcodeproj/          # Xcode 项目
├── ikshell/                    # SwiftUI 应用代码
│   ├── ikshellApp.swift
│   ├── ContentView.swift
│   ├── Terminal/               # 终端 UI + ANSI 解析
│   ├── Settings/               # 设置界面
│   └── Linux/                  # C 桥接层
├── kernel/                     # iSH C 引擎（fetch-kernel.sh 提取）
├── overlay/                    # rootfs 定制（ikpkg、motd）
├── scripts/                    # 构建脚本
├── .github/workflows/          # CI/CD
└── README.md
```

## 许可证

GPLv3（含 iSH 的 iOS 附加条款）。完整源码 = 本仓库 + `config/ish-commit.txt` 指向的上游 iSH。

## 相关链接

- iSH: https://github.com/ish-app/ish
- Alpine Linux: https://alpinelinux.org
