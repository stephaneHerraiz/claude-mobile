import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/session_listing.dart';
import '../ssh/profile.dart';
import '../state/providers.dart';
import 'chat_screen.dart';
import 'terminal_widgets.dart';

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

  /// The chat may have changed the session or made a new one: ask the server
  /// again once it is closed.
  Future<void> _openChat(
    BuildContext context,
    WidgetRef ref, {
    SessionInfo? session,
    required String cwd,
    String? name,
  }) async {
    final list = ref.read(sessionListProvider(profile.id).notifier);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          profile: profile,
          session: session,
          cwd: cwd,
          name: name,
        ),
      ),
    );
    unawaited(list.refresh());
  }

  /// Older sessions are listed without their directory; read it on demand.
  Future<void> _openSession(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
  ) async {
    var s = session;
    if (s.cwd.isEmpty || s.path.isEmpty) {
      try {
        final ssh = await ref.read(sshConnectionProvider(profile.id).future);
        // A session just created here is listed before its file is known.
        if (s.path.isEmpty) {
          final found = (await ssh.run(findSessionCommand(s.id))).trim();
          if (found.isNotEmpty) s = s.withPath(found.split('\n').first);
        }
        if (s.path.isNotEmpty) {
          s = withHead(s, await ssh.run(headCommand(s.path)));
        }
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
    unawaited(_openChat(context, ref, session: s, cwd: s.cwd));
  }

  Future<void> _newSession(
    BuildContext context,
    WidgetRef ref,
    String suggestion,
  ) async {
    final directory = TextEditingController(text: suggestion);
    final name = TextEditingController();
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                helperText: 'Shown here and in Claude Code\'s own lists.',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: directory,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Directory on the server',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    final cwd = directory.text.trim();
    final chosen = name.text.trim();
    if (start != true || cwd.isEmpty || !context.mounted) return;
    unawaited(
      _openChat(context, ref, cwd: cwd, name: chosen.isEmpty ? null : chosen),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SessionInfo session,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this session?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.title ?? session.id),
            const SizedBox(height: 12),
            const Text(
              'Its history is erased from the server. This cannot be undone.',
            ),
            if (session.recentlyActive) ...[
              const SizedBox(height: 12),
              const TermLine(
                'It was active in the last minute and may be open elsewhere.',
                fault: true,
              ),
            ],
          ],
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
    try {
      await ref.read(sessionListProvider(profile.id).notifier).delete(session);
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the session: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionListProvider(profile.id));
    // A new connection rebuilds the list, which asks the server again.
    void refresh() => ref.invalidate(sshConnectionProvider(profile.id));

    return Scaffold(
      appBar: AppBar(
        title: TermTitle(profile.name),
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
            _newSession(context, ref, sessions.value?.firstOrNull?.cwd ?? ''),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New session'),
      ),
      body: Column(
        children: [
          if (sessions.isLoading && sessions.hasValue)
            const LinearProgressIndicator(minHeight: 2),
          if (sessions.hasError && sessions.hasValue)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TermLine('${sessions.error}', fault: true),
            ),
          Expanded(
            child: sessions.when(
              // The cached list stays on screen while the server is asked again.
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              skipError: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TermLine('$e', fault: true),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(
                    child: TermLine('No session on this server yet.'),
                  );
                }
                final groups = byCwd(list);
                final scheme = Theme.of(context).colorScheme;
                return ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final (g, entry) in groups.entries.indexed) ...[
                      // A line between every session, whatever its directory.
                      if (g > 0) const Divider(height: 1),
                      // The directory only situates the sessions: kept discreet.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      for (final (i, s) in entry.value.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          title: Text(
                            s.title ?? s.id,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            // Below the ListTile default (16): two lines of
                            // name fit without crowding the list.
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.primary,
                            ),
                          ),
                          subtitle: Text(_when(s.modified)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (s.recentlyActive)
                                const Tooltip(
                                  message: 'Active in the last minute',
                                  child: Icon(Icons.circle, size: 12),
                                ),
                              IconButton(
                                tooltip: 'Delete ${s.title ?? s.id}',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    _confirmDelete(context, ref, s),
                              ),
                            ],
                          ),
                          onTap: () => _openSession(context, ref, s),
                        ),
                      ],
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
