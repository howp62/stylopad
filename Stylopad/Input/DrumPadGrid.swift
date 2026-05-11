import UIKit

/// 4×2 grid of drum pads. Pencil-only. Each pad fires `BeatEngine.triggerPad`
/// on touch-down with velocity from `force`.
final class DrumPadGrid: UIView {
    weak var engine: BeatEngine?
    /// Drum pads accept finger touch by default — drumming with a pencil is awkward.
    var pencilOnly: Bool = false

    private let columns = 4
    private let rows = 2
    private var pressedPad: Int? = nil

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.10, alpha: 1)
        isMultipleTouchEnabled = true
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 0, alpha: 0.5).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    private var padCount: Int { columns * rows }

    private func padRect(for index: Int) -> CGRect {
        let pad: CGFloat = 6
        let w = (bounds.width - pad * CGFloat(columns + 1)) / CGFloat(columns)
        let h = (bounds.height - pad * CGFloat(rows + 1)) / CGFloat(rows)
        let col = index % columns
        let row = index / columns
        return CGRect(
            x: pad + CGFloat(col) * (w + pad),
            y: pad + CGFloat(row) * (h + pad),
            width: w,
            height: h
        )
    }

    private func padIndex(at point: CGPoint) -> Int? {
        for i in 0..<padCount {
            if padRect(for: i).contains(point) { return i }
        }
        return nil
    }

    override func draw(_ rect: CGRect) {
        let labels = BeatEngine.DrumPad.allCases.map { $0.label }
        for i in 0..<padCount {
            let r = padRect(for: i)
            let path = UIBezierPath(roundedRect: r, cornerRadius: 6)
            let isPressed = (i == pressedPad)
            let fill: UIColor = isPressed
                ? UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1)
                : UIColor(white: 0.20, alpha: 1)
            fill.setFill()
            path.fill()
            UIColor(white: 1, alpha: 0.08).setStroke()
            path.lineWidth = 1
            path.stroke()

            // Label
            let label = i < labels.count ? labels[i] : "—"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(isPressed ? 1 : 0.7),
            ]
            let size = (label as NSString).size(withAttributes: attrs)
            (label as NSString).draw(
                at: CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2),
                withAttributes: attrs
            )
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if pencilOnly && touch.type != .pencil { continue }
            let p = touch.location(in: self)
            guard let idx = padIndex(at: p), idx < BeatEngine.DrumPad.allCases.count else { continue }
            let velocity = velocityFromForce(touch)
            engine?.triggerPad(BeatEngine.DrumPad.allCases[idx], velocity: velocity)
            pressedPad = idx
        }
        setNeedsDisplay()
        // Release the visual press after a short flash.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.pressedPad = nil
            self?.setNeedsDisplay()
        }
    }

    private func velocityFromForce(_ touch: UITouch) -> Float {
        let m = touch.maximumPossibleForce
        guard m > 0 else { return 0.9 }
        let n = Float(Swift.min(CGFloat(1), Swift.max(touch.force / m, CGFloat(0))))
        return 0.4 + 0.6 * n
    }
}

struct DrumPadGridRepresentable: UIViewRepresentable {
    let engine: BeatEngine
    func makeUIView(context: Context) -> DrumPadGrid {
        let v = DrumPadGrid(); v.engine = engine; return v
    }
    func updateUIView(_ uiView: DrumPadGrid, context: Context) {
        uiView.engine = engine
    }
}

import SwiftUI
