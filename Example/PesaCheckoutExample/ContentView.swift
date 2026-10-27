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
    @StateObject private var form = PesaCardFormState()

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
                        PesaPayButton(state: form, title: "Pay \(s.amount) \(s.currency)", busy: busy) { Task { await pay() } }
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
            session = try await PesaCheckout.shared.client.session(intentId: intentId, clientSecret: clientSecret)
            message = ""
        } catch {
            message = "\(error)"
        }
    }

    private func pay() async {
        guard let card = form.details() else { return }
        let email = form.trimmedEmail
        form.clear()
        busy = true
        defer { busy = false }
        do {
            let r = try await PesaCheckout.shared.pay(intentId: intentId, clientSecret: clientSecret, card: card, email: email)
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
