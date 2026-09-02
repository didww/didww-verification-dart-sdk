import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification/src/machine.dart';
import 'package:didww_verification/src/wire.dart';
import 'package:test/test.dart';

import 'support.dart';

Verification _decoded({
  String status = 'pending',
  String? errorCode,
  String? errorDetail,
  String id = 'ver-1',
  String deliveryMethod = 'sms',
  bool sms = true,
  bool callout = false,
}) =>
    decodeVerification(verificationJson(
      id: id,
      status: status,
      errorCode: errorCode,
      errorDetail: errorDetail,
      deliveryMethod: deliveryMethod,
      sms: sms,
      callout: callout,
    ));

VerificationAwaitingInput get _live => awaitingInputFor(_decoded());

List<ApiErrorItem> _items(List<String> codes) =>
    [for (final code in codes) ApiErrorItem.fromWire(code, detail: '$code!')];

/// Exhaustive with no `default` arm: adding a state without handling it here
/// fails to compile, which is the whole proof.
String label(VerificationState state) => switch (state) {
      VerificationIdle() => 'idle',
      VerificationStarting() => 'starting',
      VerificationAwaitingInput() => 'awaiting_input',
      VerificationCaptured() => 'captured',
      VerificationSubmitting() => 'submitting',
      VerificationVerified() => 'verified',
      VerificationFailed() => 'failed',
      VerificationDenied() => 'denied',
      VerificationExpired() => 'expired',
      VerificationSetupError() => 'setup_error',
    };

String reasonLabel(FailureReason reason) => switch (reason) {
      ApiFailure(:final error) => 'api:${error.code}',
      SdkFailure(:final error) => 'sdk:${sdkLabel(error)}',
    };

String sdkLabel(SdkError error) => switch (error) {
      SdkAlreadyRunning() => 'already_running',
      SdkSuperseded() => 'superseded',
      SdkTransportError() => 'transport',
      SdkConfigurationError() => 'configuration',
      SdkDecodingError() => 'decoding',
      SdkUnexpectedError() => 'unexpected',
    };

void main() {
  group('the state tree is exhaustively switchable', () {
    test('every state has a label and no default arm was needed', () {
      final all = <VerificationState>[
        const VerificationIdle(),
        const VerificationStarting(),
        _live,
        const VerificationCaptured('123456'),
        const VerificationSubmitting(),
        const VerificationVerified('ver-1'),
        const VerificationFailed(SdkFailure(SdkAlreadyRunning())),
        const VerificationDenied(null),
        const VerificationExpired(),
        const VerificationSetupError(code: 'denied_missing_callback_url'),
      ];

      expect(all.map(label).toSet(), hasLength(all.length));
    });

    test('every failure reason and sdk error has a label', () {
      expect(
        reasonLabel(ApiFailure(ApiErrorItem.fromWire('code_invalid'))),
        'api:code_invalid',
      );
      final errors = <SdkError>[
        const SdkAlreadyRunning(),
        const SdkSuperseded(),
        const SdkTransportError('x'),
        const SdkConfigurationError('x'),
        const SdkDecodingError('x'),
      ];
      expect(errors.map(sdkLabel).toSet(), hasLength(errors.length));
    });
  });

  group('recoverable — back to awaiting input, verification still alive', () {
    const recoverable = [
      'code_invalid',
      'code_blank',
      'code_value_present',
      'delivery_method_invalid',
      'validation_failed',
      'not_ready_to_report',
    ];

    for (final code in recoverable) {
      test('$code returns to awaiting input carrying lastError', () {
        final next = stateAfterReportFailure(
          live: _live,
          errors: _items([code]),
        );

        expect(next, isA<VerificationAwaitingInput>());
        expect((next as VerificationAwaitingInput).lastError?.code, code);
        expect(next.verificationId, 'ver-1');
      });
    }

    test('the set is exactly six and matches the modelled codes', () {
      expect(recoverable, hasLength(6));
      expect(
        recoverableErrorCodes.map((c) => c.wire).toSet(),
        recoverable.toSet(),
      );
    });

    test('a recoverable envelope with a terminal element is terminal', () {
      final next = stateAfterReportFailure(
        live: _live,
        errors: _items(['code_invalid', 'too_many_attempts']),
      );

      expect(next, isA<VerificationFailed>());
    });

    test('a two-element recoverable envelope reports the first', () {
      final next = stateAfterReportFailure(
        live: _live,
        errors: _items(['code_blank', 'delivery_method_invalid']),
      );

      expect(
        (next as VerificationAwaitingInput).lastError?.code,
        'code_blank',
      );
    });

    test('an unmodelled code is not recoverable', () {
      final next = stateAfterReportFailure(
        live: _live,
        errors: _items(['some_code_from_a_later_release']),
      );

      expect(next, isA<VerificationFailed>());
    });

    test('an empty envelope is terminal', () {
      expect(
        stateAfterReportFailure(live: _live, errors: const []),
        isA<VerificationFailed>(),
      );
    });
  });

  group('terminal, from an error item', () {
    test('denied_missing_callback_url is a setup error', () {
      final next = terminalStateForError(
        ApiErrorItem.fromWire('denied_missing_callback_url', detail: 'no url'),
      );

      expect(next, isA<VerificationSetupError>());
      expect(
          (next as VerificationSetupError).code, 'denied_missing_callback_url');
      expect(next.detail, 'no url');
    });

    for (final code in const [
      'denied_by_callback',
      'denied_invalid_callback_response',
    ]) {
      test('$code is denied', () {
        final next = terminalStateForError(ApiErrorItem.fromWire(code));

        expect(next, isA<VerificationDenied>());
        expect((next as VerificationDenied).error?.code, code);
      });
    }

    test('expired is expired', () {
      expect(
        terminalStateForError(ApiErrorItem.fromWire('expired')),
        isA<VerificationExpired>(),
      );
    });

    test('everything else is a failure carrying the item', () {
      final next =
          terminalStateForError(ApiErrorItem.fromWire('balance_insufficient'));

      expect(next, isA<VerificationFailed>());
      expect(
        reasonLabel((next as VerificationFailed).reason),
        'api:balance_insufficient',
      );
    });
  });

  group('terminal, from a decoded status', () {
    test('verified carries the id', () {
      final next = terminalStateFor(_decoded(status: 'verified', id: 'ver-9'));

      expect((next! as VerificationVerified).verificationId, 'ver-9');
    });

    test('expired is expired', () {
      expect(
        terminalStateFor(_decoded(status: 'expired', errorCode: 'expired')),
        isA<VerificationExpired>(),
      );
    });

    test('failed carries its outcome', () {
      final next = terminalStateFor(
        _decoded(status: 'failed', errorCode: 'superseded'),
      );

      expect(
          reasonLabel((next! as VerificationFailed).reason), 'api:superseded');
    });

    test('failed with no outcome falls back to internal_error', () {
      final next = terminalStateFor(_decoded(status: 'failed'));

      expect(reasonLabel((next! as VerificationFailed).reason),
          'api:internal_error');
    });

    test('denied delegates to the error item', () {
      final next = terminalStateFor(
        _decoded(status: 'denied', errorCode: 'denied_missing_callback_url'),
      );

      expect(next, isA<VerificationSetupError>());
    });

    test('denied with no error item is a bare denial', () {
      final next = terminalStateFor(_decoded(status: 'denied'));

      expect(next, isA<VerificationDenied>());
      expect((next! as VerificationDenied).error, isNull);
    });

    test('pending is not a transition', () {
      expect(terminalStateFor(_decoded()), isNull);
    });

    test('an unrecognised status is not a transition either', () {
      expect(terminalStateFor(_decoded(status: 'quarantined')), isNull);
    });

    test('a status the SDK does not model still lands on awaiting input', () {
      // The rule that matters: a sixth status must neither strand a caller by
      // leaving them mid-submission nor mislead one by reporting an outcome.
      final next = stateFor(_decoded(status: 'quarantined'));

      expect(next, isA<VerificationAwaitingInput>());
    });
  });

  group('the two entries that look like mistakes', () {
    test('too_many_attempts is terminal, with no local attempt counter', () {
      final next = stateAfterReportFailure(
        live: _live,
        errors: _items(['too_many_attempts']),
      );

      expect(next, isA<VerificationFailed>());
      expect(reasonLabel((next as VerificationFailed).reason),
          'api:too_many_attempts');
    });

    test('already_verified is terminal as a FAILURE, never as verified', () {
      final next = stateAfterReportFailure(
        live: _live,
        errors: _items(['already_verified']),
      );

      expect(next, isNot(isA<VerificationVerified>()));
      expect(next, isA<VerificationFailed>());
      expect(reasonLabel((next as VerificationFailed).reason),
          'api:already_verified');
    });
  });

  group('every error during a start is terminal', () {
    // The recoverable set presupposes a verification that exists. Asserted as
    // the exact mapping rather than as "not awaiting input": a weaker check
    // stays green against a reducer that returns some other non-live state.
    const expected = {
      'code_invalid': 'api:code_invalid',
      'validation_failed': 'api:validation_failed',
      'not_ready_to_report': 'api:not_ready_to_report',
      'destination_invalid': 'api:destination_invalid',
      'unauthorized': 'api:unauthorized',
    };

    expected.forEach((code, reason) {
      test('$code ends the attempt as a failure', () {
        final next = stateAfterStartFailure(_items([code]));

        expect(next, isA<VerificationFailed>());
        expect(reasonLabel((next as VerificationFailed).reason), reason);
      });
    });

    test('a recoverable code during a start is still terminal', () {
      // The same code that returns to awaiting input on a report.
      final onReport =
          stateAfterReportFailure(live: _live, errors: _items(['code_blank']));
      final onStart = stateAfterStartFailure(_items(['code_blank']));

      expect(onReport, isA<VerificationAwaitingInput>());
      expect(onStart, isA<VerificationFailed>());
    });

    test('an empty envelope ends the attempt too', () {
      expect(
        stateAfterStartFailure(const []),
        isA<VerificationFailed>(),
      );
    });
  });

  group('a live verification carries what a screen needs', () {
    test('every field survives the mapping', () {
      final live = awaitingInputFor(_decoded());

      expect(live.verificationId, 'ver-1');
      expect(live.destination, '491511234567');
      expect(live.deliveryMethod, 'sms');
      expect(live.fee, '0.06');
      expect(live.sms?.template, 'Your code is {{CODE}}');
      expect(live.sms?.language, 'en-US');
      expect(live.sms?.interceptionTimeoutSeconds, 120);
      expect(live.callout, isNull);
      expect(live.expiresAt.isUtc, isTrue);
      expect(live.lastError, isNull);
    });

    test('the callout block reaches the state on its own channel', () {
      final live = awaitingInputFor(
        _decoded(deliveryMethod: 'callout', sms: false, callout: true),
      );

      expect(live.callout?.language, 'en-US');
      expect(live.sms, isNull);
    });

    test('withError keeps everything else', () {
      final live = awaitingInputFor(_decoded())
          .withError(_items(['code_invalid']).first);

      expect(live.lastError?.known, ApiErrorCode.codeInvalid);
      expect(live.fee, '0.06');
      expect(live.sms?.template, isNotNull);
    });
  });
}
