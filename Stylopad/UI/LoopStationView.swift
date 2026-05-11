import SwiftUI

struct LoopStationView: View {
    @ObservedObject var metronome: Metronome
    @ObservedObject var looper: Looper
    @Binding var transpose: Int
    @State private var beatPulse: Int = 0

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Metronome panel
            HStack(spacing: 12) {
                BeatLamp(beat: beatPulse, count: metronome.meter)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BPM")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(1.5)
                    Text("\(Int(metronome.bpm))")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(minWidth: 60, alignment: .leading)
                }
                VStack(spacing: 4) {
                    Button {
                        metronome.bpm = min(240, metronome.bpm + 1)
                    } label: { Image(systemName: "chevron.up") }
                    Button {
                        metronome.bpm = max(40, metronome.bpm - 1)
                    } label: { Image(systemName: "chevron.down") }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))
                .foregroundStyle(.white)
                Toggle("", isOn: Binding(
                    get: { metronome.isRunning },
                    set: { $0 ? metronome.start() : metronome.stop() }
                ))
                .labelsHidden()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.18)))

            // Bars selector
            VStack(alignment: .leading, spacing: 4) {
                Text("BARS")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(1.5)
                Picker("", selection: $looper.bars) {
                    ForEach([1, 2, 4, 8], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            // Transpose
            VStack(alignment: .leading, spacing: 4) {
                Text("TRANSPOSE")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(1.5)
                HStack(spacing: 6) {
                    Button {
                        transpose = Swift.max(-12, transpose - 1)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 28)

                    Text(transposeLabel)
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(minWidth: 38)

                    Button {
                        transpose = Swift.min(12, transpose + 1)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 28)
                }
            }

            // Track strip
            HStack(spacing: 8) {
                ForEach(looper.tracks) { track in
                    TrackChip(track: track, isSelected: track.id == looper.selectedTrack)
                        .onTapGesture { looper.selectedTrack = track.id }
                        .onLongPressGesture(minimumDuration: 0.4) { looper.clear(trackIndex: track.id) }
                }
            }

            Spacer(minLength: 0)

            // Record button
            Button {
                looper.toggleRecordOnSelected()
            } label: {
                ZStack {
                    Circle().fill(recordColor).frame(width: 56, height: 56)
                    Image(systemName: recordIcon).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .onChange(of: metronome.isRunning) { _, _ in }
        .onAppear {
            metronome.onBeat = { i in beatPulse = i }
        }
    }

    private var transposeLabel: String {
        if transpose == 0 { return "0" }
        return transpose > 0 ? "+\(transpose)" : "\(transpose)"
    }

    private var recordColor: Color {
        let s = looper.tracks[looper.selectedTrack].state
        switch s {
        case .recording, .countIn: return .red
        case .overdubbing: return .orange
        case .playing: return .green
        default: return .white.opacity(0.25)
        }
    }
    private var recordIcon: String {
        let s = looper.tracks[looper.selectedTrack].state
        switch s {
        case .recording, .countIn, .overdubbing: return "stop.fill"
        case .playing: return "plus.circle.fill"
        default: return "circle.fill"
        }
    }
}

private struct BeatLamp: View {
    let beat: Int
    let count: Int
    var body: some View {
        let active = ((beat % count) + count) % count
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == active ? Color.red : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .animation(.linear(duration: 0.05), value: active)
            }
        }
    }
}

private struct TrackChip: View {
    @ObservedObject var track: Looper.Track
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("T\(track.id + 1)")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white.opacity(0.6))
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(fillColor)
                    .frame(width: 44, height: 32)
                Text(stateLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.white : .clear, lineWidth: 2))
        }
    }

    private var fillColor: Color {
        switch track.state {
        case .empty:        return Color(white: 0.18)
        case .armed:        return Color.yellow.opacity(0.7)
        case .countIn:      return Color.orange.opacity(0.8)
        case .recording:    return Color.red
        case .playing:      return Color.green.opacity(0.8)
        case .overdubbing:  return Color.orange
        case .muted:        return Color(white: 0.12)
        }
    }

    private var stateLabel: String {
        switch track.state {
        case .empty:        return "—"
        case .armed:        return "ARM"
        case .countIn(let n): return "\(n)"
        case .recording(let f, let t): return "\(min(99, Int(Double(f) / Double(t) * 99)))"
        case .playing:      return "PLAY"
        case .overdubbing:  return "OD"
        case .muted:        return "MUTE"
        }
    }
}
