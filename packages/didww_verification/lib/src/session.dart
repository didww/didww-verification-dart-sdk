import 'dart:async';

import 'auto_capture.dart';
import 'client.dart';
import 'diagnostics.dart';
import 'errors.dart';
import 'machine.dart';
import 'models.dart';
import 'options.dart';
import 'redact.dart';
import 'state.dart';
import 'wire.dart';

/// A verification as a state machine: start it, render [states], submit what
/// the user gives you.
///
/// Built on [VerificationClient], which stays available for anything this does
/// not cover. One session drives one verification at a time; starting again
/// replaces whatever it held. Call [dispose] from `State.dispose`.
final class VerificationSession {
  /// Drives verifications over [client].
  ///
  /// Supply [autoCapture] to fill the code in automatically; without one the
  /// user types it.
  VerificationSession({
    required VerificationClient client,
    SmsAutoCapture? autoCapture,
  })  : _client = client,
        _autoCapture = autoCapture;

  final VerificationClient _client;
  final SmsAutoCapture? _autoCapture;

  /// How long the app hash may take before capture is given up on.
  ///
  /// Losing capture costs autofill; blocking here costs the whole verification.
  static const Duration _appHashBudget = Duration(seconds: 5);

  final List<MultiStreamController<VerificationState>> _listeners = [];
  late final Stream<VerificationState> _states =
      Stream<VerificationState>.multi(_onListen, isBroadcast: true);

  VerificationState _state = const VerificationIdle();
  VerificationAwaitingInput? _live;

  /// Every continuation captures it and returns silently when it no longer
  /// matches, which is what makes disposing mid-request safe.
  int _generation = 0;

  bool _startInFlight = false;
  bool _submitInFlight = false;
  bool _disposed = false;

  String? _buffered;
  String? _expectedAppHash;
  String? _template;
  StreamSubscription<String>? _capture;
  Timer? _expiryTimer;
  Timer? _budgetTimer;

  /// The current state. Never null; starts at [VerificationIdle].
  VerificationState get state => _state;

  /// Every new listener receives [state] immediately, then each transition —
  /// including a second listener subscribing while the first still is.
  ///
  /// The same object on every call: `StreamBuilder` compares stream identity,
  /// so a fresh one per call would resubscribe on every rebuild.
  Stream<VerificationState> get states => _states;

  /// Whether an [SmsAutoCapture] was supplied.
  ///
  /// Synchronous and correct from construction, so a screen can decide before
  /// [start] whether to promise the user that the code will fill itself in.
  bool get hasAutoCapture => _autoCapture != null;

  /// Whether automatic capture is armed for the current verification.
  ///
  /// Needs [hasAutoCapture], a supporting platform, a readable certificate and
  /// the API echoing back the device's hash. Meaningless before [start]; false
  /// until then.
  bool get isAutoCaptureArmed => _capture != null;

  /// Starts a verification.
  ///
  /// Requests immediately, never on a rebuild or a listen, and completes once
  /// the resulting state is emitted — [VerificationAwaitingInput] on success,
  /// which is not terminal.
  ///
  /// Never throws: every outcome arrives through [states].
  Future<void> start({
    required String destination,
    required DeliveryMethod deliveryMethod,
    SmsOptions? sms,
    CalloutOptions? callout,
  }) async {
    if (_disposed) return;
    if (_startInFlight) {
      _emit(const VerificationFailed(SdkFailure(SdkAlreadyRunning())));
      return;
    }

    if (deliveryMethod == DeliveryMethod.sms && _autoCapture == null) {
      debugDiagnostic(
        'starting an sms verification with no SmsAutoCapture: the user will '
        'have to type the code. Pass autoCapture: const '
        'SmsRetrieverAutoCapture() from package:didww_verification_sms to fill '
        'it in automatically.',
      );
    }

    final generation = _beginVerification();
    _startInFlight = true;
    try {
      final appHash = await _appHash();
      if (_isStale(generation)) return;
      _expectedAppHash = appHash;

      final verification = await _client.startVerification(
        destination: destination,
        deliveryMethod: deliveryMethod,
        sms: sms,
        callout: callout,
        appHash: appHash,
      );
      if (_isStale(generation)) return;
      _enterLive(verification);
    } on VerificationException catch (error) {
      if (_isStale(generation)) return;
      _emit(_terminalFor(error));
    } catch (error) {
      if (_isStale(generation)) return;
      _emit(_unexpected(error));
    } finally {
      if (!_isStale(generation)) _startInFlight = false;
    }
  }

  /// Reattaches to the verification the API currently holds for [destination]
  /// instead of starting one. Bills nothing.
  ///
  /// The API answers with the newest verification for the number whatever its
  /// status, so the recipe tests the state rather than trusting the read:
  ///
  /// ```dart
  /// await session.resumeByNumber(number);
  /// if (session.state is! VerificationAwaitingInput) {
  ///   await session.start(destination: number, deliveryMethod: method);
  /// }
  /// ```
  ///
  /// Load-bearing, not a nicety: the guards are per session instance, so a
  /// route remount builds a new session and a second [start] bills again.
  Future<void> resumeByNumber(String destination) =>
      _reattach(() => _client.getVerificationByNumber(destination));

  /// Reattaches by id — for a verification persisted across an app restart.
  Future<void> resumeById(String verificationId) =>
      _reattach(() => _client.getVerification(verificationId));

  /// Submits a code or a caller ID. Never throws.
  ///
  /// Valid at any time: buffered until the verification is live, ignored once
  /// terminal, and single-flighted so a double tap cannot burn two attempts.
  ///
  /// **Drive your spinner from [states], never from this call:** an accepted
  /// submission emits [VerificationSubmitting], and every case where the value
  /// is dropped is one the current state already explains.
  void submit(String value) {
    if (_disposed) return;
    if (_isTerminal(_state)) return;
    if (_submitInFlight) return;

    final live = _live;
    if (live == null) {
      _buffered = value;
      return;
    }
    unawaited(_report(live, value));
  }

  /// Returns to [VerificationIdle], cancelling anything in flight.
  ///
  /// Awaitable because the cancel it performs is asynchronous.
  Future<void> reset() async {
    if (_disposed) return;
    _abandon();
    await _disarm();
    _emit(const VerificationIdle());
  }

  /// Cancels every subscription and timer and closes [states].
  ///
  /// Call it from `State.dispose`. Safe to call twice.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _abandon();
    await _disarm();

    for (final listener in List.of(_listeners)) {
      // Not awaited: a paused listener never completes its close, and dispose
      // must not be able to hang on one.
      unawaited(listener.close());
    }
    _listeners.clear();
  }

  Future<void> _reattach(Future<Verification> Function() fetch) async {
    if (_disposed) return;
    if (_startInFlight) {
      _emit(const VerificationFailed(SdkFailure(SdkAlreadyRunning())));
      return;
    }

    final generation = _beginVerification();
    _startInFlight = true;
    try {
      // Computed and compared, never sent: a resume creates nothing, and the
      // hash the API already holds is the one that decides whether capture arms.
      final appHash = await _appHash();
      if (_isStale(generation)) return;
      _expectedAppHash = appHash;

      final verification = await fetch();
      if (_isStale(generation)) return;
      _enterLive(verification);
    } on VerificationException catch (error) {
      if (_isStale(generation)) return;
      _emit(_terminalFor(error));
    } catch (error) {
      if (_isStale(generation)) return;
      _emit(_unexpected(error));
    } finally {
      if (!_isStale(generation)) _startInFlight = false;
    }
  }

  Future<void> _report(VerificationAwaitingInput live, String value) async {
    final generation = _generation;
    _submitInFlight = true;
    _emit(const VerificationSubmitting());

    try {
      final verification = await _client.reportVerification(
        live.verificationId,
        deliveryMethod: live.deliveryMethod,
        value: ReportValue.code(value),
      );
      if (_isStale(generation)) return;
      _emit(stateFor(verification));
    } on ApiException catch (error) {
      if (_isStale(generation)) return;
      _emit(stateAfterReportFailure(live: live, errors: error.errors));
    } on VerificationException catch (error) {
      if (_isStale(generation)) return;
      _emit(_terminalFor(error));
    } catch (error) {
      if (_isStale(generation)) return;
      _emit(_unexpected(error));
    } finally {
      if (!_isStale(generation)) _submitInFlight = false;
    }
  }

  /// Clears the previous verification and takes the next generation.
  int _beginVerification() {
    // A value submitted before the verification was live survives the start —
    // that is what "buffered until live" means. A terminal state drops it.
    final carried = _buffered;
    final abandoned = _submitInFlight;
    _abandon();
    _buffered = carried;
    unawaited(_disarm());
    if (abandoned) {
      _emit(const VerificationFailed(SdkFailure(SdkSuperseded())));
    }
    _emit(const VerificationStarting());
    return _generation;
  }

  void _abandon() {
    _generation++;
    _startInFlight = false;
    _submitInFlight = false;
    _buffered = null;
    _expectedAppHash = null;
    _template = null;
    _live = null;
  }

  void _enterLive(Verification verification) {
    final next = stateFor(verification);
    _emit(next);
    if (next is! VerificationAwaitingInput) return;

    _armCapture(verification);

    final buffered = _buffered;
    _buffered = null;
    if (buffered != null) submit(buffered);
  }

  Future<String?> _appHash() async {
    final capture = _autoCapture;
    if (capture == null) return null;

    final String? hash;
    try {
      // Bounded, because this gates the billed request and runs before any HTTP
      // request exists, so ClientConfig.timeout cannot reach it. invokeMethod's
      // future never completes if the reply is lost to an engine detach, and
      // _startInFlight would then stay true for the life of the session.
      hash = await capture.appHash().timeout(_appHashBudget);
    } catch (error) {
      // Swallowed on purpose: automatic capture is a convenience, and a fault
      // in it must not fail a verification the account is billed for.
      debugDiagnostic('the app hash could not be read ($error); '
          'automatic capture is unavailable for this verification');
      return null;
    }

    if (hash == null) return null;
    if (appHashFormat.hasMatch(hash)) return hash;

    debugDiagnostic('the app hash "$hash" is malformed and was not used; '
        'automatic capture is unavailable for this verification');
    return null;
  }

  void _armCapture(Verification verification) {
    final capture = _autoCapture;
    final expected = _expectedAppHash;
    if (capture == null || expected == null) return;
    // The echo gate: an absent or differing hash means the API would not
    // address a message to this build, so the platform listener is never armed.
    if (verification.sms?.appHash != expected) return;

    _template = verification.sms?.template;
    _capture = capture.messages().listen(_onMessage);
    _scheduleDisarm(verification);
  }

  /// Stops listening at the capture budget or the deadline, whichever is first.
  ///
  /// Running out of budget only stops listening; it never ends the
  /// verification, and manual entry stays live. Nothing here emits a state —
  /// expiry is the API's decision and arrives on the next response.
  void _scheduleDisarm(Verification verification) {
    final generation = _generation;
    void disarm() {
      if (_isStale(generation)) return;
      unawaited(_disarm());
    }

    final untilExpiry =
        verification.expiresAt.difference(DateTime.now().toUtc());
    _expiryTimer = Timer(
      untilExpiry.isNegative ? Duration.zero : untilExpiry,
      disarm,
    );

    final budget = verification.sms?.interceptionTimeoutSeconds;
    if (budget != null) {
      _budgetTimer = Timer(Duration(seconds: budget), disarm);
    }
  }

  void _onMessage(String body) {
    // The same three guards submit() applies. Without them a second delivered
    // message overwrites VerificationSubmitting with a VerificationCaptured
    // carrying a code that is not the one in flight, and the screen — which is
    // told to fill its field from that state — shows the wrong one.
    if (_disposed || _submitInFlight || _isTerminal(_state)) return;

    final code = extractCode(_template, body);
    if (code == null) return;
    _emit(VerificationCaptured(code));
    submit(code);
  }

  Future<void> _disarm() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _budgetTimer?.cancel();
    _budgetTimer = null;

    final subscription = _capture;
    _capture = null;
    await subscription?.cancel();
  }

  bool _isStale(int generation) => _disposed || generation != _generation;

  void _emit(VerificationState next) {
    _state = next;
    if (next is VerificationAwaitingInput) _live = next;
    if (_isTerminal(next)) {
      _buffered = null;
      unawaited(_disarm());
    }

    for (final listener in List.of(_listeners)) {
      listener.add(next);
    }
  }

  void _onListen(MultiStreamController<VerificationState> controller) {
    controller.add(_state);
    if (_disposed) {
      controller.close();
      return;
    }
    _listeners.add(controller);
    controller.onCancel = () => _listeners.remove(controller);
  }

  /// Written as an exhaustive switch so adding a state forces a decision here
  /// rather than silently leaving capture armed.
  static bool _isTerminal(VerificationState state) => switch (state) {
        VerificationIdle() ||
        VerificationStarting() ||
        VerificationAwaitingInput() ||
        VerificationCaptured() ||
        VerificationSubmitting() =>
          false,
        VerificationVerified() ||
        VerificationFailed() ||
        VerificationDenied() ||
        VerificationExpired() ||
        VerificationSetupError() =>
          true,
      };

  /// The terminal state for something outside the sealed tree.
  ///
  /// Redacted, because this is the one path that reports an error the SDK did
  /// not construct and so cannot vouch for the contents of.
  static VerificationState _unexpected(Object error) => VerificationFailed(
        SdkFailure(SdkUnexpectedError(redactDigitRuns('$error'))),
      );

  static VerificationState _terminalFor(VerificationException error) =>
      switch (error) {
        ApiException(:final errors) => stateAfterStartFailure(errors),
        TransportException(:final message, :final cause) => VerificationFailed(
            SdkFailure(SdkTransportError(message, cause: cause)),
          ),
        DecodingException(:final message) => VerificationFailed(
            SdkFailure(SdkDecodingError(message)),
          ),
        ConfigurationException(:final message) =>
          VerificationFailed(SdkFailure(SdkConfigurationError(message))),
      };
}
