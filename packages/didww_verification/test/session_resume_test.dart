import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

const String _hash = 'A1b2C3d4E5f';

void main() {
  group('resumeByNumber', () {
    test('reads by number and creates nothing', () async {
      final transport = FakeTransport([ok(verificationJson())]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.resumeByNumber('+49 (151) 1234567');

      final request = transport.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/api/v1/verifications/by_number/491511234567');
      expect(request.body, isNull);
      expect(session.state, isA<VerificationAwaitingInput>());
    });

    test('the app hash is computed and compared but NEVER sent', () async {
      final capture = FakeAutoCapture();
      final transport = FakeTransport([ok(verificationJson(appHash: _hash))]);
      final session = VerificationSession(
        client: clientOver(transport.call),
        autoCapture: capture,
      );
      addTearDown(session.dispose);

      await session.resumeByNumber('+49 151 1234567');

      // A resume creates nothing, so there is nothing to send it on: the hash
      // exists only to be compared against the one the API already holds.
      expect(capture.hashCalls, 1);
      expect(transport.requests.single.body, isNull);
      expect(transport.requests.single.method, 'GET');
      expect(session.isAutoCaptureArmed, isTrue);
      expect(capture.listens, 1);
    });

    test('a resumed sms verification still captures automatically', () async {
      final capture = FakeAutoCapture();
      final transport = FakeTransport([
        ok(verificationJson(appHash: _hash)),
        ok(verificationJson(status: 'verified')),
      ]);
      final session = VerificationSession(
        client: clientOver(transport.call),
        autoCapture: capture,
      );
      addTearDown(session.dispose);

      await session.resumeByNumber('+49 151 1234567');
      capture.deliver('<#> Your code is 123456\n$_hash');
      await pumpEventQueue();

      expect(transport.bodyAt(1)['data'], {
        'delivery_method': 'sms',
        'code': '123456',
      });
      expect(session.state, isA<VerificationVerified>());
    });

    test('a hash the API does not hold leaves capture disarmed', () async {
      final capture = FakeAutoCapture();
      final transport = FakeTransport([ok(verificationJson())]);
      final session = VerificationSession(
        client: clientOver(transport.call),
        autoCapture: capture,
      );
      addTearDown(session.dispose);

      await session.resumeByNumber('+49 151 1234567');

      expect(capture.hashCalls, 1);
      expect(session.isAutoCaptureArmed, isFalse);
      expect(capture.listens, 0);
    });

    test('resuming a finished verification lands on its terminal state',
        () async {
      final transport = FakeTransport([
        ok(verificationJson(status: 'failed', errorCode: 'too_many_attempts')),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.resumeByNumber('+49 151 1234567');

      expect(session.state, isA<VerificationFailed>());
    });

    test('a resume never throws', () async {
      final session = VerificationSession(
        client: clientOver(
          (request) async => throw const TransportException('no route'),
        ),
      );
      addTearDown(session.dispose);

      await expectLater(session.resumeByNumber('+49 151 1234567'), completes);
      expect(session.state, isA<VerificationFailed>());
    });
  });

  group('resumeById', () {
    test('reads by id', () async {
      final transport = FakeTransport([ok(verificationJson(id: 'ver-7'))]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.resumeById('ver-7');

      expect(transport.requests.single.path, '/api/v1/verifications/ver-7');
      expect(transport.requests.single.body, isNull);
      expect(
        (session.state as VerificationAwaitingInput).verificationId,
        'ver-7',
      );
    });

    test('submitting after a resume by id reports against that id', () async {
      final transport = FakeTransport([
        ok(verificationJson(id: 'ver-7')),
        ok(verificationJson(id: 'ver-7', status: 'verified')),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.resumeById('ver-7');
      session.submit('123456');
      await pumpEventQueue();

      expect(transport.requests[1].method, 'PUT');
      expect(transport.requests[1].path, '/api/v1/verifications/ver-7');
      expect(session.state, isA<VerificationVerified>());
    });

    test('a resume while one is already running is rejected', () async {
      var calls = 0;
      final session = VerificationSession(
        client: clientOver((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return ok(verificationJson());
        }),
      );
      addTearDown(session.dispose);

      final first = session.resumeById('ver-1');
      await session.resumeById('ver-2');
      await first;

      expect(calls, 1);
    });
  });

  group('the re-entry recipe', () {
    test('a number with a live verification reattaches and creates nothing',
        () async {
      final transport = FakeTransport([ok(verificationJson())]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.resumeByNumber('+49 151 1234567');
      if (session.state is! VerificationAwaitingInput) {
        await session.start(
          destination: '+49 151 1234567',
          deliveryMethod: DeliveryMethod.sms,
        );
      }

      expect(transport.callCount, 1);
      expect(transport.requests.single.method, 'GET');
      expect(session.state, isA<VerificationAwaitingInput>());
    });

    test('a 404 falls through to exactly one create', () async {
      final transport = FakeTransport([
        jsonResponse(404, errorsJson(['not_found'])),
        created(verificationJson()),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.resumeByNumber('+49 151 1234567');
      expect(session.state, isA<VerificationFailed>());

      if (session.state is! VerificationAwaitingInput) {
        await session.start(
          destination: '+49 151 1234567',
          deliveryMethod: DeliveryMethod.sms,
        );
      }

      expect(transport.callCount, 2);
      expect(transport.requests[0].method, 'GET');
      expect(transport.requests[1].method, 'POST');
      expect(session.state, isA<VerificationAwaitingInput>());
    });

    test('a finished verification also falls through to a create', () async {
      // The by-number read answers with the newest row whatever its status, so
      // "did it 404" is not the whole question.
      final transport = FakeTransport([
        ok(verificationJson(status: 'verified')),
        created(verificationJson(id: 'ver-2')),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.resumeByNumber('+49 151 1234567');
      if (session.state is! VerificationAwaitingInput) {
        await session.start(
          destination: '+49 151 1234567',
          deliveryMethod: DeliveryMethod.sms,
        );
      }

      expect(transport.callCount, 2);
      expect(
        (session.state as VerificationAwaitingInput).verificationId,
        'ver-2',
      );
    });

    test('a denied row falls through, even though a live one may remain',
        () async {
      // A denied start supersedes nothing, so it is newest for the number while
      // an earlier verification is still live. Only the state check recovers.
      final transport = FakeTransport([
        ok(verificationJson(status: 'denied', errorCode: 'denied_by_callback')),
        created(verificationJson(id: 'ver-3')),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.resumeByNumber('+49 151 1234567');
      expect(session.state, isA<VerificationDenied>());

      if (session.state is! VerificationAwaitingInput) {
        await session.start(
          destination: '+49 151 1234567',
          deliveryMethod: DeliveryMethod.sms,
        );
      }

      expect(transport.callCount, 2);
      expect(
        (session.state as VerificationAwaitingInput).verificationId,
        'ver-3',
      );
    });
  });
}
