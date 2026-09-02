/// The channels a verification can be started on.
///
/// Closed: this is a value the SDK writes, so an unmodelled channel must not
/// leave the process.
enum DeliveryMethod {
  /// A one-time code delivered by text message.
  sms('sms'),

  /// A one-time code read out by an automated call.
  callout('callout');

  const DeliveryMethod(this.wire);

  /// The value carried on the wire.
  final String wire;

  /// The channel for [value], or `null` when the API names one this release
  /// does not model.
  static DeliveryMethod? fromWire(String value) {
    for (final method in values) {
      if (method.wire == value) return method;
    }
    return null;
  }
}

/// The statuses a verification is reported with.
///
/// Open on decode: [fromWire] returns `null` for a status this release does not
/// know, and the raw string is kept alongside it.
enum VerificationStatus {
  /// Accepted and awaiting the value the user received.
  pending('pending'),

  /// The reported value was correct.
  verified('verified'),

  /// Ended without verifying.
  failed('failed'),

  /// Ran out of time before a correct value was reported.
  expired('expired'),

  /// Refused before dispatch.
  denied('denied');

  const VerificationStatus(this.wire);

  /// The value carried on the wire.
  final String wire;

  /// The status for [value], or `null` when the API names one this release does
  /// not model.
  static VerificationStatus? fromWire(String value) {
    for (final status in values) {
      if (status.wire == value) return status;
    }
    return null;
  }

  /// Whether the verification is over. Only [pending] is not.
  bool get isTerminal => this != VerificationStatus.pending;
}

/// Every coded error the API can return.
///
/// Appears either as an element of an `errors` envelope or, for the nine
/// outcomes, as the error code of a finished verification.
enum ApiErrorCode {
  /// No destination was supplied.
  destinationBlank('destination_blank'),

  /// The destination is not a usable phone number.
  destinationInvalid('destination_invalid'),

  /// No delivery method was supplied.
  deliveryMethodBlank('delivery_method_blank'),

  /// The delivery method is not one the API offers.
  deliveryMethodInclusion('delivery_method_inclusion'),

  /// The reported delivery method is not the one the verification was started on.
  deliveryMethodInvalid('delivery_method_invalid'),

  /// One or more requested template languages are not valid tags.
  languagesInvalid('languages_invalid'),

  /// The supplied app hash is not eleven characters of the accepted alphabet.
  appHashInvalid('app_hash_invalid'),

  /// A code was required and none was supplied.
  codeBlank('code_blank'),

  /// A code was supplied on a channel that does not take one.
  codeValuePresent('code_value_present'),

  /// The destination cannot be reached on the requested channel.
  destinationNotSupportedForChannel('destination_not_supported_for_channel'),

  /// The reported code was wrong.
  codeInvalid('code_invalid'),

  /// The verification is already verified and the reported value is not accepted.
  alreadyVerified('already_verified'),

  /// The verification is not in a state where a value can be reported.
  notReadyToReport('not_ready_to_report'),

  /// The request body did not contain a usable data object.
  parameterMissing('parameter_missing'),

  /// No such verification.
  notFound('not_found'),

  /// The credentials were missing, wrong, or too weak for this application.
  unauthorized('unauthorized'),

  /// The account cannot fund another verification.
  balanceInsufficient('balance_insufficient'),

  /// The request failed validation without a more specific code.
  validationFailed('validation_failed'),

  /// The API failed to handle the request.
  internalError('internal_error'),

  /// Delivery could not be attempted.
  dispatchFailed('dispatch_failed'),

  /// The verification ran out of time.
  expired('expired'),

  /// Every permitted attempt was used.
  tooManyAttempts('too_many_attempts'),

  /// The destination could not be reached.
  staleDispatch('stale_dispatch'),

  /// The application was removed while the verification was live.
  applicationDeleted('application_deleted'),

  /// A newer verification for the same destination replaced this one.
  superseded('superseded'),

  /// The application has no callback URL, which this authentication mode requires.
  deniedMissingCallbackUrl('denied_missing_callback_url'),

  /// The application's callback refused the verification.
  deniedByCallback('denied_by_callback'),

  /// The application's callback answered in a way that could not be accepted.
  deniedInvalidCallbackResponse('denied_invalid_callback_response');

  const ApiErrorCode(this.wire);

  /// The value carried on the wire.
  final String wire;

  /// The code for [value], or `null` when the API names one this release does
  /// not model. An unknown code is never an error in itself.
  static ApiErrorCode? fromWire(String value) {
    for (final code in values) {
      if (code.wire == value) return code;
    }
    return null;
  }

  /// Whether this code describes the outcome of a finished verification rather
  /// than the rejection of a request.
  bool get isOutcome => _outcomes.contains(this);

  static const Set<ApiErrorCode> _outcomes = {
    dispatchFailed,
    expired,
    tooManyAttempts,
    staleDispatch,
    applicationDeleted,
    superseded,
    deniedMissingCallbackUrl,
    deniedByCallback,
    deniedInvalidCallbackResponse,
  };
}
