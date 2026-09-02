import 'dart:convert';
import 'dart:io';

import 'hmac_sha256.dart';

/// What a customer's callback decided.
enum CallbackVerdict {
  /// The verification may start.
  allowed,

  /// The callback refused it.
  denied,

  /// The callback could not be reached, or answered in a way that cannot be read.
  invalid,
}

/// Asks a customer's callback whether a verification may start.
///
/// A **bodyless GET with no `Content-Type`**, signed over the URL path only —
/// query excluded, a bare origin signing the empty string. A pathless callback
/// URL, or an ingress that rewrites one, denies every verification even with
/// valid secrets on both sides.
///
/// Representative, not byte-compatible with the live API: it exists to produce
/// the three outcomes, not to be copied as a callback receiver.
Future<CallbackVerdict> askCallback(
  String callbackUrl, {
  required String signingSecret,
  required String destination,
  required String deliveryMethod,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final Uri url;
  try {
    url = Uri.parse(callbackUrl).replace(queryParameters: {
      'destination': destination,
      'delivery_method': deliveryMethod,
    });
  } on FormatException {
    return CallbackVerdict.invalid;
  }

  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.openUrl('GET', url);
    request.headers.removeAll(HttpHeaders.contentTypeHeader);
    request.headers.contentLength = 0;
    request.headers.set('X-Signature', signHex(signingSecret, url.path));

    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return CallbackVerdict.invalid;
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['allowed'] is! bool) {
      return CallbackVerdict.invalid;
    }
    return decoded['allowed'] == true
        ? CallbackVerdict.allowed
        : CallbackVerdict.denied;
  } on Object {
    return CallbackVerdict.invalid;
  } finally {
    client.close(force: true);
  }
}
