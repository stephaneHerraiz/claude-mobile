import 'events.dart';

sealed class ChatItem {
  const ChatItem();
}

class UserItem extends ChatItem {
  const UserItem(this.text);
  final String text;
}

class AssistantTextItem extends ChatItem {
  const AssistantTextItem(this.text, {this.streaming = false});
  final String text;
  final bool streaming;
}

enum ToolStatus { running, done, error }

class ToolItem extends ChatItem {
  const ToolItem(
    this.toolUseId,
    this.name,
    this.input, {
    this.status = ToolStatus.running,
    this.output,
  });
  final String toolUseId;
  final String name;
  final Map<String, dynamic> input;
  final ToolStatus status;
  final String? output;

  ToolItem _with(ToolStatus status, [String? output]) => ToolItem(
    toolUseId,
    name,
    input,
    status: status,
    output: output ?? this.output,
  );
}

/// An out-of-band line in the chat: errors, connection changes.
class NoticeItem extends ChatItem {
  const NoticeItem(this.text);
  final String text;
}

class ChatState {
  const ChatState({
    required this.items,
    this.pendingQueue = const [],
    this.busy = false,
    this.sessionId,
    this.costUsd = 0,
  });

  factory ChatState.empty() => const ChatState(items: []);

  final List<ChatItem> items;

  /// Permission requests not answered yet, oldest first. Parallel tool calls
  /// can ask several at once; each needs its own answer.
  final List<PermissionRequest> pendingQueue;

  /// The permission request to show the user now, if any.
  PermissionRequest? get pending =>
      pendingQueue.isEmpty ? null : pendingQueue.first;

  /// True while Claude is working on a turn.
  final bool busy;
  final String? sessionId;
  final double costUsd;

  ChatState _copy({
    List<ChatItem>? items,
    List<PermissionRequest>? pendingQueue,
    bool? busy,
    String? sessionId,
    double? costUsd,
  }) => ChatState(
    items: items ?? this.items,
    pendingQueue: pendingQueue ?? this.pendingQueue,
    busy: busy ?? this.busy,
    sessionId: sessionId ?? this.sessionId,
    costUsd: costUsd ?? this.costUsd,
  );
}

ChatState reduce(ChatState s, ClaudeEvent e) {
  switch (e) {
    case SystemInit():
      return s._copy(sessionId: e.sessionId);
    case StreamDelta():
      final last = s.items.isEmpty ? null : s.items.last;
      if (last is AssistantTextItem && last.streaming) {
        return s._copy(
          items: [
            ...s.items.take(s.items.length - 1),
            AssistantTextItem(last.text + e.text, streaming: true),
          ],
        );
      }
      return s._copy(
        items: [...s.items, AssistantTextItem(e.text, streaming: true)],
      );
    case AssistantMessage():
      // A thinking-only message carries nothing to show: keep the draft.
      if (e.blocks.isEmpty) return s;
      return s._copy(
        items: [
          ...s.items.where((i) => !(i is AssistantTextItem && i.streaming)),
          for (final b in e.blocks)
            switch (b) {
              TextBlock() => AssistantTextItem(b.text),
              ToolUseBlock() => ToolItem(b.id, b.name, b.input),
            },
        ],
      );
    case ToolResult():
      if (!s.items.any((i) => i is ToolItem && i.toolUseId == e.toolUseId)) {
        return s;
      }
      return s._copy(
        items: [
          for (final i in s.items)
            if (i is ToolItem && i.toolUseId == e.toolUseId)
              i._with(e.isError ? ToolStatus.error : ToolStatus.done, e.content)
            else
              i,
        ],
      );
    case PermissionRequest():
      return s._copy(pendingQueue: [...s.pendingQueue, e]);
    case ResultEvent():
      return s._copy(
        items: [..._settled(s.items), if (e.isError) NoticeItem(e.text)],
        pendingQueue: const [],
        busy: false,
        costUsd: e.costUsd,
      );
    case UnknownEvent():
      return s;
  }
}

ChatState addUserMessage(ChatState s, String text) =>
    s._copy(items: [...s.items, UserItem(text)], busy: true);

/// The user answered the request on screen; the next queued one shows up.
ChatState permissionAnswered(ChatState s) =>
    s._copy(pendingQueue: s.pendingQueue.skip(1).toList());

/// The remote process is gone: nothing is running or waiting any more.
ChatState turnAbandoned(ChatState s) => s._copy(
  items: [
    for (final i in _settled(s.items))
      if (i is ToolItem && i.status == ToolStatus.running)
        i._with(ToolStatus.error, 'Interrupted')
      else
        i,
  ],
  pendingQueue: const [],
  busy: false,
);

/// The transport dropped under the remote process.
ChatState connectionLost(ChatState s) =>
    addNotice(turnAbandoned(s), 'Connection lost');

List<ChatItem> _settled(List<ChatItem> items) => [
  for (final i in items)
    if (i is AssistantTextItem && i.streaming) AssistantTextItem(i.text) else i,
];

ChatState addNotice(ChatState s, String text) =>
    s._copy(items: [...s.items, NoticeItem(text)]);
