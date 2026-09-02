# Security policy

## Reporting a vulnerability

Use GitHub's **[private vulnerability reporting](https://github.com/didww/didww-verification-dart-sdk/security/advisories/new)**
— *Security* → *Report a vulnerability* on this repository. It opens a channel visible only to
the maintainers. Please do not open a public issue for a suspected vulnerability.

Include the package and version, and enough detail to reproduce. If you have a proof of
concept, a failing test against this repository is the most useful form.

If the issue is in the DIDWW verification API rather than in this client, raise it through your
DIDWW account instead — it is fixed server-side and needs no SDK release.

## Supported versions

Only the latest release is supported. There is no backporting.

## Things that are working as intended

Three behaviours look like findings and are not. All three are documented where they occur;
they are repeated here because this is the page a reader checks first.

### `BasicAuthorization` puts a server-to-server secret in your app

`BasicAuthorization(key:, secret:)` sends `Authorization: Basic base64(key:secret)`. **The
secret is recoverable from any binary that contains it.** It exists for local development and
for hosts that proxy through their own backend. The SDK emits one diagnostic per process when
it is used — through `dart:developer`, so the warning is present in a debug build and compiled
out of a release build, where it would be a string in the binary saying what to look for.

Ship `PublicAuthorization(applicationKey)` instead. The application key identifies your
application but is not a secret: extracting it gains an attacker nothing they could not do by
installing the app, because the server asks your application's callback URL to authorise each
verification.

If you have shipped `BasicAuthorization` in a released app, treat the secret as disclosed and
rotate it.

Request signing is absent from this SDK, and deliberately: it needs a secret that must never
be embedded in an application binary at all. Use a server-side SDK for it.

### The SMS broadcast receiver is registered as exported

`didww_verification_sms` registers a runtime receiver for the SMS Retriever's broadcast, which
Android requires to be exported because the sender is Google Play services. It is registered
with `SmsRetriever.SEND_PERMISSION`. Without that permission any app on the device could forge
the Retriever's extras and inject a code this SDK would then submit on the user's behalf — the
guard is deliberate and load-bearing.

### A start or a report is never retried

`ClientConfig.retry` applies to reads only. A start or a report that timed out may still have
been carried out at the server, so repeating it bills a second verification or burns an
attempt. A timeout is reported as a `TransportException`; deciding what to do about it is the
caller's, because only the caller knows whether the user is still there.

## What this SDK does not do

- **It stores nothing.** No credential, code, or verification state is persisted. Neither
  package opens a file or writes to platform preferences; the only `dart:io` import in the
  client is `HttpClient`, in the transport.
- **It logs no code, no destination number, and no credential.** There is one log site in the
  client — `debugDiagnostic`, which runs inside an `assert` and so vanishes from a release
  build. It carries the `BasicAuthorization` warning above and a note when a language tag is
  dropped as unacceptable. The message on `SdkUnexpectedError` passes through a redactor that
  replaces every run of six or more digits with its length, because that path can carry an
  arbitrary error string and a by-number request path contains the destination.
- **The Android plugin logs three lines**, all in the app-hash computation: two warnings that
  capture is unavailable, and the package name with its app hash at `DEBUG`. The hash is
  appended to every message and is derived from public inputs.
- **It declares no permission of its own.** The plugin's manifest is empty, and the SMS
  Retriever needs neither `READ_SMS` nor `RECEIVE_SMS`. That every variant's *merged* manifest
  is free of SMS and call-log permissions is asserted by a Gradle task, run from
  `tool/check_manifest_permissions.sh`. Your application still has to declare `INTERNET`
  itself — Flutter's template declares it for debug and profile builds only.
