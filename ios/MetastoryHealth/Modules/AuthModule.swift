import Foundation
import UIKit
import CryptoKit
import AuthenticationServices

/// Sign-in, natively.
///
/// Two reasons this can't stay in the web layer:
///
///   * Google refuses to serve its OAuth pages inside an embedded web view
///     (`disallowed_useragent`), so `signInWithPopup` and `signInWithRedirect`
///     both dead-end in a wrapped app. ASWebAuthenticationSession runs the
///     flow in a real Safari context, which Google does allow.
///   * App Review guideline 4.8 requires Sign in with Apple alongside a
///     third-party login like Google.
///
/// Both paths end the same way: this module hands a token back to the page,
/// and the Firebase SDK already loaded there turns it into a session with
/// `signInWithCredential`. No Firebase dependency is linked natively.
final class AuthModule: NSObject, BridgeModule {

    private unowned let host: WebViewController

    private var pendingReply: Reply?
    private var appleRawNonce: String?
    private var authorizationController: ASAuthorizationController?
    private var webAuthSession: ASWebAuthenticationSession?

    init(host: WebViewController) {
        self.host = host
        super.init()
    }

    // MARK: - BridgeModule

    func handle(action: String, payload: [String: Any], reply: Reply) {
        switch action {
        case "isGoogleConfigured":
            reply.success(AppConfig.isGoogleConfigured)

        case "signInWithApple":
            begin(reply) { self.startAppleSignIn() }

        case "signInWithGoogle":
            guard AppConfig.isGoogleConfigured else {
                reply.failure("Google sign-in isn't set up in this build yet.")
                return
            }
            begin(reply) { self.startGoogleSignIn() }

        default:
            reply.failure("Unknown auth action '\(action)'.")
        }
    }

    /// One flow at a time — two sign-in sheets racing each other would leave
    /// one of the page's promises unresolved forever.
    private func begin(_ reply: Reply, _ start: () -> Void) {
        if pendingReply != nil {
            reply.failure("A sign-in is already in progress.")
            return
        }
        pendingReply = reply
        start()
    }

    private func finish(success value: [String: Any]) {
        let reply = pendingReply
        pendingReply = nil
        reply?.success(value)
    }

    private func finish(failure message: String) {
        let reply = pendingReply
        pendingReply = nil
        reply?.failure(message)
    }

    // MARK: - Sign in with Apple

    private func startAppleSignIn() {
        // Firebase checks that the token's nonce hashes to the one Apple was
        // given, which is what stops a stolen token being replayed.
        let rawNonce = Self.randomURLSafeString(length: 32)
        appleRawNonce = rawNonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        authorizationController = controller
        controller.performRequests()
    }

    // MARK: - Sign in with Google

    private func startGoogleSignIn() {
        // Public clients can't keep a secret, so PKCE is what proves the app
        // that redeems the code is the one that asked for it.
        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.base64URLEncodedSHA256(verifier)
        let nonce = Self.randomURLSafeString(length: 32)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.googleClientID),
            URLQueryItem(name: "redirect_uri", value: AppConfig.googleRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: nonce)
        ]

        guard let url = components.url else {
            finish(failure: "Couldn't build the Google sign-in link.")
            return
        }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: AppConfig.googleRedirectScheme
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            self.webAuthSession = nil

            if let error = error as? ASWebAuthenticationSessionError,
               error.code == .canceledLogin {
                self.finish(failure: "cancelled")
                return
            }
            if let error {
                self.finish(failure: error.localizedDescription)
                return
            }
            guard
                let callbackURL,
                let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "code" })?
                    .value
            else {
                self.finish(failure: "Google didn't return a sign-in code.")
                return
            }

            self.exchangeGoogleCode(code, verifier: verifier)
        }

        session.presentationContextProvider = self
        // Not ephemeral: reusing the Safari session means someone already
        // signed in to Google on their phone just taps their account.
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session

        if !session.start() {
            webAuthSession = nil
            finish(failure: "Couldn't open the Google sign-in page.")
        }
    }

    private func exchangeGoogleCode(_ code: String, verifier: String) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: AppConfig.googleClientID),
            URLQueryItem(name: "redirect_uri", value: AppConfig.googleRedirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            if let error {
                self.finish(failure: error.localizedDescription)
                return
            }
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                self.finish(failure: "Google's reply couldn't be read.")
                return
            }
            guard let idToken = json["id_token"] as? String else {
                let description = json["error_description"] as? String
                    ?? json["error"] as? String
                    ?? "Google didn't return an identity token."
                self.finish(failure: description)
                return
            }

            var result: [String: Any] = ["provider": "google", "idToken": idToken]
            if let accessToken = json["access_token"] as? String {
                result["accessToken"] = accessToken
            }
            self.finish(success: result)
        }.resume()
    }

    // MARK: - Crypto helpers

    private static func randomURLSafeString(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else {
            // SecRandomCopyBytes failing means the system CSPRNG is broken;
            // quietly falling back to a weaker source would undermine the
            // whole point of the nonce.
            fatalError("Unable to generate secure random bytes (OSStatus \(status))")
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func base64URLEncodedSHA256(_ input: String) -> String {
        Data(SHA256.hash(data: Data(input.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Sign in with Apple delegates

extension AuthModule: ASAuthorizationControllerDelegate {

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        authorizationController = nil

        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let rawNonce = appleRawNonce
        else {
            finish(failure: "Apple didn't return an identity token.")
            return
        }
        appleRawNonce = nil

        var result: [String: Any] = [
            "provider": "apple",
            "idToken": idToken,
            "rawNonce": rawNonce
        ]

        // Apple sends the name and email on the *first* authorization only,
        // so whatever arrives here has to be passed straight through and
        // saved by the page — there is no second chance to ask.
        if let email = credential.email {
            result["email"] = email
        }
        if let name = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            let display = formatter.string(from: name).trimmingCharacters(in: .whitespaces)
            if !display.isEmpty { result["displayName"] = display }
        }
        if let codeData = credential.authorizationCode,
           let code = String(data: codeData, encoding: .utf8) {
            // Kept so account deletion can revoke the token, which Apple
            // requires of any app offering Sign in with Apple.
            result["authorizationCode"] = code
        }

        finish(success: result)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        authorizationController = nil
        appleRawNonce = nil

        if let error = error as? ASAuthorizationError, error.code == .canceled {
            finish(failure: "cancelled")
        } else {
            finish(failure: error.localizedDescription)
        }
    }
}

// MARK: - Presentation anchors

extension AuthModule: ASAuthorizationControllerPresentationContextProviding,
                      ASWebAuthenticationPresentationContextProviding {

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }

    private var anchor: ASPresentationAnchor {
        host.view.window ?? ASPresentationAnchor()
    }
}
