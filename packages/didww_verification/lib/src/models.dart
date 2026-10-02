import 'vocabulary.dart';

export 'vocabulary.dart' show ApiErrorCode, DeliveryMethod, VerificationStatus;

/// One element of an error envelope, or the outcome of a finished verification.
///
/// [code] is always the raw value; [known] is non-null only when this release
/// models it. Switch on [known]; show [detail] only as a fallback.
final class ApiErrorItem {
  /// Wraps a raw error element.
  const ApiErrorItem({required this.code, this.detail});

  /// Builds an item from a raw code.
  factory ApiErrorItem.fromWire(String code, {String? detail}) =>
      ApiErrorItem(code: code, detail: detail);

  /// The raw code, always present.
  final String code;

  /// Fixed prose for [code]. Null on a finished verification's outcome.
  final String? detail;

  /// The typed code, or null when this release does not model it.
  ///
  /// Derived rather than stored, like the three `known*` getters on
  /// [Verification], so it cannot disagree with [code].
  ApiErrorCode? get known => ApiErrorCode.fromWire(code);

  @override
  String toString() => 'ApiErrorItem($code)';
}

/// How the API marks the sms for on-device autofill.
final class SmsAutofill {
  /// Wraps an autofill block.
  const SmsAutofill({required this.type, this.value});

  /// The marker type: `app_hash` for the Android SMS Retriever.
  ///
  /// A string rather than an enum, so a type added on the server later still
  /// decodes instead of failing the response.
  final String type;

  /// The app hash when [type] is `app_hash`; null for a type without a value.
  final String? value;

  @override
  bool operator ==(Object other) =>
      other is SmsAutofill && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);

  @override
  String toString() => 'SmsAutofill($type, $value)';
}

/// The `sms` block of a response, present only on the sms channel.
final class SmsInfo {
  /// Wraps an sms block.
  const SmsInfo({
    this.template,
    this.language,
    this.interceptionTimeoutSeconds,
    this.autofill,
    @Deprecated('Use autofill instead.') String? appHash,
    this.codeLength,
  })  : assert(autofill == null || appHash == null),
        _appHash = appHash;

  /// The rendered message with its code placeholder still in place.
  ///
  /// The key is always present; its value may be null.
  final String? template;

  /// The BCP 47 tag the message was written in.
  ///
  /// What the API chose, not what you asked for: the first requested tag with a
  /// template, or the default when none had one. Compare it against your own
  /// first preference to detect a fallback.
  final String? language;

  /// How long to keep an on-device listener armed, in seconds.
  ///
  /// A budget, not a deadline and not a countdown: manual entry keeps working
  /// until [Verification.expiresAt], which bounds the listener whether or not
  /// this is set.
  final int? interceptionTimeoutSeconds;

  /// The autofill marker the API stored, absent when none was stored.
  ///
  /// Comparing its value against the hash the device computed is the one
  /// diagnostic that explains why automatic capture is not firing.
  final SmsAutofill? autofill;

  final String? _appHash;

  /// The app hash the API stored, absent when none was stored.
  ///
  /// Deprecated: read [autofill] instead.
  @Deprecated('Use autofill instead.')
  String? get appHash => autofill == null
      ? _appHash
      : (autofill?.type == 'app_hash' ? autofill?.value : null);

  /// How many digits the code is, chosen per application on the server.
  ///
  /// Never compile a length in; a template that renders eight digits one day
  /// must keep working.
  final int? codeLength;

  @override
  String toString() => 'SmsInfo(template: ${template != null}, '
      'autofill: $autofill, codeLength: $codeLength)';
}

/// The `callout` block of a response, present only on the callout channel.
final class CalloutInfo {
  /// Wraps a callout block.
  const CalloutInfo({this.language, this.codeLength});

  /// The BCP 47 tag the code is announced in.
  ///
  /// What the API chose, not what you asked for: the first requested tag with a
  /// recording, or the default when none had one. Compare it against your own
  /// first preference to detect a fallback — a tag that works on the sms
  /// channel may have no recording here, and that difference is only visible
  /// in this field.
  final String? language;

  /// How many digits the code is, chosen per application on the server.
  final int? codeLength;

  @override
  String toString() => 'CalloutInfo(language: $language, '
      'codeLength: $codeLength)';
}

/// A verification, as the API reports it.
final class Verification {
  /// Wraps a verification response.
  const Verification({
    required this.id,
    required this.destination,
    required this.deliveryMethod,
    required this.status,
    required this.expiresAt,
    this.fee,
    this.errorCode,
    this.errorDetail,
    this.sms,
    this.callout,
  });

  /// The verification's identifier.
  final String id;

  /// The destination as the API holds it: digits only, with no leading `+`.
  ///
  /// Compare with `digitsOf`, never against a formatted string, and keep your
  /// own copy of what the user typed for display.
  final String destination;

  /// The raw channel. May name one this release does not model.
  final String deliveryMethod;

  /// The typed channel, or null when this release does not model it.
  DeliveryMethod? get knownDeliveryMethod =>
      DeliveryMethod.fromWire(deliveryMethod);

  /// The raw status.
  final String status;

  /// The typed status, or null when this release does not model it.
  VerificationStatus? get knownStatus => VerificationStatus.fromWire(status);

  /// VAT-inclusive, as a decimal string. Never parse it as a `double`.
  ///
  /// A quote, not a charge: billed on a verified outcome, with the message or
  /// call billed separately.
  final String? fee;

  /// The raw outcome code on a finished verification.
  final String? errorCode;

  /// The typed outcome code, or null when absent or unmodelled.
  ApiErrorCode? get knownErrorCode {
    final code = errorCode;
    return code == null ? null : ApiErrorCode.fromWire(code);
  }

  /// Fixed prose for [errorCode].
  final String? errorDetail;

  /// The deadline, in UTC. Assigned at creation and kept once finished.
  final DateTime expiresAt;

  /// The sms block, non-null exactly when the channel is sms.
  final SmsInfo? sms;

  /// The callout block, non-null exactly when the channel is callout.
  final CalloutInfo? callout;

  /// The outcome as an error item, or null while the verification is live.
  ApiErrorItem? get outcome {
    final code = errorCode;
    return code == null
        ? null
        : ApiErrorItem.fromWire(code, detail: errorDetail);
  }

  /// Whether the verification is over. False for an unmodelled status.
  bool get isFinished => knownStatus?.isTerminal ?? false;

  @override
  String toString() => 'Verification($id, $deliveryMethod, $status)';
}
