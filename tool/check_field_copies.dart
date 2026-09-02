// Checks that every field of a class is named by the function that rebuilds it.
//
// Those functions copy field by field, so a field added to one of these classes
// and forgotten in its copier compiles, passes the whole suite, and is silently
// null at runtime forever. That is the one failure mode a new response field is
// most likely to hit, and nothing else in the tree catches it.
//
// It matches on the field's NAME, so it catches a field nothing carries — not a
// field dropped from one of two copiers that share a name, as the two channel
// blocks in `startBody` do. The wire tests cover that direction.
//
//   dart run tool/check_field_copies.dart

import 'dart:io';

const _client = 'packages/didww_verification/lib/src';

/// A class and the function that has to mention every one of its fields.
final class _Copy {
  const _Copy({
    required this.type,
    required this.typeFile,
    required this.function,
    required this.functionFile,
    this.except = const {},
  });

  final String type;
  final String typeFile;
  final String function;
  final String functionFile;

  /// Fields this copier drops on purpose. Each one has to stay dropped: an
  /// exception that no longer applies is reported rather than ignored, so the
  /// list cannot quietly outlive its reason.
  final Set<String> except;
}

const _copies = [
  _Copy(
    type: 'VerificationAwaitingInput',
    typeFile: '$_client/state.dart',
    function: 'withError',
    functionFile: '$_client/state.dart',
  ),
  _Copy(
    type: 'Verification',
    typeFile: '$_client/models.dart',
    function: 'decodeVerification',
    functionFile: '$_client/wire.dart',
  ),
  _Copy(
    type: 'SmsInfo',
    typeFile: '$_client/models.dart',
    function: '_decodeSms',
    functionFile: '$_client/wire.dart',
  ),
  _Copy(
    type: 'CalloutInfo',
    typeFile: '$_client/models.dart',
    function: '_decodeCallout',
    functionFile: '$_client/wire.dart',
  ),
  _Copy(
    type: 'SmsOptions',
    typeFile: '$_client/options.dart',
    function: 'startBody',
    functionFile: '$_client/wire.dart',
  ),
  _Copy(
    type: 'CalloutOptions',
    typeFile: '$_client/options.dart',
    function: 'startBody',
    functionFile: '$_client/wire.dart',
  ),
  _Copy(
    type: 'Verification',
    typeFile: '$_client/models.dart',
    function: 'awaitingInputFor',
    functionFile: '$_client/machine.dart',
    // A live state is the one the verification is NOT finished in, so what
    // finished it has no place in it: those three pick the terminal state.
    except: {'status', 'errorCode', 'errorDetail'},
  ),
];

void main() {
  final failures = <String>[];
  var checked = 0;

  for (final copy in _copies) {
    final fields = _fieldsOf(_bodyOfClass(_read(copy.typeFile), copy.type));
    if (fields.isEmpty) {
      failures.add('no fields found on ${copy.type} — has it been renamed?');
      continue;
    }

    final body = _bodyOfFunction(_read(copy.functionFile), copy.function);
    for (final field in fields) {
      checked++;
      final named = RegExp('\\b$field\\b').hasMatch(body);
      if (!named && !copy.except.contains(field)) {
        failures.add(
          '${copy.type}.$field is never named in ${copy.function} '
          '(${copy.functionFile}), so it is dropped',
        );
      }
      if (named && copy.except.contains(field)) {
        failures.add(
          '${copy.type}.$field IS named in ${copy.function}, so listing it '
          'under `except` is stale — drop the exception',
        );
      }
    }
  }

  print('${_copies.length} copiers, $checked fields');
  if (failures.isEmpty) {
    print('every field is carried by its copier');
    return;
  }
  print('\nfields dropped by their copier:');
  for (final failure in failures) {
    print('  $failure');
  }
  exitCode = 1;
}

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('$path is missing');
    exit(1);
  }
  return file.readAsStringSync();
}

/// The instance field names declared directly on the class, in order.
Iterable<String> _fieldsOf(String classBody) => RegExp(
      r'^  final [\w<>?, ]+ (\w+);$',
      multiLine: true,
    ).allMatches(classBody).map((match) => match.group(1)!);

String _bodyOfClass(String source, String type) {
  final start = source.indexOf(RegExp('class $type\\b'));
  if (start < 0) return '';
  return _balanced(source, source.indexOf('{', start));
}

/// The function's body, parameter list included.
///
/// Anchored on the declaration — a return type, then the name — because the
/// unanchored name matches a call site first, and scanning from there silently
/// swallows the rest of the file and passes whatever it was meant to catch.
String _bodyOfFunction(String source, String name) {
  final declaration = source.indexOf(
      RegExp(r'^\s*[\w<>?,\[\] ]+ ' '$name' r'\s*\(', multiLine: true));
  if (declaration < 0) {
    stderr.writeln('$name is not declared — has it been renamed?');
    exit(1);
  }

  final open = source.indexOf('(', declaration);
  final params = _balanced(source, open);
  var cursor = open + params.length;
  while (cursor < source.length && source[cursor].trim().isEmpty) {
    cursor++;
  }

  // An arrow body runs to its `;`, a block body to its closing brace.
  if (source.startsWith('{', cursor)) return params + _balanced(source, cursor);
  return params + _upTo(source, cursor, ';');
}

const _pairs = {'(': ')', '{': '}', '[': ']'};

/// From [open] to its matching close, both included.
String _balanced(String source, int open) => _upTo(source, open, null);

/// From [from] to [stop] at nesting depth zero, or to where the nesting the
/// scan started inside closes. Either way the scan cannot outrun its own scope.
String _upTo(String source, int from, String? stop) {
  var depth = 0;
  for (var i = from; i < source.length; i++) {
    final char = source[i];
    if (_pairs.containsKey(char)) depth++;
    if (_pairs.containsValue(char)) {
      depth--;
      if (depth <= 0) return source.substring(from, i + 1);
    }
    if (char == stop && depth == 0) return source.substring(from, i + 1);
  }
  return source.substring(from);
}
