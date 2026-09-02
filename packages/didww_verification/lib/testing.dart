/// Test helpers for code built on this package.
///
/// Exported so an integrator can drive the client without a network.
library;

import 'dart:async';
import 'dart:convert';

import 'src/auto_capture.dart';
import 'src/transport.dart';

export 'src/transport.dart' show HttpRequest, HttpResponse, HttpTransport;

/// A transport that returns scripted responses and records what it was asked.
///
/// Responses are returned in order; the last one repeats once the script runs
/// out, so a test that retries does not have to script every attempt.
final class FakeTransport {
  /// Replays [responses] in order.
  FakeTransport(this.responses);

  /// Replays a single JSON response.
  factory FakeTransport.json(Object body, {int status = 200}) => FakeTransport([
        HttpResponse(
          status: status,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        ),
      ]);

  /// The scripted responses.
  final List<HttpResponse> responses;

  /// Every request received, in order.
  final List<HttpRequest> requests = [];

  /// Errors to throw instead of returning a response, by attempt index.
  final Map<int, Object> throwOnAttempt = {};

  /// The most recent request, or null if there has been none.
  HttpRequest? get lastRequest => requests.isEmpty ? null : requests.last;

  /// How many requests have been received.
  int get callCount => requests.length;

  /// The transport function to hand to a client.
  Future<HttpResponse> call(HttpRequest request) async {
    requests.add(request);
    final index = requests.length - 1;

    final failure = throwOnAttempt[index];
    if (failure != null) throw failure;

    if (responses.isEmpty) {
      throw StateError('FakeTransport was given no responses');
    }
    return responses[index < responses.length ? index : responses.length - 1];
  }

  /// The decoded JSON body of the request at [index].
  Map<String, dynamic> bodyAt(int index) =>
      jsonDecode(requests[index].body!) as Map<String, dynamic>;
}

/// An [SmsAutoCapture] a test drives by hand, and can assert against.
///
/// The seam is harder to fake than it looks: [messages] has to hand back the
/// same stream on every call *and* tolerate a fresh listen before the previous
/// cancel has settled, which is what a session does when a verification is
/// restarted. A plain broadcast controller fails the second requirement.
final class FakeAutoCapture implements SmsAutoCapture {
  /// Reports [hash], and delivers whatever is pushed to [deliver].
  FakeAutoCapture({this.hash = 'A1b2C3d4E5f', this.failsWith});

  /// The value [appHash] resolves to. Null stands for a platform with none.
  final String? hash;

  /// Thrown by [appHash] instead of returning, when set.
  final Object? failsWith;

  /// How many times a session has subscribed.
  int listens = 0;

  /// How many times a session has cancelled.
  int cancels = 0;

  /// How many times a session has asked for the hash.
  int hashCalls = 0;

  final StreamController<String> _messages =
      StreamController<String>.broadcast();

  late final Stream<String> _stream = Stream<String>.multi((controller) {
    listens++;
    final subscription = _messages.stream.listen(controller.add);
    controller.onCancel = () {
      cancels++;
      return subscription.cancel();
    };
  });

  /// Pushes a message body to whatever is listening.
  void deliver(String body) => _messages.add(body);

  /// Releases the underlying controller.
  Future<void> close() => _messages.close();

  @override
  Future<String?> appHash() async {
    hashCalls++;
    final failure = failsWith;
    if (failure != null) throw failure;
    return hash;
  }

  @override
  Stream<String> messages() => _stream;
}
