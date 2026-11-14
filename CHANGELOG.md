# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- 3-D Secure runs in a full-screen `WKWebView` page inside the app
  (`WebViewChallengeOpener`), the default for `PesaCheckout`. The SDK
  closes the page once the attempt settles; the customer no longer leaves
  the app and the universal link is no longer needed for cards. Pass
  `challenge: .browser` to `PesaCheckout(configuration:challenge:)` or
  `configure(_:challenge:)` for `SFSafariViewController` as before.
- `PesaCheckoutClient.payWithCard` and `payWithSavedCard` take
  `challenge: PesaChallengePresenter`; the `openChallenge:` closure forms
  stay and wrap it in `ClosureChallengePresenter`.

### Added
- `PesaChallengePresenter` (`open(_:onCancelled:)`, `close()`),
  `ClosureChallengePresenter`, `challengeReturnPath(for:)`.
- `PesaCheckoutError.Code.challengeCancelled` when the cardholder closes
  the page before it finished, with `PesaStrings.errorChallengeCancelled`.
  `SafariChallengeOpener` reports Done the same way.
- The in-app 3-D Secure page has a close button and no title: the bank's
  page has its own heading. It shows "Connecting to your bank…" until that
  page has loaded, and closing asks "Cancel this payment?" first. Pass
  `challengeTitle:` to `PesaCheckout` or `configure`, or `title:` to
  `WebViewChallengeOpener`, for a title of your own. `PesaStrings` has
  `challengeLabel` (the VoiceOver name), `challengeConnecting`,
  `challengeCancelQuestion`, `challengeCancel` and `challengeKeepGoing`.
- `PesaCardTheme` can restyle the saved-card list without redrawing it,
  with the same options as pesa-flutter: `separateRows` and `rowSpacing`
  (a box per row, the card fields in their own box under "Use another
  card"), `selectedRowBorder` and `selectedRowBorderWidth`, `brandChip`,
  `anotherCardFirst`, `anotherCardSubtitle` and `anotherCardSymbol`. The
  defaults keep the list as it was.
- Languages: `en`, `fr`, `fr-CA` and `zh-Hans`. `PesaStrings` in
  `PesaCheckoutCore` holds every string, one table per language in code
  (`.en`, `.fr`, `.frCA`, `.zhHans`). `PesaStrings.resolve(_:session:)`
  picks the host's locale, then the session's, then
  `Locale.preferredLanguages`, then English. Close tags are mapped
  (`fr-BE` to `fr`, `zh` and `zh-Hant` to `zh-Hans`).
- `CheckoutSession.locale`.
- `locale` on `PesaCheckoutConfiguration`, `PesaCardFormState`,
  `PesaCardForm`, `PesaSaveCardSwitch`, `PesaPayButton` and
  `PesaCardFormViewController`.
- `PesaStrings.formatAmount` formats money with `NumberFormatter` for the
  language. `PesaPayButton(state:amount:currency:)` and
  `PesaCardFormState.payLabel(amount:currency:)` give "Pay £2.00" or
  "Pay £2.00 with •••• 0165".
- `PesaCardFormViewController` takes `amount` and `currency` for its
  button. `payTitle` is optional; nil gives "Pay" in the form's language.
- `CardValidation` functions take an optional `strings:` (English by
  default).
- `PesaCheckoutError.gatewayMessage` keeps the gateway's sentence.
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
- The saved-card picker is a payment sheet: one rounded list with
  hairlines, two-line rows (brand chip, `•••• 0165`, `Expires 09/28`), a
  trailing radio, expired cards greyed and unselectable, the CVV inline
  on the selected row, and "Use another card" as the last row opening the
  card fields in place. `PesaCardTheme.listBackground` sets the list's
  surface; the defaults follow dark mode.
- `PesaCardForm(showSaveCardSwitch:)`,
  `PesaCardFormViewController.showsSaveCardSwitch` and
  `PesaSaveCardSwitch`. The form draws "Save this card for next time" as
  the last line of the card fields. Hosts that place their own switch pass
  `false` and drop their copy from under the form, or it shows twice.
- `PesaPayButton` names the selected saved card ("Pay £1.00 with •••• 0165");
  `namesSavedCard: false` keeps the title as given.
  `PesaCardFormState.payLabel(_:)` gives the same text for your own button.
- `CardBrand.parse(_:)` reads brand names in any case, without spaces,
  `_` or `-`, and accepts `mc`, `americanexpress`, `cup` and
  `chinaunionpay`. `SavedCard.cardBrand` uses it.
- `SavedCard.parsedExpiry`, `shortExpiry` (MM/YY) and `isUsable(at:)`.

### Changed
- `PesaCheckoutError.message` comes from the error code in the client's
  language. It was the gateway's sentence or a system description. The
  codes do not change.
- `payLabel(_:)` and `PesaPayButton` add the card in the form's language.
- The card number field shows no brand until the brand is known. It
  showed "Card".
- `savedCardSecurityCode` defaults to `.never` when missing or unknown, in
  `CheckoutSession`, `PesaCardFormState` and `PesaCardFormViewController`.
  It was `.optional`.
- The form selects the first saved card that has not expired, and a
  selected expired card is not complete (`error(for: .expiry)`).
- A 400 on `savedCard.token` or `savedCard.securityCode` maps to
  `invalidCard`.
- Version 0.3.0 in `PesaCheckout.podspec` and `PesaCheckoutVersion.current`.

## [0.1.0] - 2026-10-24

### Added
- First release: card payment on a Pesa intent, 3-D Secure, pinned transport.
