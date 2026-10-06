import AppKit
import Foundation
import SwiftUI

/// Every user preference, in one place. Views read these with `@AppStorage(Prefs.key)`.
enum Prefs {
    static let textSize = "textSize"            // TextSize.rawValue
    static let volume = "volume"                // 0...1
    static let toneSeconds = "toneSeconds"      // length of demo sounds
    static let passMark = "passMark"            // correct answers needed to complete a lesson
    static let showExplanations = "showExplanations"
    static let customImagePath = "customImagePath"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            textSize: TextSize.medium.rawValue, volume: 0.5, toneSeconds: 1.5,
            passMark: 2, showExplanations: true, customImagePath: ""
        ])
    }
}

enum TextSize: String, CaseIterable, Identifiable {
    case small = "Small", medium = "Medium", large = "Large", extraLarge = "Extra Large"
    var id: String { rawValue }
    var bodySize: CGFloat { [13, 15, 17, 20][Self.allCases.firstIndex(of: self)!] }
}

/// Which lessons are done and the best quiz score per lesson. Stored in UserDefaults as JSON.
@MainActor
final class ProgressStore: ObservableObject {
    struct Snapshot: Codable, Equatable {
        var completed: Set<String> = []
        var bestScores: [String: Int] = [:]
        var lastLessonID: String?
    }

    @Published private(set) var snapshot: Snapshot
    private let defaults: UserDefaults
    private let key = "progress.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
    }

    func isComplete(_ lesson: Lesson) -> Bool { snapshot.completed.contains(lesson.id) }
    func bestScore(_ lesson: Lesson) -> Int? { snapshot.bestScores[lesson.id] }
    var completedCount: Int { snapshot.completed.count }

    func recordQuiz(_ lesson: Lesson, score: Int, passMark: Int) {
        snapshot.bestScores[lesson.id] = max(score, snapshot.bestScores[lesson.id] ?? 0)
        if score >= passMark { snapshot.completed.insert(lesson.id) }
        save()
    }

    func visit(_ lesson: Lesson) {
        guard snapshot.lastLessonID != lesson.id else { return }
        snapshot.lastLessonID = lesson.id
        save()
    }

    func reset() { snapshot = Snapshot(); save() }

    private func save() { defaults.set(try? JSONEncoder().encode(snapshot), forKey: key) }
}

/// Feedback stays on this Mac: appended to a JSON-lines file. Nothing is sent anywhere
/// unless the user explicitly chooses "Open as GitHub Issue".
enum FeedbackStore {
    static let repoIssuesURL = URL(string: "https://github.com/amalmehta/SignalProcessingPrimer/issues/new")!

    struct Entry: Codable { var date: Date; var kind: String; var lesson: String?; var message: String }

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signal Processing Primer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Feedback.jsonl")
    }

    static func save(_ entry: Entry, to url: URL = fileURL) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        var line = try enc.encode(entry); line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            try h.seekToEnd(); try h.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    static func issueURL(for entry: Entry) -> URL {
        var c = URLComponents(url: repoIssuesURL, resolvingAgainstBaseURL: false)!
        let title = "[\(entry.kind)] " + (entry.lesson ?? "General")
        c.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: entry.message)]
        return c.url!
    }
}
