@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:didww_verification/didww_verification.dart';
import 'package:test/test.dart';

/// Drives the session against `tool/mock_api` over a real socket.
///
/// Every other session suite answers from a `FakeTransport`, which proves the
/// state machine against responses this repository wrote in Dart. This one puts
/// real JSON through a real HTTP client, so an encoding, header or routing fault
/// between the two layers has somewhere to show up.
final class _Mock {
  _Mock._(this._process, this.origin);

  final Process _process;

  /// The base URL the mock printed.
  final Uri origin;

  static File get script => File.fromUri(
        Directory.current.uri.resolve('../../tool/mock_api/bin/mock_api.dart'),
      );

  static Future<_Mock> start() async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['run', script.path, '--port', '0'],
    );

    final origin = Completer<Uri>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        // The origin only: the mock prints the API prefix too, and the client
        // appends its own.
        final match = RegExp(r'^mock api on (http://[^/]+)').firstMatch(line);
        if (match != null && !origin.isCompleted) {
          origin.complete(Uri.parse(match.group(1)!));
        }
      },
    );

    return _Mock._(
      process,
      await origin.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw StateError('the mock API did not start'),
      ),
    );
  }

  void stop() => _process.kill();
}

void main() {
  late _Mock mock;

  // tool/ lives outside the package, so it is not in the published archive.
  // Skipped rather than red there: its absence is expected, not a regression.
  if (!_Mock.script.existsSync()) {
    test('the mock API is not available here', () {}, skip: 'tool/mock_api');
    return;
  }

  setUpAll(() async => mock = await _Mock.start());
  tearDownAll(() => mock.stop());

  VerificationSession sessionFor(String key) {
    final client = VerificationClient(
      auth: PublicAuthorization(key),
      environment: VerificationEnvironment.custom(mock.origin),
      config: const ClientConfig(retry: RetryPolicy.none()),
    );
    addTearDown(client.close);

    final session = VerificationSession(client: client);
    addTearDown(session.dispose);
    return session;
  }

  /// Submits and waits for the round trip to land.
  ///
  /// `pumpEventQueue` is enough for a FakeTransport and is not enough for a
  /// socket: the state is read back before the response has arrived, and the
  /// assertion then fails on VerificationSubmitting. Subscribes after the
  /// submit on purpose — the current state is replayed to every new listener,
  /// so subscribing first would match the state we are waiting to leave.
  Future<void> submitAndSettle(VerificationSession session, String value) {
    session.submit(value);
    return session.states
        .firstWhere((state) => state is! VerificationSubmitting)
        .timeout(const Duration(seconds: 10));
  }

  test('a wrong code then the right one, over real HTTP', () async {
    final session = sessionFor('demo-key');
    final seen = <VerificationState>[];
    final subscription = session.states.listen(seen.add);
    addTearDown(subscription.cancel);

    await session.start(
      destination: '+49 151 9000001',
      deliveryMethod: DeliveryMethod.sms,
    );

    final live = session.state as VerificationAwaitingInput;
    expect(live.destination, '491519000001');
    expect(live.fee, isNotEmpty);
    expect(live.sms?.template, contains('{{CODE}}'));
    expect(live.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);

    await submitAndSettle(session, '000000');
    final rejected = session.state as VerificationAwaitingInput;
    expect(rejected.lastError?.known, ApiErrorCode.codeInvalid);
    expect(rejected.lastError?.detail, isNotEmpty);

    await submitAndSettle(session, '123456');
    expect(session.state, isA<VerificationVerified>());

    expect(
      [for (final state in seen) state.runtimeType.toString()],
      [
        'VerificationIdle',
        'VerificationStarting',
        'VerificationAwaitingInput',
        'VerificationSubmitting',
        'VerificationAwaitingInput',
        'VerificationSubmitting',
        'VerificationVerified',
      ],
    );
  });

  test('a callout verification reports a code', () async {
    final session = sessionFor('demo-key');

    await session.start(
      destination: '+49 151 9000002',
      deliveryMethod: DeliveryMethod.callout,
    );
    expect((session.state as VerificationAwaitingInput).sms, isNull);

    await submitAndSettle(session, '123456');

    expect(session.state, isA<VerificationVerified>());
  });

  test('three wrong codes end the verification, with no local counter',
      () async {
    final session = sessionFor('demo-key');

    await session.start(
      destination: '+49 151 9000003',
      deliveryMethod: DeliveryMethod.sms,
    );

    for (var attempt = 0; attempt < 3; attempt++) {
      await submitAndSettle(session, '000000');
    }

    // The SDK counts nothing: the API said no with too_many_attempts.
    final failed = session.state as VerificationFailed;
    expect(
      (failed.reason as ApiFailure).error.known,
      ApiErrorCode.tooManyAttempts,
    );
  });

  test('an application with no callback URL reaches a setup error', () async {
    final session = sessionFor('no-callback-key');

    await session.start(
      destination: '+49 151 9000004',
      deliveryMethod: DeliveryMethod.sms,
    );

    final setup = session.state as VerificationSetupError;
    expect(setup.code, 'denied_missing_callback_url');
  });

  test('an application whose callback refuses is denied', () async {
    final session = sessionFor('deny-key');

    await session.start(
      destination: '+49 151 9000005',
      deliveryMethod: DeliveryMethod.sms,
    );

    expect(session.state, isA<VerificationDenied>());
    expect(
      (session.state as VerificationDenied).error?.known,
      ApiErrorCode.deniedByCallback,
    );
  });

  test('bad credentials end the attempt rather than throwing', () async {
    final session = sessionFor('no-such-key');

    await expectLater(
      session.start(
        destination: '+49 151 9000006',
        deliveryMethod: DeliveryMethod.sms,
      ),
      completes,
    );

    final failed = session.state as VerificationFailed;
    expect(
      (failed.reason as ApiFailure).error.known,
      ApiErrorCode.unauthorized,
    );
  });

  test('the re-entry recipe reattaches to a live verification', () async {
    const destination = '+49 151 9000007';
    final first = sessionFor('demo-key');

    await first.start(
      destination: destination,
      deliveryMethod: DeliveryMethod.sms,
    );
    final id = (first.state as VerificationAwaitingInput).verificationId;

    // A route remount: a brand new session, whose guards cannot see the old one.
    final second = sessionFor('demo-key');
    await second.resumeByNumber(destination);
    if (second.state is! VerificationAwaitingInput) {
      await second.start(
        destination: destination,
        deliveryMethod: DeliveryMethod.sms,
      );
    }

    // The same verification, so nothing was billed and the first was not
    // superseded.
    expect((second.state as VerificationAwaitingInput).verificationId, id);

    await submitAndSettle(second, '123456');
    expect(second.state, isA<VerificationVerified>());
  });

  test('a second start on the same number supersedes the first', () async {
    const destination = '+49 151 9000008';
    final first = sessionFor('demo-key');
    final second = sessionFor('demo-key');

    await first.start(
      destination: destination,
      deliveryMethod: DeliveryMethod.sms,
    );
    final id = (first.state as VerificationAwaitingInput).verificationId;

    await second.start(
      destination: destination,
      deliveryMethod: DeliveryMethod.sms,
    );

    // What the recipe above exists to avoid: the first session still holds a
    // live-looking state for a verification the API has already ended.
    final abandoned = sessionFor('demo-key');
    await abandoned.resumeById(id);

    final failed = abandoned.state as VerificationFailed;
    expect(
      (failed.reason as ApiFailure).error.known,
      ApiErrorCode.superseded,
    );
  });
}
