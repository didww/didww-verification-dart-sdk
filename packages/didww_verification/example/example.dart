// A full verification, start to outcome.
//
// Runs against a scripted transport by default, so `dart run example/example.dart`
// works with no server and no credentials. Set DIDWW_VERIFICATION_KEY to run the
// same code against the real API, and DIDWW_VERIFICATION_BASE_URL to point it at
// the sandbox or at tool/mock_api.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification/testing.dart';

void main() async {
  final key = Platform.environment['DIDWW_VERIFICATION_KEY'];
  final baseUrl = Platform.environment['DIDWW_VERIFICATION_BASE_URL'];

  final client = VerificationClient(
    auth: PublicAuthorization(key ?? 'demo-application-key'),
    environment: baseUrl == null
        ? null
        : VerificationEnvironment.custom(Uri.parse(baseUrl)),
    config: const ClientConfig(userAgent: 'didww_verification-example/1.0.0'),
    transport: key == null ? _scripted.call : null,
  );

  try {
    await _run(client, destination: '+49 151 1234567', code: '123456');
  } finally {
    client.close();
  }
}

Future<void> _run(
  VerificationClient client, {
  required String destination,
  required String code,
}) async {
  final Verification started;
  try {
    started = await client.startVerification(
      destination: destination,
      deliveryMethod: DeliveryMethod.sms,
      sms: const SmsOptions(languages: ['en-US']),
    );
  } on ApiException catch (e) {
    print('could not start: ${e.first?.code ?? e.status}');
    return;
  } on TransportException catch (e) {
    print('could not reach the API: ${e.message}');
    return;
  }

  // The API echoes the destination digits-only, so keep the formatted copy for
  // display and compare with digitsOf.
  print('started ${started.id} for ${started.destination}');
  print('fee ${started.fee} (a decimal string; never parse it as a double)');
  print('template ${started.sms?.template}');

  if (started.isFinished) {
    print('finished on create: ${started.status} / ${started.errorCode}');
    return;
  }

  final Verification reported;
  try {
    reported = await client.reportVerification(
      started.id,
      deliveryMethod: started.deliveryMethod,
      value: ReportValue.code(code),
    );
  } on ApiException catch (e) {
    switch (e.first?.known) {
      case ApiErrorCode.codeInvalid:
        print('wrong code; the verification is still open');
      case ApiErrorCode.tooManyAttempts:
        print('no attempts left');
      case null:
        print('unrecognised failure: ${e.first?.code ?? e.status}');
      default:
        print('rejected: ${e.first!.code}');
    }
    return;
  }

  print('outcome ${reported.status} ${reported.errorCode ?? ''}');
}

FakeTransport get _scripted => FakeTransport([
      _response(201, {
        'data': {
          'id': '0f9c8b7a-1111-7222-8333-444455556666',
          'destination': '491511234567',
          'delivery_method': 'sms',
          'fee': '0.0345',
          'status': 'pending',
          'error_code': null,
          'error_detail': null,
          'expires_at': '2026-08-25T12:00:00Z',
          'sms': {
            'template': 'Your code is {{CODE}}',
            'interception_timeout': 120
          },
        },
      }),
      _response(200, {
        'data': {
          'id': '0f9c8b7a-1111-7222-8333-444455556666',
          'destination': '491511234567',
          'delivery_method': 'sms',
          'fee': '0.0345',
          'status': 'verified',
          'error_code': null,
          'error_detail': null,
          'expires_at': '2026-08-25T12:00:00Z',
          'sms': {
            'template': 'Your code is {{CODE}}',
            'interception_timeout': 120
          },
        },
      }),
    ]);

HttpResponse _response(int status, Map<String, dynamic> body) => HttpResponse(
      status: status,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(body),
    );
