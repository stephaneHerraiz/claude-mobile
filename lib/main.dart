import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'ui/lock_gate.dart';
import 'ui/profiles_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const ProviderScope(child: ClaudeMobileApp()));
}

class ClaudeMobileApp extends StatelessWidget {
  const ClaudeMobileApp({super.key, this.authenticate = deviceAuthenticate});

  final Future<bool?> Function() authenticate;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Claude Mobile',
      theme: terminalTheme,
      home: LockGate(authenticate: authenticate, child: const ProfilesScreen()),
    );
  }
}
