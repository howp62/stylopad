import SwiftUI

/// Visual chrome modeled after the 1968 Stylophone:
/// matte-black plastic case, large silver horizontal-line speaker grille
/// on top with a script-style brand plaque, rotating tape reels (gimmick!),
/// vintage knobs and LEDs.
struct StylophoneBody<Content: View>: View {
    @Binding var vibratoOn: Bool
    @Binding var powerOn: Bool
    @Binding var volume: Double
    @Binding var octaveShift: Int
    @Binding var tuningCents: Double

    @State private var reverbAmt: Double = 0.3
    @State private var toneAmt: Double = 0.55
    @State private var driveAmt: Double = 0.4
    @State private var echoAmt: Double = 0.25

    let tapeActive: Bool
    let bpm: Double
    let content: Content

    init(vibratoOn: Binding<Bool>,
         powerOn: Binding<Bool>,
         volume: Binding<Double>,
         octaveShift: Binding<Int>,
         tuningCents: Binding<Double>,
         tapeActive: Bool,
         bpm: Double,
         @ViewBuilder content: () -> Content) {
        self._vibratoOn = vibratoOn
        self._powerOn = powerOn
        self._volume = volume
        self._octaveShift = octaveShift
        self._tuningCents = tuningCents
        self.tapeActive = tapeActive
        self.bpm = bpm
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                bodyShell

                // Corner screws (decorative)
                screwAt(.topLeading, geo: geo)
                screwAt(.topTrailing, geo: geo)
                screwAt(.bottomLeading, geo: geo)
                screwAt(.bottomTrailing, geo: geo)

                VStack(spacing: 0) {
                    // Top half: grille + tape deck + brand
                    HStack(alignment: .top, spacing: 10) {
                        SpeakerGrille(brand: "Stylopad")
                            .frame(maxWidth: .infinity)
                        TapeDeck(isActive: tapeActive, bpm: bpm)
                            .frame(width: 180)
                    }
                    .frame(height: geo.size.height * 0.42)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)

                    StylusRecess()
                        .frame(height: 26)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)

                    // Lower row: switches+knobs (left) — keyboard (center) — knobs+controls (right)
                    HStack(alignment: .top, spacing: 12) {
                        leftPanel
                            .frame(width: 168)
                        Spacer(minLength: 0)
                        content
                            .frame(maxWidth: 820)
                        Spacer(minLength: 0)
                        rightPanel
                            .frame(width: 168)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                }
            }
        }
    }

    // MARK: - Sub-blocks

    private var bodyShell: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.06)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.7), lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 8)
    }

    private func screwAt(_ corner: UnitPoint, geo: GeometryProxy) -> some View {
        let inset: CGFloat = 10
        let x: CGFloat = (corner == .topLeading || corner == .bottomLeading) ? inset : geo.size.width - inset
        let y: CGFloat = (corner == .topLeading || corner == .topTrailing) ? inset : geo.size.height - inset
        return ScrewHead().position(x: x, y: y)
    }

    private var leftPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                SwitchPanel(powerOn: $powerOn, vibratoOn: $vibratoOn)
                PowerLED(isOn: powerOn, color: .red, label: "PWR")
            }
            HStack(spacing: 4) {
                VintageKnob(label: "REVERB", value: $reverbAmt, range: 0...1, tint: .cyan)
                VintageKnob(label: "ECHO", value: $echoAmt, range: 0...1, tint: .green)
            }
        }
    }

    private var rightPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                VintageKnob(label: "TONE", value: $toneAmt, range: 0...1, tint: .yellow)
                VintageKnob(label: "DRIVE", value: $driveAmt, range: 0...1, tint: .orange)
            }
            SideControls(volume: $volume, octaveShift: $octaveShift, tuningCents: $tuningCents)
        }
    }
}

// MARK: - Speaker grille

private struct SpeakerGrille: View {
    let brand: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.94), Color(white: 0.78)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.45), lineWidth: 1))

            Canvas { ctx, size in
                let count = Int(size.height / 6)
                let pad: CGFloat = 8
                for i in 0..<count {
                    let y = pad + CGFloat(i) * 6
                    if y > size.height - pad { break }
                    let r = CGRect(x: pad, y: y, width: size.width - 2*pad, height: 2)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 1), with: .color(.black.opacity(0.85)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))

            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(.black)
                HStack(spacing: 2) {
                    Text(brand).font(.system(size: 26, weight: .bold, design: .serif))
                        .italic().foregroundStyle(.white)
                    Text("®").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8)).baselineOffset(8)
                }
            }
            .frame(width: 220, height: 44)
            .padding(.top, 10).padding(.trailing, 12)
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Stylus recess

private struct StylusRecess: View {
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.04), Color(white: 0.18)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().stroke(.black.opacity(0.8), lineWidth: 1))
            HStack(spacing: 0) {
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.7)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 14, height: 10)
                Rectangle()
                    .fill(LinearGradient(colors: [Color(white: 0.18), .black],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 8)
                Circle().fill(.black).frame(width: 8, height: 8)
            }
            .padding(.leading, 30)
            Text("STYLUS").font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white.opacity(0.4)).tracking(2)
                .padding(.leading, 8)
        }
    }
}

// MARK: - Switch panel

private struct SwitchPanel: View {
    @Binding var powerOn: Bool
    @Binding var vibratoOn: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VerticalSwitch(label: "POWER", isOn: $powerOn, topLabel: "OFF", bottomLabel: "ON")
            VerticalSwitch(label: "VIBRATO", isOn: $vibratoOn, topLabel: "ON", bottomLabel: "OFF")
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.92))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.4), lineWidth: 1))
        )
    }
}

private struct VerticalSwitch: View {
    let label: String
    @Binding var isOn: Bool
    let topLabel: String
    let bottomLabel: String
    var body: some View {
        VStack(spacing: 3) {
            Text(topLabel).font(.system(size: 7, weight: .heavy)).foregroundStyle(.black.opacity(0.7))
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.18))
                    .frame(width: 20, height: 50)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(white: 0.4), .black],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 16, height: 20)
                    .offset(y: isOn ? 12 : -12)
                    .animation(.spring(duration: 0.18), value: isOn)
            }
            .onTapGesture { isOn.toggle() }
            Text(bottomLabel).font(.system(size: 7, weight: .heavy)).foregroundStyle(.black.opacity(0.7))
            Text(label).font(.system(size: 7, weight: .heavy)).foregroundStyle(.black.opacity(0.6)).tracking(0.5)
        }
    }
}

// MARK: - Side controls (volume slider, octave stepper, tune slider)

private struct SideControls: View {
    @Binding var volume: Double
    @Binding var octaveShift: Int
    @Binding var tuningCents: Double

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 2) {
                Text("VOL").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white.opacity(0.7)).tracking(1)
                Slider(value: $volume, in: 0...1).tint(.white)
            }
            HStack(spacing: 4) {
                Text("OCT").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
                Button("-") { octaveShift = max(-1, octaveShift - 1) }
                    .frame(width: 22, height: 22)
                Text(octaveShift > 0 ? "+\(octaveShift)" : "\(octaveShift)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white).frame(minWidth: 18)
                Button("+") { octaveShift = min(1, octaveShift + 1) }
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderedProminent).tint(.white.opacity(0.15)).foregroundStyle(.white)
            .font(.system(size: 12, weight: .bold))
            VStack(spacing: 1) {
                Text("TUNE").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white.opacity(0.7)).tracking(1)
                Slider(value: $tuningCents, in: -50...50).tint(.red)
                Text(String(format: "%+.0fc", tuningCents))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.5)))
    }
}
