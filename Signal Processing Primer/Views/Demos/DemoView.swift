import SwiftUI

/// Routes a lesson's `DemoKind` to its interactive view.
struct DemoView: View {
    let kind: DemoKind

    var body: some View {
        switch kind {
        case .sineMixer:      SineMixerDemo()
        case .aliasing:       AliasingDemo()
        case .quantization:   QuantizationDemo()
        case .spectrum:       SpectrumDemo()
        case .windowing:      WindowingDemo()
        case .spectrogram:    SpectrogramDemo()
        case .convolution:    ConvolutionDemo()
        case .filterDesigner: FilterDesignerDemo()
        case .compressor:     CompressorDemo()
        case .imageKernels:   ImageKernelsDemo()
        case .jpeg:           JPEGDemo()
        case .frameRate:      FrameRateDemo()
        }
    }
}

/// Shared helpers for audio demos.
enum DemoAudio {
    static let fs = TonePlayer.sampleRate

    static var toneSeconds: Double {
        let v = UserDefaults.standard.double(forKey: Prefs.toneSeconds)
        return v > 0 ? v : 1.5
    }
    static var toneCount: Int { Int(fs * toneSeconds) }

    static func formatHz(_ f: Double) -> String {
        f >= 1000 ? String(format: "%.2f kHz", f / 1000) : String(format: "%.0f Hz", f)
    }
}
