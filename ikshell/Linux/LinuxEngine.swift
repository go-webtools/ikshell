import SwiftUI
import Foundation

/// Coordinates rootfs preparation, the ARM64 guest and the terminal pipe.
final class LinuxEngine: ObservableObject {
    @Published var isRunning = false
    @Published var rootfsStatus = "未下载"
    @Published var errorMessage: String?

    private let rootfsManager = RootfsManager()
    private var outputBuffer = Data()
    private let outputLock = NSLock()

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

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

    func writeStdin(_ text: String) {
        guard let data = text.data(using: .utf8), !data.isEmpty else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            _ = kernel_send_input(baseAddress, rawBuffer.count)
        }
    }

    func drainOutput() -> Data {
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        let count = bytes.withUnsafeMutableBytes { rawBuffer -> Int32 in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return kernel_read_output(baseAddress, rawBuffer.count)
        }
        guard count > 0 else { return Data() }

        outputLock.lock()
        outputBuffer.append(contentsOf: bytes.prefix(Int(count)))
        let data = outputBuffer
        outputBuffer.removeAll(keepingCapacity: true)
        outputLock.unlock()
        return data
    }

    func setTerminalSize(cols: Int, rows: Int) {
        _ = kernel_set_winsize(Int32(cols), Int32(rows))
    }

    func shutdown() {
        kernel_shutdown()
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    private func bootAndRun(rootfs: String) {
        let bootResult = rootfs.withCString { cRootfs in
            kernel_boot(cRootfs)
        }
        guard bootResult == 0 else {
            DispatchQueue.main.async {
                self.errorMessage = "引擎启动失败 (code: \(bootResult))"
            }
            return
        }

        let shellResult = kernel_start_shell()
        guard shellResult == 0 else {
            kernel_shutdown()
            DispatchQueue.main.async {
                self.errorMessage = "Shell 启动失败 (code: \(shellResult))"
            }
            return
        }

        DispatchQueue.main.async {
            self.isRunning = true
        }

        // The emulator owns this background thread until the guest exits.
        kernel_run()
    }
}
