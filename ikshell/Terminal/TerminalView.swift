import SwiftUI

/// Terminal view with PTY-based text rendering
struct TerminalView: View {
    @EnvironmentObject var engine: LinuxEngine
    @AppStorage("fontSize") private var fontSize: Double = 14
    @StateObject private var vm = TerminalViewModel()
    @State private var inputBuffer = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            if isLandscape {
                // 横屏：左终端右键盘
                HStack(spacing: 0) {
                    terminalContent
                        .frame(width: geo.size.width * 0.65)

                    Divider()

                    keyboardArea
                        .frame(width: geo.size.width * 0.35)
                }
            } else {
                // 竖屏：上终端下键盘
                VStack(spacing: 0) {
                    terminalContent

                    Divider()

                    keyboardArea
                }
            }
        }
        .background(Color.black)
        .onAppear {
            vm.attachEngine(engine)
            isInputFocused = true
        }
    }

    // MARK: - Terminal Content

    private var terminalContent: some View {
        ZStack(alignment: .bottomLeading) {
            // 历史输出
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        TerminalTextView(
                            lines: vm.lines,
                            fontSize: fontSize
                        )

                        // 当前输入行（内嵌在终端中）
                        HStack(spacing: 4) {
                            Text(vm.currentPrompt)
                                .foregroundColor(.green)
                                .font(.custom("Menlo", size: fontSize))

                            TextField("", text: $inputBuffer)
                                .font(.custom("Menlo", size: fontSize))
                                .foregroundColor(.white)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($isInputFocused)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onSubmit {
                                    vm.sendInput(inputBuffer + "\n")
                                    inputBuffer = ""
                                }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .id("inputLine")
                    }
                    .id("terminalContent")
                }
                .onChange(of: vm.lines.count) { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("inputLine", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Keyboard Area

    private var keyboardArea: some View {
        VStack(spacing: 0) {
            // 快捷键栏
            KeyboardAccessoryView { key in
                vm.sendKey(key)
            }
            .frame(height: 48)
        }
        .background(Color(white: 0.1))
    }
}

/// Renders terminal text lines with ANSI color support
struct TerminalTextView: View {
    let lines: [TerminalLine]
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.attributedString)
                    .font(.custom("Menlo", size: fontSize))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
    }
}

// MARK: - Terminal Line Model

struct TerminalLine: Identifiable {
    let id = UUID()
    let segments: [TextSegment]
    let raw: String

    var attributedString: AttributedString {
        var result = AttributedString()
        for segment in segments {
            var attr = AttributedString(segment.text)
            if let fg = segment.foregroundColor {
                attr.foregroundColor = fg
            }
            if segment.bold {
                attr.font = .custom("Menlo-Bold", size: 14)
            }
            if segment.underline {
                attr.underlineStyle = .single
            }
            result += attr
        }
        return result
    }
}

struct TextSegment {
    let text: String
    var foregroundColor: Color? = nil
    var bold: Bool = false
    var underline: Bool = false
}
