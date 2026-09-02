import 'dart:convert';

import 'diagnostics.dart';
import 'errors.dart';
import 'models.dart';
import 'options.dart';
import 'phone_number.dart';

/// The alphabet and length the API accepts for an app hash.
final RegExp appHashFormat = RegExp(r'^[A-Za-z0-9+/]{11}$');

/// The tag shape the API accepts: a primary subtag and at most one more.
///
/// Narrower than BCP 47, which is the trap: `zh-Hans-CN` is a well-formed BCP 47
/// tag and the API rejects it outright rather than falling back.
final RegExp languageTagFormat = RegExp(r'^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?$');

/// The tags worth sending, or null when none are.
///
/// A malformed tag is dropped rather than sent, for the same reason a malformed
/// app hash is: the API answers `languages_invalid` and fails the whole
/// verification, where dropping it costs only the preferred language. Flutter's
/// own `Locale.toLanguageTag()` produces rejected tags for Chinese, Serbian,
/// Azerbaijani and Uzbek.
List<String>? acceptedLanguages(List<String>? requested) {
  if (requested == null || requested.isEmpty) return null;

  final accepted = <String>[];
  final dropped = <String>[];
  for (final tag in requested) {
    (languageTagFormat.hasMatch(tag) ? accepted : dropped).add(tag);
  }

  if (dropped.isNotEmpty) {
    debugDiagnostic(
      'the language tags ${dropped.join(', ')} are not the shape the API '
      'accepts and were not sent; it takes a primary subtag and at most one '
      'more, so a script subtag such as the Hans in zh-Hans-CN has to go',
    );
  }
  return accepted.isEmpty ? null : accepted;
}

/// Builds the body of a start request.
///
/// Per-channel options travel in a block named after the channel; only the
/// block matching the channel is read by the API.
Map<String, dynamic> startBody({
  required String destination,
  required DeliveryMethod method,
  SmsOptions? sms,
  CalloutOptions? callout,
  String? appHash,
}) {
  final digits = digitsOf(destination);
  if (digits == null) {
    throw ConfigurationException(
      'the destination "$destination" contains no digits',
    );
  }

  final data = <String, dynamic>{
    'destination': digits,
    'delivery_method': method.wire,
  };

  if (method == DeliveryMethod.sms) {
    final block = <String, dynamic>{};
    final languages = acceptedLanguages(sms?.languages);
    if (languages != null) block['languages'] = languages;

    if (appHash != null) {
      if (appHashFormat.hasMatch(appHash)) {
        block['app_hash'] = appHash;
      } else {
        // Dropped, not sent: the API rejects a malformed hash and fails the
        // whole verification. Omitting it costs automatic capture only.
        debugDiagnostic(
          'app hash "$appHash" is malformed and was not sent; '
          'automatic capture is unavailable for this verification',
        );
      }
    }

    if (block.isNotEmpty) data['sms'] = block;
  }

  if (method == DeliveryMethod.callout) {
    final block = <String, dynamic>{};
    final languages = acceptedLanguages(callout?.languages);
    if (languages != null) block['languages'] = languages;

    if (block.isNotEmpty) data['callout'] = block;
  }

  return {'data': data};
}

/// Builds the body of a report request.
Map<String, dynamic> reportBody({
  required String deliveryMethod,
  required ReportValue value,
}) {
  final key = switch (value) {
    ReportCode() => 'code',
  };
  return {
    'data': {'delivery_method': deliveryMethod, key: value.value},
  };
}

/// Decodes a verification response body.
Verification decodeVerification(String body) {
  final data = _dataObject(body);

  final expiresAtRaw = data['expires_at'];
  if (expiresAtRaw is! String) {
    throw DecodingException('the response has no expires_at', body: body);
  }
  final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
  if (expiresAt == null) {
    throw DecodingException(
      'expires_at "$expiresAtRaw" is not a timestamp',
      body: body,
    );
  }

  return Verification(
    id: _requiredString(data, 'id', body),
    destination: _requiredString(data, 'destination', body),
    deliveryMethod: _requiredString(data, 'delivery_method', body),
    status: _requiredString(data, 'status', body),
    expiresAt: expiresAt,
    fee: _optionalString(data, 'fee', body),
    errorCode: _optionalString(data, 'error_code', body),
    errorDetail: _optionalString(data, 'error_detail', body),
    sms: _decodeSms(data['sms'], body),
    callout: _decodeCallout(data['callout'], body),
  );
}

SmsInfo? _decodeSms(Object? raw, String body) {
  if (raw is! Map) return null;
  return SmsInfo(
    template: _optionalString(raw, 'template', body),
    language: _optionalString(raw, 'language', body),
    interceptionTimeoutSeconds: _optionalInt(raw, 'interception_timeout', body),
    appHash: _optionalString(raw, 'app_hash', body),
  );
}

CalloutInfo? _decodeCallout(Object? raw, String body) {
  if (raw is! Map) return null;
  return CalloutInfo(language: _optionalString(raw, 'language', body));
}

/// Decodes an error envelope, element by element.
///
/// An unmodelled code resolves to a null [ApiErrorItem.known] and an element
/// that is not an object is skipped; neither poisons the rest.
List<ApiErrorItem> decodeErrors(String body) {
  final Object? root;
  try {
    root = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  if (root is! Map) return const [];

  final errors = root['errors'];
  if (errors is! List) return const [];

  final items = <ApiErrorItem>[];
  for (final element in errors) {
    if (element is! Map) continue;
    final code = element['code'];
    if (code is! String) continue;
    // Coerced rather than cast: this decoder skips an element it cannot read
    // and must not throw on one, least of all on the error path, where doing so
    // destroys the very exception that says the code was wrong.
    final detail = element['detail'];
    items.add(
      ApiErrorItem.fromWire(code, detail: detail is String ? detail : null),
    );
  }
  return items;
}

Map<String, dynamic> _dataObject(String body) {
  final Object? root;
  try {
    root = jsonDecode(body);
  } on FormatException catch (e) {
    throw DecodingException('the response is not JSON: ${e.message}',
        body: body);
  }
  if (root is! Map) {
    throw DecodingException('the response is not a JSON object', body: body);
  }
  final data = root['data'];
  if (data is! Map) {
    throw DecodingException('the response has no data object', body: body);
  }
  return data.cast<String, dynamic>();
}

/// A value that may be absent, but must be a string when it is present.
///
/// Cast rather than coerced everywhere else, which is the bug this replaces: an
/// unexpected type threw a raw `_TypeError` outside the sealed tree, and the
/// session, catching only [VerificationException], emitted no state at all.
String? _optionalString(Map<Object?, Object?> data, String key, String body) {
  final value = data[key];
  if (value == null) return null;
  if (value is String) return value;
  throw DecodingException('$key is not a string', body: body);
}

/// A value that may be absent, but must be a whole number when present.
int? _optionalInt(Map<Object?, Object?> data, String key, String body) {
  final value = data[key];
  if (value == null) return null;
  if (value is int) return value;
  throw DecodingException('$key is not a whole number', body: body);
}

String _requiredString(Map<String, dynamic> data, String key, String body) {
  final value = data[key];
  if (value is! String) {
    throw DecodingException('the response has no $key', body: body);
  }
  return value;
}
