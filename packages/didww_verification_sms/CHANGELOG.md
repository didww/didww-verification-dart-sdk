# Changelog

Notable changes to `didww_verification_sms`. Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): from 1.0.0 onwards a breaking
change to the public surface requires a major version.

## 1.0.0

First public release — 2026-09.

- **`SmsRetrieverAutoCapture`** — an `SmsAutoCapture` over Google's SMS Retriever API, so a
  one-time code arrives on its own. Pass it to `VerificationSession` and nothing else in your
  screen changes: `start()` and `submit()` behave identically with and without it.

- **No SMS or call-log permission.** The Retriever needs none, and the receiver is registered
  behind `SmsRetriever.SEND_PERMISSION` so only Play Services can reach it. The merged
  manifest is asserted permission-free in CI.

- **`getAppHash()`** — the 11-character app hash for the running build, so the value Play App
  Signing actually produces can be read off a real build rather than derived by hand.

- **Android only, and no `ios/` directory.** iOS needs no plugin: one-time code autofill there
  is `AutofillHints.oneTimeCode` on your own text field. The package is safe to depend on
  unconditionally — everywhere but Android `appHash()` resolves to null and `messages()` is an
  empty stream, with no `MissingPluginException` and no framework error. That degradation is
  code in this package, not a consequence of the platform declaration.

- **An arming failure reaches Dart.** `startSmsRetriever()` reports failure asynchronously
  through its `Task`, which is what happens on a device without Play Services; the receiver is
  torn down and the error surfaces, instead of capture being reported as armed where it can
  never fire.

- **`smsPackageVersion`** — the version constant is named distinctly from the client's, so
  importing both barrels is unambiguous.
