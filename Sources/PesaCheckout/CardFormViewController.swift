#if canImport(UIKit)
import Combine
import SwiftUI
import UIKit
import PesaCheckoutCore

@MainActor
public protocol PesaCardFormViewControllerDelegate: AnyObject {
    func cardForm(_ controller: PesaCardFormViewController, completeDidChange complete: Bool)
    func cardForm(_ controller: PesaCardFormViewController, didFinish result: CheckoutResult)
    func cardForm(_ controller: PesaCardFormViewController, didFail error: PesaCheckoutError)
}

/// The SwiftUI form for UIKit apps: embed as a child view controller, call
/// `pay()` from your own button, or let `showsPayButton` draw one.
@MainActor
public final class PesaCardFormViewController: UIViewController {
    public weak var delegate: PesaCardFormViewControllerDelegate?
    public let state: PesaCardFormState
    public var intentId: String
    public var clientSecret: String
    public var checkout: PesaCheckout
    public var theme: PesaCardTheme
    public var showsPayButton: Bool
    /// Pass false to place `PesaSaveCardSwitch` yourself.
    public var showsSaveCardSwitch = true
    /// The pay button's title. With a saved card selected the button adds
    /// the card ("Pay £1.00 with •••• 0165"). Nil writes "Pay £1.00" from
    /// `amount` and `currency`, or "Pay" without them, in the form's language.
    public var payTitle: String?
    /// The amount as a decimal string, such as `1.00`, for the pay button.
    public var amount: String?
    public var currency: String?

    private var busy = false { didSet { host.rootView = makeRoot() } }
    private lazy var host = UIHostingController(rootView: makeRoot())
    private var completeObservation: Any?

    /// `locale` sets the form's language. Nil follows `sessionLocale` (the
    /// session's `locale`), then the device.
    public init(intentId: String, clientSecret: String, needsEmail: Bool = false,
                savedCards: [SavedCard] = [], savedCardSecurityCode: SavedCardSecurityCode = .never,
                canSaveCard: Bool = false,
                checkout: PesaCheckout? = nil, theme: PesaCardTheme = .pesa,
                showsPayButton: Bool = true, payTitle: String? = nil,
                amount: String? = nil, currency: String? = nil,
                locale: String? = nil, sessionLocale: String? = nil) {
        self.intentId = intentId
        self.clientSecret = clientSecret
        self.checkout = checkout ?? .shared
        self.theme = theme
        self.showsPayButton = showsPayButton
        self.payTitle = payTitle
        self.amount = amount
        self.currency = currency
        self.state = PesaCardFormState(needsEmail: needsEmail, savedCards: savedCards,
                                       savedCardSecurityCode: savedCardSecurityCode, canSaveCard: canSaveCard,
                                       locale: locale, sessionLocale: sessionLocale)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        completeObservation = state.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.delegate?.cardForm(self, completeDidChange: self.state.isComplete)
            }
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        SecureScreenGuard.shared.acquire()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        SecureScreenGuard.shared.release()
    }

    /// Sends the selected saved card or the typed card. Safe to call from
    /// your own button.
    public func pay() {
        guard !busy, state.isComplete else { return }
        let email = state.trimmedEmail
        let charge: @MainActor () async throws -> CheckoutResult
        if let saved = state.selectedSavedCard {
            let code = state.savedSecurityCodeBytes()
            charge = {
                try await self.checkout.payWithSavedCard(intentId: self.intentId, clientSecret: self.clientSecret, token: saved.token,
                                                         securityCode: code, email: email, from: self)
            }
        } else {
            guard let card = state.details() else { return }
            let saveCard = state.savesCard
            charge = {
                try await self.checkout.pay(intentId: self.intentId, clientSecret: self.clientSecret, card: card, email: email,
                                            saveCard: saveCard, from: self)
            }
        }
        busy = true
        state.clear()
        Task {
            defer { busy = false }
            do {
                let result = try await charge()
                delegate?.cardForm(self, didFinish: result)
            } catch let e as PesaCheckoutError {
                delegate?.cardForm(self, didFail: e)
            } catch {
                delegate?.cardForm(self, didFail: PesaCheckoutError(.transport, state.strings.errorNetwork))
            }
        }
    }

    private func makeRoot() -> AnyView {
        AnyView(VStack(spacing: 16) {
            PesaCardForm(state: state, theme: theme, showSaveCardSwitch: showsSaveCardSwitch)
            if showsPayButton {
                payButton
            }
        }.padding())
    }

    private var payButton: PesaPayButton {
        let action: () -> Void = { [weak self] in self?.pay() }
        if payTitle == nil, let amount, let currency {
            return PesaPayButton(state: state, amount: amount, currency: currency, busy: busy, theme: theme, action: action)
        }
        return PesaPayButton(state: state, title: payTitle ?? state.strings.payButton, busy: busy, theme: theme, action: action)
    }
}

#endif
