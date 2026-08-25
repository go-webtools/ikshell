import SwiftUI

@main
struct ikshellApp: App {
    @StateObject private var linuxEngine = LinuxEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(linuxEngine)
                .onAppear {
                    linuxEngine.start()
                }
        }
    }
}
