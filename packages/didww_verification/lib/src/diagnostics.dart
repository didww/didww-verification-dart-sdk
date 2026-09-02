import 'dart:developer' as developer;

/// Emits a diagnostic in debug builds only.
///
/// `assert` throws, so it cannot carry a warning about a path that is supposed
/// to continue. The side-effect form runs the body in debug and vanishes in
/// release, which is what a warning needs.
void debugDiagnostic(String message) {
  assert(() {
    developer.log(message, name: 'didww_verification');
    return true;
  }());
}
