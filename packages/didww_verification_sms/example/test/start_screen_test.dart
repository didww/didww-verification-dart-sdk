import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification_sms_example/app_hash_screen.dart';
import 'package:didww_verification_sms_example/main.dart';
import 'package:didww_verification_sms_example/start_screen.dart';
import 'package:didww_verification_sms_example/verify_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(TextField),
      );

  testWidgets('the origin defaults to the address this runtime can reach',
      (tester) async {
    // The emulator does not route localhost to the development machine, so a
    // mock reached at localhost from the simulator is reached at 10.0.2.2 here.
    expect(defaultTargetPlatform, TargetPlatform.android);
    expect(defaultOrigin, 'http://10.0.2.2:8787');

    await open(tester);
    expect(find.text('http://10.0.2.2:8787'), findsOneWidget);
  });

  testWidgets('an empty destination is refused before anything is billed',
      (tester) async {
    await open(tester);

    await tester.enterText(field('Destination'), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Start verification'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a number'), findsOneWidget);
    expect(find.byType(VerifyScreen), findsNothing);
  });

  testWidgets('an origin that is not a URL is refused', (tester) async {
    await open(tester);

    await tester.enterText(field('API origin'), 'not a url');
    await tester.tap(find.widgetWithText(FilledButton, 'Start verification'));
    await tester.pumpAndSettle();

    expect(find.text('Not a URL'), findsOneWidget);
    expect(find.byType(VerifyScreen), findsNothing);
  });

  testWidgets('picking a channel changes what is selected', (tester) async {
    await open(tester);

    await tester.tap(find.text('Callout'));
    await tester.pumpAndSettle();

    final picker = tester.widget<SegmentedButton<DeliveryMethod>>(
      find.byType(SegmentedButton<DeliveryMethod>),
    );
    expect(picker.selected.single, DeliveryMethod.callout);
  });

  testWidgets('starting hands the verification to the verify screen',
      (tester) async {
    FakePlugin();
    await open(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Start verification'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyScreen), findsOneWidget);
    // flutter_test answers every request with 400, so the session lands on a
    // failure rather than hanging. That start() reports it instead of throwing
    // is the point.
    expect(find.text('Failed'), findsOneWidget);

    // The route owns the client, so tearing it down is what closes the socket.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('the app hash is one tap away, for the value to register',
      (tester) async {
    FakePlugin();
    await open(tester);

    await tester.tap(find.byTooltip('App hash'));
    await tester.pumpAndSettle();

    expect(find.byType(AppHashScreen), findsOneWidget);
    expect(find.text('FA+9qCX9VSu'), findsOneWidget);
  });
}
