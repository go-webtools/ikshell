import SwiftUI

struct SettingsView: View {
    @AppStorage("fontSize") private var fontSize: Double = 14
    @AppStorage("fontName") private var fontName: String = "Menlo"
    @AppStorage("theme") private var theme: String = "dark"

    let themes = ["dark", "light", "green", "amber"]

    var body: some View {
        NavigationView {
            Form {
                Section("外观") {
                    HStack {
                        Text("字体大小")
                        Spacer()
                        Slider(value: $fontSize, in: 10...32, step: 1) {
                            Text("字体大小")
                        }
                        .frame(width: 200)
                        Text("\(Int(fontSize))")
                            .monospacedDigit()
                    }

                    Picker("字体", selection: $fontName) {
                        Text("Menlo").tag("Menlo")
                        Text("SF Mono").tag("SF Mono")
                        Text("Courier").tag("Courier")
                    }

                    Picker("主题", selection: $theme) {
                        ForEach(themes, id: \.self) { t in
                            Text(t.capitalized).tag(t)
                        }
                    }
                }

                Section("Linux") {
                    HStack {
                        Text("状态")
                        Spacer()
                        if engine.isRunning {
                            Label("运行中", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("未启动", systemImage: "xmark.circle")
                                .foregroundColor(.red)
                        }
                    }

                    HStack {
                        Text("Rootfs")
                        Spacer()
                        Text(engine.rootfsStatus)
                            .foregroundColor(.secondary)
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("基于")
                        Spacer()
                        Text("iSH (GPLv3)")
                            .foregroundColor(.secondary)
                    }
                    Link("iSH GitHub", destination: URL(string: "https://github.com/ish-app/ish")!)
                }
            }
            .navigationTitle("设置")
        }
        .navigationViewStyle(.stack)
    }
}

extension SettingsView {
    @EnvironmentObject var engine: LinuxEngine
}
