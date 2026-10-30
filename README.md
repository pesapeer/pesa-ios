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
`v0.3.0`. Pick the `PesaCheckout` product. Pick `PesaCheckoutCore` for a
headless integration with your own UI.

CocoaPods:

```ruby
pod 'PesaCheckout', '~> 0.3'
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

## Saved cards

A customer can keep a card for the next payment. Your server must set
`customerReference` on the intent. Without it, the session offers no saved
cards and ignores `saveCard`.

The session tells the form what to show:

- `canSaveCard`: the form may show the "Save this card" switch.
- `savedCards`: the customer's cards, most recently used first. Each has
  `brand`, `last4`, `expiry` (MM/YYYY) and `holderName`. The list is empty
  when there are none.
- `savedCardSecurityCode`: `.required`, `.optional` or `.never`. It tells
  the form when to ask for the CVV again. A missing or unknown value reads
  as `.never`.

### The picker

With saved cards, `PesaCardForm` is a payment sheet: one rounded list with
hairlines between the rows.

- One row per saved card: the brand on a small white chip, `•••• 0165` on
  the first line and `Expires 09/28` under it, and a radio at the end. The
  selected row has a filled radio and a semibold title.
- An expired card stays in the list, greyed, and reads `Expired`. It
  cannot be selected. The form selects the first card that has not
  expired.
- With `.required` or `.optional`, the selected row takes the CVV in a
  narrow field at its end. With `.never` there is no CVV field.
- "Use another card" is the last row. Selecting it opens the card fields
  in the same list. "Save this card for next time" is their last line
  while `canSaveCard` is true. Pass `showSaveCardSwitch: false` (UIKit:
  `showsSaveCardSwitch = false`) and place `PesaSaveCardSwitch(state:)`
  yourself if your screen has its own spot for it.
- Colours come from `PesaCardTheme`. The defaults are system colours and
  follow dark mode; `listBackground` is the list's surface and `border`
  its outline and hairlines. The brand chip stays white so the marks read
  on any surface.
- Brand names from the gateway are read in any case, with or without
  spaces, `_` or `-`. `mc`, `americanexpress`, `cup` and `chinaunionpay`
  are understood (`CardBrand.parse`).

The pay button names the selected card. `PesaPayButton(state:title:)` and
`PesaCardFormViewController` show "Pay £1.00 with •••• 0165" while a saved
card is selected and "Pay £1.00" otherwise; pass `namesSavedCard: false`
to keep your title as is. `PesaPayButton(state:amount:currency:)` writes
the title for you in the form's language. For your own button,
`form.payLabel(amount: "1.00", currency: "GBP")` or
`form.payLabel("Pay £1.00")` gives the same text, and
`form.selectedSavedCard` has the card.

### Paying

```swift
let form = PesaCardFormState(session: session)

func pay() async throws -> CheckoutResult? {
    let email = form.trimmedEmail
    if let saved = form.selectedSavedCard {
        let code = form.savedSecurityCodeBytes()
        form.clear()
        return try await PesaCheckout.shared.payWithSavedCard(
            intentId: intentId, clientSecret: secret, token: saved.token, securityCode: code, email: email)
    }
    guard let card = form.details() else { return nil }
    let saveCard = form.savesCard
    form.clear()
    return try await PesaCheckout.shared.pay(
        intentId: intentId, clientSecret: secret, card: card, email: email, saveCard: saveCard)
}
```

UIKit: pass `savedCards`, `savedCardSecurityCode` and `canSaveCard` to
`PesaCardFormViewController`. Its `pay()` picks the saved card or the
typed card.

Rules:

- The token is opaque. Do not log it, show it or put it in a URL.
- The SDK sends the token and the CVV in the request body only.
- The CVV is held in `SecretBytes`. The SDK wipes it after it encodes the
  request.
- The gateway keeps a card only after a successful charge. A decline
  keeps nothing.
- A refused token gives `invalidCard`. Ask the customer to choose another
  card.
- The 3-D Secure challenge and the result are the same as for a typed
  card.

## Language

The SDK ships four languages: `en`, `fr`, `fr-CA` and `zh-Hans`. The
strings are Swift code in `PesaCheckoutCore` (`PesaStrings`). There are no
`.strings` files, so SPM and CocoaPods need no resources.

The SDK picks the language in this order:

1. The `locale` that your app gives.
2. The session's `locale`. The merchant sets it on the intent.
3. The device language (`Locale.preferredLanguages`).
4. English.

Close tags are mapped: `fr-BE` gives `fr`, `zh` and `zh-Hant` give
`zh-Hans`. An unknown tag such as `de` goes to the next step.

```swift
PesaCheckout.configure(.init(pins: pins, locale: "fr"))            // error messages
let form = PesaCardFormState(session: session, locale: "fr")      // the form
PesaCardForm(state: form)
PesaPayButton(state: form, amount: session.amount, currency: session.currency) { pay() }
```

- Leave `locale` nil to follow the session and then the device.
- `PesaCardForm`, `PesaPayButton`, `PesaSaveCardSwitch` and
  `PesaCardFormViewController` also take `locale`.
- `PesaStrings.resolve(locale, session: session.locale)` gives the strings
  for your own screens. `formatAmount`, `payLabel` and `message(for:)`
  fill them.
- To change a sentence, copy a table: `var s = PesaStrings.fr`, then set
  the property.
- `CardValidation` uses English unless you pass `strings:`.

Money uses Foundation's `NumberFormatter` (`.currency`) for the chosen
language. The SDK does not change its output. ICU (CLDR 48) gives for
£2.00:

| Language | Output |
|---|---|
| `en`, `zh-Hans` | `£2.00` |
| `fr-CA` | `2,00 £` |
| `fr` | `2,00 £GB` |

In `fr` and `fr-CA` the space before the symbol is a no-break space
(U+00A0), not a narrow no-break space (U+202F). In `fr` the pound is
`£GB`. Apple's ICU data can differ by iOS version.

## Error codes

`PesaCheckoutError.code` is one of the codes below. `message` is in the
client's language and is safe to show. `gatewayMessage` is the gateway's
English sentence for support.

| Code | Meaning |
|---|---|
| `invalidCard` | The card failed local validation, or the checkout service refused the card or the saved card. |
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
2. Tag with an SSH key listed in `.github/allowed_signers`:
   `git tag -s vX.Y.Z -m "vX.Y.Z"`. Push the tag.
3. `release.yml` verifies the tag signature, builds and tests on macOS, lints
   and pushes the podspec to CocoaPods trunk, and creates a GitHub release.
   SPM resolves the tag directly.

Repository setup: secret `COCOAPODS_TRUNK_TOKEN`; `.github/allowed_signers`.

## License

MIT. See [LICENSE](LICENSE).
