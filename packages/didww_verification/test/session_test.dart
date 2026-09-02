import 'dart:async';

import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('states is one object with independent listeners', () {
    test('identical(session.states, session.states) is true', () {
      final session = VerificationSession(
        client: clientOver(FakeTransport([created(verificationJson())]).call),
      );
      addTearDown(session.dispose);

      // A fresh stream per call would make StreamBuilder resubscribe on every
      // rebuild and flicker back to `waiting`.
      expect(identical(session.states, session.states), isTrue);
    });

    test(
        'a second listener subscribing WHILE THE FIRST STILL IS receives the '
        'current state', () async {
      final transport = FakeTransport([created(verificationJson())]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );

      final first = <VerificationState>[];
      final firstSub = session.states.listen(first.add);
      await pumpEventQueue();
      expect(first, hasLength(1));

      // The whole point: the first subscription is NOT cancelled here. Written
      // as listen/cancel/listen this passes against a broadcast controller,
      // whose onListen fires only on the 0->1 transition, and the bug ships.
      final second = <VerificationState>[];
      final secondSub = session.states.listen(second.add);
      await pumpEventQueue();

      expect(second, hasLength(1));
      expect(second.single, isA<VerificationAwaitingInput>());
      expect(first, hasLength(1), reason: 'the first listener saw no replay');

      await firstSub.cancel();
      await secondSub.cancel();
    });

    test('both concurrent listeners see every later transition', () async {
      final transport = FakeTransport([
        created(verificationJson()),
        ok(verificationJson(status: 'verified')),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      final a = StateRecorder(session);
      final b = StateRecorder(session);
      addTearDown(a.cancel);
      addTearDown(b.cancel);
      await pumpEventQueue();

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      session.submit('123456');
      await pumpEventQueue();

      expect(a.names, b.names);
      expect(a.names, [
        'VerificationIdle',
        'VerificationStarting',
        'VerificationAwaitingInput',
        'VerificationSubmitting',
        'VerificationVerified',
      ]);
    });

    test('a listener that cancels stops receiving, and the rest carry on',
        () async {
      final transport = FakeTransport([
        created(verificationJson()),
        ok(verificationJson(status: 'verified')),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      final a = StateRecorder(session);
      final b = StateRecorder(session);
      addTearDown(b.cancel);
      await pumpEventQueue();
      await a.cancel();

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      await pumpEventQueue();

      expect(a.names, ['VerificationIdle']);
      expect(b.names, hasLength(3));
    });
  });

  group('single flight', () {
    test(
        'a second start while one is running sends nothing and reports '
        'SdkAlreadyRunning', () async {
      final gate = Completer<void>();
      final transport = FakeTransport([created(verificationJson())]);
      var calls = 0;
      final session = VerificationSession(
        client: clientOver((request) async {
          calls++;
          await gate.future;
          return transport.call(request);
        }),
      );
      addTearDown(session.dispose);
      final recorder = StateRecorder(session);
      addTearDown(recorder.cancel);

      final first = session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      await session.start(
        destination: '+49 151 7654321',
        deliveryMethod: DeliveryMethod.sms,
      );

      gate.complete();
      await first;
      await pumpEventQueue();

      expect(calls, 1);
      expect(recorder.names, contains('VerificationFailed'));
      final rejected =
          recorder.states.whereType<VerificationFailed>().single.reason;
      expect(rejected, isA<SdkFailure>());
      expect((rejected as SdkFailure).error, isA<SdkAlreadyRunning>());
      expect(recorder.states.last, isA<VerificationAwaitingInput>());
    });

    test('a second submit while one is in flight is dropped', () async {
      final gate = Completer<void>();
      var reports = 0;
      final session = VerificationSession(
        client: clientOver((request) async {
          if (request.method != 'POST') {
            reports++;
            await gate.future;
            return ok(verificationJson(status: 'verified'));
          }
          return created(verificationJson());
        }),
      );
      addTearDown(session.dispose);

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );

      session.submit('111111');
      session.submit('222222');
      gate.complete();
      await pumpEventQueue();

      // A double tap must not burn two attempts.
      expect(reports, 1);
      expect(session.state, isA<VerificationVerified>());
    });

    test('a submit made before the verification is live is buffered', () async {
      final transport = FakeTransport([
        created(verificationJson()),
        ok(verificationJson(status: 'verified')),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      session.submit('123456');
      expect(session.state, isA<VerificationIdle>());

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      await pumpEventQueue();

      expect(transport.callCount, 2);
      expect(transport.bodyAt(1)['data'], {
        'delivery_method': 'sms',
        'code': '123456',
      });
      expect(session.state, isA<VerificationVerified>());
    });

    test('a submit after a terminal state is ignored', () async {
      final transport = FakeTransport([
        created(verificationJson(
            status: 'denied', errorCode: 'denied_by_callback')),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      expect(session.state, isA<VerificationDenied>());

      session.submit('123456');
      await pumpEventQueue();

      expect(transport.callCount, 1);
    });

    test('a buffered value is dropped when the start ends terminally',
        () async {
      final transport = FakeTransport([
        created(verificationJson(
            status: 'denied', errorCode: 'denied_by_callback')),
        created(verificationJson(id: 'ver-2')),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      session.submit('123456');
      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      await pumpEventQueue();

      // Carrying it into the next verification would spend an attempt on a code
      // the user typed for a different one.
      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      await pumpEventQueue();

      expect(transport.callCount, 2);
      expect(session.state, isA<VerificationAwaitingInput>());
    });
  });

  group('the generation counter', () {
    test('a response arriving after dispose emits nothing', () async {
      final gate = Completer<void>();
      final session = VerificationSession(
        client: clientOver(gated(gate, created(verificationJson()))),
      );
      final recorder = StateRecorder(session);

      final pending = session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      await session.dispose();

      gate.complete();
      await pending;
      await pumpEventQueue();

      expect(recorder.names, ['VerificationIdle', 'VerificationStarting']);
      expect(recorder.done, isTrue, reason: 'dispose closes states');
    });

    test('a response arriving after reset emits nothing', () async {
      final gate = Completer<void>();
      final session = VerificationSession(
        client: clientOver(gated(gate, created(verificationJson()))),
      );
      addTearDown(session.dispose);
      final recorder = StateRecorder(session);
      addTearDown(recorder.cancel);

      final pending = session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      await session.reset();

      gate.complete();
      await pending;
      await pumpEventQueue();

      expect(recorder.names, [
        'VerificationIdle',
        'VerificationStarting',
        'VerificationIdle',
      ]);
      expect(session.state, isA<VerificationIdle>());
    });

    test('a start after a reset that interrupted one still works', () async {
      final transport = FakeTransport([created(verificationJson())]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      final gate = Completer<void>();
      unawaited(session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      ));
      await session.reset();
      gate.complete();

      // The in-flight guard must not be left stuck on by the interruption.
      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );

      expect(session.state, isA<VerificationAwaitingInput>());
    });

    test('a superseded submission is reported as such', () async {
      final gate = Completer<void>();
      final session = VerificationSession(
        client: clientOver((request) async {
          if (request.method == 'POST') return created(verificationJson());
          await gate.future;
          return ok(verificationJson(status: 'verified'));
        }),
      );
      addTearDown(session.dispose);
      final recorder = StateRecorder(session);
      addTearDown(recorder.cancel);

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      session.submit('123456');
      await pumpEventQueue();

      await session.start(
        destination: '+49 151 7654321',
        deliveryMethod: DeliveryMethod.sms,
      );
      gate.complete();
      await pumpEventQueue();

      final superseded = recorder.states
          .whereType<VerificationFailed>()
          .map((s) => s.reason)
          .whereType<SdkFailure>()
          .map((r) => r.error)
          .whereType<SdkSuperseded>();
      expect(superseded, hasLength(1));
      expect(session.state, isA<VerificationAwaitingInput>());
    });
  });

  group('start never throws', () {
    test('a transport failure becomes a state, not an exception', () async {
      final session = VerificationSession(
        client: clientOver(
          (request) async => throw const TransportException('no route'),
        ),
      );
      addTearDown(session.dispose);

      await expectLater(
        session.start(
          destination: '+49 151 1234567',
          deliveryMethod: DeliveryMethod.sms,
        ),
        completes,
      );

      final failed = session.state as VerificationFailed;
      expect((failed.reason as SdkFailure).error, isA<SdkTransportError>());
    });

    test('a body that is not the documented shape becomes a state', () async {
      final session = VerificationSession(
        client: clientOver(
          (request) async => jsonResponse(200, '<html>nope</html>'),
        ),
      );
      addTearDown(session.dispose);

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );

      final failed = session.state as VerificationFailed;
      expect((failed.reason as SdkFailure).error, isA<SdkDecodingError>());
    });

    test('a destination with no digits becomes a state', () async {
      final transport = FakeTransport([created(verificationJson())]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await expectLater(
        session.start(
          destination: 'not a number',
          deliveryMethod: DeliveryMethod.sms,
        ),
        completes,
      );

      final failed = session.state as VerificationFailed;
      expect((failed.reason as SdkFailure).error, isA<SdkConfigurationError>());
      expect(transport.callCount, 0);
    });

    test('a rejected start becomes a terminal state carrying the code',
        () async {
      final session = VerificationSession(
        client: clientOver(
          (request) async =>
              jsonResponse(422, errorsJson(['destination_invalid'])),
        ),
      );
      addTearDown(session.dispose);

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );

      final failed = session.state as VerificationFailed;
      expect((failed.reason as ApiFailure).error.known,
          ApiErrorCode.destinationInvalid);
    });

    test(
        'a start rejected with a code that is recoverable ON A REPORT is '
        'still terminal', () async {
      final transport = FakeTransport([
        jsonResponse(422, errorsJson(['code_invalid'])),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );

      // Proves the start path routes through the start reducer, not the report
      // one: nothing is retryable before a verification exists, and landing on
      // awaiting input here would offer a text field for a verification that
      // was never created.
      expect(session.state, isA<VerificationFailed>());
      expect(session.state, isNot(isA<VerificationAwaitingInput>()));
    });

    test('an sms start with no SmsAutoCapture completes normally', () async {
      // Run under `dart test`, so asserts are on: a bare `assert(condition)`
      // guarding this path would fail this test rather than pass it.
      final transport = FakeTransport([created(verificationJson())]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      expect(session.hasAutoCapture, isFalse);
      await expectLater(
        session.start(
          destination: '+49 151 1234567',
          deliveryMethod: DeliveryMethod.sms,
        ),
        completes,
      );

      expect(session.state, isA<VerificationAwaitingInput>());
      expect(session.isAutoCaptureArmed, isFalse);
      // The diagnostic goes through dart:developer's log(), which has no
      // override hook, so its emission is deliberately not asserted here.
      expect(transport.bodyAt(0)['data'], isNot(contains('sms')));
    });

    test('callout options reach the wire and the chosen language reaches state',
        () async {
      final transport = FakeTransport([
        created(
          verificationJson(
            deliveryMethod: 'callout',
            sms: false,
            callout: true,
            language: 'en-US',
          ),
        ),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.callout,
        callout: const CalloutOptions(languages: ['ka-GE']),
      );

      final data = transport.bodyAt(0)['data'] as Map<String, dynamic>;
      expect((data['callout'] as Map<String, dynamic>)['languages'], ['ka-GE']);

      // The fallback is only visible here: a tag with no recording is accepted
      // rather than rejected, so nothing else in the response says it happened.
      final state = session.state as VerificationAwaitingInput;
      expect(state.callout?.language, 'en-US');
      expect(state.sms, isNull);
    });
  });

  group('reporting a value', () {
    test('a wrong code returns to awaiting input with lastError', () async {
      final transport = FakeTransport([
        created(verificationJson()),
        jsonResponse(422, errorsJson(['code_invalid'])),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      session.submit('000000');
      await pumpEventQueue();

      final live = session.state as VerificationAwaitingInput;
      expect(live.lastError?.known, ApiErrorCode.codeInvalid);
      expect(live.verificationId, 'ver-1');
    });

    test('a second attempt is allowed after a recoverable rejection', () async {
      final transport = FakeTransport([
        created(verificationJson()),
        jsonResponse(422, errorsJson(['code_invalid'])),
        ok(verificationJson(status: 'verified')),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
      session.submit('000000');
      await pumpEventQueue();
      session.submit('123456');
      await pumpEventQueue();

      expect(session.state, isA<VerificationVerified>());
      expect(transport.callCount, 3);
    });

    test('a callout verification reports a code, on its own channel', () async {
      final transport = FakeTransport([
        created(verificationJson(deliveryMethod: 'callout', sms: false)),
        ok(verificationJson(
            deliveryMethod: 'callout', sms: false, status: 'verified')),
      ]);
      final session = VerificationSession(client: clientOver(transport.call));
      addTearDown(session.dispose);

      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.callout,
      );
      session.submit('123456');
      await pumpEventQueue();

      expect(transport.bodyAt(1)['data'], {
        'delivery_method': 'callout',
        'code': '123456',
      });
    });
  });

  group('dispose', () {
    test('is safe to call twice and closes the stream', () async {
      final session = VerificationSession(
        client: clientOver(FakeTransport([created(verificationJson())]).call),
      );
      final recorder = StateRecorder(session);

      await session.dispose();
      await session.dispose();
      await pumpEventQueue();

      expect(recorder.done, isTrue);
    });

    test(
        'a listener attached after dispose still gets the last state, then '
        'done', () async {
      final session = VerificationSession(
        client: clientOver(FakeTransport([created(verificationJson())]).call),
      );
      await session.dispose();

      final recorder = StateRecorder(session);
      await pumpEventQueue();

      expect(recorder.names, ['VerificationIdle']);
      expect(recorder.done, isTrue);
    });

    test('submit and start after dispose do nothing', () async {
      final transport = FakeTransport([created(verificationJson())]);
      final session = VerificationSession(client: clientOver(transport.call));

      await session.dispose();
      session.submit('123456');
      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );

      expect(transport.callCount, 0);
    });
  });
}
