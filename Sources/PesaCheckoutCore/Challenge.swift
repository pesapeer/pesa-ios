import Foundation

/// Shows the 3-D Secure challenge page to the cardholder.
///
/// The client calls `open` once when the issuer asks for a challenge, keeps
/// polling the attempt meanwhile, and calls `close` once the attempt has
/// settled. The page is the checkout edge's, which posts to the issuer and
/// takes the cardholder back when they are done.
public protocol PesaChallengePresenter: AnyObject, Sendable {
    /// Shows `url`. True once the page is up, false when it could not be
    /// shown at all. `onCancelled` is called if the cardholder dismisses the
    /// page before it finished; the payment then ends with
    /// `PesaCheckoutError.Code.challengeCancelled`.
    func open(_ url: URL, onCancelled: @escaping @Sendable () -> Void) async -> Bool

    /// Hides the page. A no-op when nothing is open.
    func close() async
}

/// A presenter from an open-only closure: the pre-0.4.0 contract, for a
/// browser the SDK cannot close. The checkout's return page then sends the
/// browser to the intent's `returnUrl`, the app's own link.
public final class ClosureChallengePresenter: PesaChallengePresenter {
    private let openURL: @Sendable (URL) async -> Bool

    public init(_ open: @escaping @Sendable (URL) async -> Bool) {
        openURL = open
    }

    public func open(_ url: URL, onCancelled: @escaping @Sendable () -> Void) async -> Bool {
        await openURL(url)
    }

    public func close() async {}
}

/// The challenge's return page on the checkout edge: `/c/{intent}/return`,
/// next to the `/c/{intent}/challenge` page the presenter was given.
public func challengeReturnPath(for challengeURL: URL) -> String {
    challengeURL.path.replacingOccurrences(of: #"/challenge/?$"#, with: "/return", options: .regularExpression)
}
