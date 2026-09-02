import 'package:didww_verification/didww_verification.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The method channel the Kotlin side registers.
const String methodChannelName = 'didww_verification_sms';

/// The event channel message bodies arrive on.
const String messageChannelName = 'didww_verification_sms/messages';

/// The method that answers with this build's app hash.
const String appHashMethod = 'getAppHash';

const MethodChannel _methods = MethodChannel(methodChannelName);
const EventChannel _messages = EventChannel(messageChannelName);

Stream<String>? _stream;

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// SMS Retriever-backed automatic capture for a [VerificationSession].
///
/// Android only. Elsewhere [appHash] resolves to null and [messages] is empty,
/// so an app can depend on this package unconditionally.
final class SmsRetrieverAutoCapture implements SmsAutoCapture {
  /// Creates the capture. It holds no state; the platform channels are shared.
  const SmsRetrieverAutoCapture();

  @override
  Future<String?> appHash() => getAppHash();

  @override
  Stream<String> messages() => _messageStream();
}

/// The 11-character app hash for this build, or null on a non-Android platform
/// or when the signing certificate cannot be read.
///
/// **Display it during development and register the value you see there.** Play
/// App Signing re-signs the upload artifact, so a hash from a locally signed
/// build never matches in production and capture silently never fires.
Future<String?> getAppHash() async {
  // Unguarded this throws MissingPluginException off Android.
  if (!_isAndroid) return null;
  return _methods.invokeMethod<String>(appHashMethod);
}

Stream<String> _messageStream() {
  // receiveBroadcastStream routes platform errors to FlutterError.reportError,
  // not to the stream, so an unguarded listen off Android is silently empty and
  // logs a framework error per listener.
  if (!_isAndroid) return const Stream<String>.empty(broadcast: true);

  // Cached: the contract is the same instance for every call, and the session
  // counts listens against cancels. Errors are dropped — losing capture is not a
  // verification failure, and the session subscribes without an error handler.
  return _stream ??= _messages
      .receiveBroadcastStream()
      .cast<String>()
      .handleError((Object _) {});
}
