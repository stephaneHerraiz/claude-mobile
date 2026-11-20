import 'dart:convert';

import 'events.dart';

/// Reassembles newline-delimited lines from arbitrary stream chunks.
class LineBuffer {
  String _rest = '';

  /// Returns the complete lines contained so far; keeps the remainder.
  List<String> add(String chunk) {
    final parts = (_rest + chunk).split('\n');
    _rest = parts.removeLast();
    return parts;
  }
}

/// Parses one stdout line. Returns null when the line is not a JSON object.
ClaudeEvent? parseEvent(String line) {
  final events = parseEvents(line);
  return events.isEmpty ? null : events.first;
}

/// Parses one stdout line into all the events it carries: a single `user`
/// line may hold several tool results. Empty when the line is not a JSON
/// object.
List<ClaudeEvent> parseEvents(String line) {
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map<String, dynamic>) return const [];
  try {
    final events = _fromMap(decoded);
    return events.isEmpty ? [UnknownEvent(decoded)] : events;
  } on TypeError {
    return [UnknownEvent(decoded)];
  }
}

List<ClaudeEvent> _fromMap(Map<String, dynamic> m) {
  final e = _single(m);
  if (e != null) return [e];
  if (m['type'] != 'user') return const [];
  final content = (m['message'] as Map<String, dynamic>?)?['content'];
  if (content is! List) return const [];
  return [
    for (final b in content)
      if (b is Map<String, dynamic> && b['type'] == 'tool_result')
        ToolResult(
          b['tool_use_id'] as String,
          _flattenContent(b['content']),
          b['is_error'] == true,
        ),
  ];
}

ClaudeEvent? _single(Map<String, dynamic> m) {
  switch (m['type']) {
    case 'system':
      if (m['subtype'] != 'init') return null;
      return SystemInit(
        m['session_id'] as String,
        m['cwd'] as String? ?? '',
        m['model'] as String? ?? '',
      );
    case 'assistant':
      final msg = m['message'] as Map<String, dynamic>?;
      if (msg == null) return null;
      final blocks = <ContentBlock>[];
      for (final b in (msg['content'] as List? ?? const [])) {
        if (b is! Map<String, dynamic>) continue;
        if (b['type'] == 'text') {
          blocks.add(TextBlock(b['text'] as String));
        } else if (b['type'] == 'tool_use') {
          blocks.add(
            ToolUseBlock(
              b['id'] as String,
              b['name'] as String,
              (b['input'] as Map?)?.cast<String, dynamic>() ?? const {},
            ),
          );
        }
      }
      return AssistantMessage(msg['id'] as String? ?? '', blocks);
    case 'stream_event':
      final ev = m['event'] as Map<String, dynamic>?;
      final delta = ev?['delta'];
      if (ev?['type'] == 'content_block_delta' &&
          delta is Map<String, dynamic> &&
          delta['type'] == 'text_delta') {
        return StreamDelta(delta['text'] as String);
      }
      return null;
    case 'control_request':
      final r = m['request'] as Map<String, dynamic>?;
      if (r == null || r['subtype'] != 'can_use_tool') return null;
      return PermissionRequest(
        m['request_id'] as String,
        r['tool_use_id'] as String? ?? '',
        r['tool_name'] as String,
        (r['input'] as Map?)?.cast<String, dynamic>() ?? const {},
        r['description'] as String? ?? '',
      );
    case 'result':
      return ResultEvent(
        m['is_error'] == true,
        m['result'] as String? ?? '',
        (m['total_cost_usd'] as num?)?.toDouble() ?? 0,
      );
  }
  return null;
}

String _flattenContent(Object? content) {
  if (content is String) return content;
  if (content is List) {
    return content
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join('\n');
  }
  return '';
}

String encodeUserMessage(String text) => _line({
  'type': 'user',
  'message': {'role': 'user', 'content': text},
});

String encodeAllow(PermissionRequest r) => _controlResponse(r.requestId, {
  'behavior': 'allow',
  'updatedInput': r.input,
});

/// UNVERIFIED wire format: the allow reply was confirmed by the spike, the
/// deny reply was not (see the design doc, "Spike result 2").
String encodeDeny(String requestId, String message) =>
    _controlResponse(requestId, {'behavior': 'deny', 'message': message});

String _controlResponse(String requestId, Map<String, dynamic> response) =>
    _line({
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': requestId,
        'response': response,
      },
    });

String _line(Map<String, dynamic> m) => '${jsonEncode(m)}\n';
