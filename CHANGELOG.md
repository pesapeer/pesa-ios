# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Saved cards. `CheckoutSession` has `canSaveCard`, `savedCards` (`SavedCard`)
  and `savedCardSecurityCode` (`SavedCardSecurityCode`).
- `PesaCheckoutClient.payWithSavedCard` and `PesaCheckout.payWithSavedCard`
  pay with a saved card token and an optional CVV. They follow 3-D Secure
  and poll like `payWithCard`.
- `PesaCardForm` shows the saved cards, "Use another card", the CVV for a
  saved card and the "Save this card" switch. `PesaCardFormState(session:)`
  sets them up from the session.
- `PesaCardFormViewController` takes `savedCards`, `savedCardSecurityCode`
  and `canSaveCard`. Its `pay()` sends the saved card or the typed card, and
  sends `saveCard` when the payer asked.

### Changed
- A 400 on `savedCard.token` or `savedCard.securityCode` maps to
  `invalidCard`.
- Version 0.2.0 in `PesaCheckout.podspec` and `PesaCheckoutVersion.current`.

## [0.1.0] - 2026-10-24

### Added
- First release: card payment on a Pesa intent, 3-D Secure, pinned transport.
