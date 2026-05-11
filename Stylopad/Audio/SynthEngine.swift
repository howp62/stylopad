import AVFoundation
import Combine
import os

/// Monophonic Stylophone synth.
/// - The render block reads parameters via a small lock-protected struct (OSAllocatedUnfairLock).
/// - UI thread sets target frequency / gate on note-on/off.
/// - Attack ~50 ms, release ~1 ms, both modeled as 1-pole IIR slews towards a target amplitude.
final class SynthEngine: ObservableObject, @unchecked Sendable {
    let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    let sampleRate: Double = 44_100

    // Shared state — read by audio thread, written by main.
    private struct Params {
        var targetFreq: Double = 220     // A3 default
        var gate: Bool = false
        var vibratoEnabled: Bool = false
        var vibratoDepthSemis: Double = 0.6
        var pitchBendSemis: Double = 0   // Pencil Pro rollAngle
        var volume: Float = 0.9
    }

    private let lock = OSAllocatedUnfairLock<Params>(initialState: Params())

    // Render-thread-only state
    private var osc = StylophoneOscillator()
    private var vibrato = VibratoLFO()
    private var amp: Float = 0
    private var currentFreq: Double = 220
    private var currentNoteMidi: Int? = nil

    @Published private(set) var isRunning = false

    init() {
        osc.sampleRate = sampleRate
        vibrato.sampleRate = sampleRate
    }

    func start() {
        guard !isRunning else { return }
        do {
            try configureSession()
            attachSourceNode()
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            os_log("SynthEngine start failed: %{public}@", "\(error)")
        }
    }

    func stop() {
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        isRunning = false
    }

    // MARK: - Note control

    /// Note-on. Replaces any currently sounding note (monophonic).
    func noteOn(midi: Int, velocity: Float = 1.0) {
        let freq = resolvedFreq(midi: Double(midi))
        currentNoteMidi = midi
        lock.withLock { params in
            params.targetFreq = freq
            params.gate = true
            params.volume = max(0, min(1, velocity))
        }
    }

    /// Fretless note-on: continuous MIDI value (e.g. 60.4 = slightly sharp C4).
    func noteOnContinuous(midi: Double, velocity: Float = 1.0, snap: Bool = false) {
        let m = snap ? round(midi) : midi
        let freq = resolvedFreq(midi: m)
        currentNoteMidi = Int(m.rounded())
        lock.withLock { params in
            params.targetFreq = freq
            params.gate = true
            params.volume = max(0, min(1, velocity))
        }
    }

    /// Fretless slide: only updates pitch, leaves gate alone.
    func slidePitch(toMidi midi: Double) {
        let freq = resolvedFreq(midi: midi)
        lock.withLock { $0.targetFreq = freq }
    }

    /// Note-off. Only releases if `midi` matches the currently held note (so a
    /// stale finger-up doesn't kill a new note).
    func noteOff(midi: Int) {
        guard currentNoteMidi == midi else { return }
        currentNoteMidi = nil
        lock.withLock { $0.gate = false }
    }

    /// Force release regardless of which note (used on touchesCancelled).
    func releaseAll() {
        currentNoteMidi = nil
        lock.withLock { $0.gate = false }
    }

    func setVibrato(enabled: Bool) { lock.withLock { $0.vibratoEnabled = enabled } }
    func setVibratoDepth(semitones: Double) { lock.withLock { $0.vibratoDepthSemis = semitones } }
    func setPitchBend(semitones: Double) { lock.withLock { $0.pitchBendSemis = semitones } }
    func setVolume(_ v: Float) { lock.withLock { $0.volume = max(0, min(1, v)) } }
    func setMasterVolume(_ v: Float) {
        let clamped = max(0, min(1, v))
        engine.mainMixerNode.outputVolume = clamped
    }

    /// Octave shift (-1, 0, +1), transpose in semitones (-12..+12), and fine
    /// tuning in cents (-50..+50). All applied at the resolved freq.
    private var octaveShift: Int = 0
    private var transposeSemis: Int = 0
    private var tuningCents: Double = 0

    func setOctaveShift(_ semitones: Int) { octaveShift = semitones }
    func setTranspose(_ semitones: Int) { transposeSemis = semitones }
    func setTuningCents(_ cents: Double) { tuningCents = cents }

    private func resolvedFreq(midi: Double) -> Double {
        let baseMidi = midi + Double(octaveShift) * 12 + Double(transposeSemis)
        return 440 * pow(2, (baseMidi - 69 + tuningCents / 100) / 12)
    }

    // MARK: - Internals

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }

    private func attachSourceNode() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            return self.render(frameCount: frameCount, abl: audioBufferList)
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    /// Real-time render. Must not allocate, lock for long, or call ObjC.
    private func render(frameCount: AVAudioFrameCount, abl: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let bufferList = UnsafeMutableAudioBufferListPointer(abl)
        let snapshot = lock.withLock { $0 }

        // Target amp: gate ? volume : 0. Slews via per-sample IIR.
        let targetAmp: Float = snapshot.gate ? snapshot.volume : 0
        // Time constants → coefficient: a = 1 - exp(-dt / tau)
        let attackCoef: Float = 1 - Float(exp(-1.0 / (sampleRate * 0.050)))   // 50 ms attack
        let releaseCoef: Float = 1 - Float(exp(-1.0 / (sampleRate * 0.001)))  // 1 ms release
        // 35 ms portamento — short enough for tap-on accuracy, long enough that
        // sliding across keys sounds like a smooth glissando ("주우욱").
        let freqSlew: Double = 1 - exp(-1.0 / (sampleRate * 0.035))

        for frame in 0..<Int(frameCount) {
            // Slew current frequency towards target
            currentFreq += (snapshot.targetFreq - currentFreq) * freqSlew

            // Vibrato
            var freq = currentFreq
            if snapshot.vibratoEnabled {
                let semis = vibrato.renderSemitones(depth: snapshot.vibratoDepthSemis)
                freq *= pow(2, semis / 12)
            }
            if snapshot.pitchBendSemis != 0 {
                freq *= pow(2, snapshot.pitchBendSemis / 12)
            }

            // Oscillator
            let sample = osc.render(frequency: freq)

            // Envelope
            let coef: Float = (targetAmp > amp) ? attackCoef : releaseCoef
            amp += (targetAmp - amp) * coef

            let out = sample * amp
            for buf in bufferList {
                let p = buf.mData!.assumingMemoryBound(to: Float.self)
                p[frame] = out
            }
        }
        return noErr
    }
}

// MARK: - MIDI helpers
@inline(__always)
func midiToFreq(_ midi: Int) -> Double {
    440 * pow(2, Double(midi - 69) / 12)
}

/// Stylopad range: C3 (MIDI 48) → G4 (MIDI 67). 20 chromatic notes —
/// matches the original 1968 Stylophone numbering (12 white + 8 black).
enum StylophoneRange {
    static let lowestMidi = 48              // C3
    static let highestMidi = 67             // G4
    static let count = highestMidi - lowestMidi + 1   // 20
    static func midi(forKeyIndex index: Int) -> Int { lowestMidi + index }

    /// True if the note at this MIDI value is a black (sharp/flat) key.
    static func isBlack(midi: Int) -> Bool {
        let pitchClass = ((midi % 12) + 12) % 12
        return [1, 3, 6, 8, 10].contains(pitchClass)
    }

    /// All white-key MIDIs in range, in ascending order.
    static var whiteMidis: [Int] {
        (lowestMidi...highestMidi).filter { !isBlack(midi: $0) }
    }
}

/// Quantizes a continuous chromatic position `x` (in semitones from
/// `lowestMidi`) into the user-requested "dead-zone" curve:
/// most of each key snaps to that key's exact MIDI; the outer
/// `transitionFrac` of each side interpolates linearly to the neighbour.
///
/// Defaults: 60% dead zone in the middle of each key, 20% transition on
/// each side. Tweak via `transitionFrac`.
@inline(__always)
func quantizeWithDeadzone(continuousChromatic x: Double, transitionFrac: Double = 0.2) -> Double {
    let lower = floor(x)
    let frac = x - lower
    if frac < transitionFrac {
        return lower
    } else if frac > 1 - transitionFrac {
        return lower + 1
    } else {
        // Linear interpolation across the centre band → exact integer at the centre.
        let t = (frac - transitionFrac) / (1 - 2 * transitionFrac)
        return lower + t
    }
}
