import UIKit

/// Physical feedback for the moments that matter: a set logged, a rest timer
/// finishing, a workout closed out. `prepare()` is what keeps the tap feeling
/// immediate rather than arriving a beat late.
final class HapticsModule: BridgeModule {

    private let impactGenerators: [String: UIImpactFeedbackGenerator] = [
        "light": UIImpactFeedbackGenerator(style: .light),
        "medium": UIImpactFeedbackGenerator(style: .medium),
        "heavy": UIImpactFeedbackGenerator(style: .heavy),
        "soft": UIImpactFeedbackGenerator(style: .soft),
        "rigid": UIImpactFeedbackGenerator(style: .rigid)
    ]
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    func handle(action: String, payload: [String: Any], reply: Reply) {
        switch action {
        case "impact":
            let style = payload["style"] as? String ?? "medium"
            guard let generator = impactGenerators[style] else {
                reply.failure("Unknown haptic style '\(style)'.")
                return
            }
            generator.prepare()
            generator.impactOccurred()
            reply.success(true)

        case "selection":
            selectionGenerator.prepare()
            selectionGenerator.selectionChanged()
            reply.success(true)

        case "notification":
            let type: UINotificationFeedbackGenerator.FeedbackType
            switch payload["type"] as? String {
            case "warning": type = .warning
            case "error": type = .error
            default: type = .success
            }
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(type)
            reply.success(true)

        default:
            reply.failure("Unknown haptics action '\(action)'.")
        }
    }
}
