import SwiftUI

struct ContentView: View {
    @Binding var showFeedback: Bool
    @EnvironmentObject private var progress: ProgressStore
    @Environment(\.openSettings) private var openSettings
    /// `-initialLesson <id>` on the command line opens straight to a lesson (used for screenshots).
    @State private var selection: String? = UserDefaults.standard.string(forKey: "initialLesson")

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 340)
        } detail: {
            if let id = selection, let lesson = Course.lesson(id: id) {
                LessonView(lesson: lesson, selection: $selection)
                    .id(lesson.id)                     // fresh scroll position + demo state per lesson
            } else {
                WelcomeView(selection: $selection)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .help("Settings (⌘,)")
            }
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackView(lessonTitle: selection.flatMap { Course.lesson(id: $0)?.title })
        }
        .onAppear {
            // Screenshot helpers: `-showFeedback YES` / `-showSettings YES` on the command line.
            if UserDefaults.standard.bool(forKey: "showFeedback") { showFeedback = true }
            if UserDefaults.standard.bool(forKey: "showSettings") { openSettings() }
        }
        .onChange(of: selection) { _, id in
            if let id, let lesson = Course.lesson(id: id) { progress.visit(lesson) }
            TonePlayer.shared.stop()
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(Course.modules) { module in
                Section {
                    ForEach(module.lessons) { lesson in
                        HStack(spacing: 8) {
                            Text("\(Course.number(of: lesson))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            Text(lesson.title).lineLimit(2)
                            Spacer(minLength: 4)
                            if progress.isComplete(lesson) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    .accessibilityLabel("Completed")
                            }
                        }
                        .tag(lesson.id)
                    }
                } header: {
                    Label(module.title, systemImage: module.icon)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                let total = Course.allLessons.count
                ProgressView(value: Double(progress.completedCount), total: Double(total)) {
                    Text("\(progress.completedCount) of \(total) lessons complete").font(.caption)
                }
                Button { showFeedback = true } label: {
                    Label("Feedback", systemImage: "bubble.left")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Send feedback (⇧⌘F)")
            }
            .padding(12)
            .background(.bar)
        }
    }
}

struct WelcomeView: View {
    @Binding var selection: String?
    @EnvironmentObject private var progress: ProgressStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 44)).foregroundStyle(Color.series1)
                Text("Signal Processing Primer").font(.largeTitle.bold())
                Text("A hands-on course in the maths behind audio, images, video and film. Twelve lessons, each with something to play with and a short quiz.")
                    .font(.title3).foregroundStyle(.secondary)
                ForEach(Course.modules) { module in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(module.title, systemImage: module.icon).font(.headline)
                        ForEach(module.lessons) { lesson in
                            Text("\(Course.number(of: lesson)). \(lesson.title) — ").foregroundStyle(.primary)
                            + Text(lesson.summary).foregroundStyle(.secondary)
                        }
                    }
                }
                let resume = progress.snapshot.lastLessonID.flatMap(Course.lesson(id:))
                Button {
                    selection = (resume ?? Course.allLessons[0]).id
                } label: {
                    Text(resume == nil ? "Start Lesson 1" : "Continue: \(resume!.title)").padding(.horizontal, 8)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
            .padding(40)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}
