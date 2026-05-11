import AVFoundation
import Combine
import os

/// Stylopad Beat: 8 synthesized drum pads + a bass voice.
/// Shares the host's `AVAudioEngine` so it plays simultaneously with the
/// melody synth and gets recorded by the looper's mixer tap.
final class BeatEngine: ObservableObject, @unchecked Sendable {
    unowned let host: SynthEngine

    enum DrumPad: Int, CaseIterable, Identifiable {
        case kick = 0, snare, closedHat, openHat, clap, tomLo, tomHi, perc
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .kick: return "KICK"
            case .snare: return "SNARE"
            case .closedHat: return "HAT"
            case .openHat: return "OPEN"
            case .clap: return "CLAP"
            case .tomLo: return "TOM L"
            case .tomHi: return "TOM H"
            case .perc: return "PERC"
            }
        }
    }

    // MARK: - Drum playback

    private var padPlayers: [AVAudioPlayerNode] = []
    private var padBuffers: [AVAudioPCMBuffer] = []
    private let format: AVAudioFormat

    // MARK: - Bass voice

    private var bassNode: AVAudioSourceNode?
    private struct BassParams { var targetFreq: Double = 55; var gate: Bool = false; var volume: Float = 0.9 }
    private let bassLock = OSAllocatedUnfairLock<BassParams>(initialState: BassParams())
    /// Single StylophoneOscillator — identical timbre to the melody synth so
    /// pressing "C" on melody and "C" on bass sound like the same note, one
    /// octave apart.
    private var bassOsc = StylophoneOscillator()
    private var bassAmp: Float = 0
    private var bassCurrentFreq: Double = 55
    private var bassCurrentMidi: Int? = nil

    /// Global transpose in semitones, shared with the melody synth so both
    /// keyboards shift together.
    private var transposeSemis: Int = 0
    func setTranspose(_ semitones: Int) { transposeSemis = semitones }

    /// Bass master volume (0…1) — multiplied into the bass render path.
    /// Default 0.9 keeps headroom for the rest of the mix.
    private var bassMasterVolume: Float = 0.9
    func setBassVolume(_ v: Float) {
        bassMasterVolume = Swift.max(0, Swift.min(1, v))
    }
    private func bassFreq(midi: Double) -> Double {
        440 * pow(2, (midi + Double(transposeSemis) - 69) / 12)
    }

    init(host: SynthEngine) {
        self.host = host
        self.format = AVAudioFormat(standardFormatWithSampleRate: host.sampleRate, channels: 2)!
        bassOsc.sampleRate = host.sampleRate
        buildDrums()
        attachBass()
    }

    // MARK: - Drum triggering

    /// Plays a pad. Retriggering interrupts the previous voice on that pad.
    func triggerPad(_ pad: DrumPad, velocity: Float = 1.0) {
        let i = pad.rawValue
        guard i < padPlayers.count, i < padBuffers.count else { return }
        let player = padPlayers[i]
        let buffer = padBuffers[i]
        player.volume = max(0.05, min(1, velocity))
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionCallbackType: .dataPlayedBack) { _ in }
        if !player.isPlaying { player.play() }
        Task { @MainActor in HapticEngine.shared.fire(.beat) }
    }

    // MARK: - Bass control

    /// One bass octave below the melody Stylophone (A1..G3 region by default).
    func bassNoteOn(midi: Int, velocity: Float = 0.9) {
        bassCurrentMidi = midi
        let freq = bassFreq(midi: Double(midi))
        bassLock.withLock { p in
            p.targetFreq = freq
            p.gate = true
            p.volume = max(0, min(1, velocity))
        }
    }

    func bassNoteOnContinuous(midi: Double, velocity: Float = 0.9) {
        bassCurrentMidi = Int(midi.rounded())
        let freq = bassFreq(midi: midi)
        bassLock.withLock { p in
            p.targetFreq = freq
            p.gate = true
            p.volume = max(0, min(1, velocity))
        }
    }

    func bassSlide(toMidi midi: Double) {
        let freq = bassFreq(midi: midi)
        bassLock.withLock { $0.targetFreq = freq }
    }

    func bassNoteOff(midi: Int) {
        guard bassCurrentMidi == midi else { return }
        bassCurrentMidi = nil
        bassLock.withLock { $0.gate = false }
    }

    func bassReleaseAll() {
        bassCurrentMidi = nil
        bassLock.withLock { $0.gate = false }
    }

    // MARK: - Setup

    private func buildDrums() {
        for pad in DrumPad.allCases {
            let buf = synthDrum(pad)
            let player = AVAudioPlayerNode()
            host.engine.attach(player)
            host.engine.connect(player, to: host.engine.mainMixerNode, format: format)
            padBuffers.append(buf)
            padPlayers.append(player)
        }
    }

    private func attachBass() {
        let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, abl -> OSStatus in
            guard let self else { return noErr }
            return self.renderBass(frameCount: frameCount, abl: abl)
        }
        host.engine.attach(node)
        host.engine.connect(node, to: host.engine.mainMixerNode, format: format)
        bassNode = node
    }

    /// Bass render: saw + sub-octave saw at -7dB. Same envelope shape as melody.
    private func renderBass(frameCount: AVAudioFrameCount, abl: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let bufferList = UnsafeMutableAudioBufferListPointer(abl)
        let snapshot = bassLock.withLock { $0 }
        let sr = host.sampleRate
        let targetAmp: Float = snapshot.gate ? snapshot.volume : 0
        let attackCoef: Float = 1 - Float(exp(-1.0 / (sr * 0.030)))
        let releaseCoef: Float = 1 - Float(exp(-1.0 / (sr * 0.060)))
        let freqSlew: Double = 1 - exp(-1.0 / (sr * 0.040))

        let master = bassMasterVolume
        for frame in 0..<Int(frameCount) {
            bassCurrentFreq += (snapshot.targetFreq - bassCurrentFreq) * freqSlew
            let s = bassOsc.render(frequency: bassCurrentFreq)
            let coef: Float = (targetAmp > bassAmp) ? attackCoef : releaseCoef
            bassAmp += (targetAmp - bassAmp) * coef
            let out = s * bassAmp * master
            for buf in bufferList {
                let p = buf.mData!.assumingMemoryBound(to: Float.self)
                p[frame] = out
            }
        }
        return noErr
    }

    // MARK: - Drum synthesis

    private func synthDrum(_ pad: DrumPad) -> AVAudioPCMBuffer {
        switch pad {
        case .kick:      return renderKick()
        case .snare:     return renderSnare()
        case .closedHat: return renderHat(durationMs: 70, decayMs: 50)
        case .openHat:   return renderHat(durationMs: 350, decayMs: 280)
        case .clap:      return renderClap()
        case .tomLo:     return renderTom(freq: 110)
        case .tomHi:     return renderTom(freq: 200)
        case .perc:      return renderPerc()
        }
    }

    private func renderKick() -> AVAudioPCMBuffer {
        let durMs = 320.0
        let buf = makeBuffer(ms: durMs)
        let sr = host.sampleRate
        let n = Int(buf.frameLength)
        let lp = buf.floatChannelData![0]
        let rp = buf.floatChannelData![1]
        var phase: Double = 0
        for i in 0..<n {
            let t = Double(i) / sr
            // Pitch envelope 180 → 45 Hz over 60ms
            let pitchEnv = 45 + (180 - 45) * exp(-t / 0.04)
            phase += 2 * .pi * pitchEnv / sr
            let amp = exp(-t / 0.18)
            let s = Float(sin(phase)) * Float(amp) * 0.95
            lp[i] = s; rp[i] = s
        }
        return buf
    }

    private func renderSnare() -> AVAudioPCMBuffer {
        let buf = makeBuffer(ms: 200)
        let sr = host.sampleRate
        let n = Int(buf.frameLength)
        let lp = buf.floatChannelData![0]
        let rp = buf.floatChannelData![1]
        var phase: Double = 0
        var noise: Float = 0
        let lpCoef: Float = 0.6
        for i in 0..<n {
            let t = Double(i) / sr
            phase += 2 * .pi * 200 / sr
            let tone = Float(sin(phase)) * 0.4
            let rawNoise = Float.random(in: -1...1)
            noise = noise * (1 - lpCoef) + rawNoise * lpCoef    // mild low-pass
            let amp = exp(-Float(t) / 0.09)
            let s = (tone + noise * 0.8) * amp * 0.55
            lp[i] = s; rp[i] = s
        }
        return buf
    }

    private func renderHat(durationMs: Double, decayMs: Double) -> AVAudioPCMBuffer {
        let buf = makeBuffer(ms: durationMs)
        let sr = host.sampleRate
        let n = Int(buf.frameLength)
        let lp = buf.floatChannelData![0]
        let rp = buf.floatChannelData![1]
        var hp: Float = 0
        var prevNoise: Float = 0
        for i in 0..<n {
            let t = Double(i) / sr
            let rawNoise = Float.random(in: -1...1)
            // simple high-pass: y[n] = x[n] - x[n-1]
            hp = rawNoise - prevNoise
            prevNoise = rawNoise
            let amp = exp(-Float(t) / Float(decayMs / 1000 / 4))
            let s = hp * amp * 0.45
            lp[i] = s; rp[i] = s
        }
        return buf
    }

    private func renderClap() -> AVAudioPCMBuffer {
        let buf = makeBuffer(ms: 180)
        let sr = host.sampleRate
        let n = Int(buf.frameLength)
        let lp = buf.floatChannelData![0]
        let rp = buf.floatChannelData![1]
        let pulses: [Double] = [0.0, 0.010, 0.018, 0.030]  // four bursts
        for i in 0..<n {
            let t = Double(i) / sr
            var amp: Float = 0
            for p in pulses {
                let dt = t - p
                if dt >= 0 { amp += Float(exp(-dt / 0.025)) }
            }
            let body = exp(-Float(t) / 0.06)
            let noise = Float.random(in: -1...1)
            let s = noise * amp * body * 0.4
            lp[i] = s; rp[i] = s
        }
        return buf
    }

    private func renderTom(freq: Double) -> AVAudioPCMBuffer {
        let buf = makeBuffer(ms: 250)
        let sr = host.sampleRate
        let n = Int(buf.frameLength)
        let lp = buf.floatChannelData![0]
        let rp = buf.floatChannelData![1]
        var phase: Double = 0
        for i in 0..<n {
            let t = Double(i) / sr
            let pitchEnv = freq * (1 + 0.5 * exp(-t / 0.03))
            phase += 2 * .pi * pitchEnv / sr
            let amp = exp(-Float(t) / 0.14)
            let s = Float(sin(phase)) * amp * 0.85
            lp[i] = s; rp[i] = s
        }
        return buf
    }

    private func renderPerc() -> AVAudioPCMBuffer {
        let buf = makeBuffer(ms: 90)
        let sr = host.sampleRate
        let n = Int(buf.frameLength)
        let lp = buf.floatChannelData![0]
        let rp = buf.floatChannelData![1]
        var phase: Double = 0
        for i in 0..<n {
            let t = Double(i) / sr
            phase += 2 * .pi * 2400 / sr
            let amp = exp(-Float(t) / 0.025)
            let noise = Float.random(in: -1...1) * 0.3
            let s = (Float(sin(phase)) * 0.6 + noise) * amp * 0.55
            lp[i] = s; rp[i] = s
        }
        return buf
    }

    private func makeBuffer(ms: Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(host.sampleRate * ms / 1000)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        return buf
    }
}

/// Bass keyboard range: one octave below the melody Stylopad (C2 → G3 = 20 chromatic notes).
enum BassRange {
    static let lowestMidi = StylophoneRange.lowestMidi - 12   // C2 = 36
    static let highestMidi = StylophoneRange.highestMidi - 12 // G3 = 55
    static let count = highestMidi - lowestMidi + 1
    static func isBlack(midi: Int) -> Bool { StylophoneRange.isBlack(midi: midi) }
    static var whiteMidis: [Int] {
        (lowestMidi...highestMidi).filter { !isBlack(midi: $0) }
    }
}
