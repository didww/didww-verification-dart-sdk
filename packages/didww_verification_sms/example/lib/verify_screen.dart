import 'dart:async';

import 'package:didww_verification/didww_verification.dart';
import 'package:didww_verification_sms/didww_verification_sms.dart';
import 'package:flutter/material.dart';

/// Runs one verification and renders whatever state it reaches.
class VerifyScreen extends StatefulWidget {
  /// Verifies [destination] over [deliveryMethod], starting or resuming.
  const VerifyScreen({
    required this.client,
    required this.destination,
    required this.deliveryMethod,
    this.resume = false,
    super.key,
  });

  /// The client to run on. This screen closes it.
  final VerificationClient client;

  /// The number being verified.
  final String destination;

  /// The channel to start on. Unused when [resume] is set — every option is a
  /// create-time choice.
  final DeliveryMethod deliveryMethod;

  /// Reattach to the number's live verification instead of starting one.
  final bool resume;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  late final VerificationSession _session = VerificationSession(
    client: widget.client,
    autoCapture: const SmsRetrieverAutoCapture(),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_begin());
  }

  @override
  void dispose() {
    // The session holds a platform subscription and two timers, the client holds
    // a socket, and both belong to this route.
    unawaited(_session.dispose());
    widget.client.close();
    super.dispose();
  }

  Future<void> _begin() => widget.resume
      ? _session.resumeByNumber(widget.destination)
      : _session.start(
          destination: widget.destination,
          deliveryMethod: widget.deliveryMethod,
        );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.destination)),
        body: StreamBuilder<VerificationState>(
          stream: _session.states,
          initialData: _session.state,
          builder: (context, snapshot) => VerificationView(
            state: snapshot.data!,
            armed: _session.isAutoCaptureArmed,
            onSubmit: _session.submit,
            onRestart: () => unawaited(_begin()),
          ),
        ),
      );
}

/// Renders one [VerificationState].
///
/// Separated from [VerifyScreen] so every state can be rendered in a test
/// without a client, a session or a platform channel behind it.
class VerificationView extends StatelessWidget {
  /// Renders [state].
  const VerificationView({
    required this.state,
    required this.onSubmit,
    required this.onRestart,
    this.armed = false,
    super.key,
  });

  /// The state to render.
  final VerificationState state;

  /// Called with whatever the user typed.
  final ValueChanged<String> onSubmit;

  /// Called to start the verification over.
  final VoidCallback onRestart;

  /// Whether automatic capture is running for this verification.
  final bool armed;

  @override
  Widget build(BuildContext context) {
    // Exhaustive, with no default arm: a state added in a later release is a
    // compile error here rather than a screen that renders nothing.
    final body = switch (state) {
      VerificationIdle() => const _Busy('Idle'),
      VerificationStarting() => const _Busy('Starting'),
      VerificationAwaitingInput(:final lastError) => _Entry(
          prompt: 'Enter the code',
          error: lastError?.detail,
          armed: armed,
          onSubmit: onSubmit,
        ),
      VerificationCaptured(:final value) => _Entry(
          prompt: 'Captured from the message',
          value: value,
          enabled: false,
          onSubmit: onSubmit,
        ),
      VerificationSubmitting() => const _Busy('Checking'),
      VerificationVerified() => _Outcome(
          icon: Icons.check_circle_outline,
          title: 'Verified',
          onRestart: onRestart,
        ),
      VerificationExpired() => _Outcome(
          icon: Icons.timer_off_outlined,
          title: 'Expired',
          detail: 'The deadline passed. Start a new verification.',
          onRestart: onRestart,
        ),
      VerificationDenied(:final error) => _Outcome(
          icon: Icons.block_outlined,
          title: 'Denied',
          detail: error?.detail ?? 'Refused before the message was sent.',
          onRestart: onRestart,
        ),
      VerificationSetupError(:final code, :final detail) => _Outcome(
          icon: Icons.build_outlined,
          title: 'Application misconfigured',
          // No retry offered: nothing the user does here can fix it.
          detail: detail ?? code,
        ),
      VerificationFailed(:final reason) => _Outcome(
          icon: Icons.error_outline,
          title: 'Failed',
          detail: describeFailure(reason),
          onRestart: onRestart,
        ),
    };

    return Padding(
        padding: const EdgeInsets.all(24), child: Center(child: body));
  }
}

/// A human-readable line for [reason].
///
/// Exhaustive over both sealed trees, so a reason added later has to be given
/// words rather than falling through to a type name.
String describeFailure(FailureReason reason) => switch (reason) {
      ApiFailure(:final error) => error.detail ?? error.code,
      SdkFailure(:final error) => switch (error) {
          SdkAlreadyRunning() => 'A verification is already starting.',
          SdkSuperseded() => 'Replaced by a newer verification.',
          SdkTransportError(:final message) => 'Network: $message',
          SdkConfigurationError(:final message) => message,
          SdkDecodingError(:final message) => 'Unreadable response: $message',
          SdkUnexpectedError(:final message) => 'Unexpected: $message',
        },
    };

class _Busy extends StatelessWidget {
  const _Busy(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label),
        ],
      );
}

class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.icon,
    required this.title,
    this.detail,
    this.onRestart,
  });

  final IconData icon;
  final String title;
  final String? detail;

  /// Null where no retry is offered, because nothing the user does can fix it.
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(detail!, textAlign: TextAlign.center),
          ],
          if (onRestart != null) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRestart,
              child: const Text('Start again'),
            ),
          ],
        ],
      );
}

class _Entry extends StatefulWidget {
  const _Entry({
    required this.prompt,
    required this.onSubmit,
    this.value,
    this.error,
    this.enabled = true,
    this.armed = false,
  });

  final String prompt;
  final ValueChanged<String> onSubmit;
  final String? value;
  final String? error;
  final bool enabled;
  final bool armed;

  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.value != null) _controller.text = widget.value!;
  }

  @override
  void didUpdateWidget(_Entry oldWidget) {
    super.didUpdateWidget(oldWidget);
    final captured = widget.value;
    if (captured != null && captured != _controller.text) {
      _controller.text = captured;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.prompt),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: widget.enabled,
            autofocus: widget.enabled,
            keyboardType: TextInputType.text,
            // Recognised by iOS, where there is no plugin and no need for one.
            autofillHints: const [AutofillHints.oneTimeCode],
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              errorText: widget.error,
              helperText: widget.armed ? 'Listening for the message' : null,
            ),
            onSubmitted: widget.onSubmit,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed:
                widget.enabled ? () => widget.onSubmit(_controller.text) : null,
            child: const Text('Submit'),
          ),
        ],
      );
}
