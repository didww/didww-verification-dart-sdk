import 'dart:convert';

import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification/testing.dart';
import 'package:test/test.dart';

Map<String, dynamic> _verification({String status = 'pending'}) => {
      'data': {
        'id': 'ver-1',
        'destination': '4915112345678',
        'delivery_method': 'sms',
        'fee': '0.06',
        'status': status,
        'error_code': null,
        'error_detail': null,
        'expires_at': '2026-08-25T12:00:00Z',
        'sms': {'template': 'code {{CODE}}', 'interception_timeout': 120},
      },
    };

VerificationClient _client(
  FakeTransport fake, {
  ClientConfig config = const ClientConfig(),
}) =>
    VerificationClient(
      auth: const PublicAuthorization('app-key'),
      environment:
          VerificationEnvironment.custom(Uri.parse('https://example.test')),
      config: config,
      transport: fake.call,
    );

void main() {
  group('request shape', () {
    test('start posts to the verifications collection', () async {
      final fake = FakeTransport.json(_verification(), status: 201);
      await _client(fake).startVerification(
        destination: '+49 151 1234-5678',
        deliveryMethod: DeliveryMethod.sms,
      );

      final req = fake.lastRequest!;
      expect(req.method, 'POST');
      expect(req.url.path, '/api/v1/verifications');
      expect(req.headers['Authorization'], 'Application app-key');
      expect(req.headers['Content-Type'], 'application/json');
      expect(fake.bodyAt(0), {
        'data': {'destination': '4915112345678', 'delivery_method': 'sms'},
      });
    });

    test('a read sends no body and no content type', () async {
      final fake = FakeTransport.json(_verification());
      await _client(fake).getVerification('ver-1');

      final req = fake.lastRequest!;
      expect(req.method, 'GET');
      expect(req.url.path, '/api/v1/verifications/ver-1');
      // Null rather than empty, and no content type at all: the API folds the
      // content type into its request signature and reads none when none was
      // sent, so a defaulted header would break a signed request silently.
      expect(req.body, isNull);
      expect(req.headers.containsKey('Content-Type'), isFalse);
    });

    test('report is sent as PUT', () async {
      final fake = FakeTransport.json(_verification(status: 'verified'));
      await _client(fake).reportVerification(
        'ver-1',
        deliveryMethod: 'sms',
        value: const ReportValue.code('123456'),
      );
      expect(fake.lastRequest!.method, 'PUT');
      expect(fake.bodyAt(0), {
        'data': {'delivery_method': 'sms', 'code': '123456'},
      });
    });

    test('the id segment is percent-encoded', () async {
      final fake = FakeTransport.json(_verification());
      await _client(fake).getVerification('a/b c?d');
      expect(fake.lastRequest!.url.path, '/api/v1/verifications/a%2Fb%20c%3Fd');
    });

    test('the by-number segment is digits only', () async {
      final fake = FakeTransport.json(_verification());
      await _client(fake).getVerificationByNumber('+49 (151) 1234-567');
      expect(
        fake.lastRequest!.url.path,
        '/api/v1/verifications/by_number/491511234567',
      );
    });

    test('a custom base path is preserved', () async {
      final fake = FakeTransport.json(_verification());
      final client = VerificationClient(
        auth: const PublicAuthorization('k'),
        environment: VerificationEnvironment.custom(
          Uri.parse('https://proxy.test/verify'),
        ),
        transport: fake.call,
      );
      await client.getVerification('ver-1');
      expect(fake.lastRequest!.url.path, '/verify/api/v1/verifications/ver-1');
    });
  });

  group('money and attempts are never spent twice', () {
    test('start is not retried even when the policy allows retries', () async {
      final fake = FakeTransport([])
        ..throwOnAttempt[0] = const TransportException('boom');
      final client = _client(
        fake,
        config: const ClientConfig(
          retry: RetryPolicy(attempts: 5, baseDelay: Duration.zero),
        ),
      );

      await expectLater(
        client.startVerification(
          destination: '491511234567',
          deliveryMethod: DeliveryMethod.sms,
        ),
        throwsA(isA<TransportException>()),
      );
      expect(fake.callCount, 1,
          reason: 'a start that timed out may have landed');
    });

    test('report is not retried even when the policy allows retries', () async {
      final fake = FakeTransport([])
        ..throwOnAttempt[0] = const TransportException('boom');
      final client = _client(
        fake,
        config: const ClientConfig(
          retry: RetryPolicy(attempts: 5, baseDelay: Duration.zero),
        ),
      );

      await expectLater(
        client.reportVerification(
          'ver-1',
          deliveryMethod: 'sms',
          value: const ReportValue.code('123456'),
        ),
        throwsA(isA<TransportException>()),
      );
      expect(fake.callCount, 1,
          reason: 'a report is not retried even when attempts remain');
    });

    test('a read is retried', () async {
      final fake = FakeTransport([
        HttpResponse(
          status: 200,
          headers: const {},
          body: jsonEncode(_verification()),
        ),
      ])
        ..throwOnAttempt[0] = const TransportException('transient');

      final client = _client(
        fake,
        config: const ClientConfig(
          retry: RetryPolicy(attempts: 2, baseDelay: Duration.zero),
        ),
      );
      final v = await client.getVerification('ver-1');
      expect(v.id, 'ver-1');
      expect(fake.callCount, 2);
    });

    test('a read gives up after the configured attempts', () async {
      final fake = FakeTransport([])
        ..throwOnAttempt[0] = const TransportException('down')
        ..throwOnAttempt[1] = const TransportException('down')
        ..throwOnAttempt[2] = const TransportException('down');

      final client = _client(
        fake,
        config: const ClientConfig(
          retry: RetryPolicy(attempts: 2, baseDelay: Duration.zero),
        ),
      );
      await expectLater(
        client.getVerification('ver-1'),
        throwsA(isA<TransportException>()),
      );
      expect(fake.callCount, 2);
    });

    test('RetryPolicy.none makes exactly one attempt', () async {
      final fake = FakeTransport([])
        ..throwOnAttempt[0] = const TransportException('down');
      final client = _client(
        fake,
        config: const ClientConfig(retry: RetryPolicy.none()),
      );
      await expectLater(
        client.getVerification('ver-1'),
        throwsA(isA<TransportException>()),
      );
      expect(fake.callCount, 1);
    });
  });

  group('the client makes no judgment about the channel', () {
    test('makes no judgment about a channel it does not model', () async {
      final fake = FakeTransport.json(_verification());
      await _client(fake).reportVerification(
        'ver-1',
        deliveryMethod: 'telepathy',
        value: const ReportValue.code('123456'),
      );
      expect(fake.callCount, 1,
          reason: 'an unmodelled channel is the API to judge');
    });
  });

  group('error responses', () {
    test('401 becomes UnauthorizedException', () async {
      final fake = FakeTransport([
        HttpResponse(
          status: 401,
          headers: const {},
          body: jsonEncode({
            'errors': [
              {'code': 'unauthorized', 'detail': 'unauthorized'},
            ],
          }),
        ),
      ]);
      await expectLater(
        _client(fake).getVerification('ver-1'),
        throwsA(
          isA<UnauthorizedException>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.codes, 'codes', ['unauthorized']),
        ),
      );
    });

    test('402, 404 and 422 map to their own types', () async {
      Future<void> check(int status, Matcher matcher) async {
        final fake = FakeTransport([
          HttpResponse(
              status: status, headers: const {}, body: '{"errors":[]}'),
        ]);
        await expectLater(_client(fake).getVerification('v'), throwsA(matcher));
      }

      await check(402, isA<BalanceInsufficientException>());
      await check(404, isA<NotFoundException>());
      await check(422, isA<ValidationException>());
    });

    test('an unmapped status is still a usable answer', () async {
      final fake = FakeTransport([
        HttpResponse(status: 418, headers: const {}, body: '{"errors":[]}'),
      ]);
      await expectLater(
        _client(fake).getVerification('v'),
        throwsA(
          isA<ApiException>().having((e) => e.status, 'status', 418),
        ),
      );
    });

    test('a 5xx is retried on a read and then surfaces', () async {
      final fake = FakeTransport([
        HttpResponse(status: 503, headers: const {}, body: '{"errors":[]}'),
      ]);
      final client = _client(
        fake,
        config: const ClientConfig(
          retry: RetryPolicy(attempts: 2, baseDelay: Duration.zero),
        ),
      );
      await expectLater(
        client.getVerification('v'),
        throwsA(isA<ServerException>()),
      );
      expect(fake.callCount, 2);
    });
  });

  group('logging', () {
    test('a by-number path is redacted', () async {
      final lines = <String>[];
      final fake = FakeTransport.json(_verification());
      final client =
          _client(fake, config: ClientConfig(logger: _Recorder(lines)));

      await client.getVerificationByNumber('+49 151 1234567');

      expect(lines.single, contains('[12 digits]'));
      expect(lines.single, isNot(contains('491511234567')));
    });
  });
}

final class _Recorder implements VerificationLogger {
  _Recorder(this.lines);
  final List<String> lines;

  @override
  void log(String line) => lines.add(line);
}
