import Foundation
import UserNotifications

/// Rest timers, as real local notifications.
///
/// The PWA schedules these through a service worker `setTimeout`, which iOS
/// stops running within seconds of the app going to the background — so the
/// bell only ever rang if you happened to be looking at the screen. A local
/// notification is handed to the system at schedule time and fires whether the
/// app is backgrounded, suspended or killed.
final class NotificationsModule: NSObject, BridgeModule, UNUserNotificationCenterDelegate {

    static let shared = NotificationsModule()

    weak var host: WebViewController?

    /// Namespaced so `cancelAll` can't clear a notification some future
    /// feature scheduled.
    private static let identifierPrefix = "metastory.timer."

    private let center = UNUserNotificationCenter.current()

    private override init() { super.init() }

    // MARK: - BridgeModule

    func handle(action: String, payload: [String: Any], reply: Reply) {
        switch action {
        case "requestPermission":
            requestPermission(reply: reply)

        case "permission":
            center.getNotificationSettings { settings in
                reply.success(Self.name(for: settings.authorizationStatus))
            }

        case "schedule":
            schedule(payload: payload, reply: reply)

        case "cancel":
            let id = payload["id"] as? String ?? "rest"
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifierPrefix + id])
            center.removeDeliveredNotifications(withIdentifiers: [Self.identifierPrefix + id])
            reply.success(true)

        case "cancelAll":
            cancelAll()
            reply.success(true)

        default:
            reply.failure("Unknown timers action '\(action)'.")
        }
    }

    // MARK: - Permission

    private func requestPermission(reply: Reply) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else {
                reply.success("denied")
                return
            }

            switch settings.authorizationStatus {
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        reply.failure(error)
                    } else {
                        reply.success(granted ? "granted" : "denied")
                    }
                }
            default:
                reply.success(Self.name(for: settings.authorizationStatus))
            }
        }
    }

    private static func name(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "granted"
        case .denied: return "denied"
        case .notDetermined: return "default"
        @unknown default: return "default"
        }
    }

    // MARK: - Scheduling

    private func schedule(payload: [String: Any], reply: Reply) {
        let id = payload["id"] as? String ?? "rest"
        let seconds = (payload["seconds"] as? NSNumber)?.doubleValue ?? 0

        // Anything under a second would fire immediately (or be rejected by
        // the system); treat it as a cancel.
        guard seconds >= 1 else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifierPrefix + id])
            reply.success(false)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = payload["title"] as? String ?? "Rest Over"
        content.body = payload["body"] as? String ?? "Time to get back to it."
        content.sound = .default
        content.categoryIdentifier = "REST_TIMER"
        content.userInfo = ["timerId": id]
        // A rest timer is the textbook time-sensitive notification: it is
        // worthless a few minutes late, so it should break through Focus.
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )

        // Re-adding the same identifier replaces the pending one, which is
        // exactly what restarting a timer should do.
        center.add(request) { error in
            if let error {
                reply.failure(error)
            } else {
                reply.success(true)
            }
        }
    }

    private func cancelAll() {
        center.getPendingNotificationRequests { [weak self] requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.identifierPrefix) }
            guard !ids.isEmpty else { return }
            self?.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func clearDeliveredTimerNotifications() {
        center.getDeliveredNotifications { [weak self] delivered in
            let ids = delivered
                .map(\.request.identifier)
                .filter { $0.hasPrefix(Self.identifierPrefix) }
            guard !ids.isEmpty else { return }
            self?.center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// With the app on screen the page is already counting down and plays its
    /// own chime, so a banner and a second sound would just talk over it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let id = notification.request.content.userInfo["timerId"] as? String ?? "rest"
        host?.emit(event: "timer-fired", payload: "{\"id\":\(id.jsQuoted)}")
        completionHandler([])
    }

    /// Tapped from the lock screen — bring the page back in sync with a timer
    /// that ran out while it was suspended.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.content.userInfo["timerId"] as? String ?? "rest"
        host?.emit(event: "timer-fired", payload: "{\"id\":\(id.jsQuoted),\"opened\":true}")
        completionHandler()
    }
}
