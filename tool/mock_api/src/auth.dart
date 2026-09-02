import 'dart:convert';

import 'state.dart';

/// Which scheme an `Authorization` header selected.
enum AuthScheme {
  /// `Basic <base64(key:secret)>`.
  basic,

  /// `Application <key>` — the key alone, no secret.
  public,

  /// `Application <key>:<signature>` — request signing.
  signed,

  /// Absent, empty, or a scheme the API does not offer.
  none,
}

/// The result of reading an `Authorization` header.
final class AuthOutcome {
  const AuthOutcome(this.scheme, {this.application});

  /// The scheme the header selected, whether or not it authenticated.
  final AuthScheme scheme;

  /// The application, non-null only when the credentials matched one.
  final MockApplication? application;

  /// Whether the request may proceed.
  bool get authenticated => application != null;
}

/// Reads [header] the way the API dispatches on it.
///
/// The trap worth reproducing: the first colon **anywhere** after the
/// `Application ` prefix selects request signing, so a key with something
/// appended is not a public-mode key with a bad suffix — it is a different scheme
/// that then fails.
AuthOutcome authenticate(String? header, List<MockApplication> applications) {
  if (header == null || header.isEmpty) {
    return const AuthOutcome(AuthScheme.none);
  }

  if (header.startsWith('Basic ')) {
    final decoded = _decodeBase64(header.substring(6).trim());
    if (decoded == null) return const AuthOutcome(AuthScheme.basic);
    final separator = decoded.indexOf(':');
    if (separator < 0) return const AuthOutcome(AuthScheme.basic);

    final key = decoded.substring(0, separator);
    final secret = decoded.substring(separator + 1);
    for (final application in applications) {
      if (application.key == key && application.secret == secret) {
        return AuthOutcome(AuthScheme.basic, application: application);
      }
    }
    return const AuthOutcome(AuthScheme.basic);
  }

  if (header.startsWith('Application ')) {
    final credential = header.substring(12).trim();
    if (credential.contains(':')) {
      return const AuthOutcome(AuthScheme.signed);
    }
    for (final application in applications) {
      if (application.key == credential) {
        return AuthOutcome(AuthScheme.public, application: application);
      }
    }
    return const AuthOutcome(AuthScheme.public);
  }

  return const AuthOutcome(AuthScheme.none);
}

String? _decodeBase64(String value) {
  try {
    return utf8.decode(base64.decode(value));
  } on FormatException {
    return null;
  }
}
