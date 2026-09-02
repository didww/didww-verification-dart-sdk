# didww_verification_sms

Android automatic one-time code capture for
[`didww_verification`](https://pub.dev/packages/didww_verification), over Google's SMS
Retriever API.

## Use it

```dart
import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification_sms/didww_verification_sms.dart';

final session = VerificationSession(
  client: VerificationClient(auth: const PublicAuthorization('your-application-key')),
  autoCapture: const SmsRetrieverAutoCapture(),
);
```

That is the whole integration. `start()` and `submit()` behave identically with and without
it, so nothing else in your screen changes; the code simply arrives on its own when it can.
The session arms the platform listener only when the API echoes back the same app hash this
build computed, and disarms it on any terminal state, on the server's interception budget, on
the verification's deadline, and on `dispose()`.

## Android only, and there is no `ios/`

iOS has no SMS Retriever equivalent, and it needs no plugin. One-time code autofill there is a
hint on your own text field:

```dart
TextField(autofillHints: const [AutofillHints.oneTimeCode])
```

So this package declares `platforms: android:` and ships no iOS directory, and it is safe to
depend on unconditionally: everywhere but Android `appHash()` resolves to null and `messages()`
is an empty stream.

**That degradation is code in this package, not a consequence of the declaration.** With no
iOS registration `MethodChannel.invokeMethod` throws `MissingPluginException`, and
`EventChannel.receiveBroadcastStream()` is worse — its `onListen` routes the platform exception
to `FlutterError.reportError` rather than to the stream, so the stream is silently empty *and*
every listener logs a red framework error. The facade checks the target platform before
touching either channel. The absence of `ios/` is asserted in CI.

## No permissions

The SMS Retriever API needs none — not `RECEIVE_SMS`, not `READ_SMS`, not `READ_CALL_LOG`. The
receiver is registered at runtime, behind `SmsRetriever.SEND_PERMISSION` so only Play Services
can reach it, and the platform hands over only the one message addressed to your app.

This package declares no permission and no `<receiver>` element. A Gradle check over the
example app's **merged** manifest asserts that none of the three appears, and diffs the whole
component set against a committed golden so a dependency bump cannot contribute one quietly:

```
cd example/android && ./gradlew :app:checkManifestComponents
```

That matters beyond tidiness: those permissions are the ones that draw Play Console review.

## The app hash

The Retriever only delivers a message that ends with an 11-character hash derived from your
package name and your signing certificate. The verification API stores that hash and appends it
to the message it sends.

```dart
final hash = await getAppHash(); // 11 characters, or null off Android
```

Two facts to know before you ship:

- **Play App Signing re-signs your upload artifact.** A hash computed from your local upload key
  does not match the one on the installed build, and nothing reports this — messages simply
  never arrive automatically, and manual entry keeps working. Read the value off the installed
  build; the example app displays it for exactly this reason.
- **Omitting the hash costs autofill only. Sending a malformed one fails the whole
  verification.** The client validates the format and drops a bad value rather than sending it,
  for exactly that reason.

## What has been verified

The hash algorithm is asserted against a constant derived from Google's reference
implementation outside this codebase, and the receiver's registration, teardown and re-arming
are covered by unit tests.

Automatic capture end to end on a real handset is **not** verified. The emulator establishes
that the hash is computed and that the wiring holds; it cannot deliver a real SMS. Check your
own hash on your own device — it is the only place it can be checked.

## Licence

MIT — see [LICENSE](LICENSE).
