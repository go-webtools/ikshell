import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: LinuxEngine
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TerminalView()
                .environmentObject(engine)
                .tabItem {
                    Label("终端", systemImage: "terminal")
                }
                .tag(0)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(1)
        }
    }
}
