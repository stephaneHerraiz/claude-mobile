import 'dart:convert';

import 'chat_state.dart';
import 'codec.dart';
import 'events.dart';
import 'session_listing.dart';

/// Reads the end of a session file: enough for recent context without
/// pulling a multi-megabyte transcript onto the phone. The first line may be
/// cut; [parseHistory] skips it.
String historyCommand(String path) => 'tail -c 2000000 ${shellQuote(path)}';

/// Rebuilds the visible conversation from a session `.jsonl`.
List<ChatItem> parseHistory(String jsonl) {
  var state = ChatState.empty();
  for (final line in const LineSplitter().convert(jsonl)) {
    final Object? m;
    try {
      m = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (m is! Map<String, dynamic>) continue;
    if (m['isMeta'] == true || m['isSidechain'] == true) continue;
    final type = m['type'];
    if (type != 'user' && type != 'assistant') continue;

    final text = type == 'user' ? _userText(m) : null;
    if (text != null) {
      state = ChatState(items: [...state.items, UserItem(text)]);
      continue;
    }
    for (final event in parseEvents(line)) {
      if (event is AssistantMessage || event is ToolResult) {
        state = reduce(state, event);
      }
    }
  }
  return [
    for (final item in state.items)
      if (item is ToolItem && item.status == ToolStatus.running)
        ToolItem(
          item.toolUseId,
          item.name,
          item.input,
          status: ToolStatus.error,
          output: 'No result recorded',
        )
      else
        item,
  ];
}

String? _userText(Map<String, dynamic> m) {
  final message = m['message'];
  if (message is! Map) return null;
  final content = message['content'];
  if (content is String) return content;
  if (content is List) {
    final texts = [
      for (final b in content)
        if (b is Map && b['type'] == 'text' && b['text'] is String)
          b['text'] as String,
    ];
    if (texts.isNotEmpty) return texts.join('\n');
  }
  return null;
}
