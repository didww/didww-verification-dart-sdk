/// Fails if anything internal appears anywhere in this repository.
///
/// Scans the working tree, not the package archives: `contract/`,
/// `docs/`, `tool/` and the example are as public as `lib/`.
///
/// The vocabulary lives in a file rather than here — holding it inline would
/// make the guard itself the leak. Without that file only the terms that can be
/// named in public are checked; `--public` additionally fails while `internal/`
/// is still present.
library;

import 'dart:io';

/// Checks that name nothing internal, so they can live in a public file.
final List<_Term> _publicTerms = [
  // Deliberately the only one. A generic ticket-key shape belongs in the list
  // too, because anchoring it needs the project's own prefix — and unanchored
  // it matches UTF-8, SHA-256 and RFC-4231.
  _Term(
    'a private hostname',
    RegExp(r'\b[A-Za-z0-9-]+\.in\.didww\.com\b', caseSensitive: false),
  ),
];

const String defaultTermsPath = 'internal/forbidden-terms.txt';

const Set<String> skippedDirectories = {
  '.git',
  '.dart_tool',
  '.gradle',
  '.idea',
  'build',
  '.omc',
  'Pods',
  '.symlinks',
  'internal',
};

const Set<String> skippedExtensions = {
  '.png', '.jpg', '.jpeg', '.gif', '.ico', '.webp', //
  '.jar', '.zip', '.apk', '.aab', '.keystore', '.jks',
  '.ttf', '.otf', '.woff', '.woff2',
  '.so', '.dylib', '.a', '.bin',
};

void main(List<String> arguments) {
  final public = arguments.contains('--public');
  final termsPath = _option(arguments, '--terms') ?? defaultTermsPath;
  final termsFile = File(termsPath);

  final terms = [..._publicTerms];
  if (termsFile.existsSync()) {
    terms.addAll(_parse(termsFile.readAsLinesSync()));
    stdout.writeln('${terms.length} terms, from $termsPath');
  } else {
    // Said out loud every run. A guard quietly checking less than it used to is
    // worse than one that is absent, because the job still reports green.
    stdout.writeln(
      'NO TERM LIST at $termsPath — private hostnames only; ticket keys and\n'
      'every other listed term are NOT checked',
    );
  }

  final root = Directory.current;
  final failures = <String>[];
  var scanned = 0;

  for (final file in _files(root)) {
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      continue;
    } on FormatException {
      continue; // Not text after all.
    }
    scanned++;

    final relative = file.path.replaceFirst('${root.path}/', '');
    for (final term in terms) {
      final found = term.findIn(text);
      if (found != null) failures.add('$relative: $found (${term.label})');
    }
  }

  stdout.writeln('scanned $scanned files; internal/ is never scanned');

  if (public && Directory('internal').existsSync()) {
    failures.add(
      'internal/ is still present — it must be deleted before the public push',
    );
  }

  if (failures.isEmpty) {
    stdout.writeln('no internal information found');
    return;
  }

  stderr.writeln('\ninternal information found:');
  for (final failure in failures) {
    stderr.writeln('  $failure');
  }
  exitCode = 1;
}

String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}

List<_Term> _parse(List<String> lines) {
  final terms = <_Term>[];
  for (final line in lines) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith('#')) continue;

    if (text.startsWith('re:')) {
      terms.add(
        _Term('a listed pattern',
            RegExp(text.substring(3), caseSensitive: false)),
      );
    } else if (text.startsWith('word:')) {
      terms.add(
        _Term(
          'a listed term',
          RegExp('\\b${RegExp.escape(text.substring(5))}\\b',
              caseSensitive: false),
        ),
      );
    } else {
      terms.add(
        _Term(
            'a listed term', RegExp(RegExp.escape(text), caseSensitive: false)),
      );
    }
  }
  return terms;
}

final class _Term {
  _Term(this.label, this.pattern);

  final String label;
  final RegExp pattern;

  String? findIn(String text) => pattern.firstMatch(text)?.group(0);
}

Iterable<File> _files(Directory root) sync* {
  for (final entity in root.listSync()) {
    final name =
        entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
    if (entity is Directory) {
      if (skippedDirectories.contains(name)) continue;
      yield* _files(entity);
    } else if (entity is File) {
      final dot = name.lastIndexOf('.');
      if (skippedExtensions.contains(dot < 0 ? '' : name.substring(dot))) {
        continue;
      }
      yield entity;
    }
  }
}
