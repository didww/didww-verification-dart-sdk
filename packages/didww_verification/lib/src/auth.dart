import 'dart:convert';

import 'diagnostics.dart';

/// What an [Authorization] is asked to authenticate.
///
/// Carries everything a request-signing scheme would need.
final class AuthRequest {
  /// Describes a single outbound request.
  const AuthRequest({
    required this.method,
    required this.path,
    required this.contentType,
    required this.body,
  });

  /// The HTTP method, upper case.
  final String method;

  /// The percent-encoded path, without the query.
  final String path;

  /// The content type being sent, or the empty string when there is no body.
  final String contentType;

  /// The exact bytes being sent, or the empty string when there is no body.
  final String body;
}

/// Produces the headers that authenticate a request.
///
/// A seam, not a closed set: implement it to add a scheme. This release ships
/// only the two that are safe inside an application binary.
abstract interface class Authorization {
  /// Headers to merge into [request].
  Map<String, String> headers(AuthRequest request);
}

/// Authenticates with the application key alone.
///
/// The scheme to prefer on a device: it carries no secret.
final class PublicAuthorization implements Authorization {
  /// Authenticates as [applicationKey].
  const PublicAuthorization(this.applicationKey);

  /// The application key.
  final String applicationKey;

  @override
  Map<String, String> headers(AuthRequest request) {
    // Append nothing to the key: a colon anywhere after the prefix selects
    // the signed scheme instead.
    return {'Authorization': 'Application $applicationKey'};
  }
}

/// Authenticates with the application key and its secret.
///
/// A secret embedded in an application binary is recoverable; prefer
/// [PublicAuthorization] on a device.
final class BasicAuthorization implements Authorization {
  /// Authenticates as [key] with [secret].
  const BasicAuthorization({required this.key, required this.secret});

  /// The application key.
  final String key;

  /// The application secret.
  final String secret;

  /// One warning per process, not one per request.
  static bool _warned = false;

  @override
  Map<String, String> headers(AuthRequest request) {
    if (!_warned) {
      _warned = true;
      debugDiagnostic(
        'BasicAuthorization sends the application secret with every request. A '
        'secret embedded in a shipped binary is recoverable; use '
        'PublicAuthorization on a device.',
      );
    }
    // UTF-8 bytes, so a non-ASCII secret does not depend on platform encoding.
    final token = base64.encode(utf8.encode('$key:$secret'));
    return {'Authorization': 'Basic $token'};
  }
}
