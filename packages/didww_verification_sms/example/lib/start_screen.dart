import 'package:didww_verification/didww_verification.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_hash_screen.dart';
import 'verify_screen.dart';

/// The loopback address that reaches the host from this runtime.
///
/// The Android emulator does not route `localhost` to the development machine —
/// it routes it to the emulated device — so a mock reached at `localhost` from
/// the simulator has to be reached at `10.0.2.2` from the emulator. Getting this
/// wrong looks like the SDK failing to connect.
String get defaultOrigin =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8787'
        : 'http://localhost:8787';

/// Collects what a verification needs and hands it to [VerifyScreen].
class StartScreen extends StatefulWidget {
  /// Creates the screen.
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final TextEditingController _origin =
      TextEditingController(text: defaultOrigin);
  final TextEditingController _key = TextEditingController(text: 'demo-key');
  final TextEditingController _destination =
      TextEditingController(text: '+49 151 9000001');

  DeliveryMethod _method = DeliveryMethod.sms;
  String? _error;

  @override
  void dispose() {
    _origin.dispose();
    _key.dispose();
    _destination.dispose();
    super.dispose();
  }

  void _go({required bool resume}) {
    final origin = Uri.tryParse(_origin.text.trim());
    if (origin == null || !origin.hasScheme || !origin.hasAuthority) {
      setState(() => _error = 'Not a URL');
      return;
    }
    if (_destination.text.trim().isEmpty) {
      setState(() => _error = 'Enter a number');
      return;
    }
    setState(() => _error = null);

    // Built here and owned by the route that receives it.
    final client = VerificationClient(
      auth: PublicAuthorization(_key.text.trim()),
      environment: VerificationEnvironment.custom(origin),
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VerifyScreen(
          client: client,
          destination: _destination.text.trim(),
          deliveryMethod: _method,
          resume: resume,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Verification'),
          actions: [
            IconButton(
              icon: const Icon(Icons.fingerprint),
              tooltip: 'App hash',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const AppHashScreen(),
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _origin,
              decoration: const InputDecoration(
                labelText: 'API origin',
                helperText: 'The SDK appends the version prefix itself',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _key,
              decoration: const InputDecoration(
                labelText: 'Application key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _destination,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Destination',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SegmentedButton<DeliveryMethod>(
              segments: const [
                ButtonSegment(value: DeliveryMethod.sms, label: Text('SMS')),
                ButtonSegment(
                  value: DeliveryMethod.callout,
                  label: Text('Callout'),
                ),
              ],
              selected: {_method},
              onSelectionChanged: (selection) =>
                  setState(() => _method = selection.single),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _go(resume: false),
              child: const Text('Start verification'),
            ),
            const SizedBox(height: 8),
            // Reattaches without billing, and takes no channel: every option is
            // a create-time choice.
            OutlinedButton(
              onPressed: () => _go(resume: true),
              child: const Text('Resume by number'),
            ),
          ],
        ),
      );
}
