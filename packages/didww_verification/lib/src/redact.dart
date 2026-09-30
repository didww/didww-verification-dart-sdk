/// Canonical UUIDs only, hyphens required — a bare hex blob is not an identifier here.
final _uuid = RegExp(
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
  caseSensitive: false,
);

final _digitRun = RegExp(r'\d{4,}');

/// Digit runs of four or more replaced with their length, outside a UUID.
///
/// A by-number request path carries the destination and a code is 4–8 digits, server-chosen;
/// an id is neither, and half-masking one leaves a token that no longer equals any record.
String redactDigitRuns(String line) => line.splitMapJoin(
      _uuid,
      onMatch: (m) => m[0]!,
      onNonMatch: (segment) => segment.replaceAllMapped(
        _digitRun,
        (m) => '[${m[0]!.length} digits]',
      ),
    );
