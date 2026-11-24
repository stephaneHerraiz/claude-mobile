import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../ssh/key.dart';
import '../ssh/profile.dart';
import '../state/providers.dart';
import 'sessions_screen.dart';
import 'terminal_widgets.dart';

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    return Scaffold(
      appBar: AppBar(title: const TermTitle('Profiles')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add profile',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProfileFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: profiles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const Center(
                child: TermLine('No profile yet. Add one to reach a server.'),
              )
            : ListView(
                children: [
                  for (final (i, p) in list.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: Text(p.name),
                      subtitle: Text(p.address),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SessionsScreen(profile: p),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit ${p.name}',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ProfileFormScreen(profile: p),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete ${p.name}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(context, ref, p),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Profile p,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${p.name}?'),
        content: const Text(
          'Its SSH key is removed from this phone. Sessions on the server '
          'are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(profileStoreProvider).remove(p.id);
    ref.invalidate(profilesProvider);
  }
}

/// Adds a profile, or edits [profile] when given.
class ProfileFormScreen extends ConsumerStatefulWidget {
  const ProfileFormScreen({super.key, this.profile});

  final Profile? profile;

  @override
  ConsumerState<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends ConsumerState<ProfileFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController();
  final _key = TextEditingController();
  final _passphrase = TextEditingController();
  KeyError? _keyError;
  final _jumpHost = TextEditingController();
  final _jumpPort = TextEditingController(text: '22');
  final _jumpUser = TextEditingController();

  Profile? get _editing => widget.profile;

  @override
  void initState() {
    super.initState();
    final p = _editing;
    if (p == null) return;
    _name.text = p.name;
    _host.text = p.host;
    _port.text = '${p.port}';
    _user.text = p.user;
    if (p.jump case final j?) {
      _jumpHost.text = j.host;
      _jumpPort.text = '${j.port}';
      _jumpUser.text = j.user;
    }
  }

  bool get _hasJump => _jumpHost.text.trim().isNotEmpty;

  @override
  void dispose() {
    for (final c in [
      _name,
      _host,
      _port,
      _user,
      _key,
      _passphrase,
      _jumpHost,
      _jumpPort,
      _jumpUser,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  static String? _validPort(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return (n == null || n < 1 || n > 65535) ? 'Port from 1 to 65535' : null;
  }

  Future<void> _save() async {
    setState(() => _keyError = null);
    if (!_form.currentState!.validate()) return;
    // When editing, an empty key field keeps the key already stored.
    String? key;
    if (_editing == null || _key.text.trim().isNotEmpty) {
      try {
        key = unlockKey(_key.text, _passphrase.text);
      } on KeyError catch (e) {
        setState(() => _keyError = e);
        return;
      }
    }
    final profile = Profile(
      id: _editing?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      user: _user.text.trim(),
      jump: _hasJump
          ? JumpHost(
              host: _jumpHost.text.trim(),
              port: int.parse(_jumpPort.text.trim()),
              user: _jumpUser.text.trim(),
            )
          : null,
    );
    final store = ref.read(profileStoreProvider);
    if (_editing == null) {
      await store.save(profile, privateKeyPem: key!);
    } else {
      await store.update(profile, privateKeyPem: key);
      // Drop the live connection: it was opened with the old settings.
      ref.invalidate(sshConnectionProvider(profile.id));
    }
    ref.invalidate(profilesProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const TermTitle(_editing == null ? 'New profile' : 'Edit profile')),
      body: Form(
        key: _form,
        // Not a lazy list: every field must exist to be validated.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: _required,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _host,
                decoration: const InputDecoration(labelText: 'Host'),
                autocorrect: false,
                keyboardType: TextInputType.url,
                validator: _required,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _port,
                decoration: const InputDecoration(labelText: 'Port'),
                keyboardType: TextInputType.number,
                validator: _validPort,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _user,
                decoration: const InputDecoration(labelText: 'User'),
                autocorrect: false,
                validator: _required,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _jumpHost,
                decoration: const InputDecoration(
                  labelText: 'Jump host (optional)',
                  helperText:
                      'A server to go through when the host is not reachable '
                      'directly. The same key is used on both.',
                  helperMaxLines: 2,
                ),
                autocorrect: false,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _jumpPort,
                decoration: const InputDecoration(labelText: 'Jump port'),
                keyboardType: TextInputType.number,
                validator: (v) => _hasJump ? _validPort(v) : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _jumpUser,
                decoration: const InputDecoration(labelText: 'Jump user'),
                autocorrect: false,
                validator: (v) => _hasJump && _required(v) != null
                    ? 'Required with a jump host'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _key,
                decoration: InputDecoration(
                  labelText: 'Private key (PEM)',
                  helperText: _editing == null
                      ? 'Stored only in this phone\'s secure storage.'
                      : 'Leave empty to keep the current key.',
                  errorText: _keyError?.needsPassphrase == false
                      ? _keyError!.message
                      : null,
                  errorMaxLines: 3,
                ),
                autocorrect: false,
                enableSuggestions: false,
                minLines: 3,
                maxLines: 6,
                validator: _editing == null ? _required : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passphrase,
                decoration: InputDecoration(
                  labelText: 'Key passphrase (if any)',
                  helperText: 'Used once to unlock the key. It is not stored.',
                  errorText: _keyError?.needsPassphrase == true
                      ? _keyError!.message
                      : null,
                ),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}
