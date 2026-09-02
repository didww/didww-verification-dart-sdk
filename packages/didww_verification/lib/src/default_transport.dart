/// The transport the client builds when it was given none.
///
///
/// Conditional, so `dart:io` stays out of the import graph on the web. Reaching
/// it any other way — importing the io library directly from the barrel — is
/// what excludes the whole package from web, transport seam or not.
library;

export 'default_transport_stub.dart'
    if (dart.library.io) 'default_transport_io.dart';
