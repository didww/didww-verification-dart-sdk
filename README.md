# DIDWW Verification SDK for Dart and Flutter

On-device Dart client for the [DIDWW Verification API](https://doc.didww.com/otp-verification/index.html).
Verify a phone number over SMS or callout.

Two packages, published separately from this repository:

| Package | What it is | Add it when |
|---|---|---|
| [`didww_verification`](packages/didww_verification) | Pure Dart, **no dependencies**. The API client and a stream-based verification session. | Always |
| [`didww_verification_sms`](packages/didww_verification_sms) | Flutter plugin, **Android only**. Automatic one-time code capture. | You want Android autofill |

The client package has no Flutter dependency and runs under plain `dart test`.

## Status

1.0.0 — the first release. From here a breaking change to either package's public API
requires a major version.

Neither package is on pub.dev yet. The client is published first: the plugin depends on it
by version constraint and cannot resolve until it is up.

## Authentication

Only the schemes that are safe to ship inside an application binary are supported: the
application-key scheme and HTTP Basic. Request signing requires a secret that must never
be embedded in an app, so it is intentionally absent — use a server-side SDK for that.

## iOS one-time code autofill

No SDK code is required. Set the autofill hint on your own text field:

```dart
TextField(autofillHints: const [AutofillHints.oneTimeCode])
```

That is why the SMS package is Android-only and ships no `ios/` directory.

## Development

This repository is a pub workspace: one lockfile at the root, and every package resolved
together.

```bash
flutter pub get                 # from the repository root
dart test                       # in packages/didww_verification
flutter test                    # in packages/didww_verification_sms
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

MIT — see [LICENSE](LICENSE).
