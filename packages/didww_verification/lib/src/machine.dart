import 'models.dart';
import 'state.dart';

/// The codes that leave the verification alive, so another value may be
/// reported.
///
/// Compiled-in policy: the `422` envelope carries no still-alive flag, so the
/// SDK decides. If the API moves a code between the two sets, this goes stale
/// with nothing to catch it.
const Set<ApiErrorCode> recoverableErrorCodes = {
  ApiErrorCode.codeInvalid,
  ApiErrorCode.codeBlank,
  ApiErrorCode.codeValuePresent,
  ApiErrorCode.deliveryMethodInvalid,
  ApiErrorCode.validationFailed,
  ApiErrorCode.notReadyToReport,
};

/// Stands in when a terminal state is needed and the API attached no error.
const ApiErrorItem unknownFailure = ApiErrorItem(code: 'internal_error');

/// Whether [item] leaves the verification alive.
///
/// An unmodelled code is not recoverable: the alternative spends the user's
/// attempts on a rejection that will never be accepted.
bool isRecoverable(ApiErrorItem item) => recoverableErrorCodes.contains(
      item.known,
    );

/// The terminal state [error] maps to.
VerificationState terminalStateForError(ApiErrorItem error) =>
    switch (error.known) {
      ApiErrorCode.deniedMissingCallbackUrl =>
        VerificationSetupError(code: error.code, detail: error.detail),
      ApiErrorCode.deniedByCallback ||
      ApiErrorCode.deniedInvalidCallbackResponse =>
        VerificationDenied(error),
      ApiErrorCode.expired => const VerificationExpired(),
      _ => VerificationFailed(ApiFailure(error)),
    };

/// The terminal state [verification] reports, or null while it is still live.
///
/// Null for `pending` and for an unmodelled status.
VerificationState? terminalStateFor(Verification verification) {
  switch (verification.knownStatus) {
    case VerificationStatus.verified:
      return VerificationVerified(verification.id);
    case VerificationStatus.expired:
      return const VerificationExpired();
    case VerificationStatus.failed:
      // `failed` is a failure whatever code it carries; only `denied` delegates.
      return VerificationFailed(
        ApiFailure(verification.outcome ?? unknownFailure),
      );
    case VerificationStatus.denied:
      final outcome = verification.outcome;
      return outcome == null
          ? const VerificationDenied(null)
          : terminalStateForError(outcome);
    case VerificationStatus.pending:
    case null:
      return null;
  }
}

/// The live state [verification] describes.
VerificationAwaitingInput awaitingInputFor(
  Verification verification, {
  ApiErrorItem? lastError,
}) =>
    VerificationAwaitingInput(
      verificationId: verification.id,
      deliveryMethod: verification.deliveryMethod,
      destination: verification.destination,
      expiresAt: verification.expiresAt,
      fee: verification.fee,
      sms: verification.sms,
      callout: verification.callout,
      lastError: lastError,
    );

/// The state a decoded [verification] moves the session to.
VerificationState stateFor(
  Verification verification, {
  ApiErrorItem? lastError,
}) =>
    terminalStateFor(verification) ??
    awaitingInputFor(verification, lastError: lastError);

/// The state after a report was rejected on a verification that was live.
///
/// Recoverable only when every element of the envelope is: one terminal element
/// ends the verification whatever the others say.
VerificationState stateAfterReportFailure({
  required VerificationAwaitingInput live,
  required List<ApiErrorItem> errors,
}) {
  if (errors.isNotEmpty && errors.every(isRecoverable)) {
    return live.withError(errors.first);
  }
  return terminalStateForError(errors.firstOrNull ?? unknownFailure);
}

/// The state after a start or resume was rejected.
///
/// Always terminal: nothing is retryable before a verification exists.
VerificationState stateAfterStartFailure(List<ApiErrorItem> errors) =>
    terminalStateForError(errors.firstOrNull ?? unknownFailure);
