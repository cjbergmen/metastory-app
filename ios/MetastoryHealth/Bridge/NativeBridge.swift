import Foundation
import UIKit
import WebKit

/// Guarantees the WebKit reply handler is called exactly once. Calling it
/// twice raises an Objective-C exception that takes the app down, and never
/// calling it leaves a promise pending in the page forever.
final class Reply {
    private var handler: ((Any?, String?) -> Void)?

    init(_ handler: @escaping (Any?, String?) -> Void) {
        self.handler = handler
    }

    deinit {
        // A module that forgot to answer would otherwise hang the page.
        finish(nil, "The app didn't answer that request.")
    }

    func success(_ value: Any? = nil) { finish(value, nil) }

    func failure(_ message: String) { finish(nil, message) }

    func failure(_ error: Error) { finish(nil, error.localizedDescription) }

    private func finish(_ value: Any?, _ error: String?) {
        guard let handler else { return }
        self.handler = nil
        if Thread.isMainThread {
            handler(value, error)
        } else {
            DispatchQueue.main.async { handler(value, error) }
        }
    }
}

protocol BridgeModule: AnyObject {
    func handle(action: String, payload: [String: Any], reply: Reply)
}

/// Routes `window.Metastory` calls to the native modules.
final class NativeBridge: NSObject, WKScriptMessageHandlerWithReply {

    static let handlerName = "metastory"

    private unowned let host: WebViewController
    private let modules: [String: BridgeModule]

    init(host: WebViewController) {
        self.host = host
        let audio = AudioModule.shared
        audio.host = host
        NotificationsModule.shared.host = host

        modules = [
            "haptics": HapticsModule(),
            "timers": NotificationsModule.shared,
            "audio": audio,
            "health": HealthKitModule(),
            "auth": AuthModule(host: host),
            "app": AppModule(host: host)
        ]
        super.init()
    }

    // MARK: - Injected script

    static func injectedJavaScript() -> String {
        guard
            let url = Bundle.main.url(forResource: "bridge", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            // If this ever fires, bridge.js fell out of Copy Bundle Resources.
            assertionFailure("bridge.js is missing from the app bundle")
            return ""
        }

        return source
            .replacingOccurrences(of: "__APP_VERSION__", with: Bundle.main.shortVersion)
            .replacingOccurrences(of: "__APP_BUILD__", with: Bundle.main.buildNumber)
    }

    // MARK: - WKScriptMessageHandlerWithReply

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        let reply = Reply(replyHandler)

        guard
            let body = message.body as? [String: Any],
            let moduleName = body["module"] as? String,
            let action = body["action"] as? String
        else {
            reply.failure("Malformed bridge message.")
            return
        }

        guard let module = modules[moduleName] else {
            reply.failure("Unknown bridge module '\(moduleName)'.")
            return
        }

        let payload = body["payload"] as? [String: Any] ?? [:]
        module.handle(action: action, payload: payload, reply: reply)
    }
}

/// Odds and ends that don't warrant a module of their own.
final class AppModule: BridgeModule {

    private unowned let host: WebViewController

    init(host: WebViewController) { self.host = host }

    func handle(action: String, payload: [String: Any], reply: Reply) {
        switch action {
        case "openSettings":
            // Deep link to this app's row in Settings, where notification and
            // Health permissions are re-granted after a denial.
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                reply.failure("Settings is unavailable.")
                return
            }
            UIApplication.shared.open(url)
            reply.success(true)

        case "openExternal":
            guard let string = payload["url"] as? String, let url = URL(string: string) else {
                reply.failure("Not a valid URL.")
                return
            }
            // Only the schemes a link in the page could legitimately want.
            // Without this, anything that manages to run script in the page
            // could hand the system an arbitrary scheme to open.
            let allowed: Set<String> = ["http", "https", "mailto", "tel", "sms"]
            guard let scheme = url.scheme?.lowercased(), allowed.contains(scheme) else {
                reply.failure("That kind of link can't be opened.")
                return
            }
            // Same path as a tapped link, so http(s) gets the in-app Safari
            // sheet rather than throwing the person out to another app.
            host.openExternally(url)
            reply.success(true)

        default:
            reply.failure("Unknown app action '\(action)'.")
        }
    }
}
