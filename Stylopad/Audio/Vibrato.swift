import Foundation

/// 7–8 Hz triangle LFO. Output in [-1, 1] scaled by depth (semitones).
struct VibratoLFO {
    var sampleRate: Double = 44_100
    var rateHz: Double = 7.5
    private var phase: Double = 0   // 0..1

    mutating func reset() { phase = 0 }

    /// Returns a multiplier you apply to base frequency: `freq * pow(2, semitones / 12)`.
    mutating func renderSemitones(depth: Double) -> Double {
        phase += rateHz / sampleRate
        if phase >= 1 { phase -= 1 }
        // triangle in [-1, 1]
        let tri = 4 * abs(phase - 0.5) - 1
        return tri * depth
    }
}
