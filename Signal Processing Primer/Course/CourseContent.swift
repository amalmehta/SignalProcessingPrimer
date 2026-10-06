import Foundation

/// All course text lives in `content/course.json` (shared with the website). It is bundled into the
/// app at build time and decoded once here. Edit the JSON — the app, website and content tests pick it up.
enum Course {
    struct File: Codable { var title: String; var version: Int; var modules: [Module] }

    static let modules: [Module] = load()

    static func load(from url: URL? = Bundle.main.url(forResource: "course", withExtension: "json")) -> [Module] {
        guard let url, let data = try? Data(contentsOf: url) else {
            assertionFailure("course.json missing from the app bundle"); return []
        }
        do { return try JSONDecoder().decode(File.self, from: data).modules }
        catch { assertionFailure("course.json is invalid: \(error)"); return [] }
    }
}
