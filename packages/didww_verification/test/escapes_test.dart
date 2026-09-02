// Every way something could leave the SDK outside its own sealed exception
// tree. Each of these was a live escape: the session catches only
// VerificationException, so an unwrapped throw emitted no state at all and left
// the screen on a spinner that never resolved.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:didww_verification/didww_verification.dart';
import 'package:test/test.dart';

import 'support.dart';

final class _Foreign implements Exception {
  const _Foreign();
  @override
  String toString() => 'ClientException: socket died';
}

void main() {
  group('nothing escapes the sealed exception tree', () {
    test('a transport throwing its own type becomes a TransportException',
        () async {
      final client = clientOver((_) async => throw const _Foreign());
      await expectLater(
        client.getVerification('ver-1'),
        throwsA(
          isA<TransportException>()
              .having((e) => e.cause, 'cause', isA<_Foreign>()),
        ),
      );
    });

    test('a start over a foreign transport reaches a state, and never throws',
        () async {
      final session = VerificationSession(
          client: clientOver((_) async => throw const _Foreign()));
      final recorder = StateRecorder(session);
      addTearDown(session.dispose);

      await session.start(
          destination: '491511234567', deliveryMethod: DeliveryMethod.sms);

      expect(session.state, isA<VerificationFailed>());
      await Future<void>.delayed(Duration.zero);
      expect(recorder.names, contains('VerificationFailed'));
    });

    test('a decoded field of the wrong type becomes a DecodingException',
        () async {
      final body = jsonEncode({
        'data': {
          'id': 'v1',
          'destination': '491511234567',
          'delivery_method': 'sms',
          'fee': 0.35, // a number where the API sends a decimal string
          'status': 'pending',
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
      });
      final client = clientOver((_) async => ok(body));
      await expectLater(
          client.getVerification('ver-1'), throwsA(isA<DecodingException>()));
    });

    test('a non-string detail does not destroy the API error it arrived with',
        () async {
      final client = clientOver(
        (_) async => jsonResponse(
          422,
          jsonEncode({
            'errors': [
              {
                'code': 'code_invalid',
                'detail': <String, String>{'reason': 'x'}
              },
            ],
          }),
        ),
      );

      await expectLater(
        client.reportVerification('v1',
            deliveryMethod: 'sms', value: const ReportValue.code('123456')),
        throwsA(
          isA<ValidationException>()
              .having((e) => e.codes, 'codes', ['code_invalid']).having(
                  (e) => e.first!.detail, 'detail', isNull),
        ),
      );
    });

    test('a base URL with no scheme becomes a ConfigurationException',
        () async {
      final client = VerificationClient(
        auth: const PublicAuthorization('k'),
        environment:
            VerificationEnvironment.custom(Uri.parse('verification.didww.com')),
      );
      addTearDown(client.close);

      await expectLater(client.getVerification('ver-1'),
          throwsA(isA<ConfigurationException>()));
    });

    test('a body that is not UTF-8 surfaces as the status it carried',
        () async {
      final server =
          await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(server.first.then((request) async {
        request.response.statusCode = 502;
        request.response.headers.contentType = io.ContentType('text', 'html');
        // A proxy error page in ISO-8859-1. Needs no fault on the API's side.
        request.response
            .add([0x7b, 0x22, 0x65, 0x22, 0x3a, 0x22, 0xE9, 0x22, 0x7d]);
        await request.response.close();
      }));

      final client = VerificationClient(
        auth: const PublicAuthorization('k'),
        config: const ClientConfig(retry: RetryPolicy.none()),
        environment: VerificationEnvironment.custom(
            Uri.parse('http://127.0.0.1:${server.port}')),
      );
      addTearDown(client.close);

      await expectLater(
        client.getVerification('ver-1'),
        throwsA(isA<ServerException>().having((e) => e.status, 'status', 502)),
      );
    });
  });

  group('the configured timeout bounds a supplied transport too', () {
    test('a transport that never answers times out', () async {
      final client = VerificationClient(
        auth: const PublicAuthorization('k'),
        config: const ClientConfig(
          timeout: Duration(milliseconds: 80),
          retry: RetryPolicy.none(),
        ),
        transport: (_) => Completer<HttpResponse>().future,
      );

      await expectLater(
        client.getVerification('ver-1'),
        throwsA(isA<TransportException>()),
      );
    });
  });
}
