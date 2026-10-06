import XCTest
@testable import Signal_Processing_Primer

final class DSPTests: XCTestCase {
    let fs = 44_100.0

    func testAliasedFrequencyFoldsAboutNyquist() {
        XCTAssertEqual(DSP.aliasedFrequency(1000, sampleRate: 8000), 1000, accuracy: 1e-9)
        XCTAssertEqual(DSP.aliasedFrequency(30000, sampleRate: 44100), 14100, accuracy: 1e-9)
        XCTAssertEqual(DSP.aliasedFrequency(8000, sampleRate: 8000), 0, accuracy: 1e-9)
        XCTAssertEqual(DSP.aliasedFrequency(9000, sampleRate: 8000), 1000, accuracy: 1e-9)
    }

    func testFFTPeakLandsOnTheRightBinWithCorrectAmplitude() {
        let n = 4096, bin = 100
        let x = DSP.tone(frequency: Double(bin) * fs / Double(n), amplitude: 0.5, sampleRate: fs, count: n)
        let mags = DSP.magnitudeSpectrum(x)
        XCTAssertEqual(mags.firstIndex(of: mags.max()!), bin)
        XCTAssertEqual(mags[bin], 0.5, accuracy: 1e-3)
    }

    func testWindowReducesLeakageForBetweenBinTone() {
        let n = 128
        let x = DSP.tone(frequency: 10.5, sampleRate: Double(n), count: n)
        let rect = DSP.decibels(DSP.magnitudeSpectrum(x, window: .rectangular))
        let hann = DSP.decibels(DSP.magnitudeSpectrum(x, window: .hann))
        XCTAssertLessThan(hann[50], rect[50] - 30, "Hann should leak far less 40 bins away")
    }

    func testQuantizationSNRRisesAboutSixDBPerBit() {
        let x = DSP.tone(frequency: 997, amplitude: 0.9, sampleRate: fs, count: 16384)
        let s8 = DSP.snr(reference: x, processed: DSP.quantize(x, bits: 8))
        let s12 = DSP.snr(reference: x, processed: DSP.quantize(x, bits: 12))
        XCTAssertEqual(s12 - s8, 24, accuracy: 3)
        XCTAssertEqual(s8, 6.02 * 8 + 1.76, accuracy: 3)
    }

    func testConvolutionMatchesDefinition() {
        let x: [Float] = [1, 2, 3, 4, 5], h: [Float] = [1, 0.5, 0.25]
        // y[n] = x[n] + 0.5 x[n-1] + 0.25 x[n-2]
        XCTAssertEqual(DSP.convolve(x, kernel: h), [1, 2.5, 4.25, 6, 7.75])
    }

    func testSparseConvolutionEqualsDenseForEcho() {
        let x = DSP.noise(count: 300)
        let dense = DSP.convolve(x, kernel: DSP.echoKernel(delay: 40, gain: 0.5))
        let sparse = DSP.sparseConvolve(x, taps: [(0, 1), (40, 0.5)])
        for (a, b) in zip(dense, sparse) { XCTAssertEqual(a, b, accuracy: 1e-5) }
    }

    func testBiquadLowPassResponse() {
        let lp = DSP.Biquad(.lowPass, cutoff: 1000, q: 0.7071, sampleRate: fs)
        XCTAssertEqual(lp.responseDB(at: 20, sampleRate: fs), 0, accuracy: 0.1)
        XCTAssertEqual(lp.responseDB(at: 1000, sampleRate: fs), -3, accuracy: 0.2)
        XCTAssertLessThan(lp.responseDB(at: 10000, sampleRate: fs), -38)   // 2nd order ≈ −40 dB/decade
    }

    func testBiquadProcessingAttenuatesAboveCutoff() {
        let hp = DSP.Biquad(.highPass, cutoff: 2000, q: 0.7071, sampleRate: fs)
        let low = DSP.tone(frequency: 100, sampleRate: fs, count: 8192)
        let out = hp.process(low)
        let rmsIn = sqrt(low.map { $0 * $0 }.reduce(0, +) / Float(low.count))
        let rmsOut = sqrt(out[2000...].map { $0 * $0 }.reduce(0, +) / Float(out.count - 2000))
        XCTAssertLessThan(rmsOut, rmsIn * 0.01)
    }

    func testPeakEQGainAtCentre() {
        let eq = DSP.Biquad(.peak, cutoff: 3000, q: 1, gainDB: 9, sampleRate: fs)
        XCTAssertEqual(eq.responseDB(at: 3000, sampleRate: fs), 9, accuracy: 0.05)
    }

    func testCompressorStaticCurve() {
        let c = DSP.Compressor(thresholdDB: -20, ratio: 4, attackMs: 5, releaseMs: 100)
        XCTAssertEqual(c.outputLevel(forInput: -30), -30)
        XCTAssertEqual(c.outputLevel(forInput: -8), -17)       // matches the lesson's quiz
    }

    func testCompressorReducesPeakToQuietRatio() {
        let x = DSP.drumLoop(sampleRate: fs, seconds: 1)
        let c = DSP.Compressor(thresholdDB: -24, ratio: 8, attackMs: 1, releaseMs: 80)
        let (y, gr) = c.process(x, sampleRate: fs)
        XCTAssertLessThan(gr.min()!, -6)
        XCTAssertLessThan(DSP.envelope(y, blocks: 4).max()!, DSP.envelope(x, blocks: 4).max()!)
    }

    func testDCTRoundTripIsLossless() {
        let block = (0..<64).map { Float(($0 * 37) % 255) - 128 }
        let back = ImageDSP.idct8x8(ImageDSP.dct8x8(block))
        for (a, b) in zip(block, back) { XCTAssertEqual(a, b, accuracy: 1e-3) }
    }

    func testDCTOfFlatBlockIsAllDC() {
        let c = ImageDSP.dct8x8([Float](repeating: 10, count: 64))
        XCTAssertEqual(c[0], 80, accuracy: 1e-3)                   // 8 × mean for orthonormal 8×8
        XCTAssertEqual(c.dropFirst().map(abs).max()!, 0, accuracy: 1e-4)
    }

    func testJPEGLowerQualityMeansMoreZerosAndLowerPSNR() {
        let img = ImageDSP.testCard(size: 128)
        let hi = ImageDSP.jpegRoundTrip(img, quality: 90), lo = ImageDSP.jpegRoundTrip(img, quality: 10)
        XCTAssertGreaterThan(lo.zeroFraction, hi.zeroFraction)
        XCTAssertGreaterThan(hi.psnr, lo.psnr)
        XCTAssertGreaterThan(hi.psnr, 30)
    }

    func testImageBlurPreservesFlatRegionsAndSobelFindsEdges() {
        let flat = GrayImage(width: 16, height: 16, pixels: [Float](repeating: 0.5, count: 256))
        let blurred = ImageDSP.apply(.gaussian, strength: 2, to: flat)
        for p in blurred.pixels { XCTAssertEqual(p, 0.5, accuracy: 1e-4) }

        var step = flat
        for y in 0..<16 { for x in 8..<16 { step.pixels[y * 16 + x] = 1 } }
        let edges = ImageDSP.apply(.edgeMagnitude, strength: 1, to: step)
        XCTAssertGreaterThan(edges[8, 8], 0.5)
        XCTAssertEqual(edges[2, 8], 0, accuracy: 1e-5)
    }

    func testSpectrogramShapeAndChirpRises() {
        let x = DSP.chirp(from: 500, to: 8000, sampleRate: fs, count: 44100)
        let cols = DSP.spectrogram(x, frameSize: 1024, hop: 512)
        XCTAssertEqual(cols.first?.count, 513)
        let firstPeak = cols.first!.firstIndex(of: cols.first!.max()!)!
        let lastPeak = cols.last!.firstIndex(of: cols.last!.max()!)!
        XCTAssertGreaterThan(lastPeak, firstPeak * 5)
    }
}

final class ColourTests: XCTestCase {
    func testTransferFunctionsInvert() {
        for t in ColourDSP.Transfer.allCases {
            for l in stride(from: 0.0, through: 1, by: 0.05) {
                XCTAssertEqual(t.decode(t.encode(l)), l, accuracy: 1e-9, "\(t.rawValue) at \(l)")
            }
        }
        XCTAssertEqual(ColourDSP.Transfer.sRGB.encode(0.1), 0.349, accuracy: 0.001)
    }

    func testGammaGivesShadowsMoreCodes() {
        // The lesson's numbers: 8-bit linear ≈ 26 codes for the darkest 10%; sRGB ≈ 90.
        XCTAssertEqual(ColourDSP.codesBelow(0.1, bits: 8, transfer: .linear), 26)
        XCTAssertEqual(ColourDSP.codesBelow(0.1, bits: 8, transfer: .sRGB), 90)
        let linear = Set(ColourDSP.storedRamp(count: 1000, bits: 5, transfer: .linear).filter { $0 < 0.1 })
        let srgb = Set(ColourDSP.storedRamp(count: 1000, bits: 5, transfer: .sRGB).filter { $0 < 0.1 })
        XCTAssertGreaterThan(srgb.count, linear.count * 2)
    }

    func testYCbCrRoundTripAndLumaWeights() {
        let (y, cb, cr) = ColourDSP.toYCbCr(r: 1, g: 1, b: 1)
        XCTAssertEqual(y, 1, accuracy: 1e-6); XCTAssertEqual(cb, 0, accuracy: 1e-6); XCTAssertEqual(cr, 0, accuracy: 1e-6)
        let c = ColourDSP.toYCbCr(r: 0.8, g: 0.3, b: 0.1), back = ColourDSP.toRGB(y: c.y, cb: c.cb, cr: c.cr)
        XCTAssertEqual(back.r, 0.8, accuracy: 1e-4); XCTAssertEqual(back.g, 0.3, accuracy: 1e-4); XCTAssertEqual(back.b, 0.1, accuracy: 1e-4)
    }

    func testSubsamplingKeepsLumaAndLosesChromaDetail() {
        let card = ColourDSP.colourCard(size: 64)
        let full = ColourDSP.subsample(card, .s444), quarter = ColourDSP.subsample(card, .s420)
        XCTAssertGreaterThan(ColourDSP.psnr(card, full.image), 40, "4:4:4 is (nearly) lossless")
        XCTAssertLessThan(ColourDSP.psnr(card, quarter.image), ColourDSP.psnr(card, full.image))
        XCTAssertEqual(full.y, quarter.y, "luma is never subsampled")
        XCTAssertEqual(ColourDSP.Subsampling.s420.samplesPerPixel, 1.5)
        XCTAssertEqual(ColourDSP.Subsampling.s422.samplesPerPixel, 2)
    }
}

final class WhiteBalanceTests: XCTestCase {
    func testIlluminantIsNeutralAtReferenceAndWarmerWhenLower() {
        let ref = WhiteBalance.illuminant(6500)
        XCTAssertEqual(ref.r, 1, accuracy: 1e-9); XCTAssertEqual(ref.b, 1, accuracy: 1e-9)
        let tungsten = WhiteBalance.illuminant(3200), shade = WhiteBalance.illuminant(9000)
        XCTAssertGreaterThan(tungsten.r, 1); XCTAssertLessThan(tungsten.b, 0.6)
        XCTAssertLessThan(shade.r, 1); XCTAssertGreaterThan(shade.b, 1)
    }

    func testMatchingCameraSettingRestoresNeutrals() {
        let chart = WhiteBalance.checkerChart()
        let shot = WhiteBalance.capture(chart, lightKelvin: 3200)
        let p = WhiteBalance.grayPatchCentre()
        let raw = WhiteBalance.sample(shot, x: p.x, y: p.y)
        XCTAssertGreaterThan(raw.r, raw.b * 1.5, "tungsten light makes the gray patch orange")
        let fixed = WhiteBalance.correct(shot, gains: WhiteBalance.gains(forKelvin: 3200))
        let c = WhiteBalance.sample(fixed, x: p.x, y: p.y)
        XCTAssertEqual(c.r / c.g, 1, accuracy: 0.02); XCTAssertEqual(c.b / c.g, 1, accuracy: 0.02)
    }

    func testEyedropperAndEstimateRecoverTheLight() {
        let shot = WhiteBalance.capture(WhiteBalance.checkerChart(), lightKelvin: 4000)
        let p = WhiteBalance.grayPatchCentre()
        let picked = WhiteBalance.sample(shot, x: p.x, y: p.y)
        XCTAssertEqual(WhiteBalance.estimateKelvin(picked), 4000, accuracy: 100)
        let fixed = WhiteBalance.correct(shot, gains: WhiteBalance.gains(neutral: picked))
        let c = WhiteBalance.sample(fixed, x: p.x, y: p.y)
        XCTAssertEqual(c.r / c.g, 1, accuracy: 0.02); XCTAssertEqual(c.b / c.g, 1, accuracy: 0.02)
    }

    func testGrayWorldOnANeutralSceneIsExact() {
        var gray = WhiteBalance.checkerChart()
        gray.g = gray.r; gray.b = gray.r          // a scene with no colour at all
        let est = WhiteBalance.estimateKelvin(WhiteBalance.grayWorld(WhiteBalance.capture(gray, lightKelvin: 5000)))
        XCTAssertEqual(est, 5000, accuracy: 100)
    }
}

final class TintTests: XCTestCase {
    func testTintMovesTowardsGreenOrMagenta() {
        let plain = WhiteBalance.illuminant(5000), green = WhiteBalance.illuminant(5000, tint: -50), magenta = WhiteBalance.illuminant(5000, tint: 50)
        XCTAssertEqual(WhiteBalance.illuminant(5000, tint: 0), plain)
        // Green is normalised to 1, so a greener light has smaller red and blue ratios.
        XCTAssertLessThan(green.r, plain.r); XCTAssertLessThan(green.b, plain.b)
        XCTAssertGreaterThan(magenta.r, plain.r); XCTAssertGreaterThan(magenta.b, plain.b)
    }

    func testCameraTintCancelsLightTintAndEstimateRecoversBoth() {
        let p = WhiteBalance.grayPatchCentre()
        let shot = WhiteBalance.capture(WhiteBalance.checkerChart(), lightKelvin: 4000, tint: -30)
        let fixed = WhiteBalance.correct(shot, gains: WhiteBalance.gains(forKelvin: 4000, tint: -30))
        let c = WhiteBalance.sample(fixed, x: p.x, y: p.y)
        XCTAssertEqual(c.r / c.g, 1, accuracy: 0.02); XCTAssertEqual(c.b / c.g, 1, accuracy: 0.02)
        let est = WhiteBalance.estimate(WhiteBalance.sample(shot, x: p.x, y: p.y))
        XCTAssertEqual(est.kelvin, 4000, accuracy: 100); XCTAssertEqual(est.tint, -30, accuracy: 3)
    }
}
