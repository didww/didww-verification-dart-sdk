import 'models.dart';

/// Options that apply only to the sms channel.
final class SmsOptions {
  /// Requests the given template languages.
  const SmsOptions({this.languages});

  /// Preferred template languages, most preferred first.
  ///
  /// A primary subtag and at most one more — narrower than BCP 47, so
  /// `zh-Hans-CN` from `Locale.toLanguageTag()` is not accepted. The SDK drops a
  /// tag of the wrong shape rather than sending it, because the API would answer
  /// `languages_invalid` and create no verification at all.
  ///
  /// Matched exactly, so a region subtag is required: `pl` does not match
  /// `pl-PL`. A well-formed tag with no template falls back to the default
  /// language; read [SmsInfo.language] to learn which one was used.
  final List<String>? languages;
}

/// Options that apply only to the callout channel.
final class CalloutOptions {
  /// Requests the given announcement languages.
  const CalloutOptions({this.languages});

  /// Preferred announcement languages, most preferred first.
  ///
  /// The same shape and the same semantics as [SmsOptions.languages], so one
  /// list serves both channels — but the two are backed by separate sets, and a
  /// tag with a message template but no recording is accepted and falls back
  /// silently. Read [CalloutInfo.language] to learn which one was used.
  final List<String>? languages;
}

/// The value being reported for a verification.
///
/// Sealed, so a channel that takes a different kind of value is added as a
/// member here rather than by widening what a bare string may mean.
sealed class ReportValue {
  const ReportValue();

  /// Reports a one-time code, which is what every channel takes.
  const factory ReportValue.code(String value) = ReportCode;

  /// The value itself.
  String get value;
}

/// A one-time code the user received.
final class ReportCode extends ReportValue {
  /// Reports [value] as a code.
  const ReportCode(this.value);

  @override
  final String value;
}
