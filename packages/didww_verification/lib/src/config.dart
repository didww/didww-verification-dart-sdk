import 'version.dart';

/// Receives one line per request.
///
/// Implementations are given method, URL and status only — never bodies and
/// never headers, so a code or a credential cannot reach a log through it.
abstract interface class VerificationLogger {
  /// Records [line].
  void log(String line);
}

/// How often a read may be retried.
///
/// Reads only, and structurally so: retry is attached at the two reading call
/// sites, so no value here can make a write retryable. A start bills the
/// account, a report consumes an attempt, and a request that timed out may
/// still have been carried out.
final class RetryPolicy {
  /// Retries a read up to [attempts] times, backing off from [baseDelay].
  const RetryPolicy({
    this.attempts = 2,
    this.baseDelay = const Duration(milliseconds: 200),
  });

  /// Makes one attempt and never retries.
  const RetryPolicy.none()
      : attempts = 1,
        baseDelay = Duration.zero;

  /// Total attempts, including the first.
  final int attempts;

  /// Delay before the second attempt; doubled for each one after.
  final Duration baseDelay;
}

/// What the SDK identifies itself as when no other value is configured.
const String defaultUserAgent = 'didww_verification/$packageVersion';

/// Client-wide settings.
final class ClientConfig {
  /// Builds a configuration.
  const ClientConfig({
    this.connectTimeout = const Duration(seconds: 10),
    this.timeout = const Duration(seconds: 30),
    this.retry = const RetryPolicy(),
    this.userAgent = defaultUserAgent,
    this.logger,
  });

  /// How long to wait for a connection.
  final Duration connectTimeout;

  /// How long to wait for a whole request.
  final Duration timeout;

  /// How often a read may be retried.
  final RetryPolicy retry;

  /// Sent as `User-Agent`. Pass null to send none.
  ///
  /// Defaults to [defaultUserAgent] so SDK version adoption is visible in the
  /// API's own logs; the runtime otherwise supplies its own opaque value.
  final String? userAgent;

  /// Receives one line per request when set.
  final VerificationLogger? logger;
}

/// Which API to talk to.
///
/// The SDK appends the API version itself, so a custom base carries only a
/// scheme, a host and optionally a base path.
final class VerificationEnvironment {
  /// Targets [baseUrl].
  const VerificationEnvironment.custom(this.baseUrl);

  /// The live API.
  static final VerificationEnvironment production =
      VerificationEnvironment.custom(
          Uri.parse('https://verification.didww.com'));

  /// The sandbox API.
  static final VerificationEnvironment sandbox = VerificationEnvironment.custom(
    Uri.parse('https://verification-sandbox.didww.com'),
  );

  /// The origin, without the API version.
  final Uri baseUrl;
}
