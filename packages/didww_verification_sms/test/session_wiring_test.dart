import 'dart:convert';

import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification/testing.dart';
import 'package:didww_verification_sms/didww_verification_sms.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real capture, plugged into a real session, over the channel surface.
///
/// Everything below the channels is the emulator's job. What this covers is the
/// join: that the session sends the hash the plugin computed, arms only on an
/// echo of it, and submits a code recovered from a message the platform handed
/// over.
const String hash = 'FA+9qCX9VSu';

String verificationJson({String? appHash, String status = 'pending'}) =>
    jsonEncode({
      'data': {
        'id': 'ver-1',
        'destination': '491511234567',
        'delivery_method': 'sms',
        'fee': '0.06',
        'status': status,
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'sms': {
          'template': 'Your code is {{CODE}}',
          'interception_timeout': 120,
          if (appHash != null) 'app_hash': appHash,
        },
      },
    });

HttpResponse json(int status, String body) => HttpResponse(
      status: status,
      headers: const {'content-type': 'application/json'},
      body: body,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel('didww_verification_sms');
  const events = EventChannel('didww_verification_sms/messages');

  late void Function(String body) deliver;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(methods, (call) async => hash);
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) => deliver = (body) => sink.success(body),
      ),
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  });

  VerificationSession sessionOver(FakeTransport transport) {
    final session = VerificationSession(
      client: VerificationClient(
        auth: const PublicAuthorization('key'),
        transport: transport.call,
        config: const ClientConfig(retry: RetryPolicy.none()),
      ),
      autoCapture: const SmsRetrieverAutoCapture(),
    );
    addTearDown(session.dispose);
    return session;
  }

  test('the hash the plugin computed is what the start request carries',
      () async {
    final transport =
        FakeTransport([json(201, verificationJson(appHash: hash))]);
    final session = sessionOver(transport);

    await session.start(
      destination: '+49 151 1234567',
      deliveryMethod: DeliveryMethod.sms,
    );

    final data = transport.bodyAt(0)['data'] as Map<String, dynamic>;
    expect(data['sms'], {'app_hash': hash});
    expect(session.isAutoCaptureArmed, isTrue);
  });

  test('a message the platform hands over is submitted without typing',
      () async {
    final transport = FakeTransport([
      json(201, verificationJson(appHash: hash)),
      json(200, verificationJson(status: 'verified')),
    ]);
    final session = sessionOver(transport);

    await session.start(
      destination: '+49 151 1234567',
      deliveryMethod: DeliveryMethod.sms,
    );
    deliver('Your code is 123456\n$hash');
    await pumpEventQueue();

    expect(transport.bodyAt(1)['data'], {
      'delivery_method': 'sms',
      'code': '123456',
    });
    expect(session.state, isA<VerificationVerified>());
  });

  test('an echo of a different hash never touches the platform listener',
      () async {
    // The Play App Signing case: the API holds the hash of the upload key and
    // the device computed the one from the installed build.
    final transport =
        FakeTransport([json(201, verificationJson(appHash: 'ZZZZZZZZZZZ'))]);
    final session = sessionOver(transport);

    await session.start(
      destination: '+49 151 1234567',
      deliveryMethod: DeliveryMethod.sms,
    );

    expect(session.hasAutoCapture, isTrue);
    expect(session.isAutoCaptureArmed, isFalse);
  });
}
