import 'package:flutter/material.dart';

import 'start_screen.dart';

void main() => runApp(const ExampleApp());

/// Demonstrates `didww_verification` and `didww_verification_sms`.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'didww_verification',
        home: const StartScreen(),
      );
}
