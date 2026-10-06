import Foundation

/// All course text lives here. Edit freely — the app and the content tests pick up changes automatically.
enum Course {
    static let modules: [Module] = [foundations, frequency, filtering, picture]

    // MARK: - Module 1

    static let foundations = Module(id: "foundations", title: "Foundations", icon: "waveform", lessons: [
        Lesson(
            id: "signals",
            title: "What Is a Signal?",
            summary: "Sound, pictures and video are all just numbers that change over something.",
            blocks: [
                .text("A **signal** is any quantity that varies over time or space. The pressure wave hitting a microphone is a signal over time. The brightness of pixels across a photo is a signal over space. A video is both at once: brightness that varies across the frame *and* from frame to frame."),
                .text("The simplest signal is the **sine wave**. It is described by three numbers: how often it repeats (**frequency**, in hertz), how big it is (**amplitude**), and where in its cycle it starts (**phase**)."),
                .equation("x(t) = A · sin(2π f t + φ)", caption: "A = amplitude, f = frequency in Hz, φ = phase in radians"),
                .text("Why care about sines? Because almost any signal can be built by adding sines together. A violin and a flute playing the same note share the same *fundamental* frequency but differ in the mix of *harmonics* — sines at 2×, 3×, 4× the fundamental. That mix is what we hear as **timbre**."),
                .demo,
                .heading("Loudness and pitch are logarithmic"),
                .text("We perceive both pitch and loudness on ratios, not differences. Doubling the frequency raises the pitch one **octave** (A4 = 440 Hz, A5 = 880 Hz). Loudness is measured in **decibels**, a log scale where every 6 dB is roughly a doubling of amplitude."),
                .equation("level (dB) = 20 · log₁₀(A / A_ref)"),
                .bullets([
                    "Human hearing spans roughly **20 Hz – 20 kHz**.",
                    "In digital audio, 0 dBFS is the loudest possible sample; everything else is negative.",
                    "Two identical sines with opposite phase **cancel** — the principle behind noise-cancelling headphones."
                ]),
                .inPractice(title: "On set and in the studio",
                            body: "Flip a mic's polarity and its signal is a sine-by-sine mirror image. Mix it with a second mic on the same source and the low end vanishes — the classic 'phase problem' on a drum kit. Film sound mixers check phase on every multi-mic dialogue scene for the same reason.")
            ],
            demo: .sineMixer,
            demoCaption: "Add harmonics to a fundamental and hear the timbre change. Square, sawtooth and triangle waves are just particular harmonic recipes.",
            quiz: [
                QuizQuestion(prompt: "A tone at 440 Hz is raised by one octave. What is its new frequency?",
                             choices: ["450 Hz", "660 Hz", "880 Hz", "4400 Hz"], answer: 2,
                             explanation: "An octave is a doubling of frequency, so 440 Hz → 880 Hz."),
                QuizQuestion(prompt: "Two instruments play the same note but sound different. What mainly differs?",
                             choices: ["Their fundamental frequency", "The mix of harmonics (timbre)", "The speed of sound", "Their phase only"], answer: 1,
                             explanation: "Same fundamental, different harmonic recipe — that is timbre."),
                QuizQuestion(prompt: "Halving a signal's amplitude changes its level by about…",
                             choices: ["−3 dB", "−6 dB", "−10 dB", "−50 dB"], answer: 1,
                             explanation: "20·log₁₀(0.5) ≈ −6.02 dB.")
            ]),

        Lesson(
            id: "sampling",
            title: "Sampling and Aliasing",
            summary: "How a continuous wave becomes a list of numbers — and what goes wrong.",
            blocks: [
                .text("A computer can't store a continuous wave. Instead an **analog-to-digital converter** measures it at regular instants — the **sample rate**, *fs*. CD audio takes 44,100 samples per second; film and video sound uses 48,000. A video camera samples the scene too: 24, 30 or 60 times a second."),
                .heading("The Nyquist limit"),
                .text("The **Nyquist–Shannon theorem** says a signal can be reconstructed perfectly from its samples only if it contains no frequencies at or above half the sample rate. That half-rate is the **Nyquist frequency**."),
                .equation("f_Nyquist = fs / 2", caption: "44.1 kHz audio can represent up to 22.05 kHz — just above human hearing"),
                .text("Frequencies above Nyquist don't disappear — they **fold back** and masquerade as lower ones. This impostor is an **alias**, and once it's in the samples, no processing can tell it apart from a real tone."),
                .equation("f_alias = | f − round(f / fs) · fs |"),
                .demo,
                .text("That is why every converter puts an **anti-aliasing low-pass filter** in front of the sampler, removing content above Nyquist *before* it can fold."),
                .inPractice(title: "Aliasing you've already seen",
                            body: "The **wagon-wheel effect** — spokes spinning backwards on film — is temporal aliasing at 24 fps. **Moiré** shimmer on a striped shirt is spatial aliasing: the pattern is finer than the sensor's pixel grid, so cameras add an optical low-pass filter. In audio, a cheap synth plug-in that generates a sawtooth naïvely produces aliases that sound like inharmonic whistles on high notes.")
            ],
            demo: .aliasing,
            demoCaption: "The faint line is the true signal; the dots are the samples. Push the frequency past Nyquist and the samples trace a slower impostor.",
            quiz: [
                QuizQuestion(prompt: "Audio sampled at 48 kHz can represent frequencies up to…",
                             choices: ["12 kHz", "24 kHz", "48 kHz", "96 kHz"], answer: 1,
                             explanation: "Nyquist frequency = fs / 2 = 24 kHz."),
                QuizQuestion(prompt: "A 30 kHz tone is sampled at 44.1 kHz without filtering. What do you hear?",
                             choices: ["Nothing — it's ultrasonic", "30 kHz", "14.1 kHz", "74.1 kHz"], answer: 2,
                             explanation: "It folds back: 44.1 − 30 = 14.1 kHz, squarely audible."),
                QuizQuestion(prompt: "Spokes appearing to spin backwards in a film is an example of…",
                             choices: ["Quantization noise", "Temporal aliasing", "Motion blur", "Rolling shutter"], answer: 1,
                             explanation: "The wheel rotates faster than half the frame rate allows, so the sampled motion aliases.")
            ]),

        Lesson(
            id: "quantization",
            title: "Quantization and Bit Depth",
            summary: "Every sample must be rounded to a fixed set of levels. The rounding is noise.",
            blocks: [
                .text("Sampling slices *time*. **Quantization** slices *amplitude*: each measured value is rounded to the nearest of 2ᴮ levels, where B is the **bit depth**. The difference between the true value and the rounded value is **quantization error**, and for busy signals it behaves like a quiet hiss."),
                .equation("Dynamic range ≈ 6.02 · B + 1.76 dB", caption: "16-bit ≈ 98 dB, 24-bit ≈ 146 dB (more than any real microphone can deliver)"),
                .text("Each extra bit halves the step size and buys about 6 dB of headroom. That's why recordings are tracked at 24-bit: you can leave plenty of headroom above the loudest peak and still keep the noise floor far below hearing."),
                .demo,
                .heading("Dither: adding noise to remove distortion"),
                .text("At very low bit depths the error stops being random and starts tracking the signal — it becomes harmonic **distortion**. Adding a tiny amount of random noise before rounding (**dither**) breaks that correlation. You trade an ugly, signal-dependent buzz for a smooth, constant hiss — which our ears forgive far more easily."),
                .inPractice(title: "Mastering, video banding and HDR",
                            body: "When a 24-bit mix is exported to a 16-bit CD or streaming master, mastering engineers apply dither (often noise-shaped to push the hiss into frequencies we hear least). In pictures, quantization shows up as **banding** in smooth skies on 8-bit video — one of the main reasons HDR and professional grading use 10-bit or more, and why film grain or added noise hides banding so well.")
            ],
            demo: .quantization,
            demoCaption: "Lower the bit depth and listen: the hiss rises, then turns into a gritty buzz. Turn on dither to hear the buzz turn back into hiss.",
            quiz: [
                QuizQuestion(prompt: "How many quantization levels does a 16-bit sample have?",
                             choices: ["16", "256", "65,536", "16 million"], answer: 2,
                             explanation: "2¹⁶ = 65,536 levels."),
                QuizQuestion(prompt: "Roughly how much dynamic range does each extra bit add?",
                             choices: ["1 dB", "3 dB", "6 dB", "20 dB"], answer: 2,
                             explanation: "Each bit halves the step size: 20·log₁₀(2) ≈ 6 dB."),
                QuizQuestion(prompt: "Why add dither before reducing bit depth?",
                             choices: ["To make the file smaller", "To turn signal-dependent distortion into benign noise", "To raise the sample rate", "To remove aliasing"], answer: 1,
                             explanation: "Dither decorrelates the error from the signal, replacing distortion with smooth noise.")
            ])
    ])

    // MARK: - Module 2

    static let frequency = Module(id: "frequency", title: "The Frequency Domain", icon: "chart.bar.xaxis", lessons: [
        Lesson(
            id: "fourier",
            title: "Fourier and the FFT",
            summary: "Seeing a signal as a recipe of frequencies.",
            blocks: [
                .text("Lesson 1 built sounds by adding sines. The **Fourier transform** runs that recipe backwards: given a signal, it tells you how much of each frequency it contains. Plotting that is a **spectrum** — the view behind every EQ display and spectrum analyser."),
                .equation("X[k] = Σₙ x[n] · e^(−i 2π k n / N)", caption: "The discrete Fourier transform (DFT) of N samples"),
                .text("Each output **bin** k measures how strongly the signal correlates with a sine at frequency k · fs / N. The bin spacing — the **frequency resolution** — depends only on how many samples you analyse:"),
                .equation("Δf = fs / N", caption: "4,096 samples at 44.1 kHz → bins every 10.8 Hz"),
                .text("Computed directly, the DFT costs N² operations. The **Fast Fourier Transform** (FFT, Cooley–Tukey 1965) gets the same answer in N·log₂N by recursively splitting the problem in half — for N = 4,096 that's about 340× faster. It's the reason real-time spectral audio and video processing exist at all."),
                .demo,
                .bullets([
                    "A pure sine is a single spike. A square wave is spikes at odd harmonics, falling as 1/n.",
                    "Noise spreads energy across all bins.",
                    "The transform is reversible — you can edit the spectrum and transform back (that's how spectral repair tools work)."
                ]),
                .inPractice(title: "Where the FFT runs every day",
                            body: "Spectrum analysers in DAWs, auto-tune's pitch detection, noise-reduction tools that 'learn' a hum profile, MP3/AAC encoders deciding which frequencies you won't miss, and the 'Shazam' style fingerprint that matches songs from a few seconds of spectral peaks.")
            ],
            demo: .spectrum,
            demoCaption: "Build a signal on the left and watch its spectrum on the right. Each sine you add appears as its own spike.",
            quiz: [
                QuizQuestion(prompt: "What does the Fourier transform of a signal show?",
                             choices: ["Its loudness over time", "How much of each frequency it contains", "Its sample rate", "Its bit depth"], answer: 1,
                             explanation: "It decomposes a signal into its frequency components."),
                QuizQuestion(prompt: "With fs = 48 kHz and N = 1,024 samples, what's the bin spacing?",
                             choices: ["~4.7 Hz", "~23.4 Hz", "~46.9 Hz", "1,024 Hz"], answer: 2,
                             explanation: "Δf = 48,000 / 1,024 ≈ 46.9 Hz."),
                QuizQuestion(prompt: "Why is the FFT so important in practice?",
                             choices: ["It's more accurate than the DFT", "It computes the DFT in N·log N instead of N² operations", "It removes noise", "It works without sampling"], answer: 1,
                             explanation: "Same result as the DFT, dramatically faster.")
            ]),

        Lesson(
            id: "windows",
            title: "Windows and Spectral Leakage",
            summary: "Why a pure tone doesn't always look like one spike — and how to fix it.",
            blocks: [
                .text("The FFT quietly assumes the chunk you hand it repeats forever. If a tone doesn't complete a whole number of cycles in that chunk, the loop has a jump at the seam. That discontinuity smears energy into every bin: **spectral leakage**."),
                .text("The fix is a **window function** — a smooth fade-in/fade-out applied before the FFT so the chunk's ends meet at zero. Different windows trade **main-lobe width** (how sharp a peak looks) against **side-lobe level** (how far leakage spreads)."),
                .demo,
                .bullets([
                    "**Rectangular** (no window): sharpest peak, worst leakage (first side lobe ≈ −13 dB).",
                    "**Hann**: the everyday default (≈ −31 dB side lobes).",
                    "**Hamming**: lower nearest side lobe (≈ −43 dB), popular in speech.",
                    "**Blackman**: very low leakage (≈ −58 dB), wider peak — good for spotting quiet tones next to loud ones."
                ]),
                .inPractice(title: "Choosing a window in real tools",
                            body: "Analyser plug-ins and measurement software like Smaart and REW let you pick the window. Engineers hunting a faint hum under loud music use a low-leakage window; someone tuning two close notes uses one with a narrow main lobe. Every spectrogram, pitch tracker and audio codec makes this choice somewhere.")
            ],
            demo: .windowing,
            demoCaption: "Slide the tone between bins. On an exact bin it's a clean spike; between bins the rectangular window leaks everywhere. Switch windows to contain it.",
            quiz: [
                QuizQuestion(prompt: "What causes spectral leakage?",
                             choices: ["Too high a sample rate", "Analysing a chunk that doesn't hold a whole number of cycles", "Using too many bits", "Playing too loudly"], answer: 1,
                             explanation: "The implied loop has a discontinuity, spreading energy across bins."),
                QuizQuestion(prompt: "Compared with no window, a Hann window gives…",
                             choices: ["Lower side lobes, slightly wider peak", "Narrower peak, more leakage", "No change", "Higher sample rate"], answer: 0,
                             explanation: "Windowing trades main-lobe width for much lower side lobes."),
                QuizQuestion(prompt: "You need to spot a quiet tone right next to a loud one. Which is the best choice?",
                             choices: ["Rectangular", "Blackman", "No FFT at all", "A shorter FFT"], answer: 1,
                             explanation: "Blackman's very low side lobes stop the loud tone's leakage from burying the quiet one.")
            ]),

        Lesson(
            id: "spectrogram",
            title: "Spectrograms and the STFT",
            summary: "Frequency over time — the picture of sound.",
            blocks: [
                .text("A single FFT tells you *what* frequencies are present but not *when*. The **short-time Fourier transform** (STFT) slides a window along the signal, takes an FFT at each step, and stacks the results side by side. Plotted with time across, frequency up and brightness for level, that's a **spectrogram**."),
                .equation("Time resolution ≈ N / fs     Frequency resolution ≈ fs / N", caption: "You can't have both — a longer window sharpens frequency and blurs time"),
                .text("This **time–frequency trade-off** is fundamental (it's the signal-processing cousin of the uncertainty principle). Short windows show crisp drum hits but blurry pitches; long windows show clean harmonics but smeared attacks. Overlapping frames (a **hop** smaller than the window) make the picture smoother."),
                .demo,
                .inPractice(title: "Reading sound like a picture",
                            body: "Dialogue editors use spectral editors such as iZotope RX to paint out a cough, a phone ring or a chair creak that sits between words. Bird researchers identify species by spectrogram shape. Speech recognisers, including the one in your phone, start from a (mel-scaled) spectrogram.")
            ],
            demo: .spectrogram,
            demoCaption: "Pick a test signal and change the window size. Watch the sweep sharpen while the clicks smear — and the other way round.",
            quiz: [
                QuizQuestion(prompt: "What are a spectrogram's axes?",
                             choices: ["Amplitude vs. time", "Frequency vs. time, with color for level", "Phase vs. frequency", "Bits vs. samples"], answer: 1,
                             explanation: "Time across, frequency up, brightness or color for level."),
                QuizQuestion(prompt: "You lengthen the STFT window. What happens?",
                             choices: ["Better time and frequency resolution", "Better frequency resolution, worse time resolution", "Better time resolution, worse frequency resolution", "Nothing changes"], answer: 1,
                             explanation: "More samples per FFT → finer bins but each column covers more time."),
                QuizQuestion(prompt: "A dialogue editor removes a phone ring between words without touching the voice. Which tool are they most likely using?",
                             choices: ["A compressor", "A spectral (spectrogram) editor", "A dithering plug-in", "A frame-rate converter"], answer: 1,
                             explanation: "Spectral editing lets you select and attenuate a region of time AND frequency.")
            ])
    ])

    // MARK: - Module 3

    static let filtering = Module(id: "filtering", title: "Filtering", icon: "slider.horizontal.3", lessons: [
        Lesson(
            id: "convolution",
            title: "Convolution and Impulse Responses",
            summary: "One operation behind blur, echo, reverb and every linear filter.",
            blocks: [
                .text("Clap in a cathedral and you hear the clap followed by a long, decaying wash. That wash is the room's **impulse response** — its reaction to a single instantaneous click. For any **linear, time-invariant** system (a room, a speaker, an EQ, a lens blur), the impulse response tells you *everything*: the output for any input is the input **convolved** with it."),
                .equation("y[n] = Σₖ h[k] · x[n − k]", caption: "Each output sample is a weighted sum of recent inputs, weights = impulse response h"),
                .text("Read it as: *drop a scaled copy of h at every input sample and add them all up*. A short h of equal weights is a **moving average** that smooths noise. An h with a spike at a delay is an **echo**. An h recorded in a real hall is that hall's **reverb**."),
                .demo,
                .heading("The convolution theorem"),
                .text("Convolution in time equals multiplication in frequency. So a filter's spectrum (its **frequency response**) is simply the FFT of its impulse response — and long convolutions are computed fastest by FFT-multiply-inverse-FFT."),
                .equation("y = x ∗ h   ⇔   Y(f) = X(f) · H(f)"),
                .inPractice(title: "Convolution in production",
                            body: "Convolution reverbs (Altiverb, Logic's Space Designer) load impulse responses recorded in real churches, studios and car interiors — post-production uses them to make ADR dialogue sound like it was recorded on location. Guitar cab simulators are convolution with a speaker IR. In images, every blur, sharpen and edge filter is a 2-D convolution (Lesson 10).")
            ],
            demo: .convolution,
            demoCaption: "Choose a kernel (impulse response) and see what convolution does to a noisy signal. The echo kernel is easiest to hear.",
            quiz: [
                QuizQuestion(prompt: "What is an impulse response?",
                             choices: ["A system's output for a single click input", "The loudest sample in a file", "A type of window function", "A compressor setting"], answer: 0,
                             explanation: "It's the system's reaction to an ideal impulse — and it fully characterises an LTI system."),
                QuizQuestion(prompt: "Convolving with a longer moving-average kernel makes the signal…",
                             choices: ["Noisier", "Smoother, with less high-frequency detail", "Louder", "Higher-pitched"], answer: 1,
                             explanation: "Averaging more samples is a stronger low-pass filter."),
                QuizQuestion(prompt: "Convolution in the time domain corresponds to what in the frequency domain?",
                             choices: ["Addition", "Multiplication", "Differentiation", "Nothing simple"], answer: 1,
                             explanation: "The convolution theorem: Y(f) = X(f)·H(f).")
            ]),

        Lesson(
            id: "filters",
            title: "FIR and IIR Filters and EQ",
            summary: "Shaping the spectrum: low-pass, high-pass, band-pass, peaking EQ.",
            blocks: [
                .text("A **filter** changes the balance of frequencies. There are two families:"),
                .bullets([
                    "**FIR** (finite impulse response): output = weighted sum of inputs only. Always stable, can have perfectly linear phase, but needs many taps for steep slopes.",
                    "**IIR** (infinite impulse response): output also feeds back past *outputs*. Very efficient — a few multiplies give a steep filter — but phase is non-linear and poor design can go unstable."
                ]),
                .text("The workhorse of audio is the **biquad**, a 2nd-order IIR with two zeros and two poles. Every parametric EQ band in your DAW is a biquad, typically from Robert Bristow-Johnson's *Audio EQ Cookbook*."),
                .equation("y[n] = b₀x[n] + b₁x[n−1] + b₂x[n−2] − a₁y[n−1] − a₂y[n−2]"),
                .text("The controls map onto the maths: **cutoff/centre frequency** sets where the filter acts, **Q** sets how narrow the region is (and how resonant the corner), **gain** sets how much a peaking band boosts or cuts."),
                .demo,
                .inPractice(title: "Filters everywhere",
                            body: "A high-pass at 80 Hz on dialogue removes traffic rumble and handling noise. A notch at 50/60 Hz kills mains hum. A low-pass is the anti-aliasing filter in every converter. Synthesizers sweep a resonant low-pass for the classic 'wah'. Crossovers in speakers split bands to woofer and tweeter. Camera sensors carry an optical low-pass filter for the same anti-aliasing job.")
            ],
            demo: .filterDesigner,
            demoCaption: "Design a biquad and see its frequency response. Then run it on noise or a sawtooth and listen.",
            quiz: [
                QuizQuestion(prompt: "Which filter removes low-frequency rumble from dialogue?",
                             choices: ["Low-pass", "High-pass", "Notch at 10 kHz", "All-pass"], answer: 1,
                             explanation: "A high-pass passes highs and removes lows."),
                QuizQuestion(prompt: "What distinguishes an IIR filter from an FIR filter?",
                             choices: ["IIR uses feedback of past outputs", "IIR only works on images", "FIR is always unstable", "FIR has no coefficients"], answer: 0,
                             explanation: "The feedback terms (a₁, a₂) make the impulse response ring on forever."),
                QuizQuestion(prompt: "Raising a peaking EQ band's Q does what?",
                             choices: ["Makes the affected region narrower", "Makes it wider", "Raises the sample rate", "Changes its centre frequency"], answer: 0,
                             explanation: "Q is centre frequency ÷ bandwidth; higher Q = narrower band.")
            ]),

        Lesson(
            id: "dynamics",
            title: "Dynamics: Compressors and Limiters",
            summary: "Turning the volume knob automatically, thousands of times a second.",
            blocks: [
                .text("Filters change *frequency* balance. **Dynamics processors** change *level* over time. A **compressor** watches the signal's level and turns it down when it rises above a **threshold**, by an amount set by the **ratio**."),
                .equation("out = T + (in − T) / R     (when in > T, all in dB)", caption: "Ratio 4:1 → 4 dB over the threshold comes out as 1 dB over"),
                .bullets([
                    "**Attack** — how quickly gain reduction kicks in. Slow attack lets transients (the 'snap' of a drum) through.",
                    "**Release** — how quickly it recovers once the level falls.",
                    "**Make-up gain** — raises the whole result back up, so the quiet parts end up louder than before.",
                    "A **limiter** is a compressor with a very high ratio and fast attack: a ceiling nothing crosses."
                ]),
                .text("Under the hood it's an **envelope follower** (a one-pole low-pass on the rectified signal, with different coefficients for attack and release) driving a gain computer. Note it's *non-linear* — it can't be described by an impulse response."),
                .demo,
                .inPractice(title: "Why everything you hear is compressed",
                            body: "Broadcast and streaming platforms normalise to a loudness target (measured in LUFS — often around −14 LUFS for music streaming and −23/−24 LUFS for broadcast TV), so mixes are compressed to sit consistently. Film mixers ride dialogue with compression so whispers survive a noisy cinema, and a **limiter** on the master protects against overs. A **de-esser** is a compressor that only listens to the 'sss' band; **sidechain** compression ducks music under a voice-over.")
            ],
            demo: .compressor,
            demoCaption: "A drum loop with loud and quiet hits. Lower the threshold and raise the ratio to even them out; listen before and after.",
            quiz: [
                QuizQuestion(prompt: "With a −20 dB threshold and 4:1 ratio, an input at −8 dB comes out at…",
                             choices: ["−8 dB", "−17 dB", "−20 dB", "−12 dB"], answer: 1,
                             explanation: "12 dB over threshold ÷ 4 = 3 dB over → −17 dB."),
                QuizQuestion(prompt: "A slow attack time lets what through?",
                             choices: ["Low frequencies", "Initial transients", "Background noise only", "Nothing"], answer: 1,
                             explanation: "The gain reduction lags behind, so the first few ms of a hit pass untouched."),
                QuizQuestion(prompt: "Why is a compressor not described by an impulse response?",
                             choices: ["It's non-linear — its gain depends on the input level", "It only works in stereo", "It has no output", "It's an FIR filter"], answer: 0,
                             explanation: "Impulse responses characterise linear systems; a compressor's behaviour changes with level.")
            ])
    ])

    // MARK: - Module 4

    static let picture = Module(id: "picture", title: "Images, Video and Film", icon: "film", lessons: [
        Lesson(
            id: "images",
            title: "Images as 2-D Signals",
            summary: "Blur, sharpen and edge detection are convolution in two dimensions.",
            blocks: [
                .text("An image is a signal over *space*: brightness as a function of (x, y). Everything from Module 3 carries over. **Spatial frequency** measures how fast brightness changes across the frame — smooth skies are low frequency, fine fabric, hair and text are high frequency."),
                .text("2-D filters are small grids of weights called **kernels**. Each output pixel is the weighted sum of its neighbourhood:"),
                .equation("y[i, j] = Σₘ Σₙ h[m, n] · x[i − m, j − n]"),
                .bullets([
                    "**Box / Gaussian blur** — low-pass filters. A Gaussian looks natural because it has no hard edges of its own.",
                    "**Sharpen** — boosts the centre and subtracts the neighbours: a high-frequency boost (an 'unsharp mask' is original + amount × (original − blur)).",
                    "**Sobel** — approximates the brightness gradient; large values mark **edges**, the first step of Canny edge detection and many computer-vision pipelines."
                ]),
                .demo,
                .inPractice(title: "In cameras, grading suites and VFX",
                            body: "Every camera runs sharpening and noise reduction (low-pass filtering) in its image pipeline. Colourists use blur for skin softening and unsharp-mask for detail. Compositors use edge detection for mattes and to drive rotoscoping; depth-of-field and bokeh effects are convolution with a disc-shaped kernel. Downscaling 4K to HD without a low-pass first creates moiré — 2-D aliasing.")
            ],
            demo: .imageKernels,
            demoCaption: "Apply kernels to a test card (or your own photo). Look at the fine stripes and text — that's where the high frequencies live.",
            quiz: [
                QuizQuestion(prompt: "A Gaussian blur is which kind of filter?",
                             choices: ["High-pass", "Low-pass", "Band-stop", "Non-linear"], answer: 1,
                             explanation: "It averages neighbours, removing fine (high-frequency) detail."),
                QuizQuestion(prompt: "What does a Sobel kernel detect?",
                             choices: ["Color", "Brightness gradients (edges)", "Noise level", "Frame rate"], answer: 1,
                             explanation: "Sobel approximates the derivative of brightness, which is large at edges."),
                QuizQuestion(prompt: "Which image content has the highest spatial frequencies?",
                             choices: ["A clear blue sky", "A slow vignette", "Fine text and fabric patterns", "A solid gray wall"], answer: 2,
                             explanation: "Rapid changes in brightness over short distances = high spatial frequency.")
            ]),

        Lesson(
            id: "jpeg",
            title: "The DCT and How JPEG and Video Compress",
            summary: "Throw away the frequencies nobody will miss.",
            blocks: [
                .text("Uncompressed 4K video at 24 fps is over 4 Gbit/s. Streaming services send roughly a hundredth of that. The trick is the **discrete cosine transform** (DCT), a Fourier cousin that turns each small block of pixels into a grid of spatial-frequency coefficients."),
                .equation("F[u, v] = ¼ C(u)C(v) Σₓ Σᵧ f[x, y] cos((2x+1)uπ/16) cos((2y+1)vπ/16)", caption: "JPEG's 8×8 DCT-II; u, v = horizontal and vertical frequency"),
                .text("For natural images, almost all the energy lands in a few low-frequency coefficients. JPEG then **quantizes** each coefficient — dividing by a table that's coarse for high frequencies (where the eye is least sensitive) — and most high-frequency values round to **zero**. Long runs of zeros compress beautifully with entropy coding."),
                .bullets([
                    "Quantization is where information is lost — the DCT itself is perfectly reversible.",
                    "Too-aggressive quantization shows as **blocking** (visible 8×8 squares) and **ringing** near sharp edges.",
                    "Color is usually stored at lower resolution than brightness (**chroma subsampling**, e.g. 4:2:0), because we see detail mainly in luminance."
                ]),
                .demo,
                .inPractice(title: "From JPEG to H.264, HEVC and ProRes",
                            body: "Video codecs reuse this idea per frame and add **motion compensation**: predict each block from a previous frame, then DCT-code only the error. H.264 uses 4×4 and 8×8 integer transforms, HEVC up to 32×32. ProRes and DNxHR, the editing codecs, are intra-frame DCT codecs that keep every frame independent for easy scrubbing. Audio codecs (MP3, AAC) use the MDCT, a close relative.")
            ],
            demo: .jpeg,
            demoCaption: "Lower the quality and watch blocks and ringing appear — and the share of coefficients that became zero (free to compress) climb.",
            quiz: [
                QuizQuestion(prompt: "In JPEG, where is information actually lost?",
                             choices: ["The DCT", "Quantizing the DCT coefficients", "Entropy coding", "Reading the file"], answer: 1,
                             explanation: "The DCT and entropy coding are lossless; rounding coefficients is not."),
                QuizQuestion(prompt: "Why does JPEG quantize high-frequency coefficients more coarsely?",
                             choices: ["They contain more energy", "The eye is less sensitive to fine detail errors", "They're computed less accurately", "To increase resolution"], answer: 1,
                             explanation: "Perceptual weighting: spend bits where the eye notices."),
                QuizQuestion(prompt: "What extra trick do video codecs add on top of per-block DCT coding?",
                             choices: ["Dithering", "Motion-compensated prediction from other frames", "Higher bit depth", "Sobel filtering"], answer: 1,
                             explanation: "Most of a frame is predictable from its neighbours; only the residual is coded.")
            ]),

        Lesson(
            id: "film",
            title: "Frame Rates, Shutter and Motion",
            summary: "Film is sampling in time — and the shutter is its anti-aliasing filter.",
            blocks: [
                .text("A movie camera samples the world in time: **24 frames per second** for cinema, 25 for PAL regions, 30/60 for much of TV and online video. Everything from Lesson 2 applies — fast periodic motion above half the frame rate **aliases**."),
                .text("The **shutter** decides how long each frame is exposed. Cinematographers describe it as a **shutter angle**, from the spinning-disc shutters of film cameras: 360° means the shutter is open for the whole frame interval."),
                .equation("exposure time = (shutter angle / 360°) × (1 / fps)", caption: "The cinema standard: 180° at 24 fps → 1/48 s"),
                .text("Exposing over an interval *averages* motion — a box filter in time. That **motion blur** is a temporal low-pass filter: it softens the strobing and aliasing that a pure instantaneous sample would produce. Too little (a 45° shutter, as in the battle in *Saving Private Ryan*) gives a jittery, staccato look; too much smears everything."),
                .demo,
                .heading("Flicker and frame-rate conversion"),
                .bullets([
                    "Mains-powered lights flicker at 100 or 120 Hz. Shoot with the wrong shutter speed and that aliases into slow visible pulsing — why crews in 50 Hz countries shoot at 1/50 s or 1/100 s.",
                    "Converting 24 fps to 60 Hz TV uses **3:2 pulldown** (alternately showing frames 3 and 2 fields long), which adds judder.",
                    "Motion-interpolation ('smooth motion' on TVs) estimates in-between frames — the 'soap-opera effect' many filmmakers dislike."
                ]),
                .inPractice(title: "Decisions on a real shoot",
                            body: "A DP shooting a car commercial watches the wheels: at certain speeds they freeze or spin backwards, so they adjust speed, frame rate or add blur in post. Shooting a computer monitor or LED wall, they sync shutter to the screen's refresh. Slow-motion at 120 fps needs short shutters and lots of light, because the exposure per frame shrinks.")
            ],
            demo: .frameRate,
            demoCaption: "A spinning wheel filmed at the frame rate and shutter angle you choose. Find speeds where it freezes or turns backwards, then widen the shutter.",
            quiz: [
                QuizQuestion(prompt: "At 24 fps with a 180° shutter, what's the exposure time?",
                             choices: ["1/24 s", "1/48 s", "1/180 s", "1/360 s"], answer: 1,
                             explanation: "(180/360) × 1/24 = 1/48 s."),
                QuizQuestion(prompt: "Motion blur acts like what kind of filter?",
                             choices: ["A temporal low-pass filter", "A high-pass filter", "A notch filter", "A quantizer"], answer: 0,
                             explanation: "Averaging over the exposure interval removes fast temporal changes."),
                QuizQuestion(prompt: "A wheel with 8 identical spokes spins at exactly 3 revolutions per second, filmed at 24 fps. What does it look like?",
                             choices: ["Spinning forward normally", "Frozen", "Spinning backwards fast", "Invisible"], answer: 1,
                             explanation: "Each frame it turns 3/24 = 1/8 revolution — exactly one spoke spacing — so every frame looks identical.")
            ])
    ])
}
