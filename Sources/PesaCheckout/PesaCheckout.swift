@_exported import PesaCheckoutCore

#if canImport(UIKit)
import UIKit
import SafariServices
import WebKit

/// Where the 3-D Secure challenge shows.
public enum PesaChallengeSurface: Sendable {
    /// A full-screen web view inside the app. The customer never leaves.
    case inApp
    /// `SFSafariViewController`. The intent's `returnUrl`, your universal
    /// link, brings the customer back through `handle(url:)`.
    case browser
}

/// The app-facing entry point: one client, the 3-D Secure page, and the
/// universal-link hand-off. Create one and keep it, or use `shared` after
/// `configure`.
@MainActor
public final class PesaCheckout {
    public static var shared = PesaCheckout()

    public let client: PesaCheckoutClient
    private let challenge: PesaChallengePresenter & ChallengeDismissing

    /// The in-app 3-D Secure page has a close button and no title, since
    /// the bank's page has its own heading; `challengeTitle` gives it one.
    public init(configuration: PesaCheckoutConfiguration = .init(), challenge surface: PesaChallengeSurface = .inApp,
                challengeTitle: String? = nil) {
        client = PesaCheckoutClient(configuration: configuration)
        switch surface {
        case .inApp: challenge = WebViewChallengeOpener(locale: configuration.locale, title: challengeTitle)
        case .browser: challenge = SafariChallengeOpener()
        }
    }

    public static func configure(_ configuration: PesaCheckoutConfiguration, challenge surface: PesaChallengeSurface = .inApp,
                                 challengeTitle: String? = nil) {
        shared = PesaCheckout(configuration: configuration, challenge: surface, challengeTitle: challengeTitle)
    }

    /// Charges the card and follows it to an outcome; the bank's challenge,
    /// when asked for, shows over `presenter` (the top view controller when
    /// nil). Returns when the attempt is no longer pending.
    public func pay(intentId: String,
                    clientSecret: String,
                    card: CardDetails,
                    email: String? = nil,
                    saveCard: Bool = false,
                    from presenter: UIViewController? = nil) async throws -> CheckoutResult {
        challenge.presenter = presenter
        return try await client.payWithCard(intentId: intentId, clientSecret: clientSecret, card: card,
                                            email: email, saveCard: saveCard, challenge: challenge)
    }

    /// Charges a saved card from the session and follows it to an outcome,
    /// as `pay(intentId:clientSecret:card:)` does.
    public func payWithSavedCard(intentId: String,
                                 clientSecret: String,
                                 token: String,
                                 securityCode: SecretBytes? = nil,
                                 email: String? = nil,
                                 from presenter: UIViewController? = nil) async throws -> CheckoutResult {
        challenge.presenter = presenter
        return try await client.payWithSavedCard(intentId: intentId, clientSecret: clientSecret, token: token,
                                                 securityCode: securityCode, email: email, challenge: challenge)
    }

    /// Call from `onOpenURL` / `scene(_:openURLContexts:)` /
    /// `application(_:continue:)` with the universal link the checkout
    /// return page sent the browser to. Dismisses the challenge page; the
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

/// What both surfaces share beyond the core protocol: the view controller
/// to present from, and a dismiss the app can call on a return link.
@MainActor
protocol ChallengeDismissing: AnyObject {
    var presenter: UIViewController? { get set }
    func dismiss()
}

/// Presents the 3-D Secure challenge in a full-screen `WKWebView`. Only
/// `http(s)` loads; the checkout's return page, or the bounce to the app's
/// own scheme, ends it. The close button asks before it cancels.
@MainActor
public final class WebViewChallengeOpener: PesaChallengePresenter, ChallengeDismissing {
    public var presenter: UIViewController?
    private let locale: String?
    private let title: String?
    private weak var page: ChallengeViewController?

    /// `title` is the page's title; none by default, since the bank's page
    /// has its own heading.
    public init(locale: String? = nil, title: String? = nil) {
        self.locale = locale
        self.title = title
    }

    public func open(_ url: URL, onCancelled: @escaping @Sendable () -> Void) async -> Bool {
        guard url.scheme == "https", let host = presenter ?? Self.topViewController() else { return false }
        dismiss()
        let page = ChallengeViewController(url: url, title: title, strings: PesaStrings.resolve(locale), onCancelled: onCancelled)
        let nav = UINavigationController(rootViewController: page)
        nav.modalPresentationStyle = .fullScreen
        self.page = page
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            host.present(nav, animated: true) { c.resume() }
        }
        return true
    }

    public func close() async {
        dismiss()
    }

    public func dismiss() {
        page?.endedByCheckout()
        page = nil
    }

    static func topViewController() -> UIViewController? {
        SafariChallengeOpener.topViewController()
    }
}

/// The page that hosts the challenge. Its bar holds a close button and,
/// only when the host gave one, a title. Until the bank's page has loaded
/// the page says it is connecting; after that everything on it is the
/// bank's.
@MainActor
final class ChallengeViewController: UIViewController, WKNavigationDelegate {
    private let url: URL
    private let returnPath: String
    private let strings: PesaStrings
    private let onCancelled: @Sendable () -> Void
    private var done = false
    private var web: WKWebView!
    private let connecting = UILabel()
    private let progress = UIProgressView(progressViewStyle: .bar)
    private var progressObservation: NSKeyValueObservation?

    init(url: URL, title: String?, strings: PesaStrings, onCancelled: @escaping @Sendable () -> Void) {
        self.url = url
        self.returnPath = challengeReturnPath(for: url)
        self.strings = strings
        self.onCancelled = onCancelled
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let close = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        close.accessibilityLabel = strings.challengeCancel
        navigationItem.leftBarButtonItem = close

        web = WKWebView(frame: view.bounds, configuration: WKWebViewConfiguration())
        web.navigationDelegate = self
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(web)

        connecting.frame = view.bounds
        connecting.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        connecting.text = strings.challengeConnecting
        connecting.textAlignment = .center
        connecting.textColor = .label
        connecting.backgroundColor = .systemBackground
        view.addSubview(connecting)

        progress.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progress)
        NSLayoutConstraint.activate([
            progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        progressObservation = web.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
            Task { @MainActor in
                self?.progress.progress = Float(web.estimatedProgress)
                self?.progress.isHidden = web.estimatedProgress >= 1
            }
        }
        web.load(URLRequest(url: url))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The page has no title to read out, so it is named here.
        if title == nil { UIAccessibility.post(notification: .screenChanged, argument: strings.challengeLabel) }
    }

    /// Leaving cancels the payment, so the customer is asked first.
    @objc private func closeTapped() {
        guard !done else { return }
        let question = UIAlertController(title: strings.challengeCancelQuestion, message: nil, preferredStyle: .alert)
        question.addAction(UIAlertAction(title: strings.challengeKeepGoing, style: .cancel))
        question.addAction(UIAlertAction(title: strings.challengeCancel, style: .destructive) { [weak self] _ in
            Task { @MainActor in self?.cancelledByCustomer() }
        })
        present(question, animated: true)
    }

    private func cancelledByCustomer() {
        guard !done else { return }
        done = true
        let cancelled = onCancelled
        leave { cancelled() }
    }

    /// The checkout settled the attempt, or the issuer sent the cardholder
    /// back: nothing to tell the caller.
    func endedByCheckout() {
        guard !done else { return }
        done = true
        leave()
    }

    /// Dismisses from the presenter, so a question still on screen goes
    /// with the page.
    private func leave(completion: (() -> Void)? = nil) {
        let presenter = navigationController?.presentingViewController ?? presentingViewController
        presenter?.dismiss(animated: true, completion: completion)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        connecting.removeFromSuperview()
    }

    private func isReturn(_ target: URL) -> Bool {
        target.host == url.host && target.path.replacingOccurrences(of: #"/$"#, with: "", options: .regularExpression) == returnPath
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let target = navigationAction.request.url else { return decisionHandler(.cancel) }
        if isReturn(target) {
            decisionHandler(.cancel)
            endedByCheckout()
            return
        }
        if target.scheme == "https" || target.scheme == "http" {
            return decisionHandler(.allow)
        }
        // The issuer's 3-D Secure iframes start on about:blank, about:srcdoc
        // or data:. They are part of the challenge, not the end of it.
        if navigationAction.targetFrame?.isMainFrame != true {
            let inFrame = ["about", "data", "blob"].contains(target.scheme ?? "")
            return decisionHandler(inFrame ? .allow : .cancel)
        }
        decisionHandler(.cancel)
        endedByCheckout()
    }
}

/// Presents the 3-D Secure challenge in `SFSafariViewController`, the
/// browser surface Apple intends for this: the app never sees the issuer's
/// page, and cookies stay with Safari.
@MainActor
public final class SafariChallengeOpener: NSObject, SFSafariViewControllerDelegate, PesaChallengePresenter, ChallengeDismissing {
    public var presenter: UIViewController?
    private weak var presented: SFSafariViewController?
    private var onCancelled: (@Sendable () -> Void)?

    public override init() {}

    public func open(_ url: URL, onCancelled: @escaping @Sendable () -> Void) async -> Bool {
        self.onCancelled = onCancelled
        return await open(url, from: presenter)
    }

    public func close() async {
        dismiss()
    }

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
        onCancelled = nil
        presented?.dismiss(animated: true)
        presented = nil
    }

    /// The cardholder tapped Done before the issuer sent them back.
    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        presented = nil
        let cancelled = onCancelled
        onCancelled = nil
        cancelled?()
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
