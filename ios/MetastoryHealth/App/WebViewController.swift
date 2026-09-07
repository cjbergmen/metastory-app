import UIKit
import WebKit
import SafariServices

/// The whole app. A full-bleed web view over the Metastory web app, plus the
/// native affordances the web can't provide: reliable timers, background
/// audio, haptics, Health, and sign-in.
final class WebViewController: UIViewController {

    private(set) var webView: WKWebView!
    private var bridge: NativeBridge!
    private let refreshControl = UIRefreshControl()
    private lazy var offlineView = OfflineView { [weak self] in self?.reload() }

    /// True once any page has painted. Until then a failure means "nothing to
    /// show", and we put up the offline screen rather than leaving a blank
    /// window.
    private var hasLoadedOnce = false

    // MARK: - Lifecycle

    override func loadView() {
        view = UIView()
        view.backgroundColor = UIColor(hex: AppConfig.backgroundColorHex)
        setUpWebView()
        setUpOfflineView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        load()
    }

    /// The page is a light parchment colour, so the clock and battery need to
    /// be dark to be readable.
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Web view

    private func setUpWebView() {
        let configuration = WKWebViewConfiguration()

        // The default (persistent) data store is what keeps localStorage,
        // IndexedDB and the Firebase auth session alive between launches. Do
        // not switch this to .nonPersistent — it would sign everyone out and
        // drop their local logs on every cold start.
        configuration.websiteDataStore = .default()

        configuration.allowsInlineMediaPlayback = true
        // The album has its own in-page transport controls; requiring a second
        // "real" user gesture per track would break skip and autoplay-next.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.suppressesIncrementalRendering = false

        // Appends to the system user agent rather than replacing it, so the
        // page still sees a normal Safari string and can key off
        // "MetastoryiOS" to tell it is running natively.
        configuration.applicationNameForUserAgent =
            "\(AppConfig.userAgentSuffix)/\(Bundle.main.shortVersion)"

        bridge = NativeBridge(host: self)

        let controller = configuration.userContentController
        controller.addUserScript(
            WKUserScript(
                source: NativeBridge.injectedJavaScript(),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        // The reply-based handler lets each JS call return a real promise, so
        // the page can await a Health query or a sign-in instead of wiring up
        // its own callback registry.
        controller.addScriptMessageHandler(bridge, contentWorld: .page, name: NativeBridge.handlerName)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor(hex: AppConfig.backgroundColorHex)
        webView.scrollView.backgroundColor = UIColor(hex: AppConfig.backgroundColorHex)

        // The page already handles the notch and home indicator itself via
        // `viewport-fit=cover` and env(safe-area-inset-*). Letting UIKit add
        // its own insets on top would double the padding.
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        refreshControl.tintColor = UIColor(white: 0.45, alpha: 1)
        webView.scrollView.refreshControl = refreshControl

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        // Pinned to the view's edges, not its safe area, so the page can paint
        // under the status bar the way it does as a home-screen PWA.
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setUpOfflineView() {
        offlineView.translatesAutoresizingMaskIntoConstraints = false
        offlineView.isHidden = true
        view.addSubview(offlineView)
        NSLayoutConstraint.activate([
            offlineView.topAnchor.constraint(equalTo: view.topAnchor),
            offlineView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            offlineView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            offlineView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    // MARK: - Loading

    private func load() {
        webView.load(URLRequest(url: AppConfig.webAppURL))
    }

    func reload() {
        offlineView.isHidden = true
        if hasLoadedOnce, webView.url != nil {
            webView.reload()
        } else {
            load()
        }
    }

    @objc private func handlePullToRefresh() {
        webView.reload()
    }

    private func showOffline(_ message: String) {
        offlineView.message = message
        offlineView.isHidden = false
    }

    // MARK: - Talking to the page

    /// Fire a DOM event the web app can listen for. Payload must already be
    /// JSON.
    func emit(event: String, payload: String = "null") {
        let script = "window.Metastory && window.Metastory._emit(\(event.jsQuoted), \(payload));"
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    func notifyDidBecomeActive() {
        emit(event: "resume")
    }

    // MARK: - External links

    fileprivate func openExternally(_ url: URL) {
        guard let scheme = url.scheme?.lowercased() else { return }

        if scheme == "http" || scheme == "https" {
            // In-app Safari keeps people one swipe from coming back, and it
            // shares Safari's cookies so a Fullscript or lab-portal login they
            // already have carries over.
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = UIColor(hex: 0x2F6F4E)
            present(safari, animated: true)
        } else {
            // mailto:, tel:, maps: and friends belong to other apps.
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // about:blank, blob: and data: are the page's own machinery.
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            decisionHandler(.allow)
            return
        }

        if let host = url.host, AppConfig.internalHosts.contains(host) {
            decisionHandler(.allow)
            return
        }

        // Sub-resources (the Firebase SDK from gstatic, the AI worker, images)
        // must load normally; only a *navigation the person triggered* should
        // leave the app.
        if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            openExternally(url)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoadedOnce = true
        refreshControl.endRefreshing()
        offlineView.isHidden = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleLoadFailure(error)
    }

    private func handleLoadFailure(_ error: Error) {
        refreshControl.endRefreshing()

        let nsError = error as NSError
        // -999 is "a newer navigation replaced this one", which is normal and
        // not something to show a person.
        guard nsError.code != NSURLErrorCancelled else { return }

        // Once the app has painted, the service worker serves cached content,
        // so a failed *re-*load is better left alone than covered with a
        // full-screen error over a perfectly usable page.
        guard !hasLoadedOnce else { return }

        showOffline(
            nsError.code == NSURLErrorNotConnectedToInternet
                ? "You're offline. Metastory needs a connection the first time it opens."
                : "Couldn't reach Metastory. Check your connection and try again."
        )
    }

    /// The web content process can be killed under memory pressure; without
    /// this the app is left showing a permanently blank white view.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - WKUIDelegate

extension WebViewController: WKUIDelegate {

    /// `window.open` / `target="_blank"` — the app has no second web view, so
    /// these become Safari sheets.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if let host = url.host, AppConfig.internalHosts.contains(host) {
                webView.load(navigationAction.request)
            } else {
                openExternally(url)
            }
        }
        return nil
    }

    // The page uses alert/confirm/prompt for sign-out and delete confirmations.
    // WKWebView drops them on the floor unless the host presents them.

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presentOrComplete(alert) { completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        presentOrComplete(alert) { completionHandler(false) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text)
        })
        presentOrComplete(alert) { completionHandler(nil) }
    }

    /// If something is already on screen (a Safari sheet, the sign-in dialog),
    /// presenting would fail silently and the page's completion handler would
    /// never run — which deadlocks that JS call. Fall back instead.
    private func presentOrComplete(_ alert: UIAlertController, fallback: @escaping () -> Void) {
        if presentedViewController == nil {
            present(alert, animated: true)
        } else {
            fallback()
        }
    }
}

// MARK: - Small helpers

extension Bundle {
    var shortVersion: String {
        (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    var buildNumber: String {
        (object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }
}

extension String {
    /// JSON-quotes the string so it can be dropped into evaluated JavaScript.
    var jsQuoted: String {
        let data = try? JSONSerialization.data(withJSONObject: [self], options: [])
        guard let data, var text = String(data: data, encoding: .utf8) else { return "\"\"" }
        text.removeFirst()  // [
        text.removeLast()   // ]
        return text
    }
}
