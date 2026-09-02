import 'package:didww_verification/didww_verification.dart';
import 'package:test/test.dart';

void main() {
  group('extractCode', () {
    test('recovers the code from a delivered message', () {
      expect(
        extractCode('Your code is {{CODE}}', 'Your code is 123456'),
        '123456',
      );
    });

    test('a retriever-shaped body with the hash appended still matches', () {
      // What the platform actually hands over: the prefix, the rendered
      // template, then the app hash on its own line.
      expect(
        extractCode(
          'Your code is {{CODE}}',
          '<#> Your code is 123456\nA1b2C3d4E5f',
        ),
        '123456',
      );
    });

    test('the appended app hash is not swallowed', () {
      final code = extractCode(
        'Your code is {{CODE}}',
        '<#> Your code is 123456\nA1b2C3d4E5f',
      );

      // The trap `(.+)` falls into: it matches to the end of the body and the
      // SDK submits the code with the hash stuck to it, which the API rejects
      // and which costs the user an attempt.
      expect(code, isNot(contains('A1b2C3d4E5f')));
      expect(code, matches(RegExp(r'^\d+$')));
    });

    test('a template with punctuation around the code still matches', () {
      // The reason RegExp.escape is used rather than a Kotlin `\Q…\E` port:
      // Dart reads `\Q` as a literal Q and this stops matching entirely.
      expect(
        extractCode(
          '[DIDWW] Kod: {{CODE}} (waz.ny 5 min)',
          '<#> [DIDWW] Kod: 907711 (waz.ny 5 min)\nA1b2C3d4E5f',
        ),
        '907711',
      );
    });

    test('regex metacharacters in the template are literals, not patterns', () {
      // If the halves were not quoted, `.` would match any character and this
      // body would produce a code from a message that is not ours.
      expect(
        extractCode('a.c {{CODE}}', 'abc 123456'),
        isNull,
      );
      expect(
        extractCode('a.c {{CODE}}', 'a.c 123456'),
        '123456',
      );
    });

    test('a template with no placeholder returns null', () {
      expect(extractCode('Your code was sent', 'Your code was sent'), isNull);
    });

    test('a null template returns null', () {
      expect(extractCode(null, '<#> Your code is 123456'), isNull);
    });

    test('a body that does not contain the template returns null', () {
      expect(
        extractCode('Your code is {{CODE}}', 'Your parcel is out for delivery'),
        isNull,
      );
    });

    test('a body with no digits where the code goes returns null', () {
      expect(extractCode('Your code is {{CODE}}', 'Your code is soon'), isNull);
    });

    test('a placeholder at the start of the template still matches', () {
      expect(extractCode('{{CODE}} is your code', '654321 is your code'),
          '654321');
    });

    test('the code length is not compiled in', () {
      // A server fact, never a client one: a template that renders eight digits
      // one day must not stop working.
      expect(extractCode('code {{CODE}}', 'code 12345678'), '12345678');
      expect(extractCode('code {{CODE}}', 'code 1234'), '1234');
    });

    test('a trailing template segment is required to be present', () {
      expect(
        extractCode('code {{CODE}} thanks', '<#> code 123456 thanks\nHASH'),
        '123456',
      );
      expect(
          extractCode('code {{CODE}} thanks', '<#> code 123456\nHASH'), isNull);
    });
  });
}
