import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification_sms_example/main.dart' show ExampleApp;
import 'package:didww_verification_sms_example/start_screen.dart'
    show defaultOrigin;
import 'package:didww_verification_sms_example/verify_screen.dart'
    show VerificationView;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The whole flow against `tool/mock_api`, driven from the runtime.
///
/// `session_integration_test.dart` covers the same ground on the Dart VM; what
/// only this file reaches is the device's own HTTP stack, transport security
/// policy and event loop. The origin follows [defaultOrigin] — `localhost` from
/// the iOS simulator, `10.0.2.2` from the Android emulator.
///
/// Start the mock from the repository root:
///
///     dart run tool/mock_api/bin/mock_api.dart --host 0.0.0.0
///
/// `--host 0.0.0.0` is required for the Android emulator, which reaches the
/// host at `10.0.2.2` rather than at loopback.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  VerificationSession sessionFor(String key) {
    final client = VerificationClient(
      auth: PublicAuthorization(key),
      environment: VerificationEnvironment.custom(Uri.parse(defaultOrigin)),
      config: const ClientConfig(retry: RetryPolicy.none()),
    );
    addTearDown(client.close);

    final session = VerificationSession(client: client);
    addTearDown(session.dispose);
    return session;
  }

  Future<void> submitAndSettle(VerificationSession session, String value) {
    session.submit(value);
    // Subscribed after the submit: the current state is replayed to every new
    // listener, so subscribing first matches the state being left.
    return session.states
        .firstWhere((state) => state is! VerificationSubmitting)
        .timeout(const Duration(seconds: 30));
  }

  /// Pumps real frames until [finder] matches.
  ///
  /// `pumpAndSettle` is unusable here: every busy state renders a
  /// CircularProgressIndicator, whose animation never ends, so settling can only
  /// ever time out.
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('timed out waiting for $finder');
  }

  Finder field(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(TextField),
      );

  // Scoped to the verify screen: the route below it keeps its own three fields
  // in the tree until the push transition ends, and an unscoped finder matches
  // all four.
  Finder entry() => find.descendant(
        of: find.byType(VerificationView),
        matching: find.byType(TextField),
      );

  Finder rejected() => find.descendant(
        of: find.byType(VerificationView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.errorText != null,
        ),
      );

  setUpAll(() async {
    // One legible failure when the mock is not running, instead of every test
    // failing on a state nobody expected.
    final client = VerificationClient(
      auth: PublicAuthorization('demo-key'),
      environment: VerificationEnvironment.custom(Uri.parse(defaultOrigin)),
      config: const ClientConfig(retry: RetryPolicy.none()),
    );
    final probe = VerificationSession(client: client);
    await probe.resumeByNumber('+49 151 9199999');
    final state = probe.state;
    await probe.dispose();
    client.close();

    final reason = state is VerificationFailed ? state.reason : null;
    if (reason is SdkFailure && reason.error is SdkTransportError) {
      fail('the mock API is not reachable at $defaultOrigin: '
          '${(reason.error as SdkTransportError).message}\n'
          'start it from the repository root with:\n'
          '  dart run tool/mock_api/bin/mock_api.dart --port 8787');
    }
  });

  testWidgets('the app takes a wrong code, then the right one', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    await tester.enterText(field('Destination'), '+49 151 9100001');
    await tester.tap(find.widgetWithText(FilledButton, 'Start verification'));
    await pumpUntil(tester, find.text('Enter the code'));

    // Capture arms only where there is a plugin to arm. Off Android the whole
    // flow still has to work, by hand.
    expect(
      find.text('Listening for the message'),
      defaultTargetPlatform == TargetPlatform.android
          ? findsOneWidget
          : findsNothing,
    );

    await tester.enterText(entry(), '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await pumpUntil(tester, rejected());

    await tester.enterText(entry(), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await pumpUntil(tester, find.text('Verified'));
  });

  const channels = [
    (
      method: DeliveryMethod.sms,
      destination: '+49 151 9100002',
      wrong: '000000',
      right: '123456',
      rejection: ApiErrorCode.codeInvalid,
    ),
    (
      method: DeliveryMethod.callout,
      destination: '+49 151 9100004',
      wrong: '000000',
      right: '123456',
      rejection: ApiErrorCode.codeInvalid,
    ),
  ];

  for (final channel in channels) {
    testWidgets('${channel.method.wire} rejects then verifies', (tester) async {
      final session = sessionFor('demo-key');

      await session.start(
        destination: channel.destination,
        deliveryMethod: channel.method,
      );
      expect(session.state, isA<VerificationAwaitingInput>());

      await submitAndSettle(session, channel.wrong);
      final live = session.state as VerificationAwaitingInput;
      expect(live.lastError?.known, channel.rejection);

      await submitAndSettle(session, channel.right);
      expect(session.state, isA<VerificationVerified>());
    });
  }

  testWidgets('a session with no capture sends no app hash', (tester) async {
    final session = sessionFor('demo-key');

    await session.start(
      destination: '+49 151 9100006',
      deliveryMethod: DeliveryMethod.sms,
    );

    // The mock echoes app_hash only when it receives one, so a null echo is a
    // fact about the wire and not just about this object.
    expect(session.hasAutoCapture, isFalse);
    expect(session.isAutoCaptureArmed, isFalse);
    final live = session.state as VerificationAwaitingInput;
    expect(live.sms?.template, isNotNull);
    expect(live.sms?.appHash, isNull);

    await submitAndSettle(session, '123456');
    expect(session.state, isA<VerificationVerified>());
  });

  testWidgets('an application with no callback URL reaches a setup error',
      (tester) async {
    final session = sessionFor('no-callback-key');

    await session.start(
      destination: '+49 151 9100005',
      deliveryMethod: DeliveryMethod.sms,
    );

    final setup = session.state as VerificationSetupError;
    expect(setup.code, 'denied_missing_callback_url');
  });
}
