/// Digit runs of six or more replaced with their length.
///
/// A by-number request path carries the destination; six is a code's length.
String redactDigitRuns(String line) =>
    line.replaceAllMapped(RegExp(r'\d{6,}'), (m) => '[${m[0]!.length} digits]');
