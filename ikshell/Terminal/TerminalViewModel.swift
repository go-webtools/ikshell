import SwiftUI
import Combine

/// 终端 ViewModel: 管理 LinuxEngine 的输出渲染与输入转发
///
/// I/O 模型:
///   - 输出: 定时轮询 engine.drainOutput() → ANSI 解析 → 行缓冲渲染
///   - 输入: UI 按键 → engine.writeStdin() → guest (回显由 guest 的 tty 层处理)
class TerminalViewModel: ObservableObject {
    @Published var lines: [TerminalLine] = []
    @Published var currentPrompt: String = "~ #"

    private var engine: LinuxEngine?
    private var readTimer: Timer?
    private let parser = ANSIParser()
    private var currentLine = ""

    func attachEngine(_ engine: LinuxEngine) {
        self.engine = engine
        startReading()
    }

    /// 发送用户输入到 guest。不做本地回显——guest 的 tty 层在 canonical 模式下会自行回显。
    func sendInput(_ text: String) {
        engine?.writeStdin(text)
    }

    /// 发送单个按键 (用于外接键盘的 key event)
    func sendKey(_ text: String) {
        engine?.writeStdin(text)
    }

    private func startReading() {
        // 每 20ms 轮询输出缓冲区
        readTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let data = self.engine?.drainOutput()
            guard let data = data, !data.isEmpty else { return }
            DispatchQueue.main.async {
                self.processOutput(data)
            }
        }
    }

    private func processOutput(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        for char in text {
            if char == "\n" {
                // 检测是否为提示符行（以 # 或 $ 结尾）
                let trimmed = currentLine.trimmingCharacters(in: .whitespaces)
                if trimmed.hasSuffix("#") || trimmed.hasSuffix("$") {
                    currentPrompt = trimmed
                }

                lines.append(TerminalLine(
                    segments: parser.parse(currentLine),
                    raw: currentLine
                ))
                currentLine = ""
            } else if char == "\r" {
                currentLine = ""
            } else if char == "\t" {
                currentLine += "    "
            } else if char.isASCII && char.asciiValue != nil {
                currentLine.append(char)
            }
        }

        // 限制缓冲行数防止内存膨胀
        if lines.count > 5000 {
            lines.removeFirst(1000)
        }
    }

    deinit {
        readTimer?.invalidate()
    }
}
