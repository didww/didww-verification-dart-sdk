# Changelog

Notable changes to `didww_verification`. Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): from 1.0.0 onwards a breaking
change to the public surface requires a major version.

## 1.2.0

Unreleased.

### Added

- **`custom` on `startVerification` and `VerificationSession.start`** — optional free text
  (up to 4096 characters) forwarded to your callback server, for context it can use to allow
  or deny. It is not returned by any response, so it is not on `Verification`, and it comes
  from the device, so the callback server must validate it. A longer value is refused with the
  new `customTooLong` error code.

- **`SmsOptions.autofill`**, built with `SmsAutofill.appHash(value)`, `SmsAutofill.domain()` or
  `SmsAutofill.none()`, to choose the autofill marker instead of the application's default. It
  wins over the app hash an auto-capture computes. The app hash is now sent as
  `sms.autofill`. `SmsInfo.autofill` reads back the stored marker, `app_hash` or `domain`,
  whose `value` is the hash or the domain; capture arms only on an `app_hash` echo of the
  device's own hash. New error codes `autofillInvalid` and `smsDomainNotConfigured`.

- **`templateGroup` on `SmsOptions` and `CalloutOptions`**, to pick a template group instead of
  the application's default. `SmsInfo` and `CalloutInfo` gain `templateGroup`,
  `templateGroupUsed` and `templateFallbackReason`. `templateFallbackReason` is an
  open-vocabulary value, readable as a known `TemplateFallbackReason` through
  `knownTemplateFallbackReason`. An unknown group is refused with
  the new `templateGroupNotFound` error code.

- **New error codes for 429**, all thrown as `TooManyRequestsException`: `rateLimitPerIp`
  (too many requests from this IP address), `rateLimitFailedAuth` (too many failed
  authentication attempts from this IP address), `rateLimitPerAccount` (too many requests for
  this account), `rateLimitPublicPerAccount` (too many public requests for this account) and
  `volumeLimitReached` (the application reached its daily or monthly verification limit). Wait
  for `retryAfter` before trying again; for `volumeLimitReached` it can be long (days), so
  surface it to the user instead of retrying.

- **New outcome codes:** `applicationPaused` (a `VerificationSetupError` in the session) and
  `destinationCountryDisabled` (a `VerificationDenied`).

- **`X-User-Agent`** is sent on every request with the same value as `User-Agent`, so a
  Flutter web app, whose browser drops a `User-Agent` set by script, still identifies the SDK.

### Changed

- **The session retries a rate-limited submission once.** A report refused with one of the four
  rate-limit codes is retried once after `Retry-After` when that is at most 5 seconds; a longer
  one is surfaced at once. If it is surfaced, or the retry is limited too, the session returns to
  `VerificationAwaitingInput` with the code as `lastError`, so the user can submit again — the
  four codes are now in `recoverableErrorCodes`. A start is still never retried, and
  `volumeLimitReached` stays terminal.

- **An unsupported destination is now a failed verification, not a 422.** A destination with no
  country, none reachable on the channel, or in a blocked range comes back as a 201 verification
  with status `failed` and error code `destinationNotSupportedForChannel`. Code that handled the
  422 now receives a `VerificationFailed` in the session, or a `Verification` whose `knownStatus`
  is `failed` from the client. The code stays in the envelope vocabulary for compatibility.

- **New `ApiErrorCode` values break exhaustive `switch` expressions** over the enum. Add the new
  cases, or a wildcard arm.

- Docs: a Testing section on the sandbox environment, which sends nothing and gives a predefined
  result only for the reserved test numbers.

### Deprecated

- **`SmsInfo.appHash`.** Read `SmsInfo.autofill`; `appHash` returns its value when the type
  is `app_hash`. The flat `app_hash` in responses is no longer read: `appHash` now derives from
  `autofill`.

- **`ApiErrorCode.staleDispatch`.** The service no longer sends it and reports these
  verifications as `dispatchFailed`. It stays so existing matches keep compiling, and will be
  removed in the next major version.

## 1.1.0

Released — 2026-10.

- **`SmsInfo.codeLength` and `CalloutInfo.codeLength`** — how many digits the code is,
  chosen per application on the server (4–8, default 6). A server fact, never compiled in.

- **Docs and the bundled mock API corrected: the verification lifetime is per application**
  (60–600 seconds, default 300), not the fixed 120 seconds this package used to document. No
  code change — `expires_at` and `sms.interceptionTimeoutSeconds` were always read from the
  response, never compiled in.

- **`destinationInCooldown`** — a new `ApiErrorCode` for a start requested again too soon
  after one for the same application and destination.

- **`TooManyRequestsException`** — thrown for a 429, with `retryAfter` parsed from the
  `Retry-After` header. `startVerification` is never retried, on this status or any other.

- **Logged lines redact every run of four or more digits outside a UUID**, not just six or
  more — ports and years go with them. A verification id stays readable, because it is never
  a bare digit run.

- The default `User-Agent` changed from `didww_verification/<version>` to
  `didww-verification-dart/<version>`.

- `ClientConfig.userAgent` is deprecated and ignored: the SDK always sends its
  own `User-Agent` and it can no longer be overridden or suppressed.

## 1.0.0

First public release — 2026-09.

- **`VerificationClient`** — the five verification endpoints over HTTP. Reads are retried;
  a start or a report never is, because a request that timed out may still have been carried
  out, and repeating it bills again or burns an attempt.

- **No dependencies.** The package declares no `dependencies:` key, so it adds nothing to
  your dependency tree and runs on the plain Dart VM as well as in Flutter.

- **`VerificationSession`** — the verification as a state machine: one `states` stream that
  returns the same object on every call, single-flighted calls, and automatic code capture
  behind the `SmsAutoCapture` seam.

- **A sealed `VerificationState` tree** — `Idle`, `Starting`, `AwaitingInput`, `Captured`,
  `Submitting`, `Verified`, `Expired`, `Denied`, `SetupError` and `Failed`. A `switch` over it
  needs no `default` arm, so a state added in a later release is a compile error rather than a
  screen that renders nothing. A rejected submission returns to `AwaitingInput` with
  `lastError` set instead of ending the verification, so "waiting for the first code" and
  "that code was wrong" are distinct without the SDK counting attempts locally.

- **Two channels** — SMS and callout, with `SmsOptions` and `CalloutOptions`
  carrying the per-channel request fields, including announcement languages. Language tags the
  API cannot accept are dropped before the request rather than sent: its rule is narrower than
  BCP 47, and a rejected tag would fail the whole start instead of falling back.

- **`resumeByNumber` and `resumeById`** — reattach to a verification already running for a
  number without starting, and without billing, a second one.

- **A sealed `VerificationException` tree.** Everything leaving the SDK is in it, including
  whatever a supplied transport throws, a response field of an unexpected type, a body that is
  not UTF-8, and a base URL with no scheme. `SdkUnexpectedError` is the backstop, so a session
  always reaches a terminal state rather than stalling on a spinner.

- **`isRecoverable` and `recoverableErrorCodes`** — whether a rejection leaves the
  verification alive, exported so a direct `VerificationClient` consumer can ask the same
  question the session asks.

- **`PublicAuthorization` and `BasicAuthorization`** over the `Authorization` seam. Request
  signing is deliberately absent: it needs a secret that must never be embedded in an
  application binary.

- **Web supported.** The main library carries no `dart:io`, so the package compiles for the
  web and is WASM-ready; supply a transport there over `package:http` or `fetch`.
  `IOHttpTransport` lives in `package:didww_verification/io.dart`, and the client builds one
  for itself wherever there is one to build.

- **`package:didww_verification/testing.dart`** — `FakeTransport` and `FakeAutoCapture`, so a
  host application can drive every state without a network or a platform channel.
