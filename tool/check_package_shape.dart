/// Fails if a published package's shape stops matching what was decided.
///
/// Both checks guard a decision that is invisible in the code that uses it: a
/// `path:` dependency publishes an unresolvable package, and an `ios/` directory
/// turns an Android-only plugin into one that claims a platform it cannot serve.
library;

import 'dart:io';

const List<String> publishedPackages = [
  'packages/didww_verification',
  'packages/didww_verification_sms',
];

const String plugin = 'packages/didww_verification_sms';

void main() {
  final failures = [..._noPathDependencies(), ..._noIosDirectory()];

  if (failures.isEmpty) {
    stdout.writeln('both packages are shaped as published packages');
    return;
  }
  stderr.writeln('\npackage shape guard failed:');
  for (final failure in failures) {
    stderr.writeln('  $failure');
  }
  exitCode = 1;
}

/// A `path:` dependency resolves for whoever committed it and for nobody else.
///
/// Matched on the value rather than the key, because `path` is also an ordinary
/// package name and `path: ^1.9.0` is a version constraint, not a location.
List<String> _noPathDependencies() {
  final failures = <String>[];
  final location = RegExp(r'^\s+path:\s*(\S.*)$');

  for (final package in publishedPackages) {
    final lines = File('$package/pubspec.yaml').readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final value = location.firstMatch(lines[i])?.group(1);
      if (value == null) continue;
      if (RegExp(r'^[\d^>=<~]').hasMatch(value)) continue; // A version.
      failures.add('$package/pubspec.yaml:${i + 1} depends on a path: $value');
    }
  }
  return failures;
}

/// iOS needs no plugin: one-time code autofill there is an `autofillHints` hint
/// on the application's own text field.
List<String> _noIosDirectory() {
  if (!Directory('$plugin/ios').existsSync()) return const [];
  return ['$plugin/ios exists; the plugin is Android-only by decision'];
}
