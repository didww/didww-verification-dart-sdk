import 'package:didww_verification_sms/didww_verification_sms.dart';
import 'package:flutter/material.dart';

/// Displays [getAppHash] for the running build.
///
/// Play App Signing re-signs the upload artifact, so this screen is the only
/// place the value that actually reaches the device can be read.
class AppHashScreen extends StatefulWidget {
  /// Creates the screen.
  const AppHashScreen({super.key});

  @override
  State<AppHashScreen> createState() => _AppHashScreenState();
}

class _AppHashScreenState extends State<AppHashScreen> {
  late final Future<String?> _hash = getAppHash();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('App hash')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: FutureBuilder<String?>(
              future: _hash,
              builder: (context, snapshot) => switch (snapshot) {
                AsyncSnapshot(connectionState: ConnectionState.waiting) =>
                  const CircularProgressIndicator(),
                AsyncSnapshot(:final Object error) => Text('$error'),
                AsyncSnapshot(data: final String hash) => _Hash(hash),
                _ => const Text('No app hash on this platform.'),
              },
            ),
          ),
        ),
      );
}

class _Hash extends StatelessWidget {
  const _Hash(this.hash);

  final String hash;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('App hash for this build'),
          const SizedBox(height: 8),
          SelectableText(
            hash,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 24),
          ),
          const SizedBox(height: 24),
          const Text(
            'Register this value with the verification API. It comes from the '
            'certificate that signed the installed build, so a value read off a '
            'locally signed build will not match one Play App Signing re-signed.',
            textAlign: TextAlign.center,
          ),
        ],
      );
}
