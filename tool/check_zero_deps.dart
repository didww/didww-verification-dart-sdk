/// Fails if `didww_verification` acquires a runtime dependency.
///
/// Two checks, because they catch different things. The manifest read catches a
/// dependency someone typed. The resolution catches one that arrived without
/// anyone typing it, which is the failure that would otherwise reach a release.
library;

import 'dart:convert';
import 'dart:io';

const String package = 'packages/didww_verification';

void main() {
  final failures = [
    ..._manifestHasNoDependencies(),
    ..._resolvesToItselfAlone()
  ];

  if (failures.isEmpty) {
    stdout.writeln('didww_verification has no runtime dependency');
    return;
  }
  stderr.writeln('\nzero-dependency guard failed:');
  for (final failure in failures) {
    stderr.writeln('  $failure');
  }
  exitCode = 1;
}

/// The `dependencies:` key must be absent, not merely empty.
///
/// Scoped to a line starting at column zero, so `dev_dependencies:` — which is
/// exempt, and holds the test and lint packages — cannot satisfy or break it.
List<String> _manifestHasNoDependencies() {
  final lines = File('$package/pubspec.yaml').readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimRight() == 'dependencies:') {
      return ['$package/pubspec.yaml:${i + 1} declares a dependencies: key'];
    }
  }
  return const [];
}

/// A project depending only on this package must resolve to it and nothing else.
///
/// Run against a copy with `resolution: workspace` removed, because inside the
/// workspace every member is resolved anyway and the question would answer
/// itself.
List<String> _resolvesToItselfAlone() {
  final scratch = Directory.systemTemp.createTempSync('didww_zero_deps');
  try {
    final copy = Directory('${scratch.path}/didww_verification')..createSync();
    _copyInto(Directory(package), copy);

    final manifest = File('${copy.path}/pubspec.yaml');
    manifest.writeAsStringSync(
      manifest
          .readAsLinesSync()
          .where((line) => line.trim() != 'resolution: workspace')
          .join('\n'),
    );

    File('${scratch.path}/pubspec.yaml').writeAsStringSync('''
name: zero_deps_probe
publish_to: none
environment:
  sdk: ^3.6.0
dependencies:
  didww_verification:
    path: didww_verification
''');

    final result = Process.runSync(
      Platform.resolvedExecutable,
      ['pub', 'get'],
      workingDirectory: scratch.path,
    );
    if (result.exitCode != 0) {
      return [
        'a project depending only on the package fails to resolve:\n'
            '${result.stderr}'
      ];
    }

    final config = jsonDecode(
      File('${scratch.path}/.dart_tool/package_config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final resolved = {
      for (final entry in config['packages'] as List)
        (entry as Map<String, dynamic>)['name'] as String,
    };

    const expected = {'zero_deps_probe', 'didww_verification'};
    final extra = resolved.difference(expected);
    if (extra.isEmpty) return const [];
    return ['resolving the package pulled in ${extra.join(', ')}'];
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

void _copyInto(Directory from, Directory to) {
  for (final entity in from.listSync()) {
    final name =
        entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
    if (const {'.dart_tool', 'build', '.omc'}.contains(name)) continue;

    if (entity is Directory) {
      final child = Directory('${to.path}/$name')..createSync();
      _copyInto(entity, child);
    } else if (entity is File) {
      entity.copySync('${to.path}/$name');
    }
  }
}
