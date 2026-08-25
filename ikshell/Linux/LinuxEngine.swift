import SwiftUI
import Foundation

/// Bridge to the Linux emulation engine (ios-linuxkit / Asbestos,
/// ARM64 guest instruction interpreter + Linux syscall translation)
///
/// 引擎 I/O 模型:
///   - 输出: 引擎通过 C 回调 → handleOutput() → SwiftUI 渲染
///   - 输入: Swift UI → writeStdin() → kernel_send_input() → guest
///   - 仿真循环: kernel_run() 在后台线程阻塞, 直到 guest 退出
class LinuxEngine: ObservableObject {
    @Published var isRunning = false
    @Published var rootfsStatus = "未下载"
    @Published var errorMessage: String?

    private let rootfsManager = RootfsManager()
    private var outputBuffer = Data()
    private let outputLock = NSLock()

    // MARK: - 公开方法

    /// 启动引擎: 确保 rootfs → boot → run
    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. 注册回调 (必须在 boot 之前)
            self.registerCallbacks()

            // 2. 确保 rootfs 已就绪
            let rootfsPath = self.rootfsManager.rootfsPath
            if !self.rootfsManager.isRootfsReady {
                DispatchQueue.main.async {
                    self.rootfsStatus = "下载中..."
                }
                self.rootfsManager.prepareRootfs { result in
                    switch result {
                    case .success(let path):
                        DispatchQueue.main.async {
                            self.rootfsStatus = "已就绪"
                        }
                        self.bootAndRun(rootfs: path)
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self.errorMessage = "Rootfs 准备失败: \(error.localizedDescription)"
                            self.rootfsStatus = "下载失败"
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.rootfsStatus = "已就绪"
                }
                self.bootAndRun(rootfs: rootfsPath)
            }
        }
    }

    /// 向终端发送输入 (Swift → guest)
    func writeStdin(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        data.withUnsafeBytes { ptr in
            _ = kernel_send_input(ptr.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(data.count))
        }
    }

    /// 读取并清空输出缓冲区 (guest → Swift 渲染)
    func drainOutput() -> Data {
        outputLock.lock()
        let data = outputBuffer
        outputBuffer.removeAll(keepingCapacity: true)
        outputLock.unlock()
        return data
    }

    /// 设置终端窗口大小
    func setTerminalSize(cols: Int, rows: Int) {
        _ = kernel_set_winsize(Int32(cols), Int32(rows))
    }

    /// 关闭引擎
    func shutdown() {
        kernel_shutdown()
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    // MARK: - 内部

    private func registerCallbacks() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()

        let outputCallback: kernel_output_cb = { ctx, data, len in
            guard let ctx = ctx, let data = data else { return }
            let engine = Unmanaged<LinuxEngine>.fromOpaque(ctx).takeUnretainedValue()
            let bytes = UnsafeBufferPointer(start: data, count: Int(len))
            engine.handleOutput(Data(buffer: bytes))
        }

        let exitCallback: kernel_exit_cb = { ctx, code in
            guard let ctx = ctx else { return }
            let engine = Unmanaged<LinuxEngine>.fromOpaque(ctx).takeUnretainedValue()
            engine.handleExit(code: code)
        }

        kernel_set_callbacks(ctx, outputCallback, exitCallback)
    }

    private func bootAndRun(rootfs: String) {
        let initCmd = "/bin/sh -l"

        let ret = rootfs.withCString { cRootfs in
            initCmd.withCString { cCmd in
                kernel_boot(cRootfs, cCmd)
            }
        }

        if ret != 0 {
            DispatchQueue.main.async {
                self.errorMessage = "引擎启动失败 (code: \(ret))"
            }
            return
        }

        DispatchQueue.main.async {
            self.isRunning = true
        }

        // 阻塞进入仿真循环——在当前后台线程运行
        kernel_run()

        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    private func handleOutput(_ data: Data) {
        outputLock.lock()
        outputBuffer.append(data)
        outputLock.unlock()
    }

    private func handleExit(code: Int) {
        DispatchQueue.main.async {
            self.isRunning = false
            if code != 0 {
                self.errorMessage = "Linux 进程退出 (code: \(code))"
            }
        }
    }
}
