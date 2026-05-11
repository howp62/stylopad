import SwiftUI

struct KeyboardRepresentable: UIViewRepresentable {
    let engine: SynthEngine
    let looper: Looper

    func makeUIView(context: Context) -> KeyboardView {
        let v = KeyboardView()
        v.engine = engine
        v.installPencilProBridge { [weak looper] in
            Task { @MainActor in looper?.toggleRecordOnSelected() }
        }
        return v
    }

    func updateUIView(_ uiView: KeyboardView, context: Context) {
        uiView.engine = engine
    }
}
