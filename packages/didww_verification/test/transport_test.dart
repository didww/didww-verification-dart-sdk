@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:didww_verification/didww_verification.dart';
// Not in the main library: importing it there would put dart:io back in the
// barrel's import graph and exclude the package from the web again.
import 'package:didww_verification/io.dart';
import 'package:test/test.dart';

/// A loopback server that records what it was actually sent.
///
/// The point of the whole file: every other suite drives a FakeTransport, which
/// records the headers the client composed rather than the headers `dart:io` put
/// on the wire, and the two are not the same set.
final class _Loopback {
  _Loopback._(this.server);

  static Future<_Loopback> start({
    int status = 200,
    String body = '{}',
    String contentType = 'application/json',
    bool answer = true,
  }) async {
    final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    final loopback = _Loopback._(server);

    server.listen((request) async {
      loopback.headers.add({
        for (final name in const [
          'content-type',
          'content-length',
          'accept',
          'authorization',
          'user-agent',
        ])
          if (request.headers.value(name) != null)
            name: request.headers.value(name)!,
      });
      loopback.bodies.add(await utf8.decoder.bind(request).join());
      if (!answer) return;

      request.response
        ..statusCode = status
        ..headers.contentType = io.ContentType.parse(contentType)
        ..write(body);
      await request.response.close();
    });

    return loopback;
  }

  final io.HttpServer server;
  final List<Map<String, String>> headers = [];
  final List<String> bodies = [];

  Uri get origin => Uri.parse('http://127.0.0.1:${server.port}');

  Future<void> close() => server.close(force: true);
}

VerificationClient _client(
  Uri origin, {
  ClientConfig config = const ClientConfig(),
}) =>
    VerificationClient(
      auth: const PublicAuthorization('app-key'),
      environment: VerificationEnvironment.custom(origin),
      config: config,
    );

String get _verificationBody => jsonEncode({
      'data': {
        'id': 'ver-1',
        'destination': '491511234567',
        'delivery_method': 'sms',
        'fee': '0.06',
        'status': 'pending',
        'error_code': null,
        'error_detail': null,
        'expires_at': '2026-08-25T12:00:00Z',
        'sms': {'template': 'code {{CODE}}', 'interception_timeout': 120},
      },
    });

void main() {
  group('what dart:io actually puts on the wire', () {
    test('a bodyless GET arrives with no content type', () async {
      final loopback = await _Loopback.start(body: _verificationBody);
      addTearDown(loopback.close);

      final client = _client(loopback.origin);
      addTearDown(client.close);
      await client.getVerification('ver-1');

      // The API folds the content type into its request signature and reads none
      // when none was sent, so a defaulted header breaks a signed request with
      // nothing able to see it. dart:io supplies one unasked, which is why this
      // is asserted against a socket rather than against the client's own map.
      expect(loopback.headers.single.containsKey('content-type'), isFalse);
      expect(loopback.bodies.single, isEmpty);
      expect(loopback.headers.single['authorization'], 'Application app-key');
    });

    test('a POST arrives with the content type and the body', () async {
      final loopback =
          await _Loopback.start(status: 201, body: _verificationBody);
      addTearDown(loopback.close);

      final client = _client(loopback.origin);
      addTearDown(client.close);
      await client.startVerification(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
      );

      expect(loopback.headers.single['content-type'],
          startsWith('application/json'));
      expect(jsonDecode(loopback.bodies.single), {
        'data': {'destination': '491511234567', 'delivery_method': 'sms'},
      });
    });

    test('a configured user agent replaces the default one', () async {
      final loopback = await _Loopback.start(body: _verificationBody);
      addTearDown(loopback.close);

      final bare = _client(loopback.origin);
      await bare.getVerification('ver-1');
      bare.close();

      final named = _client(
        loopback.origin,
        config: const ClientConfig(userAgent: 'demo/1.0'),
      );
      await named.getVerification('ver-1');
      named.close();

      final silent = _client(
        loopback.origin,
        config: const ClientConfig(userAgent: null),
      );
      await silent.getVerification('ver-1');
      silent.close();

      expect(loopback.headers[0]['user-agent'], 'didww_verification/1.0.0');
      expect(loopback.headers[1]['user-agent'], 'demo/1.0');
      // Explicitly null means none of ours; dart:io then supplies the runtime's,
      // so the header is never actually absent from the wire.
      expect(loopback.headers[2]['user-agent'], startsWith('Dart/'));
    });
  });

  group('failures that never produce a response', () {
    test('an unreachable port becomes a TransportException', () async {
      final probe =
          await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      final client = _client(Uri.parse('http://127.0.0.1:$port'));
      addTearDown(client.close);

      await expectLater(
        client.getVerification('ver-1'),
        throwsA(isA<TransportException>()),
      );
    });

    test('a request that outlives the timeout is aborted, not left open',
        () async {
      // A raw socket, not an HttpServer: the question is whether the CLIENT let
      // go, and a server that never answers keeps its own connection active
      // either way.
      final server =
          await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      final letGo = Completer<void>();
      void done() => letGo.isCompleted ? null : letGo.complete();
      server.listen((socket) =>
          socket.listen((_) {}, onDone: done, onError: (_) => done()));

      final client = _client(
        Uri.parse('http://127.0.0.1:${server.port}'),
        config: const ClientConfig(
          timeout: Duration(milliseconds: 200),
          retry: RetryPolicy.none(),
        ),
      );
      addTearDown(client.close);

      await expectLater(
        client.getVerification('ver-1'),
        throwsA(isA<TransportException>()),
      );

      // Future.timeout only stops waiting; without an explicit abort the socket
      // stays open until the server answers, and a long-lived client leaks one
      // per timed-out request.
      await letGo.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            fail('the connection was still open after the timeout'),
      );
    });

    test('a body that is not the documented shape becomes a DecodingException',
        () async {
      final loopback = await _Loopback.start(
        body: '<html>not json</html>',
        contentType: 'text/html',
      );
      addTearDown(loopback.close);

      final client = _client(loopback.origin);
      addTearDown(client.close);

      await expectLater(
        client.getVerification('ver-1'),
        throwsA(isA<DecodingException>()),
      );
    });

    test('an error envelope still decodes over a real socket', () async {
      final loopback = await _Loopback.start(
        status: 422,
        body: jsonEncode({
          'errors': [
            {'code': 'code_invalid', 'detail': 'code is invalid'},
          ],
        }),
      );
      addTearDown(loopback.close);

      final client = _client(loopback.origin);
      addTearDown(client.close);

      await expectLater(
        client.reportVerification(
          'ver-1',
          deliveryMethod: 'sms',
          value: const ReportValue.code('000000'),
        ),
        throwsA(
          isA<ValidationException>()
              .having((e) => e.first?.known, 'first', ApiErrorCode.codeInvalid),
        ),
      );
    });
  });

  group('lifetime', () {
    test('close twice does not throw, and a closed transport refuses to send',
        () async {
      final transport = IOHttpTransport();
      transport.close();
      transport.close();

      await expectLater(
        transport.send(
          HttpRequest(
            method: 'GET',
            url: Uri.parse('http://127.0.0.1:1'),
            path: '/',
            headers: const {},
          ),
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('closing a client that was handed a transport releases nothing',
        () async {
      var calls = 0;
      final client = VerificationClient(
        auth: const PublicAuthorization('k'),
        transport: (request) async {
          calls++;
          return HttpResponse(
            status: 200,
            headers: const {},
            body: _verificationBody,
          );
        },
      );

      await client.getVerification('ver-1');
      client.close();
      await client.getVerification('ver-1');

      expect(calls, 2);
    });
  });
}
