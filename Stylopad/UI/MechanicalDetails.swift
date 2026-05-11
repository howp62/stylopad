import SwiftUI

// MARK: - Tape deck (two rotating reels)

/// A pair of cassette-style reels with tape stretched between them.
/// Spins continuously while `isActive`; rotation rate scales with `bpm` so
/// the tape's apparent speed feels musically right.
struct TapeDeck: View {
    let isActive: Bool
    let bpm: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let rps = isActive ? bpm / 60.0 / 4 : 0   // 1 rev per beat is dizzy → /4 quarter-rev per beat
            let angle = (t * rps).truncatingRemainder(dividingBy: 1)
            ZStack {
                // Recessed black plate
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Color(white: 0.04), Color(white: 0.10)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.9), lineWidth: 1))

                GeometryReader { geo in
                    let reelSize = min(geo.size.width * 0.4, geo.size.height * 0.85)
                    let cx = geo.size.width / 2
                    let cy = geo.size.height / 2
                    // Tape ribbon spanning between reel centers
                    Path { p in
                        let dx = reelSize * 0.55
                        p.move(to: CGPoint(x: cx - dx, y: cy + reelSize * 0.05))
                        p.addLine(to: CGPoint(x: cx + dx, y: cy + reelSize * 0.05))
                    }
                    .stroke(LinearGradient(colors: [Color(red: 0.45, green: 0.32, blue: 0.18),
                                                    Color(red: 0.28, green: 0.18, blue: 0.08)],
                                          startPoint: .top, endPoint: .bottom),
                            lineWidth: reelSize * 0.10)

                    Reel(rotations: angle)
                        .frame(width: reelSize, height: reelSize)
                        .position(x: cx - geo.size.width * 0.22, y: cy)
                    Reel(rotations: angle + 0.08)
                        .frame(width: reelSize, height: reelSize)
                        .position(x: cx + geo.size.width * 0.22, y: cy)
                }
                .padding(6)
            }
        }
    }
}

private struct Reel: View {
    /// Rotation expressed as turns (0..1 = one revolution).
    let rotations: Double

    var body: some View {
        ZStack {
            // Outer hub
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.35), Color(white: 0.10)],
                                     center: .center, startRadius: 0, endRadius: 30))
                .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))

            // Spokes (rotate)
            ZStack {
                ForEach(0..<6) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.20)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 6)
                        .rotationEffect(.degrees(Double(i) * 60))
                }
            }
            .rotationEffect(.degrees(rotations * 360))

            // Centre cap
            Circle().fill(Color(white: 0.6))
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(.black, lineWidth: 0.5))
        }
    }
}

// MARK: - Vintage rotary knob

struct VintageKnob: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var tint: Color = .red

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white.opacity(0.7))
                .tracking(1.5)
            ZStack {
                // LED ring
                Circle()
                    .trim(from: 0.18, to: 0.82)
                    .stroke(tint.opacity(0.25), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(90))
                let pct = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                Circle()
                    .trim(from: 0.18, to: 0.18 + 0.64 * pct)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(90))

                // Knob body
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.18)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().stroke(.black, lineWidth: 1))
                    .padding(8)

                // Tick line
                let angle = -135.0 + 270.0 * pct
                Rectangle().fill(tint)
                    .frame(width: 3, height: 12)
                    .offset(y: -16)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: 56, height: 56)
            .gesture(DragGesture()
                .onChanged { g in
                    let delta = -Double(g.translation.height) * 0.005
                    let span = range.upperBound - range.lowerBound
                    value = Swift.max(range.lowerBound,
                                      Swift.min(range.upperBound, value + delta * span))
                })
            Text(formattedValue)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(height: 12)
        }
    }

    private var formattedValue: String {
        if range.upperBound - range.lowerBound <= 1.0 {
            return String(format: "%.0f%%", value * 100)
        }
        return String(format: "%.0f", value)
    }
}

// MARK: - Power LED

struct PowerLED: View {
    let isOn: Bool
    var color: Color = .red
    var label: String = ""

    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(.black.opacity(0.4)).frame(width: 14, height: 14)
                Circle()
                    .fill(isOn ? color : Color(white: 0.25))
                    .frame(width: 10, height: 10)
                    .shadow(color: isOn ? color.opacity(pulse ? 0.95 : 0.6) : .clear,
                            radius: pulse ? 6 : 3)
            }
            .onAppear { pulse = true }
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(1)
            }
        }
    }
}

// MARK: - Decorative screw

struct ScrewHead: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.85), Color(white: 0.30)],
                                     center: .topLeading, startRadius: 1, endRadius: 6))
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 0.5))
            Rectangle().fill(.black.opacity(0.7)).frame(width: 8, height: 1.4)
        }
    }
}
