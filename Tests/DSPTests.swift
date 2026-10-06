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
