import SwiftUI

struct RootView: View {
    @StateObject private var engine: SynthEngine
    @StateObject private var beatEngine: BeatEngine
    @StateObject private var metronome: Metronome
    @StateObject private var looper: Looper

    @State private var vibratoOn = false
    @State private var powerOn = true
    @State private var beatPowerOn = true
    @State private var volume: Double = 0.85
    @State private var octaveShift: Int = 0
    @State private var tuningCents: Double = 0
    @State private var transpose: Int = 0
    @State private var bassVolume: Double = 0.85

    private var tapeIsActive: Bool {
        metronome.isRunning || looper.tracks.contains { t in
            switch t.state {
            case .playing, .recording, .overdubbing, .countIn: return true
            default: return false
            }
        }
    }

    init() {
        let synth = SynthEngine()
        let beat = BeatEngine(host: synth)
        let metro = Metronome(host: synth)
        let loop = Looper(host: synth, metronome: metro)
        _engine = StateObject(wrappedValue: synth)
        _beatEngine = StateObject(wrappedValue: beat)
        _metronome = StateObject(wrappedValue: metro)
        _looper = StateObject(wrappedValue: loop)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.08), Color(white: 0.14)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                LoopStationView(metronome: metronome, looper: looper, transpose: $transpose)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                // Melody Stylopad
                StylophoneBody(
                    vibratoOn: $vibratoOn,
                    powerOn: $powerOn,
                    volume: $volume,
                    octaveShift: $octaveShift,
                    tuningCents: $tuningCents,
                    tapeActive: tapeIsActive,
                    bpm: metronome.bpm
                ) {
                    KeyboardRepresentable(engine: engine, looper: looper)
                        .frame(maxWidth: .infinity, maxHeight: 230)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)

                // Beatbox
                BeatBoxBody(beatEngine: beatEngine,
                            powerOn: $beatPowerOn,
                            bassVolume: $bassVolume,
                            tapeActive: tapeIsActive,
                            bpm: metronome.bpm)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }
        }
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
        .onChange(of: vibratoOn) { _, new in engine.setVibrato(enabled: new) }
        .onChange(of: volume) { _, new in engine.setMasterVolume(Float(new)) }
        .onChange(of: octaveShift) { _, new in engine.setOctaveShift(new) }
        .onChange(of: tuningCents) { _, new in engine.setTuningCents(new) }
        .onChange(of: powerOn) { _, new in if new { engine.start() } else { engine.stop() } }
        .onChange(of: transpose) { _, new in
            engine.setTranspose(new)
            beatEngine.setTranspose(new)
        }
        .onChange(of: bassVolume) { _, new in
            beatEngine.setBassVolume(Float(new))
        }
    }
}

#Preview { RootView() }
