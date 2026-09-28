import 'package:didww_verification/didww_verification.dart';
// Not exported: an internal logging helper with a very collidable name.
import 'package:didww_verification/src/redact.dart';
import 'package:test/test.dart';

void main() {
  group('digitsOf', () {
    test('strips the leading plus, spaces, hyphens and parentheses', () {
      expect(digitsOf('+49 (151) 1234-567'), '491511234567');
    });

    test('strips separators the API validator would reject outright', () {
      // The API strips only whitespace, hyphens and parentheses before
      // validating, so a dot-formatted number fails there. Normalising here is
      // what makes it acceptable.
      expect(digitsOf('+49.151.1234567'), '491511234567');
    });

    test('is idempotent on an already normalised number', () {
      expect(digitsOf('491511234567'), '491511234567');
    });

    test('returns null when nothing is left', () {
      expect(digitsOf('+-- ()'), isNull);
      expect(digitsOf(''), isNull);
    });
  });

  group('redactDigitRuns', () {
    test('hides a destination in a path', () {
      expect(
        redactDigitRuns('GET /api/v1/verifications/by_number/491511234567'),
        'GET /api/v1/verifications/by_number/[12 digits]',
      );
    });

    test('hides a one-time code', () {
      expect(redactDigitRuns('code=123456'), 'code=[6 digits]');
    });

    test('hides a code at every server-chosen length', () {
      for (final length in [4, 5, 6, 7, 8]) {
        final code = '7' * length;
        expect(redactDigitRuns('code=$code'), 'code=[$length digits]');
      }
    });

    test('a UUID passes through intact', () {
      const id = '0198f3c2-7a41-71ce-8f21-419283746501';
      expect(
        redactDigitRuns('GET /api/v1/verifications/$id -> 200'),
        'GET /api/v1/verifications/$id -> 200',
      );
    });

    test('a code and a destination are still hidden alongside a UUID', () {
      const id = '0198f3c2-7a41-71ce-8f21-419283746501';
      expect(
        redactDigitRuns('id $id code 1234 long 12345678 to 491511234567'),
        'id $id code [4 digits] long [8 digits] to [12 digits]',
      );
    });

    test('a code adjacent to a UUID is still hidden', () {
      const id = '0198f3c2-7a41-71ce-8f21-419283746501';
      expect(redactDigitRuns('$id/1234'), '$id/[4 digits]');
    });

    test('a bare hex blob is not a UUID', () {
      expect(
        redactDigitRuns('blob 0198f3c27a4171ce8f21419283746501'),
        'blob [4 digits]f3c27a[4 digits]ce8f[14 digits]',
      );
    });

    test('leaves short runs alone', () {
      expect(redactDigitRuns('HTTP/1.1 201 in 42ms'), 'HTTP/1.1 201 in 42ms');
    });
  });
}
