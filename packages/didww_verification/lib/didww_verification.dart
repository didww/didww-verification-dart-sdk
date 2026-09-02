/// Dart client for the DIDWW phone number verification API.
library;

export 'src/auth.dart';
export 'src/auto_capture.dart';
export 'src/client.dart';
export 'src/config.dart';
export 'src/errors.dart';
// The recoverable/terminal partition is policy a direct VerificationClient
// consumer has no other way to ask about, and hard-coding it goes stale.
export 'src/machine.dart' show isRecoverable, recoverableErrorCodes;
export 'src/models.dart';
export 'src/options.dart';
export 'src/phone_number.dart';
export 'src/session.dart';
export 'src/state.dart';
export 'src/transport.dart';
export 'src/version.dart';
export 'src/vocabulary.dart';
export 'src/wire.dart' show appHashFormat;
