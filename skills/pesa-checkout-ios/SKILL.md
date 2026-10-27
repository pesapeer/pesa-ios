---
name: pesa-checkout-ios
description: Add a native Pesa card payment screen to an iOS app with the PesaCheckout Swift package. Use when an iOS app must take a card payment on a Pesa intent without a web view.
---

# Pesa Checkout on iOS

## When to use this skill

The merchant has a Pesa account and an API key on the server. The iOS
app must take a card payment with native fields and stay inside PCI
scope rules.

## Steps

1. Server: create an intent with `POST /v1/intents`. Set `returnUrl` to
   a universal link of the app, for example
   `https://shop.example/pay/return`. Send `id` and `clientSecret` to the
   app. Do not log `clientSecret`.

2. App: add the package.
   - SPM: `https://github.com/pesapeer/pesa-ios`, product `PesaCheckout`.
   - CocoaPods: `pod 'PesaCheckout', '~> 0.1'`.

3. App: configure once at launch.

   ```swift
   PesaCheckout.configure(.init(pins: ["<pin 1>", "<pin 2>"]))
   ```

4. App: build the payment screen.

   ```swift
   struct PayView: View {
       @StateObject var form = PesaCardFormState(needsEmail: false)
       @State var busy = false

       var body: some View {
           VStack {
               PesaCardForm(state: form)
               PesaPayButton(state: form, title: "Pay", busy: busy) { Task { await pay() } }
           }
           .pesaSecureScreen()
           .onOpenURL { PesaCheckout.shared.handle(url: $0) }
       }

       func pay() async {
           guard let card = form.details() else { return }
           let email = form.trimmedEmail
           form.clear()
           busy = true
           defer { busy = false }
           do {
               let r = try await PesaCheckout.shared.pay(
                   intentId: intentId, clientSecret: clientSecret, card: card, email: email)
               if r.isSuccess { /* show paid */ }
               else { /* show r.attempt?.failureReason; the customer can try again */ }
           } catch let e as PesaCheckoutError {
               switch e.code {
               case .pinMismatch: /* stop; report to the merchant */ break
               case .rateLimited: /* wait, then let the customer retry */ break
               default: /* show e.localizedDescription */ break
               }
           } catch {}
       }
   }
   ```

5. App: register the `returnUrl` host as an Associated Domain. Publish
   `apple-app-site-association` on that host.

6. Server: handle the `intent.state_changed` webhook. Fulfil the order on
   `state: settled`. Fulfil on `authorized` only when the merchant
   captures by hand.

## Checks before you finish

- [ ] The API key is on the server only.
- [ ] `clientSecret` is not logged and not stored.
- [ ] `pins` has two values in release builds.
- [ ] `.pesaSecureScreen()` wraps the card screen.
- [ ] `form.clear()` runs after every attempt.
- [ ] The universal link reaches `PesaCheckout.shared.handle(url:)`.
- [ ] Order fulfilment uses the webhook or the intent read.

## Reference

Full API and error codes: `README.md` in https://github.com/pesapeer/pesa-ios.
