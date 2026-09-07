import Foundation

/// Every value the app needs that isn't code. Kept in one place so that
/// pointing a build at a staging site, or renaming the bundle, is a one-line edit.
enum AppConfig {

    // MARK: - Web app

    /// The site the shell loads. The web app is the product; this app is its
    /// native container.
    static let webAppURL = URL(string: "https://app.metastoryhealth.com/")!

    /// Hosts that stay inside the app. Anything else is a link *out* of the
    /// product (a supplement store, a lab portal, a scheduler) and opens in
    /// Safari instead, so people can tell where they are and can sign in with
    /// their saved Safari credentials.
    static let internalHosts: Set<String> = [
        "app.metastoryhealth.com"
    ]

    /// Appended to the default WKWebView user agent. The web app keys off
    /// `MetastoryiOS` to know it is running natively; keep the token stable.
    static let userAgentSuffix = "MetastoryiOS"

    // MARK: - Sign in with Google
    //
    // Google refuses OAuth inside an embedded web view, so sign-in runs
    // natively through ASWebAuthenticationSession and hands the resulting
    // credential back to the Firebase SDK in the page. That needs an OAuth
    // *iOS* client (not the web client the PWA uses).
    //
    // Google Cloud console -> APIs & Services -> Credentials -> Create
    // credentials -> OAuth client ID -> iOS, with the bundle ID below.
    // See ios/SHIPPING.md, step 4.

    /// e.g. "980408905992-abc123def456.apps.googleusercontent.com"
    static let googleClientID = "REPLACE_WITH_GOOGLE_IOS_CLIENT_ID"

    /// Google's redirect scheme is the client ID with its dot-separated parts
    /// reversed. Derived rather than hand-copied so the two can't drift apart.
    static var googleRedirectScheme: String {
        googleClientID
            .split(separator: ".")
            .reversed()
            .joined(separator: ".")
    }

    static var googleRedirectURI: String {
        "\(googleRedirectScheme):/oauth2redirect"
    }

    /// True once a real client ID has been filled in above. Until then the
    /// Google button reports a setup error instead of opening a broken sheet.
    static var isGoogleConfigured: Bool {
        googleClientID.hasSuffix(".apps.googleusercontent.com")
    }

    // MARK: - Support

    static let supportEmail = "support@metastoryhealth.com"
    static let privacyPolicyURL = URL(string: "https://metastoryhealth.com/privacy")!

    // MARK: - Appearance

    /// The web app's parchment background (#f1ede5). Used for the window and
    /// the web view so there is no white flash before the page paints.
    static let backgroundColorHex = 0xF1EDE5
}
