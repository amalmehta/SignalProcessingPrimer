# Instructions

## What you need

- macOS 14 (Sonoma) or later
- Xcode 15 or later (built and tested with Xcode 26.5)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) is needed only if you change `project.yml` (`brew install xcodegen`)

## Run it

The easiest way is to open the project in Xcode and press ⌘R:

```bash
open "Signal Processing Primer.xcodeproj"
```

To build from the command line instead:

```bash
xcodebuild -project "Signal Processing Primer.xcodeproj" -scheme "Signal Processing Primer" -configuration Release -derivedDataPath build build
```

```bash
open "build/Build/Products/Release/Signal Processing Primer.app"
```

To keep it, drag `Signal Processing Primer.app` from `build/Build/Products/Release/` into `/Applications`. The app is signed ad hoc for local use only, so it isn't notarised for sharing with other Macs.

## Run the tests

```bash
xcodebuild -project "Signal Processing Primer.xcodeproj" -scheme "Signal Processing Primer" -derivedDataPath build test
```

There are 32 tests. 16 check the DSP maths (FFT, aliasing, quantisation SNR, convolution, biquads, the compressor, the DCT/JPEG round trip, image kernels, spectrograms). 4 check colour and gamma (transfer functions, shadow codes, Y′CbCr, chroma subsampling). 6 check white balance (light colour by temperature and tint, camera settings, eyedropper, gray world). 6 check the course content, progress saving and the feedback file.

## Using the app

- **Sidebar:** the 13 lessons in 4 modules. A green tick means you passed that lesson's quiz. The bar at the bottom shows your overall progress.
- **Lesson page:** text, formulas and an *In practice* box on real-world audio, video and film uses. The **Try it** demo sits in the middle, and the quiz is at the end. **Next** goes to the following lesson.
- **Demos:** move the sliders and the plots update straight away. Hover over a chart to read its values. **Play** buttons let you hear the result. Start with the volume low, because the aliasing and low-bit-depth demos are deliberately harsh.
- **Quiz:** pick an answer for each question, then click **Check Answers**. Get all but one right (the default; Settings can require all) and the lesson is marked complete.
- **Settings** (⌘, or the gear in the toolbar):
  - Reading: text size, answer explanations, pass mark (all but one correct, or all correct)
  - Sound: demo volume, tone length, test sound
  - Images: use your own photo in the picture demos (grayscale in Lessons 10–11, colour in Lesson 13)
  - Progress: reset your progress
- **Feedback** (the small button at the bottom of the sidebar, or ⇧⌘F): pick a type and write your note.
  - **Save** appends it to `~/Library/Application Support/Signal Processing Primer/Feedback.jsonl`.
  - **Open as GitHub Issue** opens a pre-filled issue in your browser. Nothing is posted until you submit it there.

## The website

The website is published as a private Artifact: <https://claude.ai/artifact/4mZjs9pvjHnj2D5RcxiPtu>. Only you can open it until you share it from the page's Share menu.

It has the same 13 lessons, demos, quizzes, settings and feedback as the Mac app.
- **Settings:** the gear button, or ⌘, while the page has focus.
- **Feedback:** the small *Feedback* tab on the right edge, or ⇧⌘F.
- **Saved data:** progress and settings are saved in each visitor's own browser. A photo you load for the picture demos is kept only for that browser tab.
- **Feedback for visitors:** filing a GitHub issue needs access to the private repo. Visitors without access can use **Copy text** and send their feedback another way.

**Run it locally.** Use this server, which wraps the page the same way the Artifact host does and serves the shared `content/course.json`:

```bash
python3 scripts/serve_web.py 8000
```

Then open <http://localhost:8000/>. Opening `web/index.html` directly from disk won't work, because browsers block loading `course.json` from a `file://` page.

**Test the web maths and content** (Node 18 or later):

```bash
node --test web/tests/dsp.test.mjs
```

**Republish** after editing `web/` or `content/course.json`: ask Claude to "republish the website". It publishes `web/index.html` with `styles.css`, `app.js`, `demos.js`, `dsp.js`, `plot.js` and `content/course.json` (as `course.json`) to the same URL.

## Changing the course

All lesson text and quizzes live in one file, `content/course.json`, which both the Mac app and the website read. Edit it, then:
- **Mac app:** rebuild; the file is bundled at build time.
- **Website:** reload the local server, or republish.

Block types are `text`, `heading`, `equation` (with optional `caption`), `bullets`, `inPractice` and `demo`. Text supports `**bold**`, `*italic*` and `` `code` ``. `CourseTests` (Swift) and the Node test both catch an invalid quiz answer, a missing demo or a missing *In practice* box.

## Screenshots

`scripts/screenshots.sh` opens the built Release app at each lesson's demo and saves `docs/images/lesson-<id>.jpg`. Your terminal needs Screen Recording permission for this. To capture just some lessons, pass their ids, for example `scripts/screenshots.sh jpeg film`. The app accepts these developer launch arguments:

| Argument | Effect |
|---|---|
| `-initialLesson <id>` | Opens straight to a lesson |
| `-scrollToDemo YES` | Scrolls to its demo |
| `-showSettings YES` | Opens Settings |
| `-showFeedback YES` | Opens the Feedback sheet |

To regenerate the app icon: `swift scripts/make_icon.swift "Signal Processing Primer/Resources/Assets.xcassets/AppIcon.appiconset"`.
