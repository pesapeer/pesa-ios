@_exported import PesaCheckoutCore

#if canImport(UIKit)
import UIKit
import SafariServices

/// The app-facing entry point: one client, the 3-D Secure opener, and the
/// universal-link hand-off. Create one and keep it, or use `shared` after
/// `configure`.
@MainActor
public final class PesaCheckout {
    public static var shared = PesaCheckout()

    public let client: PesaCheckoutClient
    private let challenge = SafariChallengeOpener()

    public init(configuration: PesaCheckoutConfiguration = .init()) {
        client = PesaCheckoutClient(configuration: configuration)
    }

    public static func configure(_ configuration: PesaCheckoutConfiguration) {
        shared = PesaCheckout(configuration: configuration)
    }

    /// Charges the card and follows it to an outcome; the bank's challenge,
    /// when asked for, opens in Safari over `presenter` (the top view
    /// controller when nil). Returns when the attempt is no longer pending.
    public func pay(intentId: String,
                    clientSecret: String,
                    card: CardDetails,
                    email: String? = nil,
                    saveCard: Bool = false,
                    from presenter: UIViewController? = nil) async throws -> CheckoutResult {
        let opener = challenge
        defer { Task { @MainActor in opener.dismiss() } }
        return try await client.payWithCard(intentId: intentId, clientSecret: clientSecret, card: card,
                                            email: email, saveCard: saveCard) { url in
            await opener.open(url, from: presenter)
        }
    }

    /// Charges a saved card from the session and follows it to an outcome,
    /// as `pay(intentId:clientSecret:card:)` does.
    public func payWithSavedCard(intentId: String,
                                 clientSecret: String,
                                 token: String,
                                 securityCode: SecretBytes? = nil,
                                 email: String? = nil,
                                 from presenter: UIViewController? = nil) async throws -> CheckoutResult {
        let opener = challenge
        defer { Task { @MainActor in opener.dismiss() } }
        return try await client.payWithSavedCard(intentId: intentId, clientSecret: clientSecret, token: token,
                                                 securityCode: securityCode, email: email) { url in
            await opener.open(url, from: presenter)
        }
    }

    /// Call from `onOpenURL` / `scene(_:openURLContexts:)` /
    /// `application(_:continue:)` with the universal link the checkout
    /// return page sent the browser to. Dismisses the challenge sheet; the
    /// outcome still arrives through `pay`'s polling. Returns true when the
    /// link was one of ours.
    @discardableResult
    public func handle(url: URL) -> Bool {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.contains(where: { $0.name == "intent" }) else { return false }
        challenge.dismiss()
        return true
    }
}

/// Presents the 3-D Secure challenge in `SFSafariViewController`, the
/// browser surface Apple intends for this: the app never sees the issuer's
/// page, and cookies stay with Safari.
@MainActor
public final class SafariChallengeOpener: NSObject, SFSafariViewControllerDelegate {
    private weak var presented: SFSafariViewController?

    public override init() {}

    /// Opens `url`; false when there is nothing to present from.
    public func open(_ url: URL, from presenter: UIViewController? = nil) async -> Bool {
        guard let host = presenter ?? Self.topViewController() else { return false }
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.delegate = self
        safari.dismissButtonStyle = .cancel
        safari.modalPresentationStyle = .formSheet
        presented = safari
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            host.present(safari, animated: true) { c.resume() }
        }
        return true
    }

    public func dismiss() {
        presented?.dismiss(animated: true)
        presented = nil
    }

    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        presented = nil
    }

    public static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}
#endif
