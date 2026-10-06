import Foundation

/// The course is plain data: modules → lessons → blocks + one demo + a quiz.
struct Module: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String          // SF Symbol
    let lessons: [Lesson]
}

struct Lesson: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let blocks: [Block]
    let demo: DemoKind
    let demoCaption: String
    let quiz: [QuizQuestion]

    static func == (a: Lesson, b: Lesson) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum Block: Hashable {
    /// A paragraph; supports inline Markdown (**bold**, *italic*, `code`).
    case text(String)
    case heading(String)
    /// A formula shown on its own line in a monospaced card.
    case equation(String, caption: String? = nil)
    case bullets([String])
    /// "Where you'll meet this" — the real-world application box.
    case inPractice(title: String, body: String)
    /// Marks where the interactive demo appears in the reading flow.
    case demo
}

struct QuizQuestion: Hashable, Identifiable {
    var id: String { prompt }
    let prompt: String
    let choices: [String]
    let answer: Int
    let explanation: String
}

enum DemoKind: String, CaseIterable {
    case sineMixer, aliasing, quantization
    case spectrum, windowing, spectrogram
    case convolution, filterDesigner, compressor
    case imageKernels, jpeg, frameRate
}

extension Course {
    static var allLessons: [Lesson] { modules.flatMap(\.lessons) }

    static func lesson(id: String) -> Lesson? { allLessons.first { $0.id == id } }

    static func module(containing lesson: Lesson) -> Module? {
        modules.first { $0.lessons.contains(lesson) }
    }

    /// 1-based position across the whole course, e.g. "Lesson 7".
    static func number(of lesson: Lesson) -> Int {
        (allLessons.firstIndex(of: lesson) ?? 0) + 1
    }

    static func next(after lesson: Lesson) -> Lesson? {
        guard let i = allLessons.firstIndex(of: lesson), i + 1 < allLessons.count else { return nil }
        return allLessons[i + 1]
    }
}
