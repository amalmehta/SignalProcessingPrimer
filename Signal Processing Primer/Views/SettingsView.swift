import SwiftUI
import UniformTypeIdentifiers

/// Every preference in one window (⌘, or the gear in the toolbar).
struct SettingsView: View {
    var body: some View {
        TabView {
            ReadingSettings().tabItem { Label("Reading", systemImage: "textformat.size") }
            SoundSettings().tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            ImageSettings().tabItem { Label("Images", systemImage: "photo") }
            ProgressSettings().tabItem { Label("Progress", systemImage: "checklist") }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 300)
    }
}

private struct ReadingSettings: View {
    @AppStorage(Prefs.textSize) private var textSize = TextSize.medium.rawValue
    @AppStorage(Prefs.showExplanations) private var showExplanations = true
    @AppStorage(Prefs.passMark) private var passMark = 2

    var body: some View {
        Form {
            Picker("Lesson text size", selection: $textSize) {
                ForEach(TextSize.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            Toggle("Explain answers after checking", isOn: $showExplanations)
            Picker("To complete a lesson", selection: $passMark) {
                Text("All but one correct").tag(2)
                Text("All correct").tag(3)
            }
        }
    }
}

private struct SoundSettings: View {
    @AppStorage(Prefs.volume) private var volume = 0.5
    @AppStorage(Prefs.toneSeconds) private var toneSeconds = 1.5

    var body: some View {
        Form {
            Slider(value: $volume, in: 0...1) { Text("Demo volume") }
            Slider(value: $toneSeconds, in: 0.5...4, step: 0.5) { Text("Tone length: \(toneSeconds, specifier: "%.1f") s") }
            PlayButton("Test Sound") {
                DSP.tone(frequency: 440, amplitude: 0.5, sampleRate: TonePlayer.sampleRate,
                         count: Int(TonePlayer.sampleRate * toneSeconds))
            }
            Text("Demo sounds are generated at 44.1 kHz. Start quietly — some demos (aliasing, low bit depth) are deliberately harsh.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ImageSettings: View {
    @AppStorage(Prefs.customImagePath) private var customImagePath = ""

    var body: some View {
        Form {
            LabeledContent("Picture demos use") {
                Text(customImagePath.isEmpty ? "Built-in test card" : URL(fileURLWithPath: customImagePath).lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Button("Choose Image…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    if panel.runModal() == .OK, let url = panel.url { customImagePath = url.path }
                }
                Button("Use Test Card") { customImagePath = "" }.disabled(customImagePath.isEmpty)
            }
            Text("Images are scaled to at most 360 px so filters run instantly. Lessons 10–11 use them in grayscale; Lesson 13 in colour.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ProgressSettings: View {
    @EnvironmentObject private var progress: ProgressStore
    @State private var confirming = false

    var body: some View {
        Form {
            LabeledContent("Lessons completed", value: "\(progress.completedCount) of \(Course.allLessons.count)")
            Button("Reset Progress…", role: .destructive) { confirming = true }
                .confirmationDialog("Reset all lesson progress and quiz scores?", isPresented: $confirming) {
                    Button("Reset", role: .destructive) { progress.reset() }
                }
        }
    }
}
