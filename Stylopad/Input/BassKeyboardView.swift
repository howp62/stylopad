import UIKit
import SwiftUI

/// Bass keyboard: same visual style as the melody keyboard (pentagon white
/// keys + rounded-bottom black keys + numbered strips above/below) but a
/// full octave lower and routed to `BeatEngine.bass*`.
final class BassKeyboardView: UIView {
    weak var engine: BeatEngine?
    /// Bass accepts finger touch too — easier to noodle bass lines with a thumb.
    var pencilOnly: Bool = false

    private var activeTouch: UITouch? = nil
    private var currentMidi: Double = Double(BassRange.lowestMidi)

    private let topLabelHeight: CGFloat = 14
    private let bottomLabelHeight: CGFloat = 14
    private let blackHeightRatio: CGFloat = 0.62
    private let blackWidthRatio: CGFloat = 0.62

    private lazy var whiteMidis: [Int] = BassRange.whiteMidis

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        clipsToBounds = false
    }
    required init?(coder: NSCoder) { fatalError() }

    private var keysRect: CGRect {
        CGRect(x: 0, y: topLabelHeight, width: bounds.width,
               height: bounds.height - topLabelHeight - bottomLabelHeight)
    }
    private var whiteKeyWidth: CGFloat { keysRect.width / CGFloat(whiteMidis.count) }
    private func whiteKeyRect(_ index: Int) -> CGRect {
        let w = whiteKeyWidth
        return CGRect(x: keysRect.minX + CGFloat(index) * w,
                      y: keysRect.minY, width: w, height: keysRect.height)
    }
    private func blackKeyRect(forMidi midi: Int) -> CGRect {
        guard let leftWhiteIdx = whiteMidis.lastIndex(where: { $0 < midi }) else { return .zero }
        let leftRect = whiteKeyRect(leftWhiteIdx)
        let bw = whiteKeyWidth * blackWidthRatio
        let bh = keysRect.height * blackHeightRatio
        return CGRect(x: leftRect.maxX - bw / 2, y: keysRect.minY, width: bw, height: bh)
    }
    private func whiteKeyPath(at index: Int) -> UIBezierPath {
        let r = whiteKeyRect(index)
        let midi = whiteMidis[index]
        let hasLeftBlack = BassRange.isBlack(midi: midi - 1) && (midi - 1) >= BassRange.lowestMidi
        let hasRightBlack = BassRange.isBlack(midi: midi + 1) && (midi + 1) <= BassRange.highestMidi
        let bw = whiteKeyWidth * blackWidthRatio
        let bh = keysRect.height * blackHeightRatio
        let cut: CGFloat = bw / 2
        let bevel: CGFloat = Swift.min(whiteKeyWidth * 0.18, keysRect.height * 0.10)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        if hasRightBlack {
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + bh))
            path.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY + bh))
            path.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
        } else {
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + bevel))
            path.addLine(to: CGPoint(x: r.maxX - bevel, y: r.minY))
        }
        if hasLeftBlack {
            path.addLine(to: CGPoint(x: r.minX + cut, y: r.minY))
            path.addLine(to: CGPoint(x: r.minX + cut, y: r.minY + bh))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY + bh))
        } else {
            path.addLine(to: CGPoint(x: r.minX + bevel, y: r.minY))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY + bevel))
        }
        path.close()
        return path
    }
    private func keyMidi(at point: CGPoint) -> Int {
        let blackZoneBottom = keysRect.minY + keysRect.height * blackHeightRatio
        if point.y >= keysRect.minY && point.y <= blackZoneBottom {
            for midi in BassRange.lowestMidi...BassRange.highestMidi
            where BassRange.isBlack(midi: midi) {
                if blackKeyRect(forMidi: midi).contains(point) { return midi }
            }
        }
        let x = max(0, min(keysRect.width - 0.5, point.x))
        let idx = Int(x / whiteKeyWidth)
        return whiteMidis[max(0, min(whiteMidis.count - 1, idx))]
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        UIColor(white: 0.04, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: bounds.width, height: topLabelHeight)).fill()
        UIBezierPath(rect: CGRect(x: 0, y: bounds.height - bottomLabelHeight, width: bounds.width, height: bottomLabelHeight)).fill()

        // Brushed silver plate.
        drawSilverPlate(in: keysRect, ctx: ctx)

        let activeMidi = (activeTouch != nil) ? Int(currentMidi.rounded()) : nil
        if let am = activeMidi {
            if BassRange.isBlack(midi: am) {
                let r = blackKeyRect(forMidi: am)
                UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1).setFill()
                UIBezierPath(roundedRect: r,
                             byRoundingCorners: [.bottomLeft, .bottomRight],
                             cornerRadii: CGSize(width: 4, height: 4)).fill()
            } else if let idx = whiteMidis.firstIndex(of: am) {
                UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1).setFill()
                whiteKeyPath(at: idx).fill()
            }
        }

        UIColor(white: 0.06, alpha: 1).setStroke()
        for (i, _) in whiteMidis.enumerated() {
            let p = whiteKeyPath(at: i)
            p.lineWidth = 1.2; p.stroke()
        }
        for midi in BassRange.lowestMidi...BassRange.highestMidi where BassRange.isBlack(midi: midi) {
            let r = blackKeyRect(forMidi: midi)
            let p = UIBezierPath(roundedRect: r,
                                 byRoundingCorners: [.bottomLeft, .bottomRight],
                                 cornerRadii: CGSize(width: 4, height: 4))
            p.lineWidth = 1.2; p.stroke()
        }

        let whiteAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        for (i, _) in whiteMidis.enumerated() {
            let r = whiteKeyRect(i)
            let label = "\(i + 1)" as NSString
            let s = label.size(withAttributes: whiteAttrs)
            label.draw(at: CGPoint(x: r.midX - s.width / 2,
                                   y: bounds.height - bottomLabelHeight + (bottomLabelHeight - s.height) / 2),
                       withAttributes: whiteAttrs)
        }
        let blackAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        for midi in BassRange.lowestMidi...BassRange.highestMidi where BassRange.isBlack(midi: midi) {
            let whitesBefore = whiteMidis.filter { $0 < midi }.count
            let label = String(format: "%.1f", Double(whitesBefore) + 0.5) as NSString
            let r = blackKeyRect(forMidi: midi)
            let s = label.size(withAttributes: blackAttrs)
            label.draw(at: CGPoint(x: r.midX - s.width / 2, y: (topLabelHeight - s.height) / 2),
                       withAttributes: blackAttrs)
        }
    }

    override func layoutSubviews() { super.layoutSubviews(); setNeedsDisplay() }

    private func drawSilverPlate(in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        let colors = [
            UIColor(white: 0.97, alpha: 1).cgColor,
            UIColor(white: 0.82, alpha: 1).cgColor,
            UIColor(white: 0.90, alpha: 1).cgColor,
            UIColor(white: 0.70, alpha: 1).cgColor,
        ]
        let locations: [CGFloat] = [0.0, 0.45, 0.55, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray, locations: locations) {
            ctx.addRect(rect); ctx.clip()
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.midX, y: rect.minY),
                                   end: CGPoint(x: rect.midX, y: rect.maxY),
                                   options: [])
        }
        ctx.setBlendMode(.multiply)
        for i in stride(from: rect.minX, to: rect.maxX, by: 3) {
            let alpha = CGFloat.random(in: 0.02...0.06)
            ctx.setStrokeColor(UIColor.black.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: i, y: rect.minY))
            ctx.addLine(to: CGPoint(x: i, y: rect.maxY))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        if pencilOnly && touch.type != .pencil { return }
        activeTouch = touch
        let p = touch.location(in: self)
        currentMidi = Double(keyMidi(at: p))
        engine?.bassNoteOnContinuous(midi: currentMidi, velocity: velocity(touch))
        setNeedsDisplay()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        let p = touch.location(in: self)
        currentMidi = Double(keyMidi(at: p))
        engine?.bassSlide(toMidi: currentMidi)
        setNeedsDisplay()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        end()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end() }
    private func end() {
        engine?.bassReleaseAll()
        activeTouch = nil
        setNeedsDisplay()
    }
    private func velocity(_ t: UITouch) -> Float {
        let m = t.maximumPossibleForce
        guard m > 0 else { return 0.9 }
        let n = Float(Swift.min(CGFloat(1), Swift.max(t.force / m, CGFloat(0))))
        return 0.3 + 0.7 * n
    }
}

struct BassKeyboardRepresentable: UIViewRepresentable {
    let engine: BeatEngine
    func makeUIView(context: Context) -> BassKeyboardView {
        let v = BassKeyboardView(); v.engine = engine; return v
    }
    func updateUIView(_ uiView: BassKeyboardView, context: Context) {
        uiView.engine = engine
    }
}
