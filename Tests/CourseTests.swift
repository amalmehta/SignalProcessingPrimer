import XCTest
@testable import Signal_Processing_Primer

final class CourseTests: XCTestCase {
    func testCourseShape() {
        XCTAssertEqual(Course.modules.count, 4)
        XCTAssertEqual(Course.allLessons.count, 13)
    }

    func testEveryLessonIsComplete() {
        for lesson in Course.allLessons {
            XCTAssertEqual(lesson.blocks.filter { $0 == .demo }.count, 1, "\(lesson.id) must place its demo exactly once")
            XCTAssertTrue(lesson.blocks.contains { if case .inPractice = $0 { return true } else { return false } },
                          "\(lesson.id) needs a real-world 'In practice' box")
            XCTAssertGreaterThanOrEqual(lesson.quiz.count, 3, lesson.id)
            for q in lesson.quiz {
                XCTAssertTrue(q.choices.indices.contains(q.answer), "\(lesson.id): bad answer index in “\(q.prompt)”")
                XCTAssertEqual(Set(q.choices).count, q.choices.count, "\(lesson.id): duplicate choices")
                XCTAssertFalse(q.explanation.isEmpty)
            }
        }
    }

    func testIDsAndDemosAreUnique() {
        let ids = Course.allLessons.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(Course.allLessons.map(\.demo)), Set(DemoKind.allCases), "every demo used exactly once")
    }

    func testNavigationHelpers() {
        let first = Course.allLessons[0]
        XCTAssertEqual(Course.number(of: first), 1)
        XCTAssertEqual(Course.next(after: first)?.id, Course.allLessons[1].id)
        XCTAssertNil(Course.next(after: Course.allLessons.last!))
    }

    @MainActor func testProgressStorePersistsAndRespectsPassMark() {
        let defaults = UserDefaults(suiteName: "test.\(UUID())")!
        let lesson = Course.allLessons[0]
        let store = ProgressStore(defaults: defaults)
        store.recordQuiz(lesson, score: 1, passMark: 2)
        XCTAssertFalse(store.isComplete(lesson))
        store.recordQuiz(lesson, score: 3, passMark: 2)
        XCTAssertTrue(store.isComplete(lesson))
        XCTAssertTrue(ProgressStore(defaults: defaults).isComplete(lesson), "progress should survive relaunch")
        store.reset()
        XCTAssertEqual(ProgressStore(defaults: defaults).completedCount, 0)
    }

    func testFeedbackIsAppendedLocally() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fb-\(UUID()).jsonl")
        try FeedbackStore.save(.init(date: .now, kind: "Bug", lesson: "Sampling", message: "one"), to: url)
        try FeedbackStore.save(.init(date: .now, kind: "Bug", lesson: nil, message: "two"), to: url)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let issue = FeedbackStore.issueURL(for: .init(date: .now, kind: "Bug", lesson: "Sampling", message: "hi there"))
        XCTAssertTrue(issue.absoluteString.contains("title=%5BBug%5D%20Sampling"))
    }
}
