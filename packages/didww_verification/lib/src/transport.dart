/// A request the SDK is about to send.
final class HttpRequest {
  /// Describes one outbound request.
  const HttpRequest({
    required this.method,
    required this.url,
    required this.path,
    required this.headers,
    this.body,
  });

  /// The HTTP method, upper case.
  final String method;

  /// The full URL, including any query.
  final Uri url;

  /// The percent-encoded path only, without the query.
  ///
  /// Read from [url] rather than rebuilt, so there is one producer of this
  /// string and it cannot drift from what is actually sent.
  final String path;

  /// Headers to send. Carries no `Content-Type` when [body] is null.
  final Map<String, String> headers;

  /// The exact body, or null when there is none.
  ///
  /// Null rather than empty: the API folds the content type into its request
  /// signature, so a bodyless request must send no `Content-Type` at all. A
  /// transport that defaults one breaks signed requests silently.
  final String? body;
}

/// A response the SDK received.
final class HttpResponse {
  /// Wraps a response.
  const HttpResponse({
    required this.status,
    required this.headers,
    required this.body,
  });

  /// The HTTP status.
  final int status;

  /// Response headers, lower-cased.
  final Map<String, String> headers;

  /// The response body as text.
  final String body;
}

/// Sends a request and returns its response.
///
/// A function rather than a class so a test double is a closure.
typedef HttpTransport = Future<HttpResponse> Function(HttpRequest request);

/// A transport the client built and therefore owns.
///
/// The seam the conditional default is reached through: [VerificationClient]
/// closes what it built and nothing else, without naming a platform.
abstract interface class OwnedTransport {
  /// Sends [request].
  Future<HttpResponse> send(HttpRequest request);

  /// Releases the underlying connections. Safe to call more than once.
  void close();
}
