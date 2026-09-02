/// Automatic code capture.
///
/// Implemented by `didww_verification_sms`; this package never depends on it.
/// Supply your own to bring a different capture mechanism.
abstract interface class SmsAutoCapture {
  /// The 11-character app hash for this build, or null when it cannot be
  /// computed or the platform has no automatic capture.
  ///
  /// Report a malformed value as null. The session re-checks the format anyway
  /// and drops a bad one rather than failing a paid verification with it.
  Future<String?> appHash();

  /// Raw message bodies the platform hands over.
  ///
  /// Listening arms the platform listener; cancelling the subscription disarms
  /// it. Returns the same stream instance on every call.
  Stream<String> messages();
}

/// The placeholder the API leaves in a template where the code goes.
const String codePlaceholder = '{{CODE}}';

/// Recovers the code from [body] by turning the server's own [template] into a
/// pattern. Returns null when there is nothing to match.
///
/// Captures the digit run, not everything after the prefix: the message carries
/// the app hash on its own line, and a greedy match would submit both.
String? extractCode(String? template, String body) {
  if (template == null) return null;

  final at = template.indexOf(codePlaceholder);
  if (at < 0) return null;

  // RegExp.escape, never Kotlin's: `\Q…\E` reads as a literal `Q` here.
  final before = RegExp.escape(template.substring(0, at));
  final after = RegExp.escape(template.substring(at + codePlaceholder.length));

  return RegExp('$before(\\d+)$after').firstMatch(body)?.group(1);
}
