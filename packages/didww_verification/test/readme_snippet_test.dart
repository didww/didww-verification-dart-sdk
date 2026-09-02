import 'package:didww_verification/didww_verification.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The README's state switch, with the widgets reduced to strings.
///
/// Here so the documented switch is compiled rather than eyeballed: it claims
/// no `default` arm is needed, and that claim is only true while every state is
/// listed.
String render(VerificationState state) => switch (state) {
      VerificationIdle() || VerificationStarting() => 'spinner',
      VerificationAwaitingInput(:final lastError) => 'field:${lastError?.code}',
      VerificationCaptured(:final value) => 'field:$value:disabled',
      VerificationSubmitting() => 'spinner',
      VerificationVerified() => 'Verified',
      VerificationExpired() => 'That code expired',
      VerificationDenied(:final error) => error?.detail ?? 'Refused',
      VerificationSetupError(:final code) => 'Application misconfigured: $code',
      VerificationFailed(:final reason) => '$reason',
    };

void main() {
  test('the documented switch covers every state', () {
    expect(render(const VerificationIdle()), 'spinner');
    expect(
        render(const VerificationCaptured('123456')), 'field:123456:disabled');
    expect(
      render(const VerificationSetupError(code: 'denied_missing_callback_url')),
      'Application misconfigured: denied_missing_callback_url',
    );
  });

  test('the documented re-entry recipe is the one the tests exercise',
      () async {
    final session = VerificationSession(
      client: clientOver((request) async => ok(verificationJson())),
    );
    addTearDown(session.dispose);

    await session.resumeByNumber('+49 151 1234567');
    if (session.state is! VerificationAwaitingInput) {
      await session.start(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );
    }

    expect(render(session.state), 'field:null');
  });
}
