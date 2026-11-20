import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../ssh/profile.dart';
import '../state/providers.dart';
import 'sessions_screen.dart';

class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
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
                child: Text('No profile yet. Add one to reach a server.'),
              )
            : ListView(
                children: [
                  for (final p in list)
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: Text(p.name),
                      subtitle: Text('${p.user}@${p.host}:${p.port}'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SessionsScreen(profile: p),
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete ${p.name}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, ref, p),
                      ),
                    ),
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

class ProfileFormScreen extends ConsumerStatefulWidget {
  const ProfileFormScreen({super.key});

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

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _user, _key]) {
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
    if (!_form.currentState!.validate()) return;
    await ref
        .read(profileStoreProvider)
        .save(
          Profile(
            id: const Uuid().v4(),
            name: _name.text.trim(),
            host: _host.text.trim(),
            port: int.parse(_port.text.trim()),
            user: _user.text.trim(),
          ),
          privateKeyPem: _key.text.trim(),
        );
    ref.invalidate(profilesProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New profile')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: _required,
            ),
            TextFormField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'Host'),
              autocorrect: false,
              keyboardType: TextInputType.url,
              validator: _required,
            ),
            TextFormField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
              validator: _validPort,
            ),
            TextFormField(
              controller: _user,
              decoration: const InputDecoration(labelText: 'User'),
              autocorrect: false,
              validator: _required,
            ),
            TextFormField(
              controller: _key,
              decoration: const InputDecoration(
                labelText: 'Private key (PEM)',
                helperText: 'Stored only in this phone\'s secure storage.',
              ),
              autocorrect: false,
              enableSuggestions: false,
              minLines: 3,
              maxLines: 6,
              validator: _required,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
