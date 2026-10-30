import SwiftUI
import PesaCheckout

/// Paste an intent id and client secret from `POST /v1/intents` (your
/// backend) and pay with a Tribe test card.
struct ContentView: View {
    @State private var checkoutURL = "https://checkout.pesa.co"
    @State private var intentId = ""
    @State private var clientSecret = ""
    @State private var session: CheckoutSession?
    @State private var busy = false
    @State private var message = ""
    @State private var form = PesaCardFormState()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        TextField("Checkout URL", text: $checkoutURL)
                        TextField("Intent id", text: $intentId)
                        SecureField("Client secret", text: $clientSecret)
                    }
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)

                    Button("Load session") { Task { await load() } }
                        .disabled(intentId.isEmpty || clientSecret.isEmpty)

                    if let s = session {
                        Text("\(s.merchant.displayName) · \(s.amount) \(s.currency) · \(s.state)").font(.footnote)
                        PesaCardForm(state: form)
                        PesaPayButton(state: form, amount: s.amount, currency: s.currency, busy: busy) { Task { await pay() } }
                    }
                    if !message.isEmpty { Text(message).font(.footnote) }
                }
                .padding()
            }
            .navigationTitle("Pesa Checkout")
        }
        .pesaSecureScreen()
        .onOpenURL { PesaCheckout.shared.handle(url: $0) }
    }

    private func configure() {
        PesaCheckout.configure(.init(checkoutURL: URL(string: checkoutURL)!, pins: []))
    }

    private func load() async {
        configure()
        do {
            let s = try await PesaCheckout.shared.client.session(intentId: intentId, clientSecret: clientSecret)
            form = PesaCardFormState(session: s)
            session = s
            message = ""
        } catch {
            message = "\(error)"
        }
    }

    private func pay() async {
        let saved = form.selectedSavedCard
        let code = form.savedSecurityCodeBytes()
        let card = form.details()
        guard saved != nil || card != nil else { return }
        let email = form.trimmedEmail
        let saveCard = form.savesCard
        form.clear()
        busy = true
        defer { busy = false }
        do {
            let r: CheckoutResult
            if let saved {
                r = try await PesaCheckout.shared.payWithSavedCard(intentId: intentId, clientSecret: clientSecret,
                                                                   token: saved.token, securityCode: code, email: email)
            } else if let card {
                r = try await PesaCheckout.shared.pay(intentId: intentId, clientSecret: clientSecret, card: card,
                                                      email: email, saveCard: saveCard)
            } else {
                return
            }
            message = r.isSuccess ? "Paid: \(r.state)" : "Not paid: \(r.failureReason ?? r.state)"
        } catch {
            message = "\(error)"
        }
    }
}

@main
struct PesaCheckoutExampleApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
