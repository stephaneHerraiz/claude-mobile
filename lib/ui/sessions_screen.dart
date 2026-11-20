import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/session_listing.dart';
import '../ssh/profile.dart';
import '../state/providers.dart';
import 'chat_screen.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key, required this.profile});

  final Profile profile;

  /// Sessions grouped by working directory; groups keep newest-first order.
  static Map<String, List<SessionInfo>> byCwd(List<SessionInfo> sessions) {
    final groups = <String, List<SessionInfo>>{};
    for (final s in sessions) {
      groups
          .putIfAbsent(s.cwd.isEmpty ? 'Older sessions' : s.cwd, () => [])
          .add(s);
    }
    return groups;
  }

  void _openChat(
    BuildContext context, {
    SessionInfo? session,
    required String cwd,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChatScreen(profile: profile, session: session, cwd: cwd),
      ),
    );
  }

  /// Older sessions are listed without their directory; read it on demand.
  Future<void> _openSession(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
  ) async {
    var s = session;
    if (s.cwd.isEmpty) {
      try {
        final ssh = await ref.read(sshConnectionProvider(profile.id).future);
        s = withHead(s, await ssh.run(headCommand(s.path)));
      } on Object {
        // Reported below: without a directory the session cannot be resumed.
      }
    }
    if (!context.mounted) return;
    if (s.cwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find this session\'s directory.'),
        ),
      );
      return;
    }
    _openChat(context, session: s, cwd: s.cwd);
  }

  Future<void> _newSession(BuildContext context, String suggestion) async {
    final input = TextEditingController(text: suggestion);
    final cwd = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New session'),
        content: TextField(
          controller: input,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Directory on the server',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (cwd == null || cwd.isEmpty || !context.mounted) return;
    _openChat(context, cwd: cwd);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionListProvider(profile.id));
    void refresh() {
      ref.invalidate(sshConnectionProvider(profile.id));
      ref.invalidate(sessionListProvider(profile.id));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(profile.name),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _newSession(context, sessions.value?.firstOrNull?.cwd ?? ''),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New session'),
      ),
      body: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: refresh, child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No session on this server yet.'));
          }
          final groups = byCwd(list);
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    entry.key,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                for (final s in entry.value)
                  ListTile(
                    title: Text(
                      s.title ?? s.id,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_when(s.modified)),
                    trailing: s.recentlyActive
                        ? const Tooltip(
                            message: 'Active in the last minute',
                            child: Icon(Icons.circle, size: 12),
                          )
                        : null,
                    onTap: () => _openSession(context, ref, s),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
