import Foundation

/// The course is plain data: modules → lessons → blocks + one demo + a quiz.
struct Module: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let icon: String          // SF Symbol
    let lessons: [Lesson]
}

struct Lesson: Identifiable, Hashable, Codable {
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

struct QuizQuestion: Hashable, Identifiable, Codable {
    var id: String { prompt }
    private enum CodingKeys: String, CodingKey { case prompt, choices, answer, explanation }
    let prompt: String
    let choices: [String]
    let answer: Int
    let explanation: String
}

enum DemoKind: String, CaseIterable, Codable {
    case sineMixer, aliasing, quantization
    case spectrum, windowing, spectrogram
    case convolution, filterDesigner, compressor
    case imageKernels, jpeg, frameRate, colourGamma
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

/// JSON shape: `{"type": "text", "text": "…"}`, `{"type": "equation", "text": "…", "caption": "…"}`,
/// `{"type": "bullets", "items": […]}`, `{"type": "inPractice", "title": "…", "body": "…"}`,
/// `{"type": "heading", "text": "…"}`, `{"type": "demo"}`. The website reads the same file.
extension Block: Codable {
    private enum Key: String, CodingKey { case type, text, caption, items, title, body }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .type) {
        case "text":       self = .text(try c.decode(String.self, forKey: .text))
        case "heading":    self = .heading(try c.decode(String.self, forKey: .text))
        case "equation":   self = .equation(try c.decode(String.self, forKey: .text),
                                            caption: try c.decodeIfPresent(String.self, forKey: .caption))
        case "bullets":    self = .bullets(try c.decode([String].self, forKey: .items))
        case "inPractice": self = .inPractice(title: try c.decode(String.self, forKey: .title),
                                              body: try c.decode(String.self, forKey: .body))
        case "demo":       self = .demo
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown block type \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .text(let t):            try c.encode("text", forKey: .type); try c.encode(t, forKey: .text)
        case .heading(let t):         try c.encode("heading", forKey: .type); try c.encode(t, forKey: .text)
        case .equation(let t, let cap):
            try c.encode("equation", forKey: .type); try c.encode(t, forKey: .text)
            try c.encodeIfPresent(cap, forKey: .caption)
        case .bullets(let items):     try c.encode("bullets", forKey: .type); try c.encode(items, forKey: .items)
        case .inPractice(let t, let b):
            try c.encode("inPractice", forKey: .type); try c.encode(t, forKey: .title); try c.encode(b, forKey: .body)
        case .demo:                   try c.encode("demo", forKey: .type)
        }
    }
}
