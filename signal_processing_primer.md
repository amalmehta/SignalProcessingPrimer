PROJECT NAME: signal_processing_primer

META-INSTRUCTIONS:

<Read it all before acting. Ask about anything unclear, contradictory or
 underspecified — before starting and mid-build. Ask in the question widget
 (AskUserQuestion): related questions batched, concrete options, your
 recommendation first. Plain text only if the widget isn't available.>

<Don't expand scope. Anything not listed here is a proposal, including changes
 to this file — propose it, don't do it.>

<Prefer doing over describing: run the code, write the files, test it.>

<Always in scope, no proposal needed: when it goes on GitHub, a README that is
 easy to read at a glance — a line on what it is, then clear visuals
 (screenshots, a diagram or a chart), then links. Everything else goes in
 linked files: docs/INSTRUCTIONS.md (setup, run, use),
 docs/SYSTEM-DESIGN.md (see below) and docs/FILE-STRUCTURE.md (what's where). If what you're
 building is an application rather than a script, also a small unobtrusive feedback tab, and a settings
 button or tab (⌘, on the Mac) that gathers its preferences in one place.>

<If what you're building is an application, build it as a Mac app first; the
 website comes after, as its own step.>

<Name things the way a person would say them — "Goal Tracker", not
 goal_tracker — for the app, its windows, titles, files people open, repo
 descriptions and README headings. When you create the GitHub repo, name it
 with no "_" or "-": one word or joined words, e.g. GoalTracker.>

<Always in scope: a system design doc in the codebase, docs/SYSTEM-DESIGN.md,
 kept current as the build changes. Cover the architecture (with a Mermaid
 diagram), each component's job, the main flows, where data lives, the key
 design decisions and their trade-offs, how it's tested, and known limits.>

<Finish by listing every deliverable: path, what it is, how to check it works.>

<Git rules (no Claude attribution, never commit .claude/) are in
 ~/.claude/CLAUDE.md and apply on their own — nothing to repeat here.>

<Keep the changelog at the bottom current.>

CONTEXT:

create a complete course on signal processing (multimodal). geared towards real-world applications (i..e used in audio, video, film)

DELIVERABLES:

mac app of the course

OPEN QUESTIONS / ASSUMPTIONS:

<Agent fills in: what it guessed, what it decided without asking.>

Asked and answered (2026-10-06): native SwiftUI app; 12 lessons in 4 modules;
live demos + quizzes (no mic/camera); private GitHub repo "SignalProcessingPrimer"
with feedback saved locally and an optional "Open as GitHub Issue".

Decided without asking:
- "Multimodal" = audio + images + video/film, each with its own demos; the
  course is 4 modules: Foundations, Frequency Domain, Filtering, Images/Video/Film.
- Target: macOS 14+, no third-party dependencies (Accelerate, AVFoundation,
  Swift Charts only); project generated with XcodeGen, .xcodeproj committed.
- All test material is synthesised (tones, drum loop, chirps, a procedural test
  card) to avoid licensing; users can load their own photo in Settings.
- Picture demos in Lessons 10–11 are grayscale. Colour and gamma got their own
  Lesson 13 (asked: new lesson; gamma + chroma subsampling). Decided without
  asking: BT.601 Y′CbCr weights (as JPEG), chroma averaged per block and
  replicated back, 4 transfer presets, and a colour test card built to expose
  subsampling; gamuts and HDR curves stay in the text.
- White balance (asked: third tab in Lesson 13; light + camera + auto + eyedropper).
  Decided without asking: lights modelled as black bodies (Planckian locus, Kim
  et al. fit), 6,500 K = neutral, per-channel gains relative to green in linear
  light, simulated auto-exposure so white never clips, a colour-checker chart as
  the default scene, one added quiz question, and the pass mark reworded to
  "all but one correct" / "all correct" so it works for a 4-question quiz.
- Progress = passing a lesson's quiz (default 2 of 3, adjustable to 3 of 3).
- Settings: text size, explanations, pass mark, volume, tone length, demo image,
  reset progress.
- App is ad-hoc signed and unsandboxed for local use; not notarised.
- Developer launch arguments (-initialLesson, -scrollToDemo, -showSettings,
  -showFeedback) were added to capture README screenshots without UI scripting.
- Website (built 2026-10-06, after asking): published as a private claude.ai
  Artifact; plain HTML/CSS/JS in web/, no build step; lesson text moved into one
  shared content/course.json read by both the Mac app and the website; feedback
  tab opens a pre-filled GitHub issue (plus "Copy text" for people without repo
  access). Decided without asking: web progress/settings live in each visitor's
  browser (no sync with the Mac app); an uploaded photo is kept for the tab only;
  the web DSP is a JS port verified by Node tests mirroring the Swift tests.

CHANGELOG:

- 2026-10-06 — created
- 2026-09-15 — added meta-instruction: built-out applications include a small feedback tab
- 2026-09-15 — added meta-instruction: no "Claude" attribution in commits, PRs, or branches
- 2026-09-16 — added meta-instruction: always include a README when adding to GitHub
- 2026-09-16 — changed meta-instruction: ask clarifying questions in the question widget
- 2026-09-17 — added meta-instructions: Claude never a contributor; never commit .claude/
- 2026-09-26 — compressed the meta-instructions and every field prompt; git rules moved to the global instruction file
- 2026-09-27 — added meta-instruction: applications are built as a Mac app first, then a website
- 2026-09-28 — folded inputs, instructions, constraints, deliverables and done criteria into one free-form CONTEXT
- 2026-09-28 — changed meta-instruction: a README on GitHub always includes a visual
- 2026-09-28 — added meta-instruction: name things like a person would, never snake_case
- 2026-09-28 — changed meta-instruction: README leads with visuals; instructions live in a linked guide
- 2026-09-28 — changed meta-instruction: README is visuals and links; details in docs/INSTRUCTIONS.md and docs/FILE-STRUCTURE.md
- 2026-09-29 — changed meta-instruction: GitHub repo names have no "_" or "-"
- 2026-10-02 — added a DELIVERABLES field after CONTEXT
- 2026-10-02 — added meta-instruction: every project has a system design doc at docs/SYSTEM-DESIGN.md
- 2026-10-05 — added meta-instruction: applications include a settings button or tab
- 2026-10-06 — built v1.0 of the Mac app: 12 lessons, 12 demos, quizzes, progress, settings, feedback, tests, docs
- 2026-10-06 — built the website (private Artifact) and moved lesson content into a shared course.json
- 2026-10-06 — added Lesson 13 "Colour, Gamma and Chroma" with a gamma + chroma subsampling demo (Mac app and website)
- 2026-10-06 — added a white balance demo (third tab of Lesson 13) and a 4th quiz question; pass mark is now "all but one" or "all" correct
