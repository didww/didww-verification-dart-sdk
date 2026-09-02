import 'io_transport.dart';
import 'transport.dart';

/// The `dart:io` transport, on every platform that has `dart:io`.
OwnedTransport createDefaultTransport({
  required Duration connectTimeout,
  required Duration timeout,
}) =>
    IOHttpTransport(connectTimeout: connectTimeout, timeout: timeout);
