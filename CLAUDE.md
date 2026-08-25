# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Project Overview

**ikshell** — iPad Linux terminal with SwiftUI + iSH C engine + Alpine Linux

- **SwiftUI UI**: Pure Swift interface (Terminal, Settings)
- **iSH C engine**: ARM64 usermode emulation + Linux syscall translation (from upstream)
- **Latest Alpine**: Downloaded at runtime from `dl-cdn.alpinelinux.org`
- **Unsigned IPA**: Built via GitHub Actions, sideload with SideStore/AltStore

## Build Commands

### Local macOS build (requires Xcode)

```sh
# 1. Extract iSH C engine
bash scripts/fetch-kernel.sh

# 2. Apply ikshell patches
python3 scripts/apply-patches.py

# 3. Generate app icons
python3 scripts/make-icons.py ikshell/Resources/Assets.xcassets/AppIcon.appiconset

# 4. Build (unsigned, arm64)
xcodebuild -project ikshell.xcodeproj -scheme ikshell -arch arm64 \
  -sdk iphoneos -configuration Release -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build

# 5. Package IPA
bash scripts/package-ipa.sh
# Output: dist/ikshell.ipa
```

### CI (GitHub Actions)

Workflow: `.github/workflows/build.yml`
- Triggers: push, PR, tag `v*`
- Runner: `macos-14`
- On tag push: creates GitHub Release with IPA

## Architecture

```
┌─────────────────────────────────────────┐
│  SwiftUI (Swift)                        │
│  TerminalView / SettingsView            │
├─────────────────────────────────────────┤
│  LinuxEngine (Swift bridge)             │
│  RootfsManager                          │
├─────────────────────────────────────────┤
│  ikshell_engine.c (C bridge)            │
│  kernel_boot / kernel_openpty           │
├─────────────────────────────────────────┤
│  iSH C engine (kernel/)                 │
│  x86 emulator + syscall translator      │
├─────────────────────────────────────────┤
│  Alpine Linux rootfs                    │
│  (runtime download, not bundled)        │
└─────────────────────────────────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `ikshell/ikshellApp.swift` | SwiftUI app entry point |
| `ikshell/Terminal/TerminalView.swift` | Terminal UI with PTY rendering |
| `ikshell/Terminal/ANSI_parser.swift` | xterm-256color escape sequence parser |
| `ikshell/Linux/LinuxEngine.swift` | Swift bridge to C engine |
| `ikshell/Linux/ikshell_engine.c` | C bridge implementation (PTY, kernel lifecycle) |
| `ikshell/Linux/ikshell-Bridging-Header.h` | Swift-C bridge header |
| `ikshell/Linux/RootfsManager.swift` | Alpine rootfs download/extract |
| `scripts/fetch-kernel.sh` | Extracts iSH C engine from upstream |
| `scripts/apply-patches.py` | Applies ikshell-specific patches to C engine |
| `overlay/rootfs/usr/local/bin/ikpkg` | Package manager shortcuts (c/go/node/python) |

## C Engine Integration

The iSH C engine is **not vendored** — it's fetched at build time:

1. `scripts/fetch-kernel.sh` clones iSH at pinned commit (`config/ish-commit.txt`)
2. Only keeps `kernel/`, `emu/`, `fs/`, `platform/`, `deps/` (removes iOS app layer)
3. `scripts/apply-patches.py` applies 3 patches:
   - Default rootfs path → iOS Documents directory
   - Memory limits (MAX_TASKS 512→1024 for iPad Air 5)
   - Timezone UTC+8 default

The C engine is compiled directly into the app via Xcode's "Compile Sources" phase. Swift calls C functions via the bridging header.

## Bridging Layer

**Swift → C bridge:**
```swift
// LinuxEngine.swift
let ret = kernel_boot(cRootfs, &args)
let fd = kernel_openpty()
kernel_pty_write(fd, ptr, count)
```

**C bridge implementation:**
```c
// ikshell_engine.c
int kernel_boot(const char *rootfs_path, char *const argv[]);
int kernel_openpty(void);
int kernel_pty_read(int fd, void *buf, size_t count);
int kernel_pty_write(int fd, const void *buf, size_t count);
```

**Current state:** The C bridge (`ikshell_engine.c`) contains placeholder implementations using system `openpty()` and `fork()` to run a local shell. Full integration requires linking to iSH kernel functions (not yet implemented).

## Rootfs Overlay

`overlay/rootfs/` contains customizations merged into Alpine at build time:

- `usr/local/bin/ikpkg` — shortcuts: `ikpkg c` (build-base), `ikpkg go`, `ikpkg node`, `ikpkg all`
- `etc/motd` — ASCII art welcome banner
- `etc/profile.d/ikshell.sh` — color aliases (ls, grep)

`RootfsManager.swift` downloads Alpine minirootfs at first launch, extracts, injects overlay, stores in Documents/.

## Development Notes

- **No iSH kernel integration yet**: `ikshell_engine.c` is a placeholder. Real integration requires:
  1. Adding iSH kernel sources to Xcode "Compile Sources"
  2. Implementing actual `kernel_boot()` → `do_init()` call
  3. Implementing `kernel_openpty()` → iSH's PTY system
  
- **Simulator won't work**: x86 emulation requires arm64 device. Test on real iPad or use remote device.

- **Unsigned builds only**: `CODE_SIGNING_ALLOWED=NO`. Users must sideload with free Apple ID.

## Verification

After build:
1. Check `dist/ikshell.ipa` exists
2. Sideload to iPad Air 5
3. Launch → should show "下载中..." while fetching Alpine rootfs
4. Terminal tab should appear (currently shows system shell, not Linux)

## Upgrading iSH

1. Update `config/ish-commit.txt` to new commit hash
2. Run `scripts/fetch-kernel.sh`
3. If patches fail, update target strings in `scripts/apply-patches.py`
4. Test build

## License

GPLv3 (same as iSH). See LICENSE.md.
