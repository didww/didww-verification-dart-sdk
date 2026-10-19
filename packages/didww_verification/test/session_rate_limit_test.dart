import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'support.dart';

HttpResponse _tooMany(String code, {String retryAfter = '1'}) => HttpResponse(
      status: 429,
      headers: {'content-type': 'application/json', 'retry-after': retryAfter},
      body: errorsJson([code]),
    );

/// Starts a session over [transport] and submits a code, inside [async].
VerificationSession _submitted(FakeAsync async, FakeTransport transport) {
  final session = VerificationSession(client: clientOver(transport.call));
  session.start(
    destination: '+49 151 1234567',
    deliveryMethod: DeliveryMethod.sms,
  );
  async.flushMicrotasks();
  session.submit('123456');
  async.flushMicrotasks();
  return session;
}

void main() {
  group('a rate-limited submission', () {
    for (final code in [
      'rate_limit_per_ip',
      'rate_limit_failed_auth',
      'rate_limit_per_account',
      'rate_limit_public_per_account',
    ]) {
      test('$code is retried once after Retry-After', () {
        fakeAsync((async) {
          final transport = FakeTransport([
            created(verificationJson()),
            _tooMany(code),
            ok(verificationJson(status: 'verified')),
          ]);
          final session = _submitted(async, transport);

          async.elapse(const Duration(milliseconds: 999));
          expect(transport.callCount, 2);
          expect(session.state, isA<VerificationSubmitting>());

          async.elapse(const Duration(milliseconds: 1));
          expect(transport.callCount, 3);
          expect(transport.bodyAt(2), transport.bodyAt(1));
          expect(session.state, isA<VerificationVerified>());
          session.dispose();
        });
      });
    }

    test('limited again surfaces the error and stays recoverable', () {
      fakeAsync((async) {
        final transport = FakeTransport([
          created(verificationJson()),
          _tooMany('rate_limit_per_ip'),
          _tooMany('rate_limit_per_ip'),
          ok(verificationJson(status: 'verified')),
        ]);
        final session = _submitted(async, transport);

        async.elapse(const Duration(seconds: 1));
        expect(transport.callCount, 3);
        final live = session.state as VerificationAwaitingInput;
        expect(live.lastError?.known, ApiErrorCode.rateLimitPerIp);

        async.elapse(const Duration(seconds: 10));
        expect(transport.callCount, 3, reason: 'retried only once');

        session.submit('123456');
        async.flushMicrotasks();
        expect(transport.callCount, 4);
        expect(session.state, isA<VerificationVerified>());
        session.dispose();
      });
    });

    test('waits at most five seconds whatever Retry-After says', () {
      fakeAsync((async) {
        final transport = FakeTransport([
          created(verificationJson()),
          _tooMany('rate_limit_per_account', retryAfter: '60'),
          ok(verificationJson(status: 'verified')),
        ]);
        final session = _submitted(async, transport);

        async.elapse(const Duration(milliseconds: 4999));
        expect(transport.callCount, 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(transport.callCount, 3);
        expect(session.state, isA<VerificationVerified>());
        session.dispose();
      });
    });

    test('a reset during the wait sends no retry', () {
      fakeAsync((async) {
        final transport = FakeTransport([
          created(verificationJson()),
          _tooMany('rate_limit_per_ip'),
        ]);
        final session = _submitted(async, transport);

        session.reset();
        async.elapse(const Duration(seconds: 6));
        expect(transport.callCount, 2);
        expect(session.state, isA<VerificationIdle>());
        session.dispose();
      });
    });

    test('volume_limit_reached is terminal and not retried', () {
      fakeAsync((async) {
        final transport = FakeTransport([
          created(verificationJson()),
          _tooMany('volume_limit_reached', retryAfter: '3600'),
        ]);
        final session = _submitted(async, transport);

        async.elapse(const Duration(seconds: 6));
        expect(transport.callCount, 2);
        expect(session.state, isA<VerificationFailed>());
        session.dispose();
      });
    });
  });

  test('a rate-limited start is terminal and not retried', () {
    fakeAsync((async) {
      final transport = FakeTransport([_tooMany('rate_limit_per_ip')]);
      final session = VerificationSession(client: clientOver(transport.call));
      session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );

      async.elapse(const Duration(seconds: 6));
      expect(transport.callCount, 1);
      expect(session.state, isA<VerificationFailed>());
      session.dispose();
    });
  });
}
