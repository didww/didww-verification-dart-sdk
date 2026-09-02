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

    test('leaves short runs alone', () {
      expect(redactDigitRuns('HTTP/1.1 201 in 42ms'), 'HTTP/1.1 201 in 42ms');
    });
  });
}
