/// Fixtures shared by the session suites. Not a test file — `dart test` only
/// collects `*_test.dart`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:didww_verification/didww_verification.dart';
// Re-exported so the suites keep one import, and so they exercise the fake the
// package actually ships rather than a private copy that can drift from it.
export 'package:didww_verification/testing.dart' show FakeAutoCapture;

/// A verification response body.
///
/// [expiresAt] defaults to an hour out, so nothing expires mid-test unless a
/// test asks for it.
String verificationJson({
  String id = 'ver-1',
  String destination = '491511234567',
  String deliveryMethod = 'sms',
  String status = 'pending',
  String? errorCode,
  String? errorDetail,
  String? fee = '0.06',
  bool sms = true,
  bool callout = false,
  String? language = 'en-US',
  String? template = 'Your code is {{CODE}}',
  int? interceptionTimeout = 120,
  String? appHash,
  DateTime? expiresAt,
}) =>
    jsonEncode({
      'data': {
        'id': id,
        'destination': destination,
        'delivery_method': deliveryMethod,
        'fee': fee,
        'status': status,
        'error_code': errorCode,
        'error_detail': errorDetail,
        'expires_at':
            (expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)))
                .toIso8601String(),
        if (sms)
          'sms': {
            'template': template,
            'language': language,
            'interception_timeout': interceptionTimeout,
            if (appHash != null) 'app_hash': appHash,
          },
        if (callout) 'callout': {'language': language},
      },
    });

/// An error envelope carrying one element per code.
String errorsJson(List<String> codes) => jsonEncode({
      'errors': [
        for (final code in codes) {'code': code, 'detail': 'detail for $code'},
      ],
    });

/// A JSON response.
HttpResponse jsonResponse(int status, String body) => HttpResponse(
      status: status,
      headers: const {'content-type': 'application/json'},
      body: body,
    );

/// A 200 carrying a verification.
HttpResponse ok(String body) => jsonResponse(200, body);

/// A 201 carrying a verification.
HttpResponse created(String body) => jsonResponse(201, body);

/// A client wired to [transport], with retries off so a test never waits.
VerificationClient clientOver(HttpTransport transport) => VerificationClient(
      auth: const PublicAuthorization('app-key'),
      config: const ClientConfig(retry: RetryPolicy.none()),
      transport: transport,
    );

/// A transport that answers only once [gate] completes.
HttpTransport gated(Completer<void> gate, HttpResponse response) =>
    (HttpRequest request) async {
      await gate.future;
      return response;
    };

/// Collects every state a session emits, from the moment it is built.
final class StateRecorder {
  /// Subscribes to [session].
  StateRecorder(VerificationSession session) {
    _subscription =
        session.states.listen(states.add, onDone: () => done = true);
  }

  /// Every state seen, in order.
  final List<VerificationState> states = [];

  /// Whether the stream closed.
  bool done = false;

  late final StreamSubscription<VerificationState> _subscription;

  /// The states seen so far, as class names.
  List<String> get names => [for (final s in states) s.runtimeType.toString()];

  /// Stops recording.
  Future<void> cancel() => _subscription.cancel();
}
