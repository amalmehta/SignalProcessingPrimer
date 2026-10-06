import AVFoundation

/// Plays short mono buffers through the default output. One shared instance; starting a new
/// sound stops the previous one so demos never pile up.
@MainActor
final class TonePlayer: ObservableObject {
    static let shared = TonePlayer()
    static let sampleRate: Double = 44_100

    @Published private(set) var isPlaying = false
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: TonePlayer.sampleRate, channels: 1)!
    private var token = 0

    private init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// `samples` are expected at `TonePlayer.sampleRate`, nominally in -1...1.
    func play(_ samples: [Float], volume: Double) {
        stop()
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = buffer.frameCapacity
        let fade = min(441, samples.count / 2)                 // 10 ms fades avoid clicks
        let dst = buffer.floatChannelData![0]
        for i in samples.indices {
            let g = Float(min(1, Double(min(i, samples.count - 1 - i)) / Double(max(fade, 1))))
            dst[i] = max(-1, min(1, samples[i])) * g
        }
        do {
            if !engine.isRunning { try engine.start() }
        } catch { return }
        engine.mainMixerNode.outputVolume = Float(volume)
        token += 1
        let current = token
        node.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in if self?.token == current { self?.isPlaying = false } }
        }
        node.play()
        isPlaying = true
    }

    func stop() {
        token += 1
        node.stop()
        isPlaying = false
    }
}
