import SwiftUI

struct FeedbackView: View {
    let lessonTitle: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var kind = "Suggestion"
    @State private var message = ""
    @State private var status: String?

    private let kinds = ["Suggestion", "Mistake in a lesson", "Bug", "Other"]
    private var entry: FeedbackStore.Entry { .init(date: .now, kind: kind, lesson: lessonTitle, message: message) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send Feedback").font(.title2.bold())
            Text(lessonTitle.map { "About: \($0)" } ?? "About the app in general")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Type", selection: $kind) { ForEach(kinds, id: \.self, content: Text.init) }
                .pickerStyle(.segmented).labelsHidden()
            TextEditor(text: $message)
                .font(.body)
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            Text("Saved only on this Mac. “Open as GitHub Issue” opens a pre-filled issue in your browser — you review it before anything is posted.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let status { Text(status).font(.caption).foregroundStyle(.green) }
            HStack {
                Button("Show Feedback File") { NSWorkspace.shared.activateFileViewerSelecting([FeedbackStore.fileURL]) }
                    .buttonStyle(.link)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open as GitHub Issue") {
                    try? FeedbackStore.save(entry)
                    openURL(FeedbackStore.issueURL(for: entry))
                    dismiss()
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Save") {
                    do { try FeedbackStore.save(entry); dismiss() } catch { status = "Couldn't save: \(error.localizedDescription)" }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
