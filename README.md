# Pesa Checkout for iOS (PesaCheckout)

[![CI](https://github.com/pesapeer/pesa-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/pesapeer/pesa-ios/actions/workflows/ci.yml)

Native Swift SDK for a card payment on a Pesa intent.

- Native card fields. No web views.
- 3-D Secure in `SFSafariViewController`.
- TLS with SPKI pinning to `checkout.pesa.co`.
- The card screen is hidden in screenshots and the app switcher.

Other platforms: [pesa-flutter](https://github.com/pesapeer/pesa-flutter),
[pesa-kotlin](https://github.com/pesapeer/pesa-kotlin) (Android and Kotlin
Multiplatform), [pesa-js](https://github.com/pesapeer/pesa-js) (web). All
use the same flow and the same error codes.

## How a payment works

1. Your server creates an intent: `POST /v1/intents` on the Pesa API.
   Set `returnUrl` to a universal link of your app.
2. Your server gives the app `id` and `clientSecret`. Never the API key.
3. The app shows `PesaCardForm`. Then it calls `PesaCheckout.shared.pay(...)`.
4. The SDK posts the card to `checkout.pesa.co` and polls the result.
   When the issuer asks for 3-D Secure, the SDK opens the challenge in
   Safari. The SDK returns a `CheckoutResult`.
5. **Your server trusts only the gateway.** It fulfils the order on the
   `intent.state_changed` event or on `GET /v1/intents/{reference}`.
   It must not trust the result the app saw.

## Install

Swift Package Manager: add `https://github.com/pesapeer/pesa-ios` from
`v0.1.0`. Pick the `PesaCheckout` product. Pick `PesaCheckoutCore` for a
headless integration with your own UI.

CocoaPods:

```ruby
pod 'PesaCheckout', '~> 0.1'
```

Requirements: iOS 15 or later, Swift 5.9 or later. No third-party
dependencies.

## SwiftUI example

```swift
import PesaCheckout

PesaCheckout.configure(.init(pins: ["<pin 1>", "<pin 2>"]))

struct PayView: View {
    @StateObject var form = PesaCardFormState(needsEmail: false)
    @State var busy = false

    var body: some View {
        VStack {
            PesaCardForm(state: form)
            PesaPayButton(state: form, title: "Pay £25.00", busy: busy) {
                Task { await pay() }
            }
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
            let result = try await PesaCheckout.shared.pay(
                intentId: intentId, clientSecret: secret, card: card, email: email)
            // result.isSuccess: show "paid". Your server confirms on the event.
        } catch let e as PesaCheckoutError {
            // e.code: see "Error codes" below
        } catch {}
    }
}
```

## UIKit example

```swift
let form = PesaCardFormViewController(intentId: id, clientSecret: secret, needsEmail: false)
form.delegate = self
addChild(form)
view.addSubview(form.view)
form.didMove(toParent: self)
// PesaCardFormViewControllerDelegate: completeDidChange, didFinish, didFail
```

## Error codes

`PesaCheckoutError.code` is one of:

| Code | Meaning |
|---|---|
| `invalidCard` | The card failed local validation. |
| `invalidRequest` | The checkout service refused the request. |
| `notFound` | Unknown intent or wrong client secret. |
| `attemptInProgress` | Another attempt is running on this intent. |
| `intentClosed` | The intent is settled, cancelled or expired. |
| `rateLimited` | Too many requests. Wait and retry. |
| `server` | The checkout service failed. |
| `transport` | Network error. |
| `timeout` | No final state before the poll limit. |
| `pinMismatch` | The server key did not match a pin. The SDK sent no request. |
| `challengeUnavailable` | The 3-D Secure page could not open. |

## Universal link for the 3-D Secure return

The checkout return page sends the browser to the intent's `returnUrl`
with `?intent=<id>&state=<state>`.

1. Make that URL a universal link of your app. Use Associated Domains and
   `apple-app-site-association`.
2. Pass the URL to `PesaCheckout.shared.handle(url:)`. Call it from
   `onOpenURL`, the scene delegate or `application(_:continue:)`.

`handle(url:)` closes the Safari sheet. The result arrives through
`pay()` in all cases. If the link is missed, the sheet stays open until
the user closes it.

## Certificate pins

A pin is the base64 SHA-256 of the SubjectPublicKeyInfo of the
`checkout.pesa.co` certificate. Android's network security config uses
the same format. Get the current pin:

```
openssl s_client -connect checkout.pesa.co:443 -servername checkout.pesa.co </dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary | base64
```

Rules:

- Set both current pins in production builds. Pesa publishes the pins
  with each release.
- An empty list turns pinning off. Use that only for development against
  a local checkout service.
- The SDK checks the pin after the system validates the chain. On a
  mismatch, the SDK cancels the connection before it sends any request
  byte. The error code is `pinMismatch`.

## How the SDK keeps card data safe

- The PAN and CVV are held in `SecretBytes`. The SDK wipes them after it
  encodes the request. `PesaCardFormState.clear()` overwrites the fields.
- Copy and cut are off on the number and CVV fields. The CVV is a secure
  entry. Autocorrection and smart punctuation are off.
- `.pesaSecureScreen()` and `PesaCardFormViewController` blank the screen
  in screenshots, recordings and the app switcher. Check this on a device
  after each major iOS release. Apple does not document the behaviour.
- The SDK logs nothing. `PesaCheckoutError` carries the gateway message
  only. Never the request.
- Keep your own code away from `PesaCardFormState.number`.

## Build and test

`PesaCheckoutCore` is pure Foundation. It builds on Linux and macOS:

```
swift build && swift test
```

`PesaCheckout` (UI, Safari, secure screen) builds only on Apple platforms.
Open the package in Xcode. For the example, create an iOS App target in
Xcode, add the package as a local dependency, and add
`Example/PesaCheckoutExample/ContentView.swift`.

## For AI agents

Read [AGENTS.md](AGENTS.md). It has the integration steps in order and the
rules an agent must follow. A skill is in `skills/pesa-checkout-ios/`.

## Security

Read [SECURITY.md](SECURITY.md). Report vulnerabilities to
security@pesa.co. Do not open a public issue.

## Releasing

1. Set the version in `PesaCheckout.podspec`. Move the Unreleased notes in
   `CHANGELOG.md`.
2. Commit on `main` with an SSH key listed in `.github/allowed_signers`.
   Then `git tag vX.Y.Z && git push origin vX.Y.Z`. Only repository admins
   can push a `v*` tag.
3. `release.yml` verifies that the tagged commit is signed by a maintainer, builds and tests on macOS, lints
   and pushes the podspec to CocoaPods trunk, and creates a GitHub release.
   SPM resolves the tag directly.

Repository setup: secret `COCOAPODS_TRUNK_TOKEN`; `.github/allowed_signers`.

## License

MIT. See [LICENSE](LICENSE).
