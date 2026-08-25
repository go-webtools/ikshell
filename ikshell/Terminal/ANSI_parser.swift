import SwiftUI

/// xterm-256color ANSI escape sequence parser
class ANSIParser {
    // Standard 16 colors
    static let standardColors: [Color] = [
        .black, .red, .green, .yellow,
        .blue, .magenta, .cyan, .white,
        Color(white: 0.5), Color(red: 1, green: 0.4, blue: 0.4),
        Color(red: 0.4, green: 1, blue: 0.4), Color(red: 1, green: 1, blue: 0.4),
        Color(red: 0.4, green: 0.4, blue: 1), Color(red: 1, green: 0.4, blue: 1),
        Color(red: 0.4, green: 1, blue: 1), .white
    ]

    func parse(_ text: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var current = ""
        var i = text.startIndex
        var currentFg: Color? = nil
        var currentBold = false
        var currentUnderline = false

        while i < text.endIndex {
            if text[i] == "\u{1B}" {
                // Flush current text
                if !current.isEmpty {
                    segments.append(TextSegment(text: current, foregroundColor: currentFg, bold: currentBold, underline: currentUnderline))
                    current = ""
                }

                // Parse escape sequence
                let (params, consumed) = parseEscapeSequence(text, from: text.index(after: i))
                i = consumed

                // Apply SGR parameters
                applyParams(params, fg: &currentFg, bold: &currentBold, underline: &currentUnderline)
            } else {
                current.append(text[i])
                i = text.index(after: i)
            }
        }

        if !current.isEmpty {
            segments.append(TextSegment(text: current, foregroundColor: currentFg, bold: currentBold, underline: currentUnderline))
        }

        return segments.isEmpty ? [TextSegment(text: text)] : segments
    }

    private func parseEscapeSequence(_ text: String, from start: String.Index) -> ([Int], String.Index) {
        var i = start
        guard i < text.endIndex, text[i] == "[" else {
            return ([], i)
        }
        i = text.index(after: i)

        var params: [Int] = []
        var currentNum = 0
        var hasNum = false

        while i < text.endIndex {
            let ch = text[i]
            if ch.isNumber {
                currentNum = currentNum * 10 + (ch.wholeNumberValue ?? 0)
                hasNum = true
                i = text.index(after: i)
            } else if ch == ";" {
                params.append(hasNum ? currentNum : 0)
                currentNum = 0
                hasNum = false
                i = text.index(after: i)
            } else if (ch.asciiValue ?? 0) >= 0x40 && (ch.asciiValue ?? 0) <= 0x7E {
                // Final character
                if hasNum {
                    params.append(currentNum)
                }
                i = text.index(after: i)
                return (params, i)
            } else {
                break
            }
        }

        return (params, i)
    }

    private func applyParams(_ params: [Int], fg: inout Color?, bold: inout Bool, underline: inout Bool) {
        guard !params.isEmpty else { return }

        var i = 0
        while i < params.count {
            let p = params[i]
            switch p {
            case 0:
                fg = nil
                bold = false
                underline = false
            case 1:
                bold = true
            case 4:
                underline = true
            case 22:
                bold = false
            case 24:
                underline = false
            case 30...37:
                fg = ANSIParser.standardColors[p - 30]
            case 38:
                // Extended foreground color
                if i + 1 < params.count {
                    if params[i + 1] == 5 && i + 2 < params.count {
                        // 256 color: ESC[38;5;Nm
                        fg = color256(params[i + 2])
                        i += 2
                    } else if params[i + 1] == 2 && i + 4 < params.count {
                        // True color: ESC[38;2;R;G;Bm
                        fg = Color(
                            red: Double(params[i + 2]) / 255.0,
                            green: Double(params[i + 3]) / 255.0,
                            blue: Double(params[i + 4]) / 255.0
                        )
                        i += 4
                    }
                }
            case 39:
                fg = nil
            default:
                break
            }
            i += 1
        }
    }

    /// Convert 256-color index to SwiftUI Color
    func color256(_ n: Int) -> Color {
        if n < 16 {
            return ANSIParser.standardColors[n]
        } else if n < 232 {
            // 6x6x6 color cube
            let idx = n - 16
            let r = idx / 36
            let g = (idx / 6) % 6
            let b = idx % 6
            return Color(
                red: r == 0 ? 0 : Double(r) * 40 + 55,
                green: g == 0 ? 0 : Double(g) * 40 + 55,
                blue: b == 0 ? 0 : Double(b) * 40 + 55
            )
        } else {
            // Grayscale ramp
            let gray = Double(n - 232) * 10 + 8
            return Color(white: gray / 255.0)
        }
    }
}
