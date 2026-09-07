import UIKit
import AVFoundation
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Claim the audio session up front. Declaring the category (without
        // activating it) doesn't interrupt whatever the phone is already
        // playing, but it does mean WebKit's media elements land in a
        // .playback session rather than the default .ambient one — which is
        // what lets the Safe Inside album keep going once the screen locks.
        AudioModule.configureSession()

        // Must be set before the app finishes launching, or a notification
        // that launched the app is delivered to nobody.
        UNUserNotificationCenter.current().delegate = NotificationsModule.shared

        return true
    }

    // MARK: - Scenes

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // MARK: - Orientation

    /// Phones stay portrait — the web layout is built for a single column.
    /// iPads get the full range so the app doesn't look broken in a Stage
    /// Manager window.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }
}
