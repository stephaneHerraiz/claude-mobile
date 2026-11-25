import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/chat_state.dart';
import '../core/codec.dart';
import '../core/session_listing.dart';
import '../ssh/ssh_service.dart';

/// Drives one Claude session over an SSH exec channel.
class SessionController extends ValueNotifier<ChatState> {
  SessionController(
    this._ssh, {
    required String? sessionId,
    required this.cwd,
    String Function()? newId,
    List<ChatItem> history = const [],
    String? model,
    this.name,
  }) : _model = model,
       _resumeId = sessionId,
       _newId = newId ?? const Uuid().v4,
       super(ChatState(items: history, sessionId: sessionId));

  SshService _ssh;
  final String cwd;
  final String Function() _newId;

  /// The name a new session is created under; a resumed one keeps its own.
  final String? name;
  final String? _resumeId;

  LineChannel? _channel;
  StreamSubscription<String>? _sub;

  /// True while the remote `claude` process is attached.
  bool get connected => _channel != null;

  /// Model aliases the app offers, as `claude --model` accepts them.
  static const modelChoices = ['sonnet', 'opus', 'haiku', 'fable'];

  String? _model;

  /// The `--model` value in use, or null for Claude's own default.
  String? get model => _model;

  /// Switches the model by re-attaching to the same session with `--model`.
  /// Does nothing if [model] is already in use.
  Future<void> setModel(String? model) {
    if (model == _model) return Future.value();
    _model = model;
    return start();
  }

  static String buildCommand({
    String? resumeId,
    String? newId,
    String? model,
    String? name,
  }) {
    final named = name != null && name.trim().isNotEmpty;
    final session = resumeId != null
        ? '--resume ${shellQuote(resumeId)}'
        : '--session-id ${shellQuote(newId!)}'
              '${named ? ' --name ${shellQuote(name.trim())}' : ''}';
    return 'claude -p --input-format stream-json --output-format stream-json '
        '--verbose --include-partial-messages --permission-prompt-tool stdio '
        '$session${model == null ? '' : ' --model ${shellQuote(model)}'}';
  }

  Future<void>? _starting;

  /// Attaches to the remote session. Calls made while one is in flight share
  /// it: two `claude --resume` on one session would fork its history.
  Future<void> start() =>
      _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    if (_channel != null) {
      // Leaving a live process: what it was doing or asking is void.
      await _detach();
      value = turnAbandoned(value);
    }
    final resume = value.sessionId ?? _resumeId;
    final claude = buildCommand(
      resumeId: resume,
      newId: resume == null ? _newId() : null,
      model: _model,
      name: name,
    );
    // Login shell: a bare SSH exec often lacks the PATH that holds `claude`.
    final command =
        'bash -lc ${shellQuote('cd ${shellQuote(cwd)} && $claude')}';
    final LineChannel channel;
    try {
      channel = await _ssh.open(command);
    } on Object catch (e) {
      value = addNotice(value, 'Could not start Claude: $e');
      return;
    }
    _channel = channel;
    _sub = channel.lines.listen(
      (line) {
        for (final event in parseEvents(line)) {
          value = reduce(value, event);
        }
      },
      onDone: () => _dropped(channel),
      onError: (_) => _dropped(channel),
      cancelOnError: true,
    );
    notifyListeners();
  }

  /// Re-attaches to the same session, over [ssh] when the previous link is
  /// dead. Never answers a request left pending.
  Future<void> reconnect({SshService? ssh}) {
    if (ssh != null) _ssh = ssh;
    return start();
  }

  /// Writes [text] in the conversation, as the app speaking.
  void notice(String text) => value = addNotice(value, text);

  /// Returns false, leaving a notice, when there is no link to send over.
  bool send(String text) {
    final channel = _channel;
    if (channel == null) {
      value = addNotice(value, 'Not connected: message not sent');
      return false;
    }
    channel.writeLine(encodeUserMessage(text));
    value = addUserMessage(value, text);
    return true;
  }

  void approve() {
    final request = value.pending;
    final channel = _channel;
    if (request == null || channel == null) return;
    channel.writeLine(encodeAllow(request));
    value = permissionAnswered(value);
  }

  void deny([String message = 'Denied from phone']) {
    final request = value.pending;
    final channel = _channel;
    if (request == null || channel == null) return;
    channel.writeLine(encodeDeny(request.requestId, message));
    value = permissionAnswered(value);
  }

  void _dropped(LineChannel channel) {
    if (!identical(channel, _channel)) return;
    _channel = null;
    _sub = null;
    final stderr = channel.stderrText.trim();
    var next = value;
    if (stderr.isNotEmpty) next = addNotice(next, stderr);
    value = connectionLost(next);
  }

  Future<void> _detach() async {
    final channel = _channel;
    _channel = null;
    await _sub?.cancel();
    _sub = null;
    await channel?.close();
  }

  @override
  void dispose() {
    unawaited(_detach());
    super.dispose();
  }
}
