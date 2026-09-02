# Changelog

Notable changes to `didww_verification`. Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): from 1.0.0 onwards a breaking
change to the public surface requires a major version.

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
