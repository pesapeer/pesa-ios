#if canImport(UIKit)
import SwiftUI
import UIKit
import PesaCheckoutCore

/// Colours and shape of the form. Defaults follow the Pesa checkout.
public struct PesaCardTheme: Sendable {
    public var primary: Color
    public var fieldBackground: Color
    public var border: Color
    public var error: Color
    public var cornerRadius: CGFloat

    public init(primary: Color = Color(red: 0x1c / 255, green: 0x3f / 255, blue: 0xaa / 255),
                fieldBackground: Color = Color(.secondarySystemBackground),
                border: Color = Color(.separator),
                error: Color = Color(.systemRed),
                cornerRadius: CGFloat = 10) {
        self.primary = primary
        self.fieldBackground = fieldBackground
        self.border = border
        self.error = error
        self.cornerRadius = cornerRadius
    }

    public static let pesa = PesaCardTheme()
}

/// What the form holds. Observe `isComplete` for the pay button; call
/// `details()` to hand the card to the client, then `clear()`.
@MainActor
public final class PesaCardFormState: ObservableObject {
    @Published public var number = "" { didSet { number = Self.groupNumber(number) } }
    @Published public var expiry = "" { didSet { expiry = Self.groupExpiry(expiry) } }
    @Published public var securityCode = "" { didSet { securityCode = String(securityCode.filter(\.isNumber).prefix(4)) } }
    @Published public var holderName = ""
    @Published public var email = ""
    @Published public var touched: Set<Field> = []

    public let needsEmail: Bool
    public let now: () -> Date

    public enum Field: Hashable, Sendable { case number, expiry, securityCode, holderName, email }

    public init(needsEmail: Bool = false, now: @escaping () -> Date = { Date() }) {
        self.needsEmail = needsEmail
        self.now = now
    }

    public var digits: String { number.filter(\.isNumber) }
    public var brand: CardBrand { CardBrand.detect(digits) }

    public func error(for field: Field) -> String? {
        switch field {
        case .number: return CardValidation.number(digits)
        case .expiry: return CardValidation.expiry(expiry, now: now())
        case .securityCode: return CardValidation.securityCode(securityCode, brand: brand)
        case .holderName: return CardValidation.holderName(holderName)
        case .email: return needsEmail ? CardValidation.email(email) : nil
        }
    }

    /// The error to show: only once the field was left.
    public func shownError(for field: Field) -> String? {
        touched.contains(field) ? error(for: field) : nil
    }

    public var isComplete: Bool {
        [Field.number, .expiry, .securityCode, .holderName, .email].allSatisfy { error(for: $0) == nil }
    }

    /// The card as typed. Nil while incomplete.
    public func details() -> CardDetails? {
        guard isComplete, let exp = CardExpiry.parse(expiry) else { return nil }
        return CardDetails(number: digits, expiry: exp, securityCode: securityCode, holderName: holderName)
    }

    public var trimmedEmail: String? {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.isEmpty ? nil : e
    }

    /// Overwrites then empties the sensitive fields.
    public func clear() {
        number = String(repeating: "0", count: number.count)
        securityCode = String(repeating: "0", count: securityCode.count)
        number = ""
        securityCode = ""
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
public struct PesaCardForm: View {
    @ObservedObject private var state: PesaCardFormState
    private let theme: PesaCardTheme
    @FocusState private var focus: PesaCardFormState.Field?

    public init(state: PesaCardFormState, theme: PesaCardTheme = .pesa) {
        self.state = state
        self.theme = theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Card number", .number) {
                HStack {
                    SecureCopyTextField(text: $state.number, placeholder: "1234 5678 9012 3456",
                                        contentType: .creditCardNumber, keyboard: .numberPad, secure: false)
                        .focused($focus, equals: .number)
                    Text(state.brand.label).font(.caption).foregroundColor(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                field("Expiry", .expiry) {
                    TextField("MM / YY", text: $state.expiry)
                        .keyboardType(.numberPad)
                        .textContentType(CardContentType.expiration)
                        .focused($focus, equals: .expiry)
                }
                field(state.brand == .amex ? "CID" : "CVV", .securityCode) {
                    SecureCopyTextField(text: $state.securityCode, placeholder: state.brand == .amex ? "1234" : "123",
                                        contentType: CardContentType.securityCode, keyboard: .numberPad, secure: true)
                        .focused($focus, equals: .securityCode)
                }
            }
            field("Name on card", .holderName) {
                TextField("As printed", text: $state.holderName)
                    .textContentType(CardContentType.name)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.words)
                    .focused($focus, equals: .holderName)
            }
            if state.needsEmail {
                field("Email for your receipt", .email) {
                    TextField("you@example.com", text: $state.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .focused($focus, equals: .email)
                }
            }
        }
        .onChange(of: focus) { newValue in
            if let left = lastFocus, left != newValue { state.touched.insert(left) }
            lastFocus = newValue
        }
    }

    @State private var lastFocus: PesaCardFormState.Field?

    private func field<Content: View>(_ label: String, _ f: PesaCardFormState.Field, @ViewBuilder content: () -> Content) -> some View {
        let err = state.shownError(for: f)
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

/// The pay button: enabled only when the form is complete, spinner while busy.
public struct PesaPayButton: View {
    @ObservedObject private var state: PesaCardFormState
    private let title: String
    private let busy: Bool
    private let theme: PesaCardTheme
    private let action: () -> Void

    public init(state: PesaCardFormState, title: String, busy: Bool = false, theme: PesaCardTheme = .pesa, action: @escaping () -> Void) {
        self.state = state
        self.title = title
        self.busy = busy
        self.theme = theme
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack {
                if busy { ProgressView().tint(.white) }
                Text(busy ? "Processing…" : title).fontWeight(.semibold)
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
