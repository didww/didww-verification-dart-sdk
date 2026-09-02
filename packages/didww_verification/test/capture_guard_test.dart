// The guards on the automatic-capture path. Both of these were reachable: a
// duplicate message could replace the submitting state with a captured one
// carrying the wrong code, and an app-hash read that never returned killed the
// session for good.
import 'dart:async';

import 'package:didww_verification/didww_verification.dart';
import 'package:test/test.dart';

import 'support.dart';

final class _HungCapture implements SmsAutoCapture {
  @override
  Future<String?> appHash() => Completer<String?>().future;
  @override
  Stream<String> messages() => const Stream<String>.empty();
}

void main() {
  test('a second delivered message cannot displace the report in flight',
      () async {
    final capture = FakeAutoCapture();
    final gate = Completer<void>();
    String? reported;

    final client = clientOver((request) async {
      if (request.method == 'POST') {
        return created(verificationJson(appHash: capture.hash));
      }
      reported = request.body!.contains('111111') ? '111111' : '222222';
      await gate.future;
      return ok(verificationJson(status: 'verified'));
    });

    final session = VerificationSession(client: client, autoCapture: capture);
    addTearDown(session.dispose);
    await session.start(
        destination: '491511234567', deliveryMethod: DeliveryMethod.sms);

    capture.deliver('Your code is 111111');
    await Future<void>.delayed(Duration.zero);
    expect(session.state, isA<VerificationSubmitting>());

    capture.deliver('Your code is 222222');
    await Future<void>.delayed(Duration.zero);

    // The screen fills its field from VerificationCaptured, so leaving this
    // state showing 222222 while 111111 is in flight shows the wrong code.
    expect(session.state, isA<VerificationSubmitting>());
    expect(reported, '111111');

    gate.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test('an app hash that never arrives does not strand the session', () async {
    var posts = 0;
    final client = clientOver((_) async {
      posts++;
      return created(verificationJson());
    });
    final session =
        VerificationSession(client: client, autoCapture: _HungCapture());
    addTearDown(session.dispose);

    await session.start(
        destination: '491511234567', deliveryMethod: DeliveryMethod.sms);

    // The start goes ahead without a hash rather than hanging on it, and the
    // in-flight flag is released so the session is still usable.
    expect(session.state, isA<VerificationAwaitingInput>());
    expect(posts, 1);
    expect(session.isAutoCaptureArmed, isFalse);
  }, timeout: const Timeout(Duration(seconds: 20)));
}
