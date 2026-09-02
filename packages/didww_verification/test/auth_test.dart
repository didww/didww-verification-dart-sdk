import 'dart:convert';

import 'package:didww_verification/didww_verification.dart';
import 'package:test/test.dart';

const _anyRequest = AuthRequest(
  method: 'GET',
  path: '/api/v1/verifications/x',
  contentType: '',
  body: '',
);

void main() {
  group('public authorization', () {
    test('carries the plain key', () {
      const auth = PublicAuthorization('9f1c-key');
      expect(
        auth.headers(_anyRequest),
        {'Authorization': 'Application 9f1c-key'},
      );
    });

    test('appends nothing after the key', () {
      const auth = PublicAuthorization('9f1c-key');
      final value = auth.headers(_anyRequest)['Authorization']!;
      // A colon anywhere after the prefix selects the signed scheme, which this
      // release cannot satisfy — the request would be rejected, not downgraded.
      expect(value.substring('Application '.length), isNot(contains(':')));
    });
  });

  group('basic authorization', () {
    test('is base64 of key:secret', () {
      const auth = BasicAuthorization(key: 'key', secret: 'secret');
      expect(
        auth.headers(_anyRequest),
        {'Authorization': 'Basic ${base64.encode(utf8.encode('key:secret'))}'},
      );
    });

    test('encodes a non-ASCII secret over UTF-8 bytes', () {
      const auth = BasicAuthorization(key: 'key', secret: 'sécrét-ß-日本');
      final value = auth.headers(_anyRequest)['Authorization']!;
      final decoded =
          utf8.decode(base64.decode(value.substring('Basic '.length)));
      expect(decoded, 'key:sécrét-ß-日本');
    });

    test('splits on the first colon only, so a secret may contain one', () {
      const auth = BasicAuthorization(key: 'key', secret: 'a:b:c');
      final value = auth.headers(_anyRequest)['Authorization']!;
      final decoded =
          utf8.decode(base64.decode(value.substring('Basic '.length)));
      expect(decoded.split(':').first, 'key');
      expect(decoded.substring('key:'.length), 'a:b:c');
    });
  });
}
