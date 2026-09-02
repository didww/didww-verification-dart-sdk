# didww_verification

Dart client for the [DIDWW Verification API](https://doc.didww.com/otp-verification/index.html).
Start a verification over SMS or callout, report the value the user received, and
read the outcome.

**No dependencies.** Pure Dart — it runs on the Dart VM, in Flutter and on the web, and adds
nothing to your dependency tree.

Two layers: [`VerificationClient`](#quick-start) is the five endpoints, and
[`VerificationSession`](#verificationsession--the-state-machine) is the state machine a screen
needs. Most Flutter apps want the session.

## Install

```yaml
dependencies:
  didww_verification: ^1.0.0
```

### Android release builds need `INTERNET` declared

Flutter's application template declares `android.permission.INTERNET` in
`android/app/src/debug/AndroidManifest.xml` and `.../profile/AndroidManifest.xml` — **not** in
`main/`. A debug build works; the release build has no network, and the first request fails with
a socket error that reads like an SDK fault. Declare it yourself:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.INTERNET" />
```

## Quick start

```dart
import 'package:didww_verification/didww_verification.dart';

final client = VerificationClient(
  auth: const PublicAuthorization('your-application-key'),
);

final started = await client.startVerification(
  destination: '+49 151 1234567',
  deliveryMethod: DeliveryMethod.sms,
);

final finished = await client.reportVerification(
  started.id,
  deliveryMethod: started.deliveryMethod,
  value: const ReportValue.code('123456'),
);

print(finished.knownStatus); // VerificationStatus.verified

client.close();
```

## `VerificationSession` — the state machine

`VerificationClient` is five methods over HTTP. `VerificationSession` wraps it in the state
machine a screen actually needs: one stream of states, single-flighted calls, and automatic
code capture when you supply it.

```dart
final session = VerificationSession(
  client: VerificationClient(auth: const PublicAuthorization('your-application-key')),
);

// In a widget:
StreamBuilder<VerificationState>(
  stream: session.states,
  initialData: session.state,
  builder: (context, snapshot) => switch (snapshot.data!) {
    VerificationIdle() || VerificationStarting() => const CircularProgressIndicator(),
    VerificationAwaitingInput(:final lastError) => CodeField(
        error: lastError?.detail,
        onSubmitted: session.submit,
      ),
    VerificationCaptured(:final value) => CodeField(value: value, enabled: false),
    VerificationSubmitting() => const CircularProgressIndicator(),
    VerificationVerified() => const Text('Verified'),
    VerificationExpired() => const Text('That code expired'),
    VerificationDenied(:final error) => Text(error?.detail ?? 'Refused'),
    VerificationSetupError(:final code) => Text('Application misconfigured: $code'),
    VerificationFailed(:final reason) => Text('$reason'),
  },
);

await session.start(
  destination: '+49 151 1234567',
  deliveryMethod: DeliveryMethod.sms,
);
```

Call `session.dispose()` from `State.dispose`. It is awaitable, safe to call twice, and cancels
every subscription and timer.

### The states

`VerificationState` is sealed, so the switch above needs no `default` arm and adding a state in
a later release is a compile error rather than a silent gap.

| State | Terminal | Means |
|---|---|---|
| `VerificationIdle` | | Nothing started, or `reset()` was called |
| `VerificationStarting` | | The start or resume request is in flight |
| `VerificationAwaitingInput` | | Live. Carries the id, the channel, `expiresAt`, the `sms` block and `lastError` |
| `VerificationCaptured` | | A code was recovered from a message and is about to be submitted |
| `VerificationSubmitting` | | A report is in flight |
| `VerificationVerified` | ✔ | The reported value was correct |
| `VerificationExpired` | ✔ | The API says the deadline passed |
| `VerificationDenied` | ✔ | Refused before dispatch |
| `VerificationSetupError` | ✔ | The application is misconfigured; no user input can fix it |
| `VerificationFailed` | ✔ | Anything else, with an `ApiFailure` or an `SdkFailure` |

`states` returns **the same object on every call**, so `StreamBuilder` will not resubscribe on
each rebuild. Every new listener receives the current state immediately, including one that
subscribes while another is still subscribed.

### Which rejections keep the verification alive

Six codes send the session back to `VerificationAwaitingInput` with `lastError` set, so the
user can try again: `code_invalid`, `code_blank`, `code_value_present`,
`delivery_method_invalid`, `validation_failed`, `not_ready_to_report`. Everything else is
terminal.

Three of those boundaries look wrong and are not:

- **`not_ready_to_report` arrives while the status reads `pending`.** `pending` is public
  before the message has finished dispatching, so the report is refused for a moment on a
  verification that looks ready. Retry it; it is not a terminal state.

- **`too_many_attempts` is terminal, and there is no local attempt counter anywhere.** Whether
  another attempt is allowed is the API's decision, and that code is how it says no.
- **`already_verified` is a failure, never `VerificationVerified`.** The verification succeeded
  earlier, but *this* submission was wrong — reporting success would let you admit someone who
  typed the wrong code.

A rejection during `VerificationStarting` is always terminal, whatever the code: nothing is
retryable before a verification exists.

This partition is compiled in, because the `422` envelope carries no "still alive" flag. If the
API ever moves a code between the two sets, this table goes stale.

### Re-entering the screen: resume first, start second

`start()` bills the account and supersedes whatever the destination already had. The session's
guards are **per instance**, so a route remount — `Navigator.pushReplacement`, a tab switch that
disposes the route, a deep link back into the same page — builds a *new* session whose guards
cannot see the old one, and a second `start()` bills again.

`resumeByNumber` bills nothing, so the recipe costs nothing:

```dart
await session.resumeByNumber(destination);
if (session.state is! VerificationAwaitingInput) {
  await session.start(destination: destination, deliveryMethod: DeliveryMethod.sms);
}
```

The check is `is! VerificationAwaitingInput` rather than "did it 404", because the by-number read
answers with the **newest** verification for the number whatever its status, which is not the same
as the live one: a start that was itself denied supersedes nothing, so it is newest while an
earlier verification is still live. `resumeById` does the same for a verification you persisted
across an app restart — and answers 404 once a finished verification passes the 24-hour retention
window, so persist the outcome rather than the id if you need it later. Neither takes
`SmsOptions` or `CalloutOptions` — every option there is a create-time choice.

### Automatic capture

`start()` and `submit()` work identically with and without it; without it the user types the
code. Supply an `SmsAutoCapture` to have it filled in:

```dart
abstract interface class SmsAutoCapture {
  Future<String?> appHash();   // 11 characters, or null where there is none
  Stream<String> messages();   // listening arms the platform listener
}

final session = VerificationSession(client: client, autoCapture: myCapture);
```

On Android, `didww_verification_sms` implements it over the SMS Retriever API, so the app needs
no SMS permission and sees no message but its own:

```dart
import 'package:didww_verification_sms/didww_verification_sms.dart';

final session = VerificationSession(
  client: client,
  autoCapture: const SmsRetrieverAutoCapture(), // a no-op off Android
);
```

Everywhere else that capture reports it has nothing rather than throwing, so an app can depend
on the package unconditionally.

`hasAutoCapture` is true from construction, so a screen can decide up front whether to promise
the user anything. `isAutoCaptureArmed` is true only once capture is actually running for the
current verification.

**Capture arms only when the API echoes back the same app hash the device computed.** The hash is
computed before the start request and sent with it; if the response's `sms.appHash` is absent or
different, the platform listener is never touched. On a resume the hash is computed and compared
but **never sent**, which is what lets a resumed SMS verification keep capturing.

> **The trap.** Play App Signing re-signs your upload artifact, so a hash computed from a locally
> signed build never matches in production and the only symptom is that capture silently never
> fires. Display `getAppHash()` in your app during development and register the value you see
> there.

The subscription is cancelled on any terminal state, when the server's `interception_timeout`
budget elapses, when `expiresAt` passes, and on `reset()` and `dispose()` — whichever comes
first. Running out of budget only stops listening: manual entry stays live, because expiry is
the API's decision and arrives on the next response.

A capture that reports a malformed hash, or throws while reading one, is **dropped**: the start
goes out with no `app_hash` and is otherwise identical to one that never had a hash. A bug in an
optional convenience must not fail an operation you are billed for.

### Calls that cannot go wrong

- `start()` and the resumes **never throw**. Every outcome, failure included, arrives through
  `states`.
- A second `start()` while one is in flight sends nothing and reports
  `SdkFailure(SdkAlreadyRunning())`.
- A second `submit()` while one is in flight is dropped, so a double tap cannot burn two
  attempts. `submit()` before the verification is live is buffered; after a terminal state
  it is ignored.
- `submit()` returns nothing on purpose. **Drive your spinner from `states`, never from the
  call** — every case where the value is dropped is one where the current state already says why.

## Authentication

| Scheme | Header | Use it |
|---|---|---|
| `PublicAuthorization(key)` | `Application <key>` | On a device. Carries no secret. |
| `BasicAuthorization(key: …, secret: …)` | `Basic <base64(key:secret)>` | Server-side only. |

**A secret compiled into an application binary is recoverable** — a release APK or IPA is a file
someone can unzip. `PublicAuthorization` exists so an app never has to carry one. Reach for
`BasicAuthorization` only where the process is yours.

Request signing is a third scheme the API accepts and this package deliberately does not
implement: it needs a signing secret, which is the thing an app must not hold.

> Never append anything to the application key. The API routes on the first colon anywhere after
> the `Application ` prefix, so `Application key:anything` selects the signed scheme and fails
> authentication rather than falling back.

### When valid credentials still return 401

An application can be configured to require a request-signing scheme this SDK does not implement.
Both `PublicAuthorization` and `BasicAuthorization` are then refused — the credentials are fine, the
mode is simply below what the application demands — and the 401 is indistinguishable from a wrong
key. If a key that works elsewhere returns 401 here, check the application's minimum authentication
mode before suspecting the key.

The scheme is deliberately absent: it signs with the same shared secret `BasicAuthorization` would
have embedded, so it is no safer on a device. `Authorization` is a public seam and carries every
input its string-to-sign needs, so a server-side integrator can implement it without forking.

## Environments

```dart
VerificationClient(auth: …);                                       // production
VerificationClient(auth: …, environment: VerificationEnvironment.sandbox);
VerificationClient(
  auth: …,
  environment: VerificationEnvironment.custom(Uri.parse('https://proxy.example.com/verify')),
);
```

A custom base carries a scheme, a host and optionally a base path. The SDK appends the API
version itself, so do not include it.

## The five methods

```dart
Future<Verification> startVerification({
  required String destination,
  required DeliveryMethod deliveryMethod,
  SmsOptions? sms,
  CalloutOptions? callout,
  String? appHash,
});

Future<Verification> getVerification(String id);
Future<Verification> getVerificationByNumber(String number);

Future<Verification> reportVerification(String id,
    {required String deliveryMethod, required ReportValue value});
Future<Verification> reportVerificationByNumber(String number,
    {required String deliveryMethod, required ReportValue value});
```

`getVerificationByNumber` returns the newest verification for a number whatever its status. That
is usually the live one, because a start supersedes what came before it — but a start that was
itself *denied* supersedes nothing, so it is newest while an earlier verification is still live.
It bills nothing, which makes it the cheap way to reattach to a verification after your screen was
rebuilt or your app was restarted.

**Report is sent as `PUT`.** The API accepts `PATCH` for the same operation.

### Retries

Reads are retried; **`startVerification` and `reportVerification` never are, under any
configuration.** A start bills the account and a report consumes one of a small number of
attempts, and a request that timed out may still have been carried out. That is structural — the
retry wrapper is attached at the two reading call sites, so no `RetryPolicy` value can change it.

```dart
VerificationClient(
  auth: …,
  config: const ClientConfig(retry: RetryPolicy(attempts: 3)),
);
```

## Phone numbers

Every destination is normalised to digits before it is sent: `'+49 (151) 1234-567'` goes out as
`'491511234567'`. The API stores and echoes that form, so `Verification.destination` never
carries a `+` or any formatting.

Keep your own copy of what the user typed for display, and compare with `digitsOf` rather than
against a formatted string:

```dart
digitsOf(userInput) == verification.destination
```

## The `sms` block

On the request, `SmsOptions` carries the template languages you would like:

```dart
await client.startVerification(
  destination: destination,
  deliveryMethod: DeliveryMethod.sms,
  sms: const SmsOptions(languages: ['pl-PL', 'en-US']),
);
```

A tag is a primary subtag of two or three letters plus **at most one more** subtag — narrower than
BCP 47, and that difference bites. `Locale.toLanguageTag()` produces `zh-Hans-CN`, `zh-Hant-TW`,
`sr-Latn-RS`, `az-Latn-AZ` and `uz-Latn-UZ`, none of which the API accepts, so passing the device
locale straight through is not safe.

The SDK drops a tag of the wrong shape rather than sending it — sent, the API answers
`languages_invalid` and creates no verification at all, where dropping it costs only the preferred
language. A debug diagnostic names what was dropped.

Two different outcomes, worth keeping apart:

| | Result |
|---|---|
| A tag of the right shape with no template | Falls back to the default language |
| A tag of the wrong shape | Dropped by the SDK; would be `422 languages_invalid` if sent |

Tags are matched **exactly**, most preferred first: `pl` does not match `pl-PL`. The response names
the tag that was actually used — see `sms.language` below.

`app_hash` is not part of `SmsOptions`. It is a property of the installed Android build, not a
choice a caller makes, and a malformed one fails the whole verification — so it is supplied by
the capture implementation and validated before it reaches the wire. `startVerification` takes an
`appHash` parameter for that path; a value that is not eleven characters of `[A-Za-z0-9+/]` is
**dropped**, and the request goes out identical to one that never carried a hash. Losing autofill
beats failing a paid verification.

On the response, `Verification.sms` is non-null exactly on the sms channel:

```dart
final sms = verification.sms;
sms?.template;                     // the message with its placeholder still in it
sms?.language;                     // the tag the API chose, which may not be the one you asked for
sms?.interceptionTimeoutSeconds;   // how long to keep a listener armed
sms?.appHash;                      // what the API stored, absent if nothing was stored
```

**`interceptionTimeoutSeconds` is a budget, not a deadline and not a countdown.** It says how
long to keep an on-device listener armed. It does not shorten the verification: manual entry keeps
working until `expiresAt`, and running out of budget only stops listening. Do not render it as a
timer to the user.

## The `callout` block

`CalloutOptions` is the same shape as `SmsOptions` and takes the same tags, so one language list
serves both channels:

```dart
await client.startVerification(
  destination: destination,
  deliveryMethod: DeliveryMethod.callout,
  callout: const CalloutOptions(languages: ['pt-BR', 'pt-PT']),
);
```

Only the block matching the channel is read, so passing `sms:` on a callout start — or the other
way round — is ignored rather than rejected. Tags of the wrong shape are dropped before the request
goes out, on whichever block is read; the rule is the same one the `sms` block documents.

On the response, `Verification.callout` is non-null exactly on the callout channel:

```dart
verification.callout?.language;    // the tag the announcement is played in
```

**The two channels have separate language sets, and neither is a subset of the other.** A tag that
picks a message template may have no recording, and an unservable tag is *accepted* — it falls
back to the default language rather than failing the request. Nothing else in the response says
that happened, so comparing what you asked for against what came back is the only way to know:

```dart
final chosen = verification.callout?.language;
if (chosen != null && chosen != myPreferredTag) {
  // The announcement is in another language; say so before the call arrives.
}
```

Both sets are server-side data that changes without a client release, so this package compiles in
neither of them and cannot tell you in advance which tags are servable.

## Reading a verification

```dart
verification.status;                // raw
verification.knownStatus;           // typed, or null for a status this release does not model
verification.isFinished;            // false for an unmodelled status, never a guess
verification.errorCode;             // raw outcome code on a finished verification
verification.knownErrorCode;        // typed
verification.outcome;               // the outcome as an ApiErrorItem
```

`status: expired` is synthesised when the API reads an unfinished verification whose deadline has
passed — the row is not rewritten on a schedule, so the status you get back on a read can differ
from the one the last write returned.

**`fee` is a decimal string, and it stays one.** Never parse it as a `double`. It is a quote
rather than a charge: it is billed on a verified outcome, VAT-inclusive, and the message or call
is billed separately.

## Errors

Everything the SDK throws descends from `VerificationException`, which is `sealed`:

| Type | When |
|---|---|
| `ConfigurationException` | Asked to do something impossible; nothing was sent. |
| `TransportException` | No response: DNS, TLS, connection or timeout. |
| `DecodingException` | A response arrived that was not the documented shape. |
| `ApiException` | The API answered with an error envelope. |

`ApiException` has five status-specific subtypes — `UnauthorizedException` (401),
`BalanceInsufficientException` (402), `NotFoundException` (404), `ValidationException` (400/422)
and `ServerException` (5xx). A status with none of its own arrives as a plain `ApiException`
rather than a decode failure.

**Switch on the code, not on the prose.** `detail` is fixed English wording that exists for logs;
`code` is the contract:

```dart
try {
  await client.reportVerification(id, deliveryMethod: method, value: value);
} on ApiException catch (e) {
  switch (e.first?.known) {
    case ApiErrorCode.codeInvalid:      // ask again
    case ApiErrorCode.tooManyAttempts:  // no attempts left; the server decides this
    case null:                          // a code this release does not model
    default:
  }
}
```

An envelope can carry several elements — one per failing field — and one naming a code this
release does not model resolves to `known: null` without poisoning the rest.

**A `401` for an account with no verification plan is by design.** It is access scoping, not a
fault to work around: the account cannot use this API until a plan is assigned.

## Seams

Two interfaces exist so you can replace what the SDK does without forking it.

`HttpTransport` is a function, so a double is a closure:

```dart
typedef HttpTransport = Future<HttpResponse> Function(HttpRequest request);

VerificationClient(auth: …, transport: myTransport);
```

Supplying one means the SDK creates no `HttpClient` and `close()` has nothing to release. Note that
a supplied transport owns its own deadlines only in part: `ClientConfig.timeout` still bounds the
call, so a transport that never answers cannot hang the session.

### Platforms, and the one import that is separate

The main library carries no `dart:io`, so the package builds and runs on the web. There is no
built-in transport there — supply one over `package:http` or `fetch`, and the client says so
explicitly if you forget.

`IOHttpTransport` therefore lives in its own library, and you only need it to hold one by hand:

```dart
import 'package:didww_verification/io.dart';
```

The client builds one for itself on the VM and in mobile Flutter when given no `transport:`, so most
callers never import this.

`Authorization` produces the headers for a request, and is handed everything a signing scheme
would need:

```dart
abstract interface class Authorization {
  Map<String, String> headers(AuthRequest request);
}
```

## Testing

```dart
import 'package:didww_verification/testing.dart';

final fake = FakeTransport.json({'data': {...}});
final client = VerificationClient(auth: const PublicAuthorization('k'), transport: fake.call);

await client.getVerification('ver-1');

fake.lastRequest!.method;   // 'GET'
fake.callCount;             // 1
fake.bodyAt(0);             // the decoded request body
```

`FakeTransport` replays scripted responses in order, repeats the last one once the script runs
out, records every request, and can be told to throw on a given attempt.

**Mock at the transport, not at the client.** `VerificationClient` and `VerificationSession` are
`final`, so `class MockClient extends Mock implements VerificationClient` will not compile. Drive a
real client over a fake transport instead — the request bodies are then asserted as they go on the
wire, rather than as a mock happened to record them.

## No dependencies

`pubspec.yaml` has no `dependencies:` key, and gaining one would be a breaking change to a
published guarantee. Check it yourself:

```bash
dart pub deps --style=compact
```

## Logging

`ClientConfig.logger` receives one line per request — method, path and status, never a body and
never a header. Digit runs of six or more are replaced with their length first, so a by-number
path cannot put a destination in your logs.

## Licence

MIT — see [LICENSE](LICENSE).
