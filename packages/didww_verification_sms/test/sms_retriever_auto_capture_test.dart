import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification_sms/didww_verification_sms.dart'
    show SmsRetrieverAutoCapture, getAppHash;
import 'package:didww_verification_sms/src/sms_retriever_auto_capture.dart'
    show appHashMethod, messageChannelName, methodChannelName;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every platform the package can be compiled for and does not serve.
const List<TargetPlatform> notAndroid = [
  TargetPlatform.iOS,
  TargetPlatform.macOS,
  TargetPlatform.linux,
  TargetPlatform.windows,
  TargetPlatform.fuchsia,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const methods = MethodChannel(methodChannelName);
  const events = EventChannel(messageChannelName);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  });

  group('the channel names', () {
    // Pinned here and in DidwwVerificationSmsPluginTest.kt. A rename on either
    // side leaves the other red; renaming in one place only produces a plugin
    // that builds, installs and answers nothing.
    test('are the ones the Kotlin side registers', () {
      expect(methodChannelName, 'didww_verification_sms');
      expect(messageChannelName, 'didww_verification_sms/messages');
      expect(appHashMethod, 'getAppHash');
    });
  });

  group('on Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('appHash asks the platform and returns its answer', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        return 'FA+9qCX9VSu';
      });

      expect(await const SmsRetrieverAutoCapture().appHash(), 'FA+9qCX9VSu');
      expect(calls.single.method, 'getAppHash');
    });

    test('a platform that cannot read the certificate yields null', () async {
      messenger.setMockMethodCallHandler(methods, (call) async => null);

      expect(await getAppHash(), isNull);
    });

    test('messages forwards what the platform hands over', () async {
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            sink.success('Your code is 123456\nFA+9qCX9VSu');
            sink.endOfStream();
          },
        ),
      );

      expect(
        await const SmsRetrieverAutoCapture().messages().first,
        'Your code is 123456\nFA+9qCX9VSu',
      );
    });

    test('a platform error is dropped rather than thrown into the zone',
        () async {
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (arguments, sink) {
            sink.error(code: 'sms_retriever_unavailable', message: 'no play');
            sink.success('Your code is 123456');
            sink.endOfStream();
          },
        ),
      );

      // No onError argument on purpose: this is how the session subscribes, and
      // an undropped error would reach the zone and fail the test.
      expect(
        await const SmsRetrieverAutoCapture().messages().toList(),
        ['Your code is 123456'],
      );
    });

    test('messages returns the same instance on every call', () {
      final capture = const SmsRetrieverAutoCapture();

      expect(identical(capture.messages(), capture.messages()), isTrue);
      expect(
        identical(
            capture.messages(), const SmsRetrieverAutoCapture().messages()),
        isTrue,
      );
    });
  });

  group('off Android, the degradation is code and not an inherited property',
      () {
    for (final platform in notAndroid) {
      test('$platform: appHash resolves null with no handler registered',
          () async {
        debugDefaultTargetPlatformOverride = platform;

        // Nothing is mocked on purpose. Without the guard this throws
        // MissingPluginException, which is exactly the bug being excluded.
        expect(await const SmsRetrieverAutoCapture().appHash(), isNull);
        expect(await getAppHash(), isNull);
      });

      test('$platform: messages is empty and reports no framework error',
          () async {
        debugDefaultTargetPlatformOverride = platform;

        final reported = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = reported.add;
        addTearDown(() => FlutterError.onError = previous);

        // The canonical const instance, not merely a stream that happens to be
        // done. The channel-backed stream is cached for the isolate, so once an
        // Android test has closed it, asserting only `emitsDone` passes with the
        // guard deleted.
        expect(
          identical(
            const SmsRetrieverAutoCapture().messages(),
            const Stream<String>.empty(broadcast: true),
          ),
          isTrue,
        );

        // receiveBroadcastStream routes an unregistered channel to
        // FlutterError.reportError rather than to the stream, so "an empty
        // stream" is right about behaviour and wrong about noise.
        await expectLater(
          const SmsRetrieverAutoCapture().messages(),
          emitsDone,
        );
        expect(reported, isEmpty);
      });

      test(
          '$platform: messages returns the same instance, and is re-listenable',
          () async {
        debugDefaultTargetPlatformOverride = platform;
        final capture = const SmsRetrieverAutoCapture();

        expect(identical(capture.messages(), capture.messages()), isTrue);
        await expectLater(capture.messages(), emitsDone);
        await expectLater(capture.messages(), emitsDone);
      });
    }
  });

  test('the capture satisfies the interface the session takes', () {
    expect(const SmsRetrieverAutoCapture(), isA<SmsAutoCapture>());
  });
}
