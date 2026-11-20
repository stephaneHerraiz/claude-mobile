import 'dart:async';

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/chat_state.dart';
import '../core/history.dart';
import '../core/session_listing.dart';
import '../ssh/profile.dart';
import '../ssh/ssh_service.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'permission_card.dart';

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
    widget.controller.send(text);
    _input.clear();
  }

  void _followNewItems(int count) {
    if (count == _seenItems) return;
    _seenItems = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
                    child: FilledButton.tonal(
                      onPressed: widget.onReconnect ?? controller.reconnect,
                      child: const Text('Reconnect'),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
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
                            border: OutlineInputBorder(),
                            isDense: true,
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
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(item.text),
          ),
        );
      case AssistantTextItem():
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: MarkdownBody(data: item.text, selectable: true),
        );
      case ToolItem():
        return _ToolTile(item);
      case NoticeItem():
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            item.text,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.error),
          ),
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
  });

  final Profile profile;

  /// Null to start a new session in [cwd].
  final SessionInfo? session;
  final String cwd;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  static const _maxAutoRetries = 5;

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

  /// Reconnects, replacing a dead SSH link first.
  Future<bool> _reconnect() async {
    final controller = _controller;
    if (controller == null) return false;
    try {
      var ssh = await _ssh();
      if (!ssh.isConnected) {
        ref.invalidate(sshConnectionProvider(widget.profile.id));
        ssh = await _ssh();
      }
      await controller.reconnect(ssh: ssh);
      return controller.connected;
    } on Object {
      return false;
    }
  }

  void _onChange() {
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
    final controller = _controller;
    if (state == AppLifecycleState.resumed &&
        controller != null &&
        !controller.connected &&
        !_retrying) {
      unawaited(_reconnect());
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.session?.title ?? widget.cwd;
    final controller = _controller;
    if (controller != null) {
      return ChatView(
        controller: controller,
        title: title,
        recentlyActive: widget.session?.recentlyActive ?? false,
        onReconnect: _reconnect,
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$_error', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        ref.invalidate(
                          sshConnectionProvider(widget.profile.id),
                        );
                        _open();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
