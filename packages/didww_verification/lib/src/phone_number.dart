/// Every non-digit removed, or `null` when nothing is left.
///
/// The form the API stores, echoes and expects in a by-number path. Its own
/// validator strips only whitespace, hyphens and parentheses, so normalising
/// here is what makes any user formatting acceptable.
String? digitsOf(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? null : digits;
}
