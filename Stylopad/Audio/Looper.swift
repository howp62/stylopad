import AVFoundation
import Combine
import os

/// 4-track loop station with sample-accurate playback.
///
/// Lifecycle for a track:
/// `.idle` → tap recordToggle → `.countIn` (1 bar of metronome only) →
/// `.recording` (captures exactly `bars * beatsPerBar * samplesPerBeat`) →
/// `.playing` (looped via scheduleBuffer .loops, sample-time anchored).
@MainActor
final class Looper: ObservableObject {
    unowned let host: SynthEngine
    unowned let metronome: Metronome

    enum TrackState: Equatable {
        case empty
        case armed
        case countIn(beatsLeft: Int)
        case recording(framesCaptured: Int, totalFrames: Int)
        case playing
        case overdubbing
        case muted
    }

    final class Track: ObservableObject, Identifiable {
        let id: Int
        let player: AVAudioPlayerNode
        @Published var state: TrackState = .empty
        var buffer: AVAudioPCMBuffer? = nil
        var startSampleTime: AVAudioFramePosition = 0
        init(id: Int, player: AVAudioPlayerNode) { self.id = id; self.player = player }
    }

    @Published private(set) var tracks: [Track] = []
    @Published var bars: Int = 2
    @Published var selectedTrack: Int = 0

    /// Audio-thread-safe shared snapshot. Updated by main, read by tap callback.
    private final class RecordingState: @unchecked Sendable {
        let lock = OSAllocatedUnfairLock<Snapshot>(initialState: Snapshot())
        struct Snapshot {
            var trackIndex: Int = -1
            var ringFrames: Int = 0
            var ringBuffer: AVAudioPCMBuffer? = nil
            var captureStartSampleTime: AVAudioFramePosition = 0
            var framesCaptured: Int = 0
            var active: Bool = false
        }
    }

    private let recState = RecordingState()
    private var firstLoopAnchor: AVAudioFramePosition? = nil
    private var tapInstalled: Bool = false

    private let format: AVAudioFormat
    private let nTracks = 4

    init(host: SynthEngine, metronome: Metronome) {
        self.host = host
        self.metronome = metronome
        self.format = AVAudioFormat(standardFormatWithSampleRate: host.sampleRate, channels: 2)!
        var built: [Track] = []
        for i in 0..<nTracks {
            let p = AVAudioPlayerNode()
            host.engine.attach(p)
            host.engine.connect(p, to: host.engine.mainMixerNode, format: format)
            built.append(Track(id: i, player: p))
        }
        tracks = built
        installTap()
    }

    // MARK: - Public controls

    func toggleRecordOnSelected() {
        let t = tracks[selectedTrack]
        switch t.state {
        case .empty, .muted, .armed:
            armForRecord(trackIndex: selectedTrack)
        case .playing:
            startOverdub(trackIndex: selectedTrack)
        case .overdubbing:
            stopOverdub(trackIndex: selectedTrack)
        case .recording, .countIn:
            cancelRecording()
        }
    }

    func clear(trackIndex: Int) {
        let t = tracks[trackIndex]
        t.player.stop()
        t.buffer = nil
        t.state = .empty
    }

    func toggleMute(trackIndex: Int) {
        let t = tracks[trackIndex]
        switch t.state {
        case .playing:
            t.player.pause(); t.state = .muted
        case .muted:
            if t.buffer != nil { t.player.play(); t.state = .playing }
        default: break
        }
    }

    // MARK: - Record flow

    private func armForRecord(trackIndex: Int) {
        guard !isRecordingActive() else { return }

        let bpm = metronome.bpm
        let beatsPerBar = metronome.meter
        let beatDurationSec = 60.0 / bpm
        let barDurationSec = beatDurationSec * Double(beatsPerBar)

        // Restart the metronome so beat 1 is exactly NOW (within ~50 ms startup).
        metronome.restart()

        tracks[trackIndex].state = .countIn(beatsLeft: beatsPerBar)

        // Tap reads sampleTime on the output node's clock → anchor capture there.
        let now = host.engine.outputNode.lastRenderTime?.sampleTime ?? 0
        let metronomeStartupSamples = AVAudioFramePosition(host.sampleRate * 0.05)
        let barSamples = AVAudioFramePosition(host.sampleRate * barDurationSec)
        let punchInTime = now + metronomeStartupSamples + barSamples

        let totalFrames = Int(host.sampleRate * beatDurationSec) * beatsPerBar * bars
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))
        buffer?.frameLength = 0

        recState.lock.withLock { s in
            s.trackIndex = trackIndex
            s.ringFrames = totalFrames
            s.ringBuffer = buffer
            s.captureStartSampleTime = punchInTime
            s.framesCaptured = 0
            s.active = true
        }
        scheduleCountInToRecording(
            trackIndex: trackIndex,
            beatsPerBar: beatsPerBar,
            beatDurationSec: beatDurationSec,
            totalDurationSec: barDurationSec + 0.05
        )
    }

    /// Wall-clock countdown for UI state transition. The audio capture itself
    /// is sample-accurate via the mixer tap; this timer just updates the
    /// `.countIn(beatsLeft:)` display and flips to `.recording` when 1 bar
    /// of metronome has elapsed.
    private func scheduleCountInToRecording(
        trackIndex: Int,
        beatsPerBar: Int,
        beatDurationSec: Double,
        totalDurationSec: Double
    ) {
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                guard case .countIn = self.tracks[trackIndex].state else { timer.invalidate(); return }
                let elapsed = Date().timeIntervalSince(start)
                if elapsed < totalDurationSec {
                    let remaining = Swift.max(1, beatsPerBar - Int(floor(elapsed / beatDurationSec)))
                    self.tracks[trackIndex].state = .countIn(beatsLeft: remaining)
                } else {
                    let total = self.recState.lock.withLock { $0.ringFrames }
                    self.tracks[trackIndex].state = .recording(framesCaptured: 0, totalFrames: total)
                    HapticEngine.shared.fire(.recordToggle)
                    timer.invalidate()
                }
            }
        }
    }

    private func cancelRecording() {
        recState.lock.withLock { s in
            s.active = false
            s.ringBuffer = nil
            s.framesCaptured = 0
        }
        for t in tracks {
            switch t.state {
            case .countIn, .recording: t.state = .empty
            default: break
            }
        }
    }

    private func finishRecording(trackIndex: Int) {
        let buf: AVAudioPCMBuffer? = recState.lock.withLock { s in
            let b = s.ringBuffer
            s.active = false
            s.ringBuffer = nil
            s.framesCaptured = 0
            return b
        }
        guard let buffer = buf else { cancelRecording(); return }
        let track = tracks[trackIndex]
        track.buffer = buffer
        track.state = .playing
        startTrackPlayback(trackIndex: trackIndex)
        HapticEngine.shared.fire(.loopBoundary)
    }

    private func startTrackPlayback(trackIndex: Int) {
        let track = tracks[trackIndex]
        guard let buf = track.buffer else { return }
        let now = host.engine.outputNode.lastRenderTime?.sampleTime ?? 0
        if firstLoopAnchor == nil { firstLoopAnchor = now + AVAudioFramePosition(host.sampleRate * 0.02) }
        let anchor = firstLoopAnchor!

        track.player.stop()
        track.player.scheduleBuffer(buf, at: AVAudioTime(sampleTime: anchor, atRate: host.sampleRate), options: [.loops], completionCallbackType: .dataPlayedBack) { _ in }
        if !track.player.isPlaying { track.player.play() }
        track.startSampleTime = anchor
    }

    private func startOverdub(trackIndex: Int) {
        guard !isRecordingActive() else { return }
        tracks[trackIndex].state = .overdubbing
        let totalFrames = Int(host.sampleRate * 60.0 / metronome.bpm) * metronome.meter * bars
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))
        buffer?.frameLength = 0
        let now = host.engine.outputNode.lastRenderTime?.sampleTime ?? 0
        let punchIn = metronome.nextBarSampleTime(after: now)
        recState.lock.withLock { s in
            s.trackIndex = trackIndex
            s.ringFrames = totalFrames
            s.ringBuffer = buffer
            s.captureStartSampleTime = punchIn
            s.framesCaptured = 0
            s.active = true
        }
        HapticEngine.shared.fire(.recordToggle)
    }

    private func stopOverdub(trackIndex: Int) {
        finishRecording(trackIndex: trackIndex)
    }

    nonisolated private func isRecordingActive() -> Bool {
        recState.lock.withLock { $0.active }
    }

    // MARK: - Mixer tap

    private func installTap() {
        guard !tapInstalled else { return }
        let bufferSize: AVAudioFrameCount = 2048
        let recState = self.recState
        let format = self.format
        host.engine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            Self.handleTap(buffer: buffer, time: time, recState: recState) { trackIdx, capturedNow, totalNeeded, finished in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .recording = self.tracks[trackIdx].state {
                        self.tracks[trackIdx].state = .recording(framesCaptured: capturedNow, totalFrames: totalNeeded)
                    }
                    if finished {
                        self.finishRecording(trackIndex: trackIdx)
                    }
                }
            }
        }
        tapInstalled = true
    }

    /// Pure off-main implementation: copies tap input into the ring buffer
    /// and fires `progress` callbacks.
    nonisolated private static func handleTap(
        buffer: AVAudioPCMBuffer,
        time: AVAudioTime,
        recState: RecordingState,
        progress: (_ trackIdx: Int, _ capturedNow: Int, _ totalNeeded: Int, _ finished: Bool) -> Void
    ) {
        let snapshot = recState.lock.withLock { $0 }
        guard snapshot.active, let ring = snapshot.ringBuffer else { return }
        let inputStart = time.sampleTime
        let frameCount = Int(buffer.frameLength)
        let inputEnd = inputStart + AVAudioFramePosition(frameCount)
        guard inputEnd > snapshot.captureStartSampleTime else { return }
        let dropFront = Swift.max(0, Int(snapshot.captureStartSampleTime - inputStart))
        let usable = frameCount - dropFront
        guard usable > 0 else { return }
        let toCopy = Swift.min(usable, snapshot.ringFrames - snapshot.framesCaptured)
        guard toCopy > 0 else { return }

        if let s = buffer.floatChannelData, let d = ring.floatChannelData {
            let channels = Int(Swift.min(buffer.format.channelCount, ring.format.channelCount))
            for ch in 0..<channels {
                let sp = s[ch].advanced(by: dropFront)
                let dp = d[ch].advanced(by: snapshot.framesCaptured)
                dp.update(from: sp, count: toCopy)
            }
        }

        let newCaptured = snapshot.framesCaptured + toCopy
        recState.lock.withLock { s in
            s.framesCaptured = newCaptured
            s.ringBuffer?.frameLength = AVAudioFrameCount(newCaptured)
        }
        let finished = newCaptured >= snapshot.ringFrames
        progress(snapshot.trackIndex, newCaptured, snapshot.ringFrames, finished)
    }
}
