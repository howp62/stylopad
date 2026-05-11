import Foundation

/// Stylophone oscillator: bandlimited sawtooth (PolyBLEP) + octave-up sine, 4:1 mix.
/// Approximates the 1968 PUT relaxation oscillator's harmonic content.
struct StylophoneOscillator {
    var sampleRate: Double = 44_100
    private var sawPhase: Double = 0      // 0..1
    private var sinePhase: Double = 0     // 0..2π

    static let sawGain: Float = 0.8
    static let sineGain: Float = 0.2

    mutating func reset() {
        sawPhase = 0
        sinePhase = 0
    }

    /// Render one sample at `frequency` Hz. Saw + octave-up sine, 4:1.
    mutating func render(frequency: Double) -> Float {
        let dt = frequency / sampleRate
        sawPhase += dt
        if sawPhase >= 1 { sawPhase -= 1 }

        // Naive saw in [-1, 1]
        var saw = 2 * sawPhase - 1
        // PolyBLEP correction at the wrap discontinuity
        saw -= polyBLEP(t: sawPhase, dt: dt)

        // Octave-up sine
        let sineDt = (2 * frequency) / sampleRate
        sinePhase += 2 * .pi * sineDt
        if sinePhase >= 2 * .pi { sinePhase -= 2 * .pi }
        let sine = Foundation.sin(sinePhase)

        return Self.sawGain * Float(saw) + Self.sineGain * Float(sine)
    }

    @inline(__always)
    private func polyBLEP(t: Double, dt: Double) -> Double {
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        } else if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }
}
