import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'errors.dart';
import 'transport.dart';

/// A transport over `dart:io`, and the handle that closes it.
final class IOHttpTransport implements OwnedTransport {
  /// Builds a transport with the given timeouts.
  IOHttpTransport({
    Duration connectTimeout = const Duration(seconds: 10),
    Duration timeout = const Duration(seconds: 30),
  })  : _timeout = timeout,
        _client = HttpClient()..connectionTimeout = connectTimeout;

  final HttpClient _client;
  final Duration _timeout;
  bool _closed = false;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    if (_closed) {
      throw const ConfigurationException('the transport is closed');
    }
    HttpClientRequest? pending;
    try {
      return await _send(request, (open) => pending = open).timeout(_timeout);
    } on TimeoutException catch (e) {
      // Future.timeout only stops waiting. Without abort() the connection stays
      // open until the server answers, so a long-lived client leaks one socket
      // per timed-out request.
      pending?.abort();
      throw TransportException('the request timed out', cause: e);
    } on SocketException catch (e) {
      throw TransportException('could not reach the API', cause: e);
    } on HttpException catch (e) {
      throw TransportException('the connection failed', cause: e);
    } on TlsException catch (e) {
      throw TransportException('the TLS handshake failed', cause: e);
    } on ArgumentError catch (e) {
      // openUrl rejects a URL with no scheme or host — a base URL read from an
      // env var is the reachable case. A configuration fault, and it must not
      // leave here as a raw ArgumentError outside the sealed tree.
      throw ConfigurationException('the API URL is not usable: ${e.message}');
    }
  }

  Future<HttpResponse> _send(
    HttpRequest request,
    void Function(HttpClientRequest) onOpen,
  ) async {
    final req = await _client.openUrl(request.method, request.url);
    onOpen(req);
    request.headers.forEach(req.headers.set);

    final body = request.body;
    if (body != null) {
      final bytes = utf8.encode(body);
      req.headers.contentLength = bytes.length;
      req.add(bytes);
    } else {
      // Not merely "no body": no content-type either, whatever the header map
      // says. Enforced here rather than only where the map is built, because
      // this is the one place that writes the socket.
      req.headers.removeAll(HttpHeaders.contentTypeHeader);
      req.headers.contentLength = 0;
    }

    final res = await req.close();

    // allowMalformed, because utf8.decoder throws a FormatException that is not
    // in the sealed tree. A captive portal or proxy answering in ISO-8859-1
    // needs no server fault to reach here, and the status it carried is the
    // useful answer — not a decode failure.
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in res) {
      bytes.add(chunk);
    }
    final text = utf8.decode(bytes.takeBytes(), allowMalformed: true);

    final headers = <String, String>{};
    res.headers.forEach(
        (name, values) => headers[name.toLowerCase()] = values.join(', '));

    return HttpResponse(status: res.statusCode, headers: headers, body: text);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
  }
}
