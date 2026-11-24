import 'dart:convert';

/// A Claude Code session stored on the server.
class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.path,
    required this.modified,
    this.cwd = '',
    this.title,
    this.recentlyActive = false,
  });

  final String id;

  /// Absolute path of the session's `.jsonl` file on the server.
  final String path;
  final DateTime modified;

  /// Working directory of the session; empty until [withHead] fills it.
  final String cwd;
  final String? title;

  /// Written to less than a minute ago: probably open somewhere else.
  final bool recentlyActive;
}

/// Prints `<epoch-seconds> <path>` for every session file. Needs GNU find.
const listSessionsCommand =
    r"find ~/.claude/projects -mindepth 2 -maxdepth 2 -name '*.jsonl' "
    r"-printf '%T@ %p\n' 2>/dev/null";

const _recentWindow = Duration(seconds: 60);
const _titleMax = 80;

/// Parses the output of [listSessionsCommand], newest first.
List<SessionInfo> parseListing(String stdout, DateTime now) {
  final sessions = <SessionInfo>[];
  for (final line in const LineSplitter().convert(stdout)) {
    final space = line.indexOf(' ');
    if (space <= 0) continue;
    final seconds = double.tryParse(line.substring(0, space));
    final path = line.substring(space + 1);
    if (seconds == null || !path.endsWith('.jsonl')) continue;
    final modified = DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000).floor(),
    );
    final name = path.substring(path.lastIndexOf('/') + 1);
    sessions.add(
      SessionInfo(
        id: name.substring(0, name.length - '.jsonl'.length),
        path: path,
        modified: modified,
        recentlyActive: now.difference(modified) < _recentWindow,
      ),
    );
  }
  sessions.sort((a, b) => b.modified.compareTo(a.modified));
  return sessions;
}

String shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// Reads the start of a session file. Byte-bounded because a single line can
/// be huge; [withHead] tolerates the truncated last line.
String headCommand(String path) => 'head -c 65536 ${shellQuote(path)}';

/// Fills [SessionInfo.cwd] and [SessionInfo.title] from the file's first lines.
SessionInfo withHead(SessionInfo s, String headOutput) {
  String? cwd;
  String? title;
  for (final line in const LineSplitter().convert(headOutput)) {
    final Object? m;
    try {
      m = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (m is! Map<String, dynamic>) continue;
    final c = m['cwd'];
    if (cwd == null && c is String && c.isNotEmpty) cwd = c;
    title ??= _userText(m);
    if (cwd != null && title != null) break;
  }
  return SessionInfo(
    id: s.id,
    path: s.path,
    modified: s.modified,
    recentlyActive: s.recentlyActive,
    cwd: cwd ?? s.cwd,
    title: title ?? s.title,
  );
}

String? _userText(Map<String, dynamic> m) {
  if (m['type'] != 'user' || m['isMeta'] == true) return null;
  final msg = m['message'];
  if (msg is! Map) return null;
  final content = msg['content'];
  String? text;
  if (content is String) {
    text = content;
  } else if (content is List) {
    for (final b in content) {
      if (b is Map && b['type'] == 'text' && b['text'] is String) {
        text = b['text'] as String;
        break;
      }
    }
  }
  if (text == null) return null;
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return null;
  return clean.length > _titleMax ? clean.substring(0, _titleMax) : clean;
}
