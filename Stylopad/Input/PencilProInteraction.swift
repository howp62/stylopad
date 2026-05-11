import UIKit

/// Wires Apple Pencil Pro squeeze and haptics into the running session.
/// Squeeze is hardware-gated to Pencil Pro; haptics fall back to the
/// generic UIImpactFeedbackGenerator on older iOS versions.
@available(iOS 17.0, *)
final class PencilProInteraction: NSObject, UIPencilInteractionDelegate {
    private let interaction = UIPencilInteraction()
    weak var hostView: UIView?

    var onSqueeze: () -> Void = {}

    func attach(to view: UIView) {
        hostView = view
        interaction.delegate = self
        view.addInteraction(interaction)
    }

    // iOS 17.5+ delivers richer squeeze events. We collapse them to a single
    // edge-trigger callback (record toggle).
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        switch squeeze.phase {
        case .ended:
            onSqueeze()
            HapticEngine.shared.fire(.recordToggle)
        default: break
        }
    }

    // Pre-Pencil Pro fallback: double-tap on the side of Pencil 2nd gen.
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        onSqueeze()
        HapticEngine.shared.fire(.recordToggle)
    }
}

/// Centralised haptic dispatcher.
/// On iPadOS 18+ with Pencil Pro we'd use UICanvasFeedbackGenerator on the
/// keyboard view; for everything else we fall back to the standard impact
/// generator, which still routes to the system-appropriate haptic device.
enum HapticEvent {
    case beat        // metronome accent / regular
    case recordToggle
    case loopBoundary
}

final class HapticEngine: @unchecked Sendable {
    static let shared = HapticEngine()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)

    private init() {
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
    }

    @MainActor
    func fire(_ event: HapticEvent) {
        switch event {
        case .beat:
            lightImpact.impactOccurred(intensity: 0.4)
        case .recordToggle:
            mediumImpact.impactOccurred(intensity: 0.9)
        case .loopBoundary:
            rigidImpact.impactOccurred(intensity: 0.7)
        }
    }
}
