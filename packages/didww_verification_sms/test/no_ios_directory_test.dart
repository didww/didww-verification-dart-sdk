import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the package declares Android and ships no ios/ directory', () {
    // iOS needs no plugin: one-time code autofill there is an autofillHints hint
    // on the application's own text field. The absence is a decision, so it is
    // asserted rather than left to be noticed.
    expect(Directory('ios').existsSync(), isFalse);

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('android:'));
    expect(pubspec, isNot(contains('ios:')));
  });
}
