import AVFoundation
import Combine
import os

/// Sample-accurate metronome. Pre-renders one click buffer at startup and
/// schedules each beat against the audio engine's `sampleTime` clock so that
/// long sessions never drift relative to the looper.
final class Metronome: ObservableObject, @unchecked Sendable {
    private unowned let host: SynthEngine
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat

    private var clickBuffer: AVAudioPCMBuffer!
    private var accentBuffer: AVAudioPCMBuffer!

    private var beatIndex: Int = 0
    private var beatsPerBar: Int = 4
    private var nextBeatSampleTime: AVAudioFramePosition = 0
    private var beatSamples: AVAudioFramePosition = 0

    @Published var bpm: Double = 90 {
        didSet { recomputeBeatSamples() }
    }
    @Published var meter: Int = 4 {
        didSet { beatsPerBar = max(1, meter); recomputeBeatSamples() }
    }
    @Published private(set) var isRunning: Bool = false
    @Published var hapticFeedback: Bool = true

    /// Fired on every beat, on the main actor. Useful for UI flashes.
    var onBeat: (Int) -> Void = { _ in }

    init(host: SynthEngine) {
        self.host = host
        self.format = AVAudioFormat(standardFormatWithSampleRate: host.sampleRate, channels: 2)!
        host.engine.attach(player)
        host.engine.connect(player, to: host.engine.mainMixerNode, format: format)
        clickBuffer = renderClick(frequency: 1200, durationMs: 35, gain: 0.85)
        accentBuffer = renderClick(frequency: 1800, durationMs: 40, gain: 1.0)
        // Keep the click hot at the player so it cuts through everything else
        // playing in the same mixer (synth + bass + drums).
        player.volume = 1.0
        recomputeBeatSamples()
    }

    func start() {
        guard !isRunning, host.engine.isRunning else { return }
        beatIndex = 0
        let now = player.lastRenderTime?.sampleTime ?? 0
        nextBeatSampleTime = now + AVAudioFramePosition(host.sampleRate * 0.05)
        if !player.isPlaying { player.play() }
        scheduleAhead(beats: 8)
        isRunning = true
    }

    /// Stop and immediately restart from beat 1 — used by the looper so the
    /// user always hears exactly one clean bar of clicks before recording.
    func restart() {
        player.stop()
        beatIndex = 0
        let now = host.engine.outputNode.lastRenderTime?.sampleTime ?? 0
        nextBeatSampleTime = now + AVAudioFramePosition(host.sampleRate * 0.05)
        if !player.isPlaying { player.play() }
        scheduleAhead(beats: 8)
        isRunning = true
    }

    func stop() {
        player.stop()
        isRunning = false
        beatIndex = 0
    }

    /// Returns the next bar boundary (sample time) AFTER `from`, useful for
    /// the looper to align punch-in to a beat 1.
    func nextBarSampleTime(after from: AVAudioFramePosition) -> AVAudioFramePosition {
        let barSamples = AVAudioFramePosition(beatsPerBar) * beatSamples
        let delta = nextBeatSampleTime - from
        // beats remaining until the next bar starts on beat 1
        let beatsUntilBar = (beatsPerBar - (beatIndex % beatsPerBar)) % beatsPerBar
        let firstUpcomingBarBeatTime = nextBeatSampleTime + AVAudioFramePosition(beatsUntilBar) * beatSamples
        _ = delta
        _ = barSamples
        return firstUpcomingBarBeatTime
    }

    /// Sample length of one beat at the current BPM.
    var samplesPerBeat: AVAudioFramePosition { beatSamples }

    // MARK: - Internals

    private func recomputeBeatSamples() {
        beatSamples = AVAudioFramePosition(60.0 / bpm * host.sampleRate)
    }

    /// Schedules `beats` future clicks. Re-invoked from the completion callback.
    private func scheduleAhead(beats: Int) {
        for _ in 0..<beats {
            let isAccent = (beatIndex % beatsPerBar) == 0
            let buffer = isAccent ? accentBuffer! : clickBuffer!
            let sampleTime = nextBeatSampleTime
            let when = AVAudioTime(sampleTime: sampleTime, atRate: host.sampleRate)
            let beat = beatIndex
            player.scheduleBuffer(buffer, at: when, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.onBeat(beat)
                    if self.hapticFeedback {
                        HapticEngine.shared.fire(.beat)
                    }
                }
                // Schedule one more so we always have ~8 beats queued.
                self.scheduleAhead(beats: 1)
            }
            beatIndex += 1
            nextBeatSampleTime += beatSamples
        }
    }

    /// Generate a short percussive blip via additive sine + exponential decay.
    private func renderClick(frequency: Double, durationMs: Double, gain: Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(host.sampleRate * (durationMs / 1000))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let leftPtr = buffer.floatChannelData![0]
        let rightPtr = buffer.floatChannelData![1]
        let omega = 2 * Double.pi * frequency / host.sampleRate
        let decayTau = (durationMs / 1000) / 4
        for i in 0..<Int(frames) {
            let t = Double(i) / host.sampleRate
            let env = Float(exp(-t / decayTau))
            let s = Float(sin(omega * Double(i))) * env * gain
            leftPtr[i] = s
            rightPtr[i] = s
        }
        return buffer
    }
}
