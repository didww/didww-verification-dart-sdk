/// Fixtures shared by the example's widget tests. Not a test file.
library;

import 'dart:convert';

import 'package:didww_verification/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

/// Counts what the plugin's channels were asked for.
///
/// The screens use the real `SmsRetrieverAutoCapture`, so without this the
/// event channel reports a missing plugin and every widget test fails for an
/// unrelated reason.
///
/// **Build it inside the test body, never in `setUp`.** A handler registered
/// from `setUp` delivers on the real event loop rather than the test's
/// fake-async one, so `pumpAndSettle` never observes it and [deliver] silently
/// does nothing.
final class FakePlugin {
  /// Installs handlers for both channels.
  FakePlugin({this.hash = 'FA+9qCX9VSu'}) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(_methods, (call) async => hash);
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          listens++;
          _sink = sink;
        },
        onCancel: (arguments) {
          cancels++;
          _sink = null;
        },
      ),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(_methods, null);
      messenger.setMockStreamHandler(_events, null);
    });
  }

  static const MethodChannel _methods = MethodChannel('didww_verification_sms');
  static const EventChannel _events =
      EventChannel('didww_verification_sms/messages');

  /// The app hash the platform reports.
  final String? hash;

  /// How many times the message stream was listened to.
  int listens = 0;

  /// How many times that subscription was cancelled.
  int cancels = 0;

  MockStreamHandlerEventSink? _sink;

  /// Hands [body] over as a message the platform captured.
  void deliver(String body) => _sink?.success(body);
}

/// A verification response body.
String verificationJson({
  String status = 'pending',
  String deliveryMethod = 'sms',
  String? appHash = 'FA+9qCX9VSu',
  String? errorCode,
}) =>
    jsonEncode({
      'data': {
        'id': 'ver-1',
        'destination': '491519000001',
        'delivery_method': deliveryMethod,
        'fee': '0.06',
        'status': status,
        'error_code': errorCode,
        'error_detail': errorCode == null ? null : 'detail for $errorCode',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        if (deliveryMethod == 'sms')
          'sms': {
            'template': 'Your code is {{CODE}}',
            'interception_timeout': 120,
            if (appHash != null) 'app_hash': appHash,
          },
      },
    });

/// An error envelope carrying one element per code.
String errorsJson(List<String> codes) => jsonEncode({
      'errors': [
        for (final code in codes) {'code': code, 'detail': 'detail for $code'},
      ],
    });

/// A JSON response.
HttpResponse json(int status, String body) => HttpResponse(
      status: status,
      headers: const {'content-type': 'application/json'},
      body: body,
    );
