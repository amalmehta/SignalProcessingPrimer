import SwiftUI

@main
struct SignalProcessingPrimerApp: App {
    @StateObject private var progress = ProgressStore()
    @State private var showFeedback = false

    init() { Prefs.registerDefaults() }

    var body: some Scene {
        WindowGroup("Signal Processing Primer") {
            ContentView(showFeedback: $showFeedback)
                .environmentObject(progress)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .help) {
                Button("Send Feedback…") { showFeedback = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }

        // The standard Settings scene gives us the app menu item and ⌘, for free.
        Settings {
            SettingsView()
                .environmentObject(progress)
        }
    }
}
