import 'models.dart';

/// Where a verification has got to.
///
/// Sealed, so a `switch` over it is exhaustive and a state added later is a
/// compile error rather than a silent gap. Every class is prefixed
/// `Verification`: Dart has no nested classes, and a bare `Failed` would
/// collide with the host app's own names.
sealed class VerificationState {
  /// Const so every stateless member can be a compile-time constant.
  const VerificationState();
}

/// Nothing has been started yet, or the session was reset.
final class VerificationIdle extends VerificationState {
  /// The state before anything happens.
  const VerificationIdle();
}

/// A start or resume request is in flight.
final class VerificationStarting extends VerificationState {
  /// The state while the create or reattach request runs.
  const VerificationStarting();
}

/// The verification is live and waiting for a code or a caller ID.
///
/// Not terminal. Reached after a successful start, and again after every
/// rejection that did not end the verification.
final class VerificationAwaitingInput extends VerificationState {
  /// Describes a live verification.
  const VerificationAwaitingInput({
    required this.verificationId,
    required this.deliveryMethod,
    required this.destination,
    required this.expiresAt,
    this.fee,
    this.sms,
    this.callout,
    this.lastError,
  });

  /// The verification's identifier.
  final String verificationId;

  /// The raw channel. May name one this release does not model.
  final String deliveryMethod;

  /// The destination as the API holds it: digits only, no leading `+`.
  final String destination;

  /// The quoted price as a decimal string. Never parse it as a `double`.
  final String? fee;

  /// The sms block, non-null exactly when the channel is sms.
  final SmsInfo? sms;

  /// The callout block, non-null exactly when the channel is callout.
  final CalloutInfo? callout;

  /// The deadline, in UTC.
  ///
  /// Nothing in the SDK ends the verification when this passes: expiry is the
  /// API's decision and arrives on the next response.
  final DateTime expiresAt;

  /// Why the previous submission was rejected, when there was one.
  final ApiErrorItem? lastError;

  /// The same state carrying [lastError].
  VerificationAwaitingInput withError(ApiErrorItem? error) =>
      VerificationAwaitingInput(
        verificationId: verificationId,
        deliveryMethod: deliveryMethod,
        destination: destination,
        expiresAt: expiresAt,
        fee: fee,
        sms: sms,
        callout: callout,
        lastError: error,
      );

  @override
  String toString() =>
      'VerificationAwaitingInput($verificationId, ${lastError?.code})';
}

/// A value was recovered from a delivered message and is about to be submitted.
///
/// Capture path only, so a screen can fill its field from [value] before the
/// spinner.
final class VerificationCaptured extends VerificationState {
  /// Reports the recovered [value].
  const VerificationCaptured(this.value);

  /// The recovered code.
  final String value;
}

/// A value is being reported.
final class VerificationSubmitting extends VerificationState {
  /// The state while a report request runs.
  const VerificationSubmitting();
}

/// The reported value was correct. Terminal.
final class VerificationVerified extends VerificationState {
  /// Reports the verified verification.
  const VerificationVerified(this.verificationId);

  /// The verification's identifier.
  final String verificationId;
}

/// The verification ended without verifying. Terminal.
final class VerificationFailed extends VerificationState {
  /// Reports why.
  const VerificationFailed(this.reason);

  /// Whether the API or the SDK ended it, and which one.
  final FailureReason reason;

  @override
  String toString() => 'VerificationFailed($reason)';
}

/// The verification was refused before anything was dispatched. Terminal.
final class VerificationDenied extends VerificationState {
  /// Reports the refusal, when the API named one.
  const VerificationDenied(this.error);

  /// The refusal's error item, or null when the API attached none.
  final ApiErrorItem? error;
}

/// The verification ran out of time. Terminal.
final class VerificationExpired extends VerificationState {
  /// The state after the API reports the deadline has passed.
  const VerificationExpired();
}

/// The application is misconfigured. Terminal, and no user input can rescue it.
///
/// Separate from [VerificationDenied] because the fix is in the account: a
/// retry button here wastes the user's time.
final class VerificationSetupError extends VerificationState {
  /// Reports the configuration fault.
  const VerificationSetupError({required this.code, this.detail});

  /// The raw error code.
  final String code;

  /// Fixed prose for [code].
  final String? detail;

  @override
  String toString() => 'VerificationSetupError($code)';
}

/// Why a verification failed.
sealed class FailureReason {
  /// Const so failures can be compile-time constants.
  const FailureReason();
}

/// The API ended it, and said why.
final class ApiFailure extends FailureReason {
  /// Wraps the API's own error item.
  const ApiFailure(this.error);

  /// What the API reported.
  final ApiErrorItem error;

  @override
  String toString() => 'ApiFailure(${error.code})';
}

/// The SDK ended it before the API had anything to say.
final class SdkFailure extends FailureReason {
  /// Wraps the SDK-side cause.
  const SdkFailure(this.error);

  /// What went wrong on this side.
  final SdkError error;

  @override
  String toString() => 'SdkFailure($error)';
}

/// A failure originating in the SDK rather than in the API.
sealed class SdkError {
  /// Const so SDK errors can be compile-time constants.
  const SdkError();
}

/// A start was requested while one was already in flight. No request was sent.
final class SdkAlreadyRunning extends SdkError {
  /// The rejected second start.
  const SdkAlreadyRunning();

  @override
  String toString() => 'SdkAlreadyRunning';
}

/// A submission was abandoned because a newer start replaced it on this
/// session.
///
/// Distinct from the wire's `superseded`, which arrives as an [ApiFailure].
final class SdkSuperseded extends SdkError {
  /// The abandoned submission.
  const SdkSuperseded();

  @override
  String toString() => 'SdkSuperseded';
}

/// The request never produced a response.
final class SdkTransportError extends SdkError {
  /// Wraps a transport failure.
  const SdkTransportError(this.message, {this.cause});

  /// A short description, safe to log.
  final String message;

  /// The underlying error, when there was one.
  final Object? cause;

  @override
  String toString() => 'SdkTransportError($message)';
}

/// The SDK was asked to do something impossible, and no request went out.
///
/// A destination with no digits is the reachable case.
final class SdkConfigurationError extends SdkError {
  /// Describes the impossible request.
  const SdkConfigurationError(this.message);

  /// A short description, safe to log.
  final String message;

  @override
  String toString() => 'SdkConfigurationError($message)';
}

/// Something threw that no other member of this tree describes.
///
/// The backstop for the session's own catch-all: it exists so a fault nothing
/// anticipated still reaches a terminal state, rather than leaving the screen on
/// a spinner that never resolves. Reaching it is a bug in this SDK.
final class SdkUnexpectedError extends SdkError {
  /// Wraps an unanticipated failure.
  const SdkUnexpectedError(this.message);

  /// A short description, safe to log. Digit runs are removed.
  final String message;

  @override
  String toString() => 'SdkUnexpectedError($message)';
}

/// A response arrived and was not the shape the API documents.
final class SdkDecodingError extends SdkError {
  /// Wraps a decode failure.
  const SdkDecodingError(this.message, {this.cause});

  /// A short description, safe to log.
  final String message;

  /// The underlying error, when there was one.
  final Object? cause;

  @override
  String toString() => 'SdkDecodingError($message)';
}
