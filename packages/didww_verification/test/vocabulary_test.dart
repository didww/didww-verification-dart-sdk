import 'dart:convert';
import 'dart:io';

import 'package:didww_verification/didww_verification.dart';
import 'package:test/test.dart';

/// The committed wire snapshot, found by walking up from the test's own
/// directory so the test works from the package or the workspace root.
Map<String, dynamic> _contract() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    final file = File('${dir.path}/contract/wire_contract.json');
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
    dir = dir.parent;
  }
  throw StateError(
    'contract/wire_contract.json not found from ${Directory.current.path}',
  );
}

List<String> _strings(Map<String, dynamic> contract, String key) =>
    (contract[key] as List).cast<String>();

void main() {
  final contract = _contract();

  group('the vocabulary matches the wire contract exactly', () {
    test('delivery methods', () {
      expect(
        DeliveryMethod.values.map((m) => m.wire).toList(),
        _strings(contract, 'deliveryMethods'),
      );
    });

    test('statuses', () {
      expect(
        VerificationStatus.values.map((s) => s.wire).toList(),
        _strings(contract, 'statuses'),
      );
    });

    test('error codes, in declaration order', () {
      expect(
        ApiErrorCode.values.map((c) => c.wire).toList(),
        _strings(contract, 'apiErrorCodes'),
      );
    });

    test('outcome codes', () {
      expect(
        ApiErrorCode.values
            .where((c) => c.isOutcome)
            .map((c) => c.wire)
            .toSet(),
        _strings(contract, 'verificationErrorCodes').toSet(),
      );
    });
  });

  group('decoding is open', () {
    test('an unknown value decodes to null rather than throwing', () {
      expect(DeliveryMethod.fromWire('telepathy'), isNull);
      expect(VerificationStatus.fromWire('pondering'), isNull);
      expect(ApiErrorCode.fromWire('code_we_have_never_heard_of'), isNull);
    });

    test('every known value round-trips', () {
      for (final m in DeliveryMethod.values) {
        expect(DeliveryMethod.fromWire(m.wire), m);
      }
      for (final s in VerificationStatus.values) {
        expect(VerificationStatus.fromWire(s.wire), s);
      }
      for (final c in ApiErrorCode.values) {
        expect(ApiErrorCode.fromWire(c.wire), c);
      }
    });
  });

  group('derived properties', () {
    test('only pending is not terminal', () {
      expect(VerificationStatus.pending.isTerminal, isFalse);
      for (final s in VerificationStatus.values
          .where((s) => s != VerificationStatus.pending)) {
        expect(s.isTerminal, isTrue, reason: '${s.wire} should be terminal');
      }
    });

    test('a request-rejection code is not an outcome', () {
      expect(ApiErrorCode.codeInvalid.isOutcome, isFalse);
      expect(ApiErrorCode.unauthorized.isOutcome, isFalse);
      expect(ApiErrorCode.tooManyAttempts.isOutcome, isTrue);
      expect(ApiErrorCode.superseded.isOutcome, isTrue);
    });
  });
}
