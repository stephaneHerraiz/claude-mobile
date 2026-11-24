import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';

/// Device unlock: true/false for the outcome, null when the device has no
/// lock at all (nothing to gate with).
Future<bool?> deviceAuthenticate() async {
  final auth = LocalAuthentication();
  if (!await auth.isDeviceSupported()) return null;
  return auth.authenticate(
    localizedReason: 'Unlock your SSH profiles',
    persistAcrossBackgrounding: true,
  );
}

/// Hides [child] until the user unlocks the app.
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.child,
    this.authenticate = deviceAuthenticate,
  });

  final Widget child;
  final Future<bool?> Function() authenticate;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  bool _unlocked = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  Future<void> _ask() async {
    setState(() => _asking = true);
    bool ok;
    try {
      ok = (await widget.authenticate()) ?? true;
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _unlocked = ok;
      _asking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return Scaffold(
      body: Center(
        child: _asking
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _ask, child: const Text('Unlock')),
                ],
              ),
      ),
    );
  }
}
