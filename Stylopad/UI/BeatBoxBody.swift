import SwiftUI

/// Stylopad Beat chassis — same matte-black body, silver speaker grille,
/// rotating tape reels and vintage knobs. Houses the bass keyboard
/// (left) and 8 drum pads (right).
struct BeatBoxBody: View {
    let beatEngine: BeatEngine
    @Binding var powerOn: Bool
    @Binding var bassVolume: Double

    let tapeActive: Bool
    let bpm: Double

    @State private var swing: Double = 0.5
    @State private var filter: Double = 0.8
    @State private var decay: Double = 0.6
    @State private var bassTone: Double = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.06)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                                .stroke(.black.opacity(0.7), lineWidth: 2))
                    .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 8)

                screwAt(.topLeading, geo: geo)
                screwAt(.topTrailing, geo: geo)
                screwAt(.bottomLeading, geo: geo)
                screwAt(.bottomTrailing, geo: geo)

                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 10) {
                        BeatGrille()
                            .frame(maxWidth: .infinity)
                        TapeDeck(isActive: tapeActive, bpm: bpm)
                            .frame(width: 170)
                    }
                    .frame(height: geo.size.height * 0.34)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)

                    HStack(alignment: .top, spacing: 10) {
                        BeatLeftPanel(powerOn: $powerOn, swing: $swing, bassTone: $bassTone)
                            .frame(width: 158)
                        BassKeyboardRepresentable(engine: beatEngine)
                            .frame(maxWidth: .infinity)
                        DrumPadGridRepresentable(engine: beatEngine)
                            .frame(width: geo.size.width * 0.36)
                        BeatRightPanel(filter: $filter, decay: $decay, bassVolume: $bassVolume)
                            .frame(width: 140)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                }
            }
        }
    }

    private func screwAt(_ corner: UnitPoint, geo: GeometryProxy) -> some View {
        let inset: CGFloat = 10
        let x: CGFloat = (corner == .topLeading || corner == .bottomLeading) ? inset : geo.size.width - inset
        let y: CGFloat = (corner == .topLeading || corner == .topTrailing) ? inset : geo.size.height - inset
        return ScrewHead().position(x: x, y: y)
    }
}

private struct BeatGrille: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6)
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
                HStack(spacing: 6) {
                    Text("Stylopad").font(.system(size: 22, weight: .bold, design: .serif)).italic().foregroundStyle(.white)
                    Text("Beat").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.red.opacity(0.85))
                    Text("®").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.8)).baselineOffset(8)
                }
            }
            .frame(width: 220, height: 40)
            .padding(.top, 8).padding(.trailing, 12)
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
        }
    }
}

private struct BeatLeftPanel: View {
    @Binding var powerOn: Bool
    @Binding var swing: Double
    @Binding var bassTone: Double

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                BeatPowerSwitch(isOn: $powerOn)
                PowerLED(isOn: powerOn, color: .green, label: "BEAT")
            }
            HStack(spacing: 4) {
                VintageKnob(label: "SWING", value: $swing, range: 0...1, tint: .red)
                VintageKnob(label: "BASS T", value: $bassTone, range: 0...1, tint: .orange)
            }
        }
    }
}

private struct BeatRightPanel: View {
    @Binding var filter: Double
    @Binding var decay: Double
    @Binding var bassVolume: Double
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                VintageKnob(label: "FILTER", value: $filter, range: 0...1, tint: .cyan)
                VintageKnob(label: "DECAY", value: $decay, range: 0...1, tint: .yellow)
            }
            VStack(spacing: 2) {
                Text("BASS VOL")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(1)
                Slider(value: $bassVolume, in: 0...1).tint(.orange)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.5)))
        }
    }
}

private struct BeatPowerSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        VStack(spacing: 4) {
            Text("BEAT").font(.system(size: 8, weight: .heavy)).foregroundStyle(.black.opacity(0.6)).tracking(1)
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.18))
                    .frame(width: 26, height: 56)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(white: 0.4), .black], startPoint: .top, endPoint: .bottom))
                    .frame(width: 20, height: 22)
                    .offset(y: isOn ? 14 : -14)
                    .animation(.spring(duration: 0.18), value: isOn)
            }
            .onTapGesture { isOn.toggle() }
            Text(isOn ? "ON" : "OFF").font(.system(size: 8, weight: .heavy)).foregroundStyle(.black.opacity(0.7))
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.92))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.4), lineWidth: 1)))
    }
}
