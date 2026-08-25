import SwiftUI

struct KeyboardAccessoryView: View {
    let onKeyPress: (String) -> Void

    // 常用快捷键
    let shortcuts = [
        ("Esc", "\u{1B}"),
        ("Tab", "\t"),
        ("Ctrl", "^"),
        ("↑", "\u{1B}[A"),
        ("↓", "\u{1B}[B"),
        ("←", "\u{1B}[D"),
        ("→", "\u{1B}[C"),
        ("|", "|"),
        ("~", "~"),
        ("/", "/")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shortcuts, id: \.0) { shortcut in
                    Button(action: {
                        onKeyPress(shortcut.1)
                    }) {
                        Text(shortcut.0)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(minWidth: 44, height: 36)
                            .background(Color(white: 0.25))
                            .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(white: 0.15))
        .frame(height: 48)
    }
}
