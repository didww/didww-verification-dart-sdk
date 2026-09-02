import 'dart:convert';
import 'dart:io';

/// The wire snapshot, read at startup.
///
/// The mock owns no vocabulary of its own: paths, channels, statuses, error codes
/// and their prose all come from `contract/wire_contract.json`, so the mock and the
/// client cannot drift apart without the parity test going red.
final class WireContract {
  WireContract._(this._root);

  /// Reads the snapshot at [path].
  factory WireContract.load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('wire contract not found', path);
    }
    final root = jsonDecode(file.readAsStringSync());
    if (root is! Map<String, dynamic>) {
      throw FormatException('wire contract is not a JSON object', path);
    }
    return WireContract._(root);
  }

  final Map<String, dynamic> _root;

  /// The path prefix every route sits under, e.g. `/api/v1`.
  String get apiPrefix =>
      (_root['basePaths'] as Map)['apiPrefix'] as String? ?? '/api/v1';

  /// The channels a verification can be started on.
  List<String> get deliveryMethods =>
      (_root['deliveryMethods'] as List).cast<String>();

  /// The statuses a verification is reported with.
  List<String> get statuses => (_root['statuses'] as List).cast<String>();

  /// Every coded error, raw.
  List<String> get apiErrorCodes =>
      (_root['apiErrorCodes'] as List).cast<String>();

  /// The alphabet and length the API accepts for an app hash.
  RegExp get appHashFormat => RegExp(
        (_root['constraints'] as Map)['appHashFormat'] as String,
      );

  /// How many values may be reported before the verification fails.
  int get maxReportAttempts =>
      ((_root['constraints'] as Map)['maxReportAttempts'] as Map)['value']
          as int;

  /// The fixed prose for [code].
  ///
  /// Unknown here is a programming error rather than a client-facing one: every
  /// code the mock emits is one it read out of the snapshot.
  String detail(String code) {
    final detail = (_root['errorDetails'] as Map)[code];
    if (detail is! String) {
      throw ArgumentError.value(code, 'code', 'not in the wire contract');
    }
    return detail;
  }
}
