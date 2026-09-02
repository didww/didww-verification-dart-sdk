import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification/testing.dart';
import 'package:didww_verification_sms_example/verify_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  VerificationClient clientOver(FakeTransport transport) => VerificationClient(
        auth: const PublicAuthorization('demo-key'),
        environment:
            VerificationEnvironment.custom(Uri.parse('https://api.test')),
        transport: transport.call,
        config: const ClientConfig(retry: RetryPolicy.none()),
      );

  Future<void> open(
    WidgetTester tester,
    FakeTransport transport, {
    bool resume = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VerifyScreen(
          client: clientOver(transport),
          destination: '+49 151 9000001',
          deliveryMethod: DeliveryMethod.sms,
          resume: resume,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a wrong code then the right one, through the real session',
      (tester) async {
    FakePlugin(); // Mocks the channels the real capture would reach for.
    final transport = FakeTransport([
      json(201, verificationJson()),
      json(422, errorsJson(['code_invalid'])),
      json(200, verificationJson(status: 'verified')),
    ]);

    await open(tester, transport);
    expect(find.text('Enter the code'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    // Recoverable: back on the same screen with the reason against the field.
    expect(find.text('detail for code_invalid'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Verified'), findsOneWidget);
    expect(transport.callCount, 3);
  });

  testWidgets('a captured message is submitted without the user typing',
      (tester) async {
    final plugin = FakePlugin();
    final transport = FakeTransport([
      json(201, verificationJson()),
      json(200, verificationJson(status: 'verified')),
    ]);

    await open(tester, transport);
    expect(plugin.listens, 1,
        reason: 'the API echoed the hash the device sent');

    plugin.deliver('Your code is 123456\nFA+9qCX9VSu');
    await tester.pumpAndSettle();

    expect(transport.bodyAt(1)['data'], {
      'delivery_method': 'sms',
      'code': '123456',
    });
    expect(find.text('Verified'), findsOneWidget);
  });

  testWidgets('leaving the route cancels the platform subscription',
      (tester) async {
    final plugin = FakePlugin();
    final transport = FakeTransport([json(201, verificationJson())]);

    await open(tester, transport);
    expect(plugin.listens, 1);
    expect(plugin.cancels, 0);

    // Disposing the tree is what a Navigator.pop does to this route.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(plugin.cancels, plugin.listens);
  });

  testWidgets('resuming reads by number and bills nothing', (tester) async {
    FakePlugin(); // Mocks the channels the real capture would reach for.
    final transport = FakeTransport([json(200, verificationJson())]);

    await open(tester, transport, resume: true);

    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.path, contains('by_number'));
    expect(find.text('Enter the code'), findsOneWidget);
  });

  testWidgets('a terminal failure is shown with the reason the API gave',
      (tester) async {
    FakePlugin(); // Mocks the channels the real capture would reach for.
    final transport = FakeTransport([
      json(422, errorsJson(['unauthorized'])),
    ]);

    await open(tester, transport);

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('detail for unauthorized'), findsOneWidget);
  });

  testWidgets('a misconfigured application reaches the setup screen',
      (tester) async {
    FakePlugin(); // Mocks the channels the real capture would reach for.
    final transport = FakeTransport([
      json(422, errorsJson(['denied_missing_callback_url'])),
    ]);

    await open(tester, transport);

    expect(find.text('Application misconfigured'), findsOneWidget);
    expect(find.text('Start again'), findsNothing);
  });
}
