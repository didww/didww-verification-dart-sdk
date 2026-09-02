import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

const String _hash = 'A1b2C3d4E5f';

/// A session whose start response echoes [echo] as the stored app hash.
({
  VerificationSession session,
  FakeAutoCapture capture,
  FakeTransport transport
}) _armed({
  String? echo = _hash,
  String? deviceHash = _hash,
  Object? hashFails,
  int? interceptionTimeout = 120,
  DateTime? expiresAt,
  List<HttpResponse> then = const [],
}) {
  final capture = FakeAutoCapture(hash: deviceHash, failsWith: hashFails);
  final transport = FakeTransport([
    created(verificationJson(
      appHash: echo,
      interceptionTimeout: interceptionTimeout,
      expiresAt: expiresAt,
    )),
    ...then,
  ]);
  return (
    session: VerificationSession(
      client: clientOver(transport.call),
      autoCapture: capture,
    ),
    capture: capture,
    transport: transport,
  );
}

Future<void> _start(VerificationSession session) => session.start(
      destination: '+49 151 1234567',
      deliveryMethod: DeliveryMethod.sms,
    );

void main() {
  group('the arming gate', () {
    test('capture arms only when the API echoes the hash that was sent',
        () async {
      final fixture = _armed();
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);

      final data = fixture.transport.bodyAt(0)['data'] as Map<String, dynamic>;
      expect(data['sms'], {'app_hash': _hash});
      expect(fixture.session.hasAutoCapture, isTrue);
      expect(fixture.session.isAutoCaptureArmed, isTrue);
      expect(fixture.capture.listens, 1);
    });

    test('an absent echo never subscribes', () async {
      final fixture = _armed(echo: null);
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);

      expect(fixture.session.isAutoCaptureArmed, isFalse);
      expect(fixture.capture.listens, 0);
    });

    test('a differing echo never subscribes', () async {
      // The Play App Signing case: the device computed a hash from a locally
      // signed build and the API holds the one from the upload key.
      final fixture = _armed(echo: 'ZZZZZZZZZZZ');
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);

      expect(fixture.session.isAutoCaptureArmed, isFalse);
      expect(fixture.capture.listens, 0);
    });

    test('a malformed device hash is dropped, and the start still succeeds',
        () async {
      final fixture = _armed(deviceHash: 'tooshort', echo: null);
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);

      expect(fixture.session.state, isA<VerificationAwaitingInput>());
      expect(fixture.transport.bodyAt(0)['data'], isNot(contains('sms')));
      expect(fixture.session.isAutoCaptureArmed, isFalse);
      expect(fixture.capture.listens, 0);
    });

    test('a capture that throws while reading the hash does not fail the start',
        () async {
      final fixture = _armed(
        hashFails: StateError('no signing certificate'),
        echo: null,
      );
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);

      expect(fixture.session.state, isA<VerificationAwaitingInput>());
      expect(fixture.transport.bodyAt(0)['data'], isNot(contains('sms')));
      expect(fixture.session.isAutoCaptureArmed, isFalse);
    });

    test('a captured code is submitted without the user typing it', () async {
      final fixture = _armed(
        then: [ok(verificationJson(status: 'verified'))],
      );
      addTearDown(fixture.session.dispose);
      final recorder = StateRecorder(fixture.session);
      addTearDown(recorder.cancel);

      await _start(fixture.session);
      fixture.capture.deliver('<#> Your code is 123456\n$_hash');
      await pumpEventQueue();

      expect(fixture.transport.bodyAt(1)['data'], {
        'delivery_method': 'sms',
        'code': '123456',
      });
      expect(recorder.names, contains('VerificationCaptured'));
      expect(fixture.session.state, isA<VerificationVerified>());
    });

    // Guaranteed by the cancel in _emit, not by a check in the message handler:
    // Dart refuses to deliver to a cancelled subscription whatever the producer
    // does, so a handler-side guard would be unreachable code.
    test('a message arriving after a terminal state cannot resurrect it',
        () async {
      final fixture = _armed(
        then: [ok(verificationJson(status: 'verified'))],
      );
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);
      fixture.session.submit('123456');
      await pumpEventQueue();
      expect(fixture.session.state, isA<VerificationVerified>());

      fixture.capture.deliver('<#> Your code is 999999\n$_hash');
      await pumpEventQueue();

      expect(fixture.session.state, isA<VerificationVerified>());
      expect(fixture.transport.callCount, 2);
    });

    test('a message that does not match the template is ignored', () async {
      final fixture = _armed();
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);
      fixture.capture.deliver('Your parcel is out for delivery');
      await pumpEventQueue();

      expect(fixture.transport.callCount, 1);
      expect(fixture.session.state, isA<VerificationAwaitingInput>());
    });
  });

  group('the subscription is cancelled on every terminal state', () {
    final terminal = <String, ({HttpResponse response, Type state})>{
      'verified': (
        response: ok(verificationJson(status: 'verified')),
        state: VerificationVerified,
      ),
      'failed': (
        response: jsonResponse(422, errorsJson(['too_many_attempts'])),
        state: VerificationFailed,
      ),
      'denied': (
        response: ok(verificationJson(
            status: 'denied', errorCode: 'denied_by_callback')),
        state: VerificationDenied,
      ),
      'expired': (
        response: ok(verificationJson(status: 'expired', errorCode: 'expired')),
        state: VerificationExpired,
      ),
      'setup error': (
        response:
            jsonResponse(422, errorsJson(['denied_missing_callback_url'])),
        state: VerificationSetupError,
      ),
    };

    terminal.forEach((name, outcome) {
      test('$name disarms capture', () async {
        final fixture = _armed(then: [outcome.response]);
        addTearDown(fixture.session.dispose);

        await _start(fixture.session);
        expect(fixture.session.isAutoCaptureArmed, isTrue);

        fixture.session.submit('000000');
        await pumpEventQueue();

        expect(fixture.session.state.runtimeType, outcome.state);
        expect(fixture.session.isAutoCaptureArmed, isFalse);
        expect(fixture.capture.cancels, 1);
      });
    });
  });

  group('the subscription is cancelled on a deadline', () {
    test(
        'when the interception budget elapses, with the verification still '
        'live', () async {
      final fixture = _armed(interceptionTimeout: 1);
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);
      expect(fixture.session.isAutoCaptureArmed, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(fixture.capture.cancels, 1);
      expect(fixture.session.isAutoCaptureArmed, isFalse);
      // Running out of budget stops listening and nothing else: manual entry
      // stays live until the API says otherwise.
      expect(fixture.session.state, isA<VerificationAwaitingInput>());
    });

    test('when expiresAt passes, even with a budget that has not', () async {
      final fixture = _armed(
        interceptionTimeout: 3600,
        expiresAt:
            DateTime.now().toUtc().add(const Duration(milliseconds: 150)),
      );
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);
      expect(fixture.session.isAutoCaptureArmed, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(fixture.capture.cancels, 1);
      expect(fixture.session.isAutoCaptureArmed, isFalse);
    });

    test('a null budget falls back to expiresAt alone', () async {
      final fixture = _armed(
        interceptionTimeout: null,
        expiresAt:
            DateTime.now().toUtc().add(const Duration(milliseconds: 150)),
      );
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fixture.session.isAutoCaptureArmed, isTrue,
          reason: 'a null budget must not disarm immediately');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(fixture.capture.cancels, 1);
    });

    test('a deadline already in the past disarms rather than throwing',
        () async {
      final fixture = _armed(
        interceptionTimeout: null,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);
      await pumpEventQueue();

      expect(fixture.capture.cancels, 1);
    });
  });

  group('reset and dispose', () {
    test('reset cancels the subscription and returns to idle', () async {
      final fixture = _armed();
      addTearDown(fixture.session.dispose);

      await _start(fixture.session);
      await fixture.session.reset();

      expect(fixture.capture.cancels, 1);
      expect(fixture.session.isAutoCaptureArmed, isFalse);
      expect(fixture.session.state, isA<VerificationIdle>());
    });

    test('dispose cancels the subscription', () async {
      final fixture = _armed();

      await _start(fixture.session);
      await fixture.session.dispose();

      expect(fixture.capture.cancels, 1);
      expect(fixture.session.isAutoCaptureArmed, isFalse);
    });

    test('50 start-to-dispose iterations end with cancels equal to listens',
        () async {
      final capture = FakeAutoCapture();

      for (var i = 0; i < 50; i++) {
        final session = VerificationSession(
          client: clientOver(
            FakeTransport([created(verificationJson(appHash: _hash))]).call,
          ),
          autoCapture: capture,
        );
        await _start(session);
        expect(session.isAutoCaptureArmed, isTrue, reason: 'iteration $i');
        await session.dispose();
      }

      expect(capture.listens, 50);
      expect(capture.cancels, capture.listens);
    });

    test('50 start-to-reset iterations on ONE session leak nothing', () async {
      final capture = FakeAutoCapture();
      final session = VerificationSession(
        client: clientOver(
          (request) async => created(verificationJson(appHash: _hash)),
        ),
        autoCapture: capture,
      );
      addTearDown(session.dispose);

      for (var i = 0; i < 50; i++) {
        await _start(session);
        await session.reset();
      }

      expect(capture.listens, 50);
      expect(capture.cancels, capture.listens);
    });

    test('starting again disarms the previous verification first', () async {
      final capture = FakeAutoCapture();
      final session = VerificationSession(
        client: clientOver(
          (request) async => created(verificationJson(appHash: _hash)),
        ),
        autoCapture: capture,
      );
      addTearDown(session.dispose);

      await _start(session);
      await _start(session);

      expect(capture.listens, 2);
      expect(capture.cancels, 1);
      expect(session.isAutoCaptureArmed, isTrue);
    });
  });
}
