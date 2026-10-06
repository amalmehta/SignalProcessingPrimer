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

There are 22 tests. 16 check the DSP maths (FFT, aliasing, quantisation SNR, convolution, biquads, the compressor, the DCT/JPEG round trip, image kernels, spectrograms). 6 check the course content, progress saving and the feedback file.

## Using the app

- **Sidebar:** the 12 lessons in 4 modules. A green tick means you passed that lesson's quiz. The bar at the bottom shows your overall progress.
- **Lesson page:** text, formulas and an *In practice* box on real-world audio, video and film uses. The **Try it** demo sits in the middle, and the quiz is at the end. **Next** goes to the following lesson.
- **Demos:** move the sliders and the plots update straight away. Hover over a chart to read its values. **Play** buttons let you hear the result. Start with the volume low, because the aliasing and low-bit-depth demos are deliberately harsh.
- **Quiz:** pick an answer for each question, then click **Check Answers**. Get enough right (2 of 3 by default) and the lesson is marked complete.
- **Settings** (⌘, or the gear in the toolbar):
  - Reading: text size, answer explanations, pass mark
  - Sound: demo volume, tone length, test sound
  - Images: use your own photo in the picture demos
  - Progress: reset your progress
- **Feedback** (the small button at the bottom of the sidebar, or ⇧⌘F): pick a type and write your note.
  - **Save** appends it to `~/Library/Application Support/Signal Processing Primer/Feedback.jsonl`.
  - **Open as GitHub Issue** opens a pre-filled issue in your browser. Nothing is posted until you submit it there.

## Changing the course

Lesson text and quizzes are plain Swift data in `Signal Processing Primer/Course/CourseContent.swift`. Edit it and rebuild. `CourseTests` will catch an invalid quiz answer, a missing demo or a missing *In practice* box.

## Screenshots

`scripts/screenshots.sh` opens the built Release app at each lesson's demo and saves `docs/images/lesson-<id>.jpg`. Your terminal needs Screen Recording permission for this. To capture just some lessons, pass their ids, for example `scripts/screenshots.sh jpeg film`. The app accepts these developer launch arguments:

| Argument | Effect |
|---|---|
| `-initialLesson <id>` | Opens straight to a lesson |
| `-scrollToDemo YES` | Scrolls to its demo |
| `-showSettings YES` | Opens Settings |
| `-showFeedback YES` | Opens the Feedback sheet |

To regenerate the app icon: `swift scripts/make_icon.swift "Signal Processing Primer/Resources/Assets.xcassets/AppIcon.appiconset"`.
