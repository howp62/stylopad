import UIKit

/// Pencil-only piano keyboard styled after the 1968 Stylophone:
/// pentagon-shaped white keys with their top "shoulders" cut where
/// adjacent black keys sit, rounded-bottom black keys on top, with
/// number strips above (black-key labels) and below (white-key labels).
///
/// Behavior: at rest on a key, the key's exact MIDI plays.
/// While dragging, pitch glides smoothly through every key the Pencil
/// touches via the synth's 35 ms portamento. In the upper region the
/// Pencil can also hit black keys (chromatic slide); in the lower
/// region only white keys are reachable (whole-tone-style slide).
final class KeyboardView: UIView {
    weak var engine: SynthEngine?

    var pencilOnly: Bool = true
    var maxVibratoDepth: Double = 0.9
    /// Pencil Pro barrel-roll pitch bend. Off by default — even small natural
    /// roll on Pencil Pro made the melody drift ~½ semitone vs the bass.
    /// Toggle to a non-zero value to re-enable.
    var maxPitchBendSemis: Double = 0.0

    private var activeTouch: UITouch? = nil
    private var currentMidi: Double = Double(StylophoneRange.lowestMidi)
    private var pencilPro: PencilProInteraction?

    // Layout constants
    private let topLabelHeight: CGFloat = 14
    private let bottomLabelHeight: CGFloat = 14
    private let blackHeightRatio: CGFloat = 0.62
    private let blackWidthRatio: CGFloat = 0.62

    private lazy var whiteMidis: [Int] = StylophoneRange.whiteMidis

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        clipsToBounds = false

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)
    }
    required init?(coder: NSCoder) { fatalError() }

    func installPencilProBridge(_ onSqueeze: @escaping () -> Void) {
        if pencilPro == nil {
            let i = PencilProInteraction()
            i.onSqueeze = onSqueeze
            i.attach(to: self)
            pencilPro = i
        }
    }

    // MARK: - Geometry

    private var keysRect: CGRect {
        CGRect(
            x: 0,
            y: topLabelHeight,
            width: bounds.width,
            height: bounds.height - topLabelHeight - bottomLabelHeight
        )
    }

    private var whiteKeyWidth: CGFloat { keysRect.width / CGFloat(whiteMidis.count) }

    private func whiteKeyRect(_ index: Int) -> CGRect {
        let w = whiteKeyWidth
        return CGRect(x: keysRect.minX + CGFloat(index) * w,
                      y: keysRect.minY,
                      width: w,
                      height: keysRect.height)
    }

    private func blackKeyRect(forMidi midi: Int) -> CGRect {
        guard let leftWhiteIdx = whiteMidis.lastIndex(where: { $0 < midi }) else { return .zero }
        let leftRect = whiteKeyRect(leftWhiteIdx)
        let bw = whiteKeyWidth * blackWidthRatio
        let bh = keysRect.height * blackHeightRatio
        return CGRect(x: leftRect.maxX - bw / 2,
                      y: keysRect.minY,
                      width: bw,
                      height: bh)
    }

    /// Pentagon path for a white key with **45-degree bevels** at the
    /// top corners (matches the original Stylophone keys). When a neighbouring
    /// black key sits on either side, that shoulder is cut horizontally first
    /// (the black-key footprint) then a 45° diagonal connects the cut to the
    /// top edge.
    private func whiteKeyPath(at index: Int) -> UIBezierPath {
        let r = whiteKeyRect(index)
        let midi = whiteMidis[index]
        let hasLeftBlack = StylophoneRange.isBlack(midi: midi - 1) && (midi - 1) >= StylophoneRange.lowestMidi
        let hasRightBlack = StylophoneRange.isBlack(midi: midi + 1) && (midi + 1) <= StylophoneRange.highestMidi

        let bw = whiteKeyWidth * blackWidthRatio
        let bh = keysRect.height * blackHeightRatio
        let cut: CGFloat = bw / 2
        // 45° bevel size on the free top corners.
        let bevel: CGFloat = Swift.min(whiteKeyWidth * 0.18, keysRect.height * 0.10)

        let leftCut: CGFloat = hasLeftBlack ? cut : 0
        let rightCut: CGFloat = hasRightBlack ? cut : 0

        let path = UIBezierPath()
        path.move(to: CGPoint(x: r.minX, y: r.maxY))                  // bottom-left
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))               // bottom-right

        // Right edge up to either the black-key shoulder OR the bevel start.
        if hasRightBlack {
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + bh))
            path.addLine(to: CGPoint(x: r.maxX - rightCut, y: r.minY + bh))
            path.addLine(to: CGPoint(x: r.maxX - rightCut, y: r.minY))
        } else {
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + bevel))
            path.addLine(to: CGPoint(x: r.maxX - bevel, y: r.minY))
        }

        // Top edge across to the left bevel / shoulder.
        if hasLeftBlack {
            path.addLine(to: CGPoint(x: r.minX + leftCut, y: r.minY))
            path.addLine(to: CGPoint(x: r.minX + leftCut, y: r.minY + bh))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY + bh))
        } else {
            path.addLine(to: CGPoint(x: r.minX + bevel, y: r.minY))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY + bevel))
        }

        path.close()
        return path
    }

    private func keyMidi(at point: CGPoint) -> Int {
        // Adjust point into keysRect coordinates.
        let local = CGPoint(x: point.x, y: point.y)
        let blackZoneBottom = keysRect.minY + keysRect.height * blackHeightRatio

        // Black-key zone (upper portion).
        if local.y >= keysRect.minY && local.y <= blackZoneBottom {
            for midi in StylophoneRange.lowestMidi...StylophoneRange.highestMidi
            where StylophoneRange.isBlack(midi: midi) {
                if blackKeyRect(forMidi: midi).contains(local) { return midi }
            }
        }
        // White key fallback.
        let x = max(0, min(keysRect.width - 0.5, local.x))
        let idx = Int(x / whiteKeyWidth)
        return whiteMidis[max(0, min(whiteMidis.count - 1, idx))]
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Top/bottom number strips — slim black bars.
        UIColor(white: 0.04, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: bounds.width, height: topLabelHeight)).fill()
        UIBezierPath(rect: CGRect(x: 0, y: bounds.height - bottomLabelHeight, width: bounds.width, height: bottomLabelHeight)).fill()

        // Shiny silver metallic plate behind the keys.
        drawSilverPlate(in: keysRect, ctx: ctx)

        let activeMidi = (activeTouch != nil) ? Int(currentMidi.rounded()) : nil

        // Highlight only the active key.
        if let am = activeMidi {
            if StylophoneRange.isBlack(midi: am) {
                let r = blackKeyRect(forMidi: am)
                UIColor(red: 0.98, green: 0.72, blue: 0.18, alpha: 1).setFill()
                UIBezierPath(roundedRect: r,
                             byRoundingCorners: [.bottomLeft, .bottomRight],
                             cornerRadii: CGSize(width: 4, height: 4)).fill()
            } else if let idx = whiteMidis.firstIndex(of: am) {
                UIColor(red: 0.98, green: 0.78, blue: 0.18, alpha: 1).setFill()
                whiteKeyPath(at: idx).fill()
            }
        }

        // Engraved pentagon outlines.
        UIColor(white: 0.10, alpha: 1).setStroke()
        for (i, _) in whiteMidis.enumerated() {
            let p = whiteKeyPath(at: i)
            p.lineWidth = 1.3
            p.stroke()
        }
        for midi in StylophoneRange.lowestMidi...StylophoneRange.highestMidi
        where StylophoneRange.isBlack(midi: midi) {
            let r = blackKeyRect(forMidi: midi)
            let p = UIBezierPath(roundedRect: r,
                                 byRoundingCorners: [.bottomLeft, .bottomRight],
                                 cornerRadii: CGSize(width: 4, height: 4))
            p.lineWidth = 1.3
            p.stroke()
        }

        // Numbers.
        let whiteAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        for (i, _) in whiteMidis.enumerated() {
            let r = whiteKeyRect(i)
            let label = "\(i + 1)" as NSString
            let s = label.size(withAttributes: whiteAttrs)
            label.draw(
                at: CGPoint(x: r.midX - s.width / 2,
                            y: bounds.height - bottomLabelHeight + (bottomLabelHeight - s.height) / 2),
                withAttributes: whiteAttrs
            )
        }

        let blackAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.white,
        ]
        for midi in StylophoneRange.lowestMidi...StylophoneRange.highestMidi
        where StylophoneRange.isBlack(midi: midi) {
            // Black key index: count of whites before + 0.5
            let whitesBefore = whiteMidis.filter { $0 < midi }.count
            let label = String(format: "%.1f", Double(whitesBefore) + 0.5) as NSString
            let r = blackKeyRect(forMidi: midi)
            let s = label.size(withAttributes: blackAttrs)
            label.draw(
                at: CGPoint(x: r.midX - s.width / 2,
                            y: (topLabelHeight - s.height) / 2),
                withAttributes: blackAttrs
            )
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    /// Shiny brushed-silver plate fill.
    private func drawSilverPlate(in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            UIColor(white: 0.97, alpha: 1).cgColor,
            UIColor(white: 0.82, alpha: 1).cgColor,
            UIColor(white: 0.90, alpha: 1).cgColor,
            UIColor(white: 0.70, alpha: 1).cgColor,
        ]
        let locations: [CGFloat] = [0.0, 0.45, 0.55, 1.0]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) {
            ctx.addRect(rect)
            ctx.clip()
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
        }
        // Subtle vertical brushed-metal streaks.
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

    // MARK: - Hover

    @objc private func handleHover(_ gr: UIHoverGestureRecognizer) {
        // Hover preview without sound; just visual highlight could be added later.
        _ = gr
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        if pencilOnly && touch.type != .pencil { return }
        activeTouch = touch
        // Belt-and-braces: clear any residual pitch bend left by an earlier
        // Pencil session so the new note plays at exact pitch.
        engine?.setPitchBend(semitones: 0)
        let p = touch.location(in: self)
        currentMidi = Double(keyMidi(at: p))
        applyExpression(touch)
        engine?.noteOnContinuous(midi: currentMidi, velocity: velocity(touch), snap: false)
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        let p = touch.location(in: self)
        currentMidi = Double(keyMidi(at: p))
        applyExpression(touch)
        engine?.slidePitch(toMidi: currentMidi)
        engine?.setVolume(velocity(touch))
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        end()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end() }

    private func end() {
        engine?.releaseAll()
        engine?.setPitchBend(semitones: 0)
        activeTouch = nil
        setNeedsDisplay()
    }

    private func velocity(_ t: UITouch) -> Float {
        let m = t.maximumPossibleForce
        guard m > 0 else { return 0.9 }
        let n = Float(Swift.min(CGFloat(1), Swift.max(t.force / m, CGFloat(0))))
        return 0.25 + 0.75 * n
    }

    private func applyExpression(_ touch: UITouch) {
        guard touch.type == .pencil else { return }
        let alt = touch.altitudeAngle
        let tiltNorm = Swift.max(CGFloat(0), Swift.min(CGFloat(1), 1 - (alt / (.pi / 2))))
        engine?.setVibratoDepth(semitones: maxVibratoDepth * Double(tiltNorm))
        if #available(iOS 17.5, *) {
            let bend = sin(touch.rollAngle)
            engine?.setPitchBend(semitones: maxPitchBendSemis * Double(bend))
        }
    }
}
