import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification_sms_example/verify_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Names every state, with no default arm.
///
/// The switch is what makes this suite complete: a state added in a later
/// release stops compiling here, which is the only mechanism that can notice a
/// screen quietly rendering nothing for it.
String label(VerificationState state) => switch (state) {
      VerificationIdle() => 'idle',
      VerificationStarting() => 'starting',
      VerificationAwaitingInput() => 'awaiting',
      VerificationCaptured() => 'captured',
      VerificationSubmitting() => 'submitting',
      VerificationVerified() => 'verified',
      VerificationFailed() => 'failed',
      VerificationDenied() => 'denied',
      VerificationExpired() => 'expired',
      VerificationSetupError() => 'setup',
    };

VerificationAwaitingInput awaiting({
  String deliveryMethod = 'sms',
  ApiErrorItem? lastError,
}) =>
    VerificationAwaitingInput(
      verificationId: 'ver-1',
      deliveryMethod: deliveryMethod,
      destination: '491519000001',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      lastError: lastError,
    );

void main() {
  final states = <VerificationState>[
    const VerificationIdle(),
    const VerificationStarting(),
    awaiting(),
    const VerificationCaptured('123456'),
    const VerificationSubmitting(),
    const VerificationVerified('ver-1'),
    const VerificationFailed(SdkFailure(SdkSuperseded())),
    const VerificationDenied(null),
    const VerificationExpired(),
    const VerificationSetupError(code: 'denied_missing_callback_url'),
  ];

  Future<void> render(WidgetTester tester, VerificationState state) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VerificationView(
              state: state,
              onSubmit: (_) {},
              onRestart: () {},
            ),
          ),
        ),
      );

  test('every state in the sealed tree is rendered by this suite', () {
    // `label` cannot compile with a state missing, and this asserts the fixture
    // list keeps up with it. Without this the switch could stay exhaustive while
    // the list quietly covered nine of ten.
    expect(states.map(label).toSet().length, states.length);
  });

  for (final state in states) {
    testWidgets('${label(state)} renders without overflowing', (tester) async {
      await render(tester, state);

      expect(tester.takeException(), isNull);
      expect(find.byType(VerificationView), findsOneWidget);
    });
  }

  testWidgets('awaiting input offers a field and a submit button',
      (tester) async {
    await render(tester, awaiting());

    expect(find.text('Enter the code'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Submit'), findsOneWidget);
  });

  testWidgets('a channel this release does not model still asks for a code',
      (tester) async {
    await render(tester, awaiting(deliveryMethod: 'carrier_pigeon'));

    expect(find.text('Enter the code'), findsOneWidget);
  });

  testWidgets('a recoverable rejection is shown against the field',
      (tester) async {
    await render(
      tester,
      awaiting(
        lastError: const ApiErrorItem(
          code: 'code_invalid',
          detail: 'code is invalid',
        ),
      ),
    );

    expect(find.text('code is invalid'), findsOneWidget);
  });

  testWidgets('a captured code fills the field and locks it', (tester) async {
    await render(tester, const VerificationCaptured('123456'));

    expect(find.text('123456'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  });

  testWidgets('a misconfigured application offers no retry', (tester) async {
    await render(
      tester,
      const VerificationSetupError(code: 'denied_missing_callback_url'),
    );

    // Nothing the user does here can fix it, so offering a button that bills
    // another attempt would be wrong.
    expect(find.text('Start again'), findsNothing);
  });

  testWidgets('every other outcome offers a retry', (tester) async {
    for (final state in [
      const VerificationVerified('ver-1'),
      const VerificationExpired(),
      const VerificationDenied(null),
      const VerificationFailed(SdkFailure(SdkSuperseded())),
    ]) {
      await render(tester, state);
      expect(find.text('Start again'), findsOneWidget, reason: label(state));
    }
  });

  test('every failure reason is given words', () {
    // Exhaustive over both sealed trees, so a reason added later cannot fall
    // through to a type name on screen.
    const reasons = <FailureReason>[
      ApiFailure(ApiErrorItem(code: 'internal_error')),
      SdkFailure(SdkAlreadyRunning()),
      SdkFailure(SdkSuperseded()),
      SdkFailure(SdkTransportError('refused')),
      SdkFailure(SdkConfigurationError('no digits')),
      SdkFailure(SdkDecodingError('bad json')),
    ];

    for (final reason in reasons) {
      expect(describeFailure(reason), isNotEmpty);
    }
  });
}
