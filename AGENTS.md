# Instructions for AI agents

This file is for coding agents that integrate PesaCheckout into an iOS app
or that change this repository. Humans: read README.md first.

## What this package is

- Swift Package `PesaCheckout` (UI) and `PesaCheckoutCore` (client, no UI).
- Native card fields. 3-D Secure in `SFSafariViewController`. SPKI-pinned
  TLS to `checkout.pesa.co`.
- No web views. No third-party dependencies. iOS 15+, Swift 5.9+.

## Hard rules

1. Never log, store or send `clientSecret` anywhere except to the SDK.
2. Never fulfil an order from `CheckoutResult`. The server fulfils only on
   `intent.state_changed` or `GET /v1/intents/{reference}`.
3. Never put the Pesa API key in the app.
4. Never read `PesaCardFormState.number` or the CVV in app code.
5. Never ship a release build with an empty `pins` list.
6. Never add a web view for card entry.

## Integrate into an app (steps in order)

1. Server: create the intent with `POST /v1/intents`. Set `returnUrl` to
   a universal link of the app. Return `id` and `clientSecret` to the app.
2. App: add the package. SPM `https://github.com/pesapeer/pesa-ios`,
   product `PesaCheckout`. Or `pod 'PesaCheckout'`.
3. App: once at launch,
   `PesaCheckout.configure(.init(pins: ["<pin 1>", "<pin 2>"]))`.
   Get the pins from the Pesa release notes, or with the `openssl` command
   in README.md.
4. App: show `PesaCardForm(state:)` with a `PesaCardFormState`. Apply
   `.pesaSecureScreen()` to the screen. UIKit: use
   `PesaCardFormViewController`.
5. App: on pay, `form.details()`, then `form.clear()`, then
   `try await PesaCheckout.shared.pay(intentId:clientSecret:card:email:)`.
6. App: route the universal link to `PesaCheckout.shared.handle(url:)`
   from `onOpenURL`, the scene delegate or `application(_:continue:)`.
7. App: show the outcome from `result.isSuccess`, `result.state` and
   `result.attempt?.failureReason`. Catch `PesaCheckoutError` and switch
   on `code`.
8. Server: handle the `intent.state_changed` webhook. Fulfil on
   `settled`, or on `authorized` when the merchant captures by hand.

A full example is in `README.md` and `Example/PesaCheckoutExample/`. A
skill with the same steps is in `skills/pesa-checkout-ios/SKILL.md`.

## Change this repository

Layout:

| Path | Content |
|---|---|
| `Sources/PesaCheckoutCore/Client.swift` | `PesaCheckoutClient`: session, pay, poll. |
| `Sources/PesaCheckoutCore/Pinning.swift` | SPKI pin check in the URLSession delegate. |
| `Sources/PesaCheckoutCore/Card.swift` | Card validation, `SecretBytes`. |
| `Sources/PesaCheckoutCore/PesaStrings*.swift` | `PesaStrings`: language resolution, money format, error messages; one table per language. |
| `Sources/PesaCheckoutCore/Models.swift` | Session, attempt, result, error. |
| `Sources/PesaCheckout/PesaCheckout.swift` | `PesaCheckout.shared`, Safari challenge, universal link. |
| `Sources/PesaCheckout/CardForm.swift` | SwiftUI form and state. |
| `Sources/PesaCheckout/CardFormViewController.swift` | UIKit form. |
| `Sources/PesaCheckout/SecureScreen.swift` | Screenshot and switcher protection. |
| `Tests/` | XCTest for Core. Runs on Linux and macOS. |
| `.github/workflows/ci.yml` | Linux build and tests; macOS build of the UI target. |
| `.github/workflows/release.yml` | CocoaPods push and GitHub release on a signed `v*` tag. |

Commands:

```
swift build
swift test
```

The UI target builds only on Apple platforms. On macOS:

```
xcodebuild -scheme PesaCheckout -destination 'generic/platform=iOS Simulator' build
```

Rules for changes:

- Run `swift build && swift test` before you finish. Both must pass.
- Add a test in `Tests/` for every behaviour change in Core.
- Keep `PesaCheckoutCore` free of UIKit and SwiftUI. It must build on
  Linux.
- Keep error codes in step with pesa-kotlin and pesa-flutter. The three
  SDKs share one error vocabulary.
- Put every user-visible string in `PesaStrings` and in all four tables.
  `PesaStringsTests` checks the keys and placeholders.
- Add a line to `CHANGELOG.md` under "Unreleased" for every user-visible
  change.
- Do not edit `.github/allowed_signers` or `.github/verify-tag.sh`.
- Do not create tags. A maintainer signs and pushes release tags.
- Do not add `Co-Authored-By` or similar trailers to commit messages.

## Terms

| Term | Meaning |
|---|---|
| intent | A payment the merchant server created on the Pesa API. |
| client secret | A per-intent token for the app. It is not the API key. |
| attempt | One try to pay an intent. |
| checkout service | `checkout.pesa.co`. It takes the card from the SDK. |
| gateway | The Pesa API that owns intents and sends events. |
| pin | Base64 SHA-256 of the checkout service's SubjectPublicKeyInfo. |
