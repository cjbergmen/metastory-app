import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private(set) var webViewController: WebViewController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let controller = WebViewController()
        webViewController = controller

        let window = UIWindow(windowScene: windowScene)
        // Matching the page background means no white flash between the launch
        // screen and the first paint.
        window.backgroundColor = UIColor(hex: AppConfig.backgroundColorHex)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // A timer that fired while we were away has already been delivered as
        // a notification; clear the badge and let the page resync its clock.
        NotificationsModule.shared.clearDeliveredTimerNotifications()
        webViewController?.notifyDidBecomeActive()
    }
}

extension UIColor {
    /// 0xRRGGBB -> UIColor. The web app's palette is written in hex, and
    /// keeping the native chrome on the same values avoids near-miss colours.
    convenience init(hex: Int) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
