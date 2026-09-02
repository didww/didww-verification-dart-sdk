import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'auth.dart';
import 'config.dart';
import 'default_transport.dart';
import 'errors.dart';
import 'models.dart';
import 'options.dart';
import 'phone_number.dart';
import 'redact.dart';
import 'transport.dart';
import 'wire.dart';

// Two segments, not one: Uri.pathSegments encodes each, so a single
// 'api/v1' would arrive as 'api%2Fv1'.
const List<String> _apiPrefix = ['api', 'v1'];
const String _jsonContentType = 'application/json';

/// A direct client for the five verification endpoints.
///
/// Use `VerificationSession` instead when a state machine and automatic SMS
/// capture are wanted.
final class VerificationClient {
  /// Builds a client.
  ///
  /// Supply [transport] to route requests elsewhere or to test without a
  /// network; otherwise one is built over `dart:io` and closed by [close].
  VerificationClient({
    required Authorization auth,
    VerificationEnvironment? environment,
    this.config = const ClientConfig(),
    HttpTransport? transport,
  })  : _auth = auth,
        _baseUrl = (environment ?? VerificationEnvironment.production).baseUrl {
    if (transport != null) {
      _transport = transport;
    } else {
      final owned = createDefaultTransport(
        connectTimeout: config.connectTimeout,
        timeout: config.timeout,
      );
      _owned = owned;
      _transport = owned.send;
    }
  }

  final Authorization _auth;
  final Uri _baseUrl;

  /// Client-wide settings.
  final ClientConfig config;

  late final HttpTransport _transport;
  OwnedTransport? _owned;

  /// Starts a verification. Bills the account, and is never retried.
  ///
  /// [destination] may carry any formatting; it is normalised to digits first.
  Future<Verification> startVerification({
    required String destination,
    required DeliveryMethod deliveryMethod,
    SmsOptions? sms,
    CalloutOptions? callout,
    String? appHash,
  }) async {
    final body = startBody(
      destination: destination,
      method: deliveryMethod,
      sms: sms,
      callout: callout,
      appHash: appHash,
    );
    // No retry: a start that timed out may still have been carried out.
    final response =
        await _send('POST', [..._apiPrefix, 'verifications'], body: body);
    return decodeVerification(response.body);
  }

  /// Fetches a verification by id.
  Future<Verification> getVerification(String id) async {
    final response = await _sendWithRetry(
      'GET',
      [..._apiPrefix, 'verifications', id],
    );
    return decodeVerification(response.body);
  }

  /// Fetches the newest verification for a number, whatever its status.
  ///
  /// Not "the live one": a denied start supersedes nothing, so it can be the
  /// newest row while an earlier verification is still live. Any formatting is
  /// accepted.
  Future<Verification> getVerificationByNumber(String number) async {
    final response = await _sendWithRetry(
      'GET',
      [..._apiPrefix, 'verifications', 'by_number', _digits(number)],
    );
    return decodeVerification(response.body);
  }

  /// Reports a value for a verification. Consumes an attempt, and is never
  /// retried.
  ///
  /// Pass the verification's own `deliveryMethod`.
  Future<Verification> reportVerification(
    String id, {
    required String deliveryMethod,
    required ReportValue value,
  }) async {
    final response = await _send(
      'PUT',
      [..._apiPrefix, 'verifications', id],
      body: reportBody(deliveryMethod: deliveryMethod, value: value),
    );
    return decodeVerification(response.body);
  }

  /// Reports a value for the latest verification on a number.
  Future<Verification> reportVerificationByNumber(
    String number, {
    required String deliveryMethod,
    required ReportValue value,
  }) async {
    final response = await _send(
      'PUT',
      [..._apiPrefix, 'verifications', 'by_number', _digits(number)],
      body: reportBody(deliveryMethod: deliveryMethod, value: value),
    );
    return decodeVerification(response.body);
  }

  /// Releases the underlying HTTP client. Safe to call more than once.
  void close() => _owned?.close();

  String _digits(String number) {
    final digits = digitsOf(number);
    if (digits == null) {
      throw ConfigurationException('the number "$number" contains no digits');
    }
    return digits;
  }

  Uri _url(List<String> segments) => _baseUrl.replace(
        pathSegments: [
          ..._baseUrl.pathSegments.where((s) => s.isNotEmpty),
          ...segments,
        ],
      );

  Future<HttpResponse> _send(
    String method,
    List<String> segments, {
    Map<String, dynamic>? body,
  }) async {
    final url = _url(segments);
    final encoded = body == null ? null : jsonEncode(body);

    final headers = <String, String>{
      'Accept': _jsonContentType,
      if (encoded != null) 'Content-Type': _jsonContentType,
      if (config.userAgent != null) 'User-Agent': config.userAgent!,
    };
    headers.addAll(
      _auth.headers(
        AuthRequest(
          method: method,
          path: url.path,
          contentType: encoded == null ? '' : _jsonContentType,
          body: encoded ?? '',
        ),
      ),
    );

    final request = HttpRequest(
      method: method,
      url: url,
      path: url.path,
      headers: headers,
      body: encoded,
    );

    // The timeout is applied here, not only inside the built-in transport, so
    // `config.timeout` means what it says for a supplied one too. Anything the
    // transport throws is wrapped: a supplied one throws its own type, and the
    // session catches only VerificationException, so an unwrapped foreign error
    // emits no state at all and leaves the screen on a spinner forever.
    final HttpResponse response;
    try {
      response = await _transport(request).timeout(config.timeout);
    } on VerificationException {
      rethrow;
    } on TimeoutException catch (e) {
      throw TransportException('the request timed out', cause: e);
    } catch (e) {
      throw TransportException('the transport failed', cause: e);
    }

    config.logger?.log(
      redactDigitRuns('$method ${url.path} -> ${response.status}'),
    );

    if (response.status >= 200 && response.status < 300) return response;

    throw apiExceptionFor(
      status: response.status,
      errors: decodeErrors(response.body),
      responseBody: response.body,
    );
  }

  /// Reads only. Attached here rather than in [_send] so no configuration can
  /// make a write retryable.
  Future<HttpResponse> _sendWithRetry(
      String method, List<String> segments) async {
    final attempts = config.retry.attempts < 1 ? 1 : config.retry.attempts;
    var delay = config.retry.baseDelay;

    for (var attempt = 1;; attempt++) {
      try {
        return await _send(method, segments);
      } on TransportException {
        if (attempt >= attempts) rethrow;
      } on ServerException {
        if (attempt >= attempts) rethrow;
      }
      if (delay > Duration.zero) {
        final jitter = Random().nextInt(delay.inMilliseconds + 1);
        await Future<void>.delayed(delay + Duration(milliseconds: jitter));
      }
      delay *= 2;
    }
  }
}
