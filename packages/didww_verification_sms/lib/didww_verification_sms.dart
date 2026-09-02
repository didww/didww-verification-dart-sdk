/// Android SMS Retriever support for `didww_verification`.
///
/// No iOS implementation: one-time code autofill there is an `autofillHints`
/// hint on the application's own text field.
library;

export 'src/sms_retriever_auto_capture.dart'
    show SmsRetrieverAutoCapture, getAppHash;
export 'src/version.dart';
