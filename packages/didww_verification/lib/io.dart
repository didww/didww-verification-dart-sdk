/// The `dart:io` transport, for a caller who wants to hold it directly.
///
/// Separate from the main library so importing that one does not drag `dart:io`
/// in, which would exclude the package from the web whatever transport the
/// caller supplies. The client builds this for itself when given no transport;
/// import this only to construct or configure one by hand.
library;

export 'src/io_transport.dart' show IOHttpTransport;
