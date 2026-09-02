import 'package:didww_verification_sms/didww_verification_sms.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the running build reports a well-formed app hash',
      (tester) async {
    final hash = await getAppHash();

    if (defaultTargetPlatform != TargetPlatform.android) {
      expect(hash, isNull);
      return;
    }

    // The alphabet and length the API accepts. A hash outside them is rejected
    // by the API, which fails the whole verification rather than only capture.
    expect(hash, matches(RegExp(r'^[A-Za-z0-9+/]{11}$')));
  });

  testWidgets('package version is reported', (tester) async {
    expect(smsPackageVersion, '1.0.0');
  });
}
