@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Drives the client against the committed wire snapshot.
///
/// `vocabulary_test.dart` covers the snapshot's enumerations. This covers the
/// rest of it — the routes, the base URLs, the authorization headers, the status
/// mapping, the request bodies and the envelopes — none of which any other test
/// reads the snapshot for, so until now they could drift from it silently.
Map<String, dynamic> _contract() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    final file = File('${dir.path}/contract/wire_contract.json');
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
    dir = dir.parent;
  }
  throw StateError('contract/wire_contract.json not found');
}

void main() {
  final contract = _contract();
  final basePaths = contract['basePaths'] as Map<String, dynamic>;
  final routes = (contract['routes'] as List).cast<Map<String, dynamic>>();
  final prefix = basePaths['apiPrefix'] as String;

  ({VerificationClient client, FakeTransport transport}) clientWith({
    Authorization auth = const PublicAuthorization('key'),
    int status = 200,
    String? body,
  }) {
    final transport = FakeTransport([
      HttpResponse(
        status: status,
        headers: const {'content-type': 'application/json'},
        body: body ?? verificationJson(),
      ),
    ]);
    final client = VerificationClient(
      auth: auth,
      environment:
          VerificationEnvironment.custom(Uri.parse('https://api.test')),
      transport: transport.call,
      config: const ClientConfig(retry: RetryPolicy.none()),
    );
    addTearDown(client.close);
    return (client: client, transport: transport);
  }

  /// Every operation the snapshot names, keyed by its `op`.
  final operations = <String, Future<void> Function(VerificationClient)>{
    'start': (client) => client.startVerification(
          destination: '+49 151 1234567',
          deliveryMethod: DeliveryMethod.sms,
        ),
    'statusById': (client) => client.getVerification('ver-1'),
    'reportById': (client) => client.reportVerification(
          'ver-1',
          deliveryMethod: 'sms',
          value: const ReportValue.code('123456'),
        ),
    'statusByNumber': (client) =>
        client.getVerificationByNumber('+49 151 1234567'),
    'reportByNumber': (client) => client.reportVerificationByNumber(
          '+49 151 1234567',
          deliveryMethod: 'sms',
          value: const ReportValue.code('123456'),
        ),
  };

  group('the routes are the ones the snapshot records', () {
    test('every recorded operation is exercised here', () {
      expect(
        operations.keys.toSet(),
        {for (final route in routes) route['op'] as String},
        reason: 'a route added to the snapshot needs a call here to check it',
      );
    });

    for (final route in routes) {
      final op = route['op'] as String;

      test('$op is ${route['method']} ${route['path']}', () async {
        final fixture = clientWith(status: route['success'] as int);
        await operations[op]!(fixture.client);

        final request = fixture.transport.requests.single;
        expect(request.method, route['method']);
        // The id and the number are per-call, so the shape is compared with
        // those segments put back.
        expect(
          request.path
              .replaceAll('ver-1', '{id}')
              .replaceAll('491511234567', '{number}'),
          route['path'],
        );
        expect(request.path, startsWith(prefix));
      });
    }

    test('a PUT is what report sends, though the API also accepts PATCH', () {
      for (final route in routes.where((r) => r.containsKey('alsoAccepts'))) {
        expect(route['method'], 'PUT');
        expect((route['alsoAccepts'] as List).cast<String>(), ['PATCH']);
      }
    });
  });

  group('the base URLs are the ones the snapshot records', () {
    test('production', () {
      expect(
        VerificationEnvironment.production.baseUrl.toString(),
        basePaths['production'],
      );
    });

    test('sandbox', () {
      expect(
        VerificationEnvironment.sandbox.baseUrl.toString(),
        basePaths['sandbox'],
      );
    });

    test('the version prefix is appended by the SDK, not by the caller',
        () async {
      final fixture = clientWith();
      await fixture.client.getVerification('ver-1');

      expect(fixture.transport.requests.single.url.toString(),
          'https://api.test$prefix/verifications/ver-1');
    });
  });

  group('the authorization header matches the dispatch table', () {
    final dispatch =
        ((contract['authSchemes'] as Map<String, dynamic>)['dispatch'] as List)
            .cast<Map<String, dynamic>>();

    Map<String, Object> schemeFor(String mode) =>
        dispatch.firstWhere((entry) => entry['mode'] == mode).cast();

    test('public sends the key with nothing appended', () async {
      expect(schemeFor('public')['inScope'], isTrue);

      final fixture = clientWith(auth: const PublicAuthorization('app-key'));
      await fixture.client.getVerification('ver-1');

      final header =
          fixture.transport.requests.single.headers['Authorization']!;
      expect(header, 'Application app-key');
      // The snapshot's warning: a colon anywhere after the prefix selects the
      // signed scheme, which this release cannot satisfy.
      expect(header.substring('Application '.length), isNot(contains(':')));
    });

    test('basic sends base64 of key:secret', () async {
      expect(schemeFor('basic')['inScope'], isTrue);

      final fixture = clientWith(
        auth: const BasicAuthorization(key: 'k', secret: 's'),
      );
      await fixture.client.getVerification('ver-1');

      final header =
          fixture.transport.requests.single.headers['Authorization']!;
      expect(header, startsWith('Basic '));
      expect(utf8.decode(base64.decode(header.substring(6))), 'k:s');
    });

    test('the signed scheme is out of scope and has no implementation', () {
      expect(schemeFor('application')['inScope'], isFalse);
    });
  });

  group('a status the snapshot names becomes the code it names', () {
    final statusCodes = (contract['statusCodes'] as Map<String, dynamic>)
        .map((key, value) => MapEntry(int.parse(key), value as String));

    for (final entry in statusCodes.entries) {
      // 422 carries whichever validation slug applies, so the snapshot names no
      // single code for it and there is nothing here to pin.
      if (entry.key == 422) continue;

      test('${entry.key} is ${entry.value}', () async {
        final fixture = clientWith(
          status: entry.key,
          body: errorsJson([entry.value]),
        );

        await expectLater(
          fixture.client.getVerification('ver-1'),
          throwsA(
            isA<ApiException>().having(
              (error) => error.errors.single.code,
              'code',
              entry.value,
            ),
          ),
        );
      });
    }
  });

  group('the request bodies carry the fields the snapshot records', () {
    final requestFields = contract['requestFields'] as Map<String, dynamic>;

    test('start', () async {
      final fixture = clientWith(status: 201);
      await fixture.client.startVerification(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.sms,
        sms: const SmsOptions(languages: ['en-US']),
      );

      final data = fixture.transport.bodyAt(0)['data'] as Map<String, dynamic>;
      final expected =
          ((requestFields['start'] as Map<String, dynamic>)['data'] as List)
              .cast<String>();

      expect(expected, contains('destination'));
      expect(expected, contains('delivery_method'));
      expect(data.keys.toSet(), {'destination', 'delivery_method', 'sms'});
      // The channel block is named for the channel, which is what
      // "<delivery_method> block" records.
      expect(data['delivery_method'], 'sms');
      expect(data, contains(data['delivery_method']));
    });

    test('start on the callout channel names its block for the channel too',
        () async {
      final fixture = clientWith(status: 201);
      await fixture.client.startVerification(
        destination: '+49 151 1234567',
        deliveryMethod: DeliveryMethod.callout,
        callout: const CalloutOptions(languages: ['pt-BR', 'pt-PT']),
      );

      final data = fixture.transport.bodyAt(0)['data'] as Map<String, dynamic>;
      expect(data.keys.toSet(), {'destination', 'delivery_method', 'callout'});
      expect(data['delivery_method'], 'callout');
      expect(data, contains(data['delivery_method']));
      expect(
        (data['callout'] as Map<String, dynamic>)['languages'],
        ['pt-BR', 'pt-PT'],
      );
    });

    test('report', () async {
      final fixture = clientWith();
      await fixture.client.reportVerification(
        'ver-1',
        deliveryMethod: 'sms',
        value: const ReportValue.code('123456'),
      );

      final data = fixture.transport.bodyAt(0)['data'] as Map<String, dynamic>;
      expect(data.keys.toSet(), {'delivery_method', 'code'});
    });
  });

  group('the envelopes decode as the snapshot describes them', () {
    final envelopes = contract['envelopes'] as Map<String, dynamic>;

    test('every required success field survives the round trip', () async {
      final required =
          ((envelopes['success'] as Map<String, dynamic>)['required'] as List)
              .cast<String>();
      final fixture = clientWith();
      final verification = await fixture.client.getVerification('ver-1');

      final read = <String, Object?>{
        'id': verification.id,
        'destination': verification.destination,
        'delivery_method': verification.deliveryMethod,
        'fee': verification.fee,
        'status': verification.status,
        'error_code': verification.errorCode,
        'error_detail': verification.errorDetail,
        'expires_at': verification.expiresAt,
      };

      expect(read.keys.toSet(), required.toSet(),
          reason: 'a field added to the envelope needs a reader here');
      expect(verification.id, isNotEmpty);
      expect(verification.expiresAt.isUtc, isTrue);
    });

    test('an error element carries a code and a detail', () async {
      final fixture =
          clientWith(status: 422, body: errorsJson(['code_invalid']));

      await expectLater(
        fixture.client.getVerification('ver-1'),
        throwsA(
          isA<ApiException>().having((error) {
            final item = error.errors.single;
            return [item.code, item.detail];
          }, 'element', ['code_invalid', 'detail for code_invalid']),
        ),
      );
    });
  });

  group('the sms block behaves as the snapshot describes it', () {
    final smsBlock = contract['smsBlock'] as Map<String, dynamic>;

    test('it is present only for the channel the snapshot names', () async {
      expect(smsBlock['presentOnlyFor'], 'sms');

      final fixture = clientWith(
        body: verificationJson(deliveryMethod: 'callout', sms: false),
      );
      final verification = await fixture.client.getVerification('ver-1');

      expect(verification.sms, isNull);
    });

    test('the required members are read and the optional one may be absent',
        () async {
      expect(
        (smsBlock['required'] as List).cast<String>(),
        ['template', 'language', 'interception_timeout'],
      );
      expect((smsBlock['optional'] as List).cast<String>(), ['app_hash']);

      final fixture = clientWith(body: verificationJson());
      final verification = await fixture.client.getVerification('ver-1');

      expect(verification.sms?.template, isNotNull);
      expect(verification.sms?.language, isNotNull);
      expect(verification.sms?.interceptionTimeoutSeconds, isNotNull);
      expect(verification.sms?.appHash, isNull);
    });
  });

  group('the callout block behaves as the snapshot describes it', () {
    final calloutBlock = contract['calloutBlock'] as Map<String, dynamic>;

    test('it is present only for the channel the snapshot names', () async {
      expect(calloutBlock['presentOnlyFor'], 'callout');

      final fixture = clientWith(
        body: verificationJson(deliveryMethod: 'sms', sms: false),
      );
      final verification = await fixture.client.getVerification('ver-1');

      expect(verification.callout, isNull);
      expect(verification.sms, isNull);
    });

    test('the required member is read and there are no optional ones',
        () async {
      expect((calloutBlock['required'] as List).cast<String>(), ['language']);
      expect(calloutBlock['optional'], isEmpty);

      final fixture = clientWith(
        body: verificationJson(
          deliveryMethod: 'callout',
          sms: false,
          callout: true,
          language: 'pt-BR',
        ),
      );
      final verification = await fixture.client.getVerification('ver-1');

      expect(verification.callout?.language, 'pt-BR');
    });
  });

  group('the constraints the snapshot records are the ones compiled in', () {
    final constraints = contract['constraints'] as Map<String, dynamic>;

    test('the app hash format is the snapshot`s, character for character', () {
      expect(appHashFormat.pattern, constraints['appHashFormat']);
    });

    test('the destination is sent as digits, so the echo can be compared',
        () async {
      expect(constraints['destinationEcho'], contains('DIGITS-ONLY'));

      final fixture = clientWith(status: 201);
      await fixture.client.startVerification(
        destination: '+49 (151) 123-4567',
        deliveryMethod: DeliveryMethod.sms,
      );

      final data = fixture.transport.bodyAt(0)['data'] as Map<String, dynamic>;
      expect(data['destination'], '491511234567');
    });

    test('no code length and no attempt count are compiled in', () {
      // Both are server facts. The snapshot records them so the SDK can be
      // checked for having taken a copy, not so it can use them.
      final sources = Directory('lib/src')
          .listSync()
          .whereType<File>()
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(sources, isNot(contains('maxAttempts')));
      expect(sources, isNot(contains('codeLength')));
    });
  });
}
