import 'errors.dart';
import 'transport.dart';

/// Refuses, on a platform with no `dart:io`.
///
/// Reached on the web, where there is nothing to build a socket from. The
/// failure is deliberate and named: without it the client constructs a transport
/// whose first call dies inside `dart:io`'s web stub, reporting an internal
/// symbol that says nothing about what to do instead.
OwnedTransport createDefaultTransport({
  required Duration connectTimeout,
  required Duration timeout,
}) =>
    throw const ConfigurationException(
      'this platform has no built-in transport; pass one to '
      'VerificationClient(transport: ...) — package:http works on the web',
    );
