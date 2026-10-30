#if canImport(UIKit)
import SwiftUI
import UIKit
import PesaCheckoutCore

/// Colours and shape of the form. Defaults follow the Pesa checkout and the
/// system colours, so they adapt to dark mode.
public struct PesaCardTheme: Sendable {
    public var primary: Color
    public var fieldBackground: Color
    /// The border of the fields, the saved-card list's outline and the
    /// hairlines between its rows.
    public var border: Color
    public var error: Color
    public var cornerRadius: CGFloat
    /// The surface of the saved-card list.
    public var listBackground: Color

    public init(primary: Color = Color(red: 0x1c / 255, green: 0x3f / 255, blue: 0xaa / 255),
                fieldBackground: Color = Color(.secondarySystemBackground),
                border: Color = Color(.separator),
                error: Color = Color(.systemRed),
                cornerRadius: CGFloat = 10,
                listBackground: Color = Color(.systemBackground)) {
        self.primary = primary
        self.fieldBackground = fieldBackground
        self.border = border
        self.error = error
        self.cornerRadius = cornerRadius
        self.listBackground = listBackground
    }

    public static let pesa = PesaCardTheme()
}

/// What the form holds. Observe `isComplete` for the pay button; call
/// `details()` to hand the card to the client, then `clear()`.
///
/// With `savedCards`, the first one that has not expired is selected. While
/// `selectedSavedCard` is set, pay with its token and
/// `savedSecurityCodeBytes()`; otherwise pay with `details()` and `savesCard`.
///
/// `strings` is the language of the form: `locale` from the host, then
/// `sessionLocale`, then the device, then English.
@MainActor
public final class PesaCardFormState: ObservableObject {
    @Published public private(set) var selectedSavedCard: SavedCard?
    @Published public var savedSecurityCode = "" { didSet { savedSecurityCode = String(savedSecurityCode.filter(\.isNumber).prefix(4)) } }
    @Published public var saveCard = false
    @Published public var number = "" { didSet { number = Self.groupNumber(number) } }
    @Published public var expiry = "" { didSet { expiry = Self.groupExpiry(expiry) } }
    @Published public var securityCode = "" { didSet { securityCode = String(securityCode.filter(\.isNumber).prefix(4)) } }
    @Published public var holderName = ""
    @Published public var email = ""
    @Published public var touched: Set<Field> = []

    public let needsEmail: Bool
    public let savedCards: [SavedCard]
    public let savedCardSecurityCode: SavedCardSecurityCode
    public let canSaveCard: Bool
    public let sessionLocale: String?
    public let strings: PesaStrings
    public let now: () -> Date

    public enum Field: Hashable, Sendable { case number, expiry, securityCode, holderName, email }

    public init(needsEmail: Bool = false,
                savedCards: [SavedCard] = [],
                savedCardSecurityCode: SavedCardSecurityCode = .never,
                canSaveCard: Bool = false,
                locale: String? = nil,
                sessionLocale: String? = nil,
                now: @escaping () -> Date = { Date() }) {
        self.needsEmail = needsEmail
        self.savedCards = savedCards
        self.savedCardSecurityCode = savedCardSecurityCode
        self.canSaveCard = canSaveCard
        self.sessionLocale = sessionLocale
        self.strings = PesaStrings.resolve(locale, session: sessionLocale)
        self.now = now
        self.selectedSavedCard = savedCards.first { $0.isUsable(at: now()) }
    }

    public convenience init(session: CheckoutSession, locale: String? = nil, now: @escaping () -> Date = { Date() }) {
        self.init(needsEmail: session.needsEmail, savedCards: session.savedCards,
                  savedCardSecurityCode: session.savedCardSecurityCode, canSaveCard: session.canSaveCard,
                  locale: locale, sessionLocale: session.locale, now: now)
    }

    public var digits: String { number.filter(\.isNumber) }
    public var brand: CardBrand { CardBrand.detect(digits) }
    public var usesSavedCard: Bool { selectedSavedCard != nil }
    public var asksSavedSecurityCode: Bool { usesSavedCard && savedCardSecurityCode != .never }
    public var savesCard: Bool { canSaveCard && saveCard && !usesSavedCard }

    /// Selects a saved card, or nil for "Use another card".
    public func select(_ card: SavedCard?) {
        selectedSavedCard = card
        savedSecurityCode = ""
        touched = []
    }

    /// `title` with the selected saved card, as "Pay £1.00 with •••• 0165";
    /// `title` alone for a typed card.
    public func payLabel(_ title: String) -> String {
        guard let card = selectedSavedCard else { return title }
        return strings.title(title, last4: card.last4)
    }

    /// "Pay £2.00", or "Pay £2.00 with •••• 0165" while a saved card is
    /// selected, in `strings`.
    public func payLabel(amount: String, currency: String) -> String {
        strings.payLabel(amount: amount, currency: currency, last4: selectedSavedCard?.last4)
    }

    /// The problem with `field`, in `strings` (the state's when nil).
    public func error(for field: Field, strings: PesaStrings? = nil) -> String? {
        let strings = strings ?? self.strings
        if let saved = selectedSavedCard {
            switch field {
            case .securityCode: return savedSecurityCodeError(brand: saved.cardBrand, strings: strings)
            case .email: return needsEmail ? CardValidation.email(email, strings: strings) : nil
            case .expiry: return saved.isUsable(at: now()) ? nil : strings.cardExpired
            case .number, .holderName: return nil
            }
        }
        switch field {
        case .number: return CardValidation.number(digits, strings: strings)
        case .expiry: return CardValidation.expiry(expiry, now: now(), strings: strings)
        case .securityCode: return CardValidation.securityCode(securityCode, brand: brand, strings: strings)
        case .holderName: return CardValidation.holderName(holderName, strings: strings)
        case .email: return needsEmail ? CardValidation.email(email, strings: strings) : nil
        }
    }

    private func savedSecurityCodeError(brand: CardBrand, strings: PesaStrings) -> String? {
        if !asksSavedSecurityCode { return nil }
        if savedCardSecurityCode == .optional && savedSecurityCode.isEmpty { return nil }
        return CardValidation.securityCode(savedSecurityCode, brand: brand, strings: strings)
    }

    /// The error to show: only once the field was left.
    public func shownError(for field: Field, strings: PesaStrings? = nil) -> String? {
        touched.contains(field) ? error(for: field, strings: strings) : nil
    }

    public var isComplete: Bool {
        [Field.number, .expiry, .securityCode, .holderName, .email].allSatisfy { error(for: $0) == nil }
    }

    /// The card as typed. Nil while incomplete.
    public func details() -> CardDetails? {
        guard !usesSavedCard, isComplete, let exp = CardExpiry.parse(expiry) else { return nil }
        return CardDetails(number: digits, expiry: exp, securityCode: securityCode, holderName: holderName)
    }

    /// The saved card's security code to send. Nil when there is none to send.
    public func savedSecurityCodeBytes() -> SecretBytes? {
        guard asksSavedSecurityCode, !savedSecurityCode.isEmpty else { return nil }
        return SecretBytes(savedSecurityCode)
    }

    public var trimmedEmail: String? {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.isEmpty ? nil : e
    }

    /// Overwrites then empties the sensitive fields.
    public func clear() {
        number = String(repeating: "0", count: number.count)
        securityCode = String(repeating: "0", count: securityCode.count)
        savedSecurityCode = String(repeating: "0", count: savedSecurityCode.count)
        number = ""
        securityCode = ""
        savedSecurityCode = ""
        expiry = ""
        touched = []
    }

    static func groupNumber(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(19))
        return CardValidation.format(digits, brand: CardBrand.detect(digits))
    }

    static func groupExpiry(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(4))
        if digits.count <= 2 { return digits }
        return digits.prefix(2) + " / " + digits.dropFirst(2)
    }
}

/// Native card fields. The PAN and CVV never leave the process except in
/// the client's request; copy is disabled on both and the screen is kept
/// out of captures by `PesaSecureScreen`.
///
/// With saved cards the form is one list: a row per saved card, then "Use
/// another card". Expired cards are listed but cannot be chosen. The
/// selected card takes its security code on its own row unless the session
/// says `.never`; "Use another card" opens the card fields under it, inside
/// the same list.
///
/// "Save this card for next time" is the last line of the card fields while
/// the session offers it. Pass `showSaveCardSwitch: false` to place
/// `PesaSaveCardSwitch` yourself.
///
/// The language is `locale` when set, else the state's `strings`.
public struct PesaCardForm: View {
    @ObservedObject private var state: PesaCardFormState
    private let theme: PesaCardTheme
    private let showSaveCardSwitch: Bool
    private let locale: String?
    private let strings: PesaStrings
    @FocusState private var focus: PesaCardFormState.Field?
    @State private var lastFocus: PesaCardFormState.Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: PesaCardFormState, theme: PesaCardTheme = .pesa, showSaveCardSwitch: Bool = true,
                locale: String? = nil) {
        self.state = state
        self.theme = theme
        self.showSaveCardSwitch = showSaveCardSwitch
        self.locale = locale
        self.strings = locale.map { PesaStrings.resolve($0, session: state.sessionLocale) } ?? state.strings
    }

    public var body: some View {
        Group {
            if state.savedCards.isEmpty {
                typedCard
            } else {
                savedCardPicker
            }
        }
        .onChange(of: focus) { newValue in
            if let left = lastFocus, left != newValue { state.touched.insert(left) }
            lastFocus = newValue
        }
    }

    private var typedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            newCardFields
            if showSaveCardSwitch {
                PesaSaveCardSwitch(state: state, theme: theme, locale: locale)
            }
        }
    }

    @ViewBuilder private var newCardFields: some View {
        field(strings.cardNumber, .number) {
            HStack {
                SecureCopyTextField(text: $state.number, placeholder: "1234 5678 9012 3456",
                                    contentType: .creditCardNumber, keyboard: .numberPad, secure: false)
                    .focused($focus, equals: .number)
                if state.brand != .unknown {
                    Text(state.brand.label).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        HStack(alignment: .top, spacing: 12) {
            field(strings.expiry, .expiry) {
                TextField(strings.expiryFormat, text: $state.expiry)
                    .keyboardType(.numberPad)
                    .textContentType(CardContentType.expiration)
                    .focused($focus, equals: .expiry)
            }
            field(state.brand == .amex ? strings.cid : strings.cvv, .securityCode) {
                SecureCopyTextField(text: $state.securityCode, placeholder: state.brand == .amex ? "1234" : "123",
                                    contentType: CardContentType.securityCode, keyboard: .numberPad, secure: true)
                    .focused($focus, equals: .securityCode)
            }
        }
        field(strings.holderName, .holderName) {
            TextField(strings.holderNamePlaceholder, text: $state.holderName)
                .textContentType(CardContentType.name)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.words)
                .focused($focus, equals: .holderName)
        }
        if state.needsEmail {
            emailField
        }
    }

    private var emailField: some View {
        field(strings.email, .email) {
            TextField(strings.emailPlaceholder, text: $state.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .focused($focus, equals: .email)
        }
    }

    private var savedCardPicker: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(state.savedCards, id: \.token) { card in
                savedCardRow(card)
                hairline
            }
            pickerRow(selected: state.selectedSavedCard == nil, usable: true, label: strings.useAnotherCard,
                      select: { state.select(nil) },
                      leading: { Image(systemName: "plus").font(.system(size: 18, weight: .semibold)) },
                      title: { Text(strings.useAnotherCard) },
                      trailing: { EmptyView() })
            if state.selectedSavedCard == nil {
                typedCard.padding(EdgeInsets(top: 4, leading: 16, bottom: 16, trailing: 16))
            } else if state.needsEmail {
                emailField.padding(EdgeInsets(top: 4, leading: 16, bottom: 16, trailing: 16))
            }
        }
        .background(theme.listBackground)
        .clipShape(shape)
        .overlay(shape.stroke(theme.border, lineWidth: 1))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state.selectedSavedCard)
    }

    private var hairline: some View {
        Rectangle().fill(theme.border).frame(height: 0.5).padding(.horizontal, 16)
    }

    private func savedCardRow(_ card: SavedCard) -> some View {
        let brand = card.cardBrand
        let usable = card.isUsable(at: state.now())
        let selected = state.selectedSavedCard?.token == card.token
        let asksCode = selected && state.asksSavedSecurityCode
        let error = asksCode ? state.shownError(for: .securityCode, strings: strings) : nil
        let expiry = usable ? strings.expiresOn(card.shortExpiry) : strings.expired
        return VStack(alignment: .leading, spacing: 0) {
            pickerRow(selected: selected, usable: usable,
                      label: strings.savedCardAccessibilityLabel(brand: strings.brandName(brand), last4: card.last4,
                                                                 expiry: usable ? card.shortExpiry : nil),
                      select: { state.select(card) },
                      leading: { brandChip(brand) },
                      title: {
                          VStack(alignment: .leading, spacing: 2) {
                              Text("•••• \(card.last4)")
                              Text(expiry).font(.footnote).foregroundColor(.secondary)
                          }
                      },
                      trailing: {
                          if asksCode { inlineSecurityCode(brand, error: error) }
                      })
            if let error {
                Text(error).font(.caption).foregroundColor(theme.error)
                    .padding(EdgeInsets(top: 0, leading: 68, bottom: 10, trailing: 16))
            }
        }
    }

    /// One row of the list. The trailing view sits outside the row's button
    /// so a text field there keeps its own taps and accessibility.
    private func pickerRow<Leading: View, Title: View, Trailing: View>(
        selected: Bool, usable: Bool, label: String, select: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading, @ViewBuilder title: () -> Title, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Button(action: select) {
                HStack(spacing: 12) {
                    leading().frame(width: 40)
                    title().font(.body.weight(selected ? .semibold : .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            trailing()
            Button(action: select) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selected ? theme.primary : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .disabled(!usable)
        .opacity(usable ? 1 : 0.45)
    }

    /// The brand on a white chip, so it reads the same on a dark surface.
    @ViewBuilder private func brandChip(_ brand: CardBrand) -> some View {
        if brand == .unknown {
            Image(systemName: "creditcard").foregroundColor(.secondary)
        } else {
            Text(Self.brandMark(brand))
                .font(.system(size: 9, weight: .black))
                .foregroundColor(Self.brandInk(brand))
                .frame(width: 40, height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.border, lineWidth: 0.5))
        }
    }

    private func inlineSecurityCode(_ brand: CardBrand, error: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        let ring = error != nil ? theme.error : (focus == .securityCode ? theme.primary : .clear)
        let name = brand == .amex ? strings.cid : strings.cvv
        return SecureCopyTextField(text: $state.savedSecurityCode, placeholder: name,
                                   contentType: CardContentType.securityCode, keyboard: .numberPad, secure: true)
            .focused($focus, equals: .securityCode)
            .padding(.horizontal, 10)
            .frame(width: 76, height: 38)
            .background(theme.fieldBackground)
            .clipShape(shape)
            .overlay(shape.stroke(ring, lineWidth: 1.5))
            .accessibilityLabel(state.savedCardSecurityCode == .optional ? strings.securityCodeOptional : strings.securityCode)
    }

    static func brandMark(_ brand: CardBrand) -> String {
        switch brand {
        case .visa: return "VISA"
        case .mastercard: return "MC"
        case .amex: return "AMEX"
        case .unionpay: return "UP"
        case .unknown: return ""
        }
    }

    static func brandInk(_ brand: CardBrand) -> Color {
        switch brand {
        case .visa: return Color(red: 0x1a / 255, green: 0x1f / 255, blue: 0x71 / 255)
        case .mastercard: return Color(red: 0xeb / 255, green: 0x00 / 255, blue: 0x1b / 255)
        case .amex: return Color(red: 0x2e / 255, green: 0x77 / 255, blue: 0xbc / 255)
        case .unionpay: return Color(red: 0xe2 / 255, green: 0x18 / 255, blue: 0x36 / 255)
        case .unknown: return .secondary
        }
    }

    private func field<Content: View>(_ label: String, _ f: PesaCardFormState.Field, @ViewBuilder content: () -> Content) -> some View {
        let err = state.shownError(for: f, strings: strings)
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote).foregroundColor(.secondary)
            content()
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(theme.fieldBackground)
                .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .stroke(err == nil ? (focus == f ? theme.primary : theme.border) : theme.error, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
            if let err {
                Text(err).font(.caption).foregroundColor(theme.error)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// "Save this card for next time", shown only while a typed card may be kept.
public struct PesaSaveCardSwitch: View {
    @ObservedObject private var state: PesaCardFormState
    private let theme: PesaCardTheme
    private let strings: PesaStrings

    public init(state: PesaCardFormState, theme: PesaCardTheme = .pesa, locale: String? = nil) {
        self.state = state
        self.theme = theme
        self.strings = locale.map { PesaStrings.resolve($0, session: state.sessionLocale) } ?? state.strings
    }

    public var body: some View {
        if state.canSaveCard && !state.usesSavedCard {
            Toggle(strings.saveCard, isOn: $state.saveCard)
                .tint(theme.primary)
        }
    }
}

/// The pay button: enabled only when the form is complete, spinner while
/// busy. With a saved card selected the title names it ("Pay £1.00 with
/// •••• 0165") unless `namesSavedCard` is false.
///
/// `init(state:amount:currency:)` writes the title itself: "Pay £2.00" in
/// the form's language, with the amount formatted for it.
public struct PesaPayButton: View {
    private enum Title {
        case text(String)
        case amount(String, currency: String)
    }

    @ObservedObject private var state: PesaCardFormState
    private let title: Title
    private let busy: Bool
    private let theme: PesaCardTheme
    private let namesSavedCard: Bool
    private let strings: PesaStrings
    private let action: () -> Void

    public init(state: PesaCardFormState, title: String, busy: Bool = false, theme: PesaCardTheme = .pesa,
                namesSavedCard: Bool = true, locale: String? = nil, action: @escaping () -> Void) {
        self.init(state: state, title: .text(title), busy: busy, theme: theme, namesSavedCard: namesSavedCard,
                  locale: locale, action: action)
    }

    public init(state: PesaCardFormState, amount: String, currency: String, busy: Bool = false,
                theme: PesaCardTheme = .pesa, namesSavedCard: Bool = true, locale: String? = nil,
                action: @escaping () -> Void) {
        self.init(state: state, title: .amount(amount, currency: currency), busy: busy, theme: theme,
                  namesSavedCard: namesSavedCard, locale: locale, action: action)
    }

    private init(state: PesaCardFormState, title: Title, busy: Bool, theme: PesaCardTheme,
                 namesSavedCard: Bool, locale: String?, action: @escaping () -> Void) {
        self.state = state
        self.title = title
        self.busy = busy
        self.theme = theme
        self.namesSavedCard = namesSavedCard
        self.strings = locale.map { PesaStrings.resolve($0, session: state.sessionLocale) } ?? state.strings
        self.action = action
    }

    private var label: String {
        let last4 = namesSavedCard ? state.selectedSavedCard?.last4 : nil
        switch title {
        case .text(let text):
            return last4.map { strings.title(text, last4: $0) } ?? text
        case .amount(let amount, let currency):
            return strings.payLabel(amount: amount, currency: currency, last4: last4)
        }
    }

    public var body: some View {
        Button(action: action) {
            HStack {
                if busy { ProgressView().tint(.white) }
                Text(busy ? strings.processing : label).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .foregroundColor(.white)
        .background(theme.primary.opacity(state.isComplete && !busy ? 1 : 0.5))
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
        .disabled(!state.isComplete || busy)
    }
}

/// The card content types that exist only from iOS 17; nil below that.
enum CardContentType {
    static var expiration: UITextContentType? {
        if #available(iOS 17, *) { return .creditCardExpiration }
        return nil
    }
    static var securityCode: UITextContentType? {
        if #available(iOS 17, *) { return .creditCardSecurityCode }
        return nil
    }
    static var name: UITextContentType? {
        if #available(iOS 17, *) { return .creditCardName }
        return nil
    }
}

/// A UITextField with copy and cut removed. Paste stays: people paste card
/// numbers from password managers.
struct SecureCopyTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let contentType: UITextContentType?
    let keyboard: UIKeyboardType
    let secure: Bool

    func makeUIView(context: Context) -> NoCopyTextField {
        let f = NoCopyTextField()
        f.placeholder = placeholder
        f.textContentType = contentType
        f.keyboardType = keyboard
        f.isSecureTextEntry = secure
        f.autocorrectionType = .no
        f.spellCheckingType = .no
        f.smartDashesType = .no
        f.smartQuotesType = .no
        f.delegate = context.coordinator
        f.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return f
    }

    func updateUIView(_ view: NoCopyTextField, context: Context) {
        if view.text != text { view.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SecureCopyTextField
        init(_ parent: SecureCopyTextField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
    }
}

final class NoCopyTextField: UITextField {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) || action == #selector(cut(_:)) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
#endif
