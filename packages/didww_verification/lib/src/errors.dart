import 'models.dart';

/// Anything this SDK throws.
///
/// Sealed, so a `switch` over it is exhaustive.
sealed class VerificationException implements Exception {
  /// Describes what went wrong.
  const VerificationException(this.message);

  /// A short description, safe to log. Never contains a code or a secret.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The SDK was asked to do something impossible, before any request went out.
final class ConfigurationException extends VerificationException {
  /// Describes the impossible request.
  const ConfigurationException(super.message);
}

/// The request never produced a response: DNS, TLS, connection or timeout.
final class TransportException extends VerificationException {
  /// Wraps [cause], the underlying failure.
  const TransportException(super.message, {this.cause});

  /// The underlying error, when there was one.
  final Object? cause;
}

/// A response arrived, but was not the JSON shape the API documents.
///
/// Distinct from an unknown vocabulary value, which decodes without complaint.
final class DecodingException extends VerificationException {
  /// Reports a body that could not be read.
  const DecodingException(super.message, {required this.body});

  /// The response body, kept so the failure can be diagnosed.
  final String body;
}

/// The API answered with an error envelope.
///
/// `base`, so it can only be extended and never implemented: anything caught
/// as an [ApiException] carries the real [status], [errors] and [responseBody].
base class ApiException extends VerificationException {
  /// Wraps the envelope returned with [status].
  const ApiException(
    super.message, {
    required this.status,
    required this.errors,
    required this.responseBody,
  });

  /// The HTTP status.
  final int status;

  /// Every element of the envelope, in the order the API sent them.
  final List<ApiErrorItem> errors;

  /// The raw response body.
  final String responseBody;

  /// The first element, or `null` when the envelope was empty.
  ApiErrorItem? get first => errors.isEmpty ? null : errors.first;

  /// Every raw code in the envelope.
  List<String> get codes => [for (final e in errors) e.code];

  /// Whether the envelope carries [code].
  bool has(ApiErrorCode code) => errors.any((e) => e.known == code);
}

/// The credentials were missing, wrong, or too weak for this application.
///
/// Also returned when the account has no verification plan — access scoping,
/// not a fault to work around.
final class UnauthorizedException extends ApiException {
  /// Wraps a 401 envelope.
  const UnauthorizedException(
    super.message, {
    required super.status,
    required super.errors,
    required super.responseBody,
  });
}

/// The account cannot fund another verification.
final class BalanceInsufficientException extends ApiException {
  /// Wraps a 402 envelope.
  const BalanceInsufficientException(
    super.message, {
    required super.status,
    required super.errors,
    required super.responseBody,
  });
}

/// No verification matched.
final class NotFoundException extends ApiException {
  /// Wraps a 404 envelope.
  const NotFoundException(
    super.message, {
    required super.status,
    required super.errors,
    required super.responseBody,
  });
}

/// The request was rejected.
final class ValidationException extends ApiException {
  /// Wraps a 400 or 422 envelope.
  const ValidationException(
    super.message, {
    required super.status,
    required super.errors,
    required super.responseBody,
  });
}

/// The API failed to handle the request.
final class ServerException extends ApiException {
  /// Wraps a 5xx envelope.
  const ServerException(
    super.message, {
    required super.status,
    required super.errors,
    required super.responseBody,
  });
}

/// A start was requested again too soon after one for the same application
/// and destination.
final class TooManyRequestsException extends ApiException {
  /// Wraps a 429 envelope.
  const TooManyRequestsException(
    super.message, {
    required super.status,
    required super.errors,
    required super.responseBody,
    this.retryAfter,
  });

  /// How long to wait before starting again, parsed from `Retry-After`.
  ///
  /// Null when the header was absent or not a whole number of seconds.
  final Duration? retryAfter;
}

final RegExp _wholeSeconds = RegExp(r'^\d+$');

// Duration stores microseconds; this keeps them exact on the web (2^53) too.
const int _maxRetryAfterSeconds = 9007199254;

/// The whole-second delay in a lower-cased `retry-after` header, or null when
/// absent, not a plain non-negative integer (never an HTTP date), or too large
/// to represent. Shape is checked first: `int.tryParse` alone accepts a `-`.
Duration? _retryAfter(Map<String, String>? headers) {
  final value = headers?['retry-after']?.trim();
  if (value == null || !_wholeSeconds.hasMatch(value)) return null;
  final seconds = int.tryParse(value);
  if (seconds == null || seconds > _maxRetryAfterSeconds) return null;
  return Duration(seconds: seconds);
}

/// Builds the exception for [status], carrying [errors].
///
/// A status with no subtype becomes a plain [ApiException], never a decode
/// failure. [headers] is read only for 429's `Retry-After`.
ApiException apiExceptionFor({
  required int status,
  required List<ApiErrorItem> errors,
  required String responseBody,
  Map<String, String>? headers,
}) {
  final message = errors.isEmpty
      ? 'the API returned $status'
      : 'the API returned $status: ${errors.map((e) => e.code).join(', ')}';

  return switch (status) {
    401 => UnauthorizedException(
        message,
        status: status,
        errors: errors,
        responseBody: responseBody,
      ),
    402 => BalanceInsufficientException(
        message,
        status: status,
        errors: errors,
        responseBody: responseBody,
      ),
    404 => NotFoundException(
        message,
        status: status,
        errors: errors,
        responseBody: responseBody,
      ),
    400 || 422 => ValidationException(
        message,
        status: status,
        errors: errors,
        responseBody: responseBody,
      ),
    429 => TooManyRequestsException(
        message,
        status: status,
        errors: errors,
        responseBody: responseBody,
        retryAfter: _retryAfter(headers),
      ),
    >= 500 && < 600 => ServerException(
        message,
        status: status,
        errors: errors,
        responseBody: responseBody,
      ),
    _ => ApiException(
        message,
        status: status,
        errors: errors,
        responseBody: responseBody,
      ),
  };
}
