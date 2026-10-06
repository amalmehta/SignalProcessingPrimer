import SwiftUI

struct LessonView: View {
    let lesson: Lesson
    @Binding var selection: String?
    @AppStorage(Prefs.textSize) private var textSizeRaw = TextSize.medium.rawValue

    private var bodySize: CGFloat { (TextSize(rawValue: textSizeRaw) ?? .medium).bodySize }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(Array(lesson.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
                Divider().padding(.vertical, 8)
                QuizView(lesson: lesson)
                if let next = Course.next(after: lesson) {
                    HStack {
                        Spacer()
                        Button { selection = next.id } label: {
                            Label("Next: \(next.title)", systemImage: "arrow.right")
                        }
                        .controlSize(.large)
                    }
                    .padding(.top, 8)
                }
            }
            .font(.system(size: bodySize))
            .textSelection(.enabled)
            .padding(.horizontal, 40).padding(.vertical, 32)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            // `-scrollToDemo YES` jumps to the demo (used for screenshots).
            if UserDefaults.standard.bool(forKey: "scrollToDemo") { proxy.scrollTo("demo", anchor: .top) }
        }
        }
        .navigationTitle(lesson.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(Course.module(containing: lesson)?.title ?? "") · Lesson \(Course.number(of: lesson))")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(lesson.title).font(.system(size: bodySize * 2, weight: .bold))
            Text(lesson.summary).font(.system(size: bodySize * 1.15)).foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder private func blockView(_ block: Block) -> some View {
        switch block {
        case .text(let md):
            Text(LocalizedStringKey(md)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        case .heading(let s):
            Text(s).font(.system(size: bodySize * 1.3, weight: .semibold)).padding(.top, 6)
        case .equation(let eq, let caption):
            VStack(alignment: .leading, spacing: 4) {
                Text(eq).font(.system(size: bodySize * 1.1, design: .monospaced))
                if let caption { Text(caption).font(.system(size: bodySize * 0.85)).foregroundStyle(.secondary) }
            }
            .padding(.vertical, 10).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(LocalizedStringKey(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .inPractice(let title, let body):
            VStack(alignment: .leading, spacing: 6) {
                Label("In practice: \(title)", systemImage: "film.stack").font(.system(size: bodySize, weight: .semibold))
                Text(LocalizedStringKey(body)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.series1.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.series1).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2))
            }
        case .demo:
            DemoCard(caption: lesson.demoCaption) {
                DemoView(kind: lesson.demo)
            }
            .font(.body)
            .textSelection(.disabled)
            .id("demo")
        }
    }
}

struct QuizView: View {
    let lesson: Lesson
    @EnvironmentObject private var progress: ProgressStore
    @AppStorage(Prefs.passMark) private var passMark = 2
    @AppStorage(Prefs.showExplanations) private var showExplanations = true
    @State private var picks: [Int?] = []
    @State private var submitted = false

    private var score: Int { zip(picks, lesson.quiz).filter { $0.0 == $0.1.answer }.count }
    private var required: Int { min(passMark, lesson.quiz.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Check your understanding", systemImage: "checklist").font(.title3.weight(.semibold))
                Spacer()
                if progress.isComplete(lesson) {
                    Label("Completed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
                }
            }
            ForEach(Array(lesson.quiz.enumerated()), id: \.offset) { i, q in
                question(i, q)
            }
            HStack(spacing: 12) {
                if submitted {
                    Text(score >= required ? "\(score)/\(lesson.quiz.count) — lesson complete!"
                                           : "\(score)/\(lesson.quiz.count) — you need \(required) to complete this lesson.")
                        .font(.callout.weight(.medium))
                    Button("Try Again") { picks = Array(repeating: nil, count: lesson.quiz.count); submitted = false }
                } else {
                    Button("Check Answers") {
                        submitted = true
                        progress.recordQuiz(lesson, score: score, passMark: required)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(picks.contains { $0 == nil })
                }
            }
        }
        .onAppear { if picks.count != lesson.quiz.count { picks = Array(repeating: nil, count: lesson.quiz.count) } }
    }

    @ViewBuilder private func question(_ i: Int, _ q: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(i + 1). \(q.prompt)").fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(q.choices.enumerated()), id: \.offset) { c, choice in
                Button {
                    if !submitted, i < picks.count { picks[i] = c }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: symbol(question: i, choice: c, answer: q.answer))
                            .foregroundStyle(tint(question: i, choice: c, answer: q.answer))
                        Text(choice).foregroundStyle(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(i < picks.count && picks[i] == c ? .isSelected : [])
            }
            if submitted && showExplanations {
                Text(q.explanation).font(.callout).foregroundStyle(.secondary).padding(.leading, 26)
            }
        }
    }

    private func symbol(question i: Int, choice c: Int, answer: Int) -> String {
        let picked = i < picks.count && picks[i] == c
        guard submitted else { return picked ? "largecircle.fill.circle" : "circle" }
        if c == answer { return "checkmark.circle.fill" }
        return picked ? "xmark.circle.fill" : "circle"
    }

    private func tint(question i: Int, choice c: Int, answer: Int) -> Color {
        guard submitted else { return i < picks.count && picks[i] == c ? .accentColor : .secondary }
        if c == answer { return .green }
        return i < picks.count && picks[i] == c ? .red : .secondary
    }
}
