import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/chat_state.dart';
import '../core/history.dart';
import '../core/session_listing.dart';
import '../ssh/profile.dart';
import '../ssh/ssh_service.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'markdown_text.dart';
import 'permission_card.dart';
import 'terminal_widgets.dart';

/// The conversation itself; knows nothing about how it is connected.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.controller,
    required this.title,
    this.recentlyActive = false,
    this.onReconnect,
  });

  final SessionController controller;
  final String title;

  /// The session file was written to moments ago: probably open elsewhere.
  final bool recentlyActive;

  /// Defaults to [SessionController.reconnect].
  final Future<void> Function()? onReconnect;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _seenItems = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    // Keep what was typed when it could not leave.
    if (widget.controller.send(text)) _input.clear();
  }

  void _followNewItems(int count) {
    if (count == _seenItems) return;
    _seenItems = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  bool _reconnecting = false;

  Future<void> _reconnect() async {
    setState(() => _reconnecting = true);
    try {
      await (widget.onReconnect ?? widget.controller.reconnect)();
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: TermTitle(widget.title)),
      body: SafeArea(
        child: ValueListenableBuilder<ChatState>(
          valueListenable: controller,
          builder: (context, state, _) {
            _followNewItems(state.items.length);
            final pending = state.pending;
            return Column(
              children: [
                if (widget.recentlyActive)
                  const MaterialBanner(
                    content: Text(
                      'This session may be open elsewhere. Writing from two '
                      'places at once can split its history.',
                    ),
                    actions: [SizedBox.shrink()],
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.items.length,
                    itemBuilder: (context, i) => _ItemView(state.items[i]),
                  ),
                ),
                if (state.busy && pending == null)
                  const LinearProgressIndicator(),
                if (pending != null)
                  PermissionCard(
                    request: pending,
                    onApprove: controller.approve,
                    onDeny: controller.deny,
                  ),
                if (!controller.connected)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: OutlinedButton(
                      onPressed: _reconnecting ? null : _reconnect,
                      child: Text(
                        _reconnecting ? 'Reconnecting…' : 'Reconnect',
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _ModelMenu(
                    current: controller.model,
                    // Re-attaching kills the turn in progress and its
                    // questions.
                    enabled: !state.busy && pending == null,
                    onSelected: controller.setModel,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            hintText: 'Message Claude',
                            // Always shown, unlike prefixText.
                            prefixIcon: Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.chevron_right, size: 20),
                            ),
                            prefixIconConstraints: BoxConstraints(),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Send',
                        icon: const Icon(Icons.send),
                        onPressed: _send,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Names the model the session runs with, above the input, and opens the
/// menu that changes it. Null is Claude's own default.
class _ModelMenu extends StatelessWidget {
  const _ModelMenu({
    required this.current,
    required this.enabled,
    required this.onSelected,
  });
  final String? current;
  final bool enabled;
  final void Function(String? model) onSelected;

  @override
  Widget build(BuildContext context) {
    // A real value for "default": a null one reads as a dismissed menu.
    const useDefault = 'default';
    final scheme = Theme.of(context).colorScheme;
    final color = enabled ? scheme.primary : scheme.outline;
    return PopupMenuButton<String>(
      tooltip: 'Model',
      enabled: enabled,
      initialValue: current ?? useDefault,
      onSelected: (m) => onSelected(m == useDefault ? null : m),
      itemBuilder: (context) => [
        for (final m in [useDefault, ...SessionController.modelChoices])
          PopupMenuItem<String>(value: m, child: Text(m)),
      ],
      // A written label: an icon alone went unnoticed.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'model: ',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            Text(
              current ?? useDefault,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

class _ItemView extends StatelessWidget {
  const _ItemView(this.item);
  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = this.item;
    switch (item) {
      case UserItem():
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.fromLTRB(48, 4, 12, 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A shell prompt marks what the user typed.
                Text(
                  '> ',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Flexible(child: SelectableText(item.text)),
              ],
            ),
          ),
        );
      case AssistantTextItem():
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: MarkdownText(item.text),
        );
      case ToolItem():
        return _ToolTile(item);
      case NoticeItem():
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TermLine(item.text, fault: true),
        );
    }
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile(this.item);
  final ToolItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = PermissionCard.detail(item.input).split('\n').first;
    return ExpansionTile(
      dense: true,
      leading: switch (item.status) {
        ToolStatus.running => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        ToolStatus.done => Icon(
          Icons.check_circle_outline,
          color: scheme.primary,
        ),
        ToolStatus.error => Icon(Icons.error_outline, color: scheme.error),
      },
      title: Text(
        '${item.name}  $summary',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          PermissionCard.detail(item.input),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        if (item.output != null && item.output!.isNotEmpty) ...[
          const Divider(),
          SelectableText(
            _clip(item.output!),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ],
    );
  }

  static String _clip(String s) =>
      s.length > 4000 ? '${s.substring(0, 4000)}\n… (truncated)' : s;
}

/// Connects to the profile's server and runs one session in a [ChatView].
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.profile,
    required this.cwd,
    this.session,
    this.name,
  });

  final Profile profile;

  /// Null to start a new session in [cwd].
  final SessionInfo? session;
  final String cwd;

  /// Name given to a new session; unused when [session] is set.
  final String? name;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  static const _maxAutoRetries = 5;
  static const _probeTimeout = Duration(seconds: 5);

  SessionController? _controller;
  Object? _error;
  bool _wasConnected = false;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Holds the SSH connection open for as long as this screen lives.
    ref.listenManual(sshConnectionProvider(widget.profile.id), (_, _) {});
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onChange);
    _controller?.dispose();
    super.dispose();
  }

  Future<SshService> _ssh() =>
      ref.read(sshConnectionProvider(widget.profile.id).future);

  Future<void> _open() async {
    setState(() => _error = null);
    try {
      final ssh = await _ssh();
      final controller = SessionController(
        ssh,
        sessionId: widget.session?.id,
        cwd: widget.cwd,
        name: widget.session == null ? widget.name : null,
        history: await _history(ssh),
      )..addListener(_onChange);
      await controller.start();
      if (!mounted) return controller.dispose();
      setState(() => _controller = controller);
      _wasConnected = controller.connected;
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// What was said before; the chat still works when it cannot be read.
  Future<List<ChatItem>> _history(SshService ssh) async {
    final session = widget.session;
    if (session == null) return const [];
    try {
      return parseHistory(await ssh.run(historyCommand(session.path)));
    } on Object {
      return const [NoticeItem('History unavailable')];
    }
  }

  /// Whether the profile's SSH link is up and answering. A link can look up
  /// long after the network under it is gone, hence the probe.
  Future<bool> _answers() async {
    try {
      final ssh = await _ssh();
      if (!ssh.isConnected) return false;
      await ssh.run('true').timeout(_probeTimeout);
      return true;
    } on Object {
      return false;
    }
  }

  /// The profile's SSH link if it answers, otherwise a new one. A failed
  /// attempt stays remembered until it is discarded, which this also does.
  Future<SshService> _liveSsh({bool knownDead = false}) async {
    if (!knownDead && await _answers()) return _ssh();
    ref.invalidate(sshConnectionProvider(widget.profile.id));
    return _ssh();
  }

  Future<bool>? _reconnecting;

  /// Reconnects, replacing a dead SSH link first. With [report], a failure
  /// is written in the conversation instead of staying silent. Callers that
  /// overlap share one attempt: two would tear down each other's link.
  Future<bool> _reconnect({bool report = false, bool knownDead = false}) =>
      _reconnecting ??= _reconnectOnce(
        report,
        knownDead,
      ).whenComplete(() => _reconnecting = null);

  Future<bool> _reconnectOnce(bool report, bool knownDead) async {
    final controller = _controller;
    if (controller == null) return false;
    try {
      await controller.reconnect(ssh: await _liveSsh(knownDead: knownDead));
      return controller.connected;
    } on Object catch (e) {
      if (report && mounted) controller.notice('Reconnect failed: $e');
      return false;
    }
  }

  /// Back from the background: the phone may have dropped the network while
  /// asleep without the app being told. Check, and reconnect if needed.
  Future<void> _wake() async {
    final controller = _controller;
    if (controller == null) {
      if (_error != null) _retryOpen();
      return;
    }
    // Probed here once; the reconnection need not probe the link again.
    final answers = await _answers();
    if (controller.connected && answers) return;
    if (mounted) await _reconnect(knownDead: !answers);
  }

  void _retryOpen() {
    ref.invalidate(sshConnectionProvider(widget.profile.id));
    _open();
  }

  bool _listed = false;

  /// A session started here joins the sessions list as soon as it has an id.
  void _listNewSession(ChatState state) {
    final id = state.sessionId;
    if (_listed || widget.session != null || id == null) return;
    _listed = true;
    unawaited(
      ref
          .read(sessionListProvider(widget.profile.id).notifier)
          .add(
            SessionInfo(
              id: id,
              path: '',
              modified: DateTime.now(),
              cwd: widget.cwd,
              title: widget.name,
              recentlyActive: true,
            ),
          ),
    );
  }

  void _onChange() {
    final controller = _controller;
    if (controller != null) _listNewSession(controller.value);
    final connected = _controller?.connected ?? false;
    final dropped = _wasConnected && !connected;
    _wasConnected = connected;
    if (dropped) unawaited(_autoRetry());
  }

  /// After a network drop, retries with backoff. A `claude` process that
  /// exits while SSH is still up is left alone: retrying would loop.
  Future<void> _autoRetry() async {
    if (_retrying) return;
    _retrying = true;
    try {
      final ssh = await _ssh().then<SshService?>(
        (s) => s,
        onError: (_) => null,
      );
      if (ssh != null && ssh.isConnected) return;
      for (var attempt = 0; attempt < _maxAutoRetries; attempt++) {
        await Future<void>.delayed(backoff(attempt));
        if (!mounted || (_controller?.connected ?? true)) return;
        if (await _reconnect()) return;
      }
    } finally {
      _retrying = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_wake());
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.session?.title ?? widget.name ?? widget.cwd;
    final controller = _controller;
    if (controller != null) {
      return ChatView(
        controller: controller,
        title: title,
        recentlyActive: widget.session?.recentlyActive ?? false,
        onReconnect: () => _reconnect(report: true),
      );
    }
    return Scaffold(
      appBar: AppBar(title: TermTitle(title)),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TermLine('$_error', fault: true),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _retryOpen,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
