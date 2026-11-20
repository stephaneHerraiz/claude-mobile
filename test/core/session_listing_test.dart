import 'package:claude_mobile/core/session_listing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1795188400 * 1000);
  const listing =
      '1795180295.5032661040 /home/h/.claude/projects/-home-h-dev-ghrun/ae2ea4ca.jsonl\n'
      '1795188350.1473002620 /home/h/.claude/projects/-home-h-dev/8df988df.jsonl\n';

  test('parses two entries sorted newest first', () {
    final l = parseListing(listing, now);
    expect(l.map((s) => s.id), ['8df988df', 'ae2ea4ca']);
    expect(l.first.path, '/home/h/.claude/projects/-home-h-dev/8df988df.jsonl');
    expect(
      l.first.modified,
      DateTime.fromMillisecondsSinceEpoch(1795188350147),
    );
    expect(l.first.cwd, '');
  });

  test('marks recentlyActive under 60s', () {
    final l = parseListing(listing, now);
    expect(l.first.recentlyActive, true, reason: 'modified 50 s ago');
    expect(l.last.recentlyActive, false);
  });

  test('ignores blank and malformed lines', () {
    final l = parseListing('\nnonsense\nabc /x/y.jsonl\n$listing', now);
    expect(l.length, 2);
  });

  test('keeps a path that contains spaces', () {
    final l = parseListing('1795180295.5 /home/h/my dir/s 1.jsonl\n', now);
    expect(l.single.path, '/home/h/my dir/s 1.jsonl');
    expect(l.single.id, 's 1');
  });

  test('withHead takes cwd from content, not from folder name', () {
    final s = parseListing(
      '1795180295.5 /home/h/.claude/projects/-home-herraiz-dev-my-app/abc.jsonl\n',
      now,
    ).single;
    const head =
        '{"type":"mode"}\n'
        '{"type":"attachment","cwd":"/home/herraiz/dev/my.app"}\n'
        '{"type":"user","cwd":"/home/herraiz/dev/my.app","message":{"role":"user","content":"fix the   login\\nbug please"}}\n'
        '{"type":"user","message":{"role":"user","content":"second"}}\n'
        '{"type":"user","message":{"role":"us'; // cut by head -c
    final filled = withHead(s, head);
    expect(filled.cwd, '/home/herraiz/dev/my.app');
    expect(filled.title, 'fix the login bug please');
    expect(filled.id, 'abc');
  });

  test('withHead skips meta and tool-result user lines for the title', () {
    final s = parseListing('1795180295.5 /p/abc.jsonl\n', now).single;
    const head =
        '{"type":"user","isMeta":true,"message":{"role":"user","content":"caveat"}}\n'
        '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}\n'
        '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"real question"}]}}\n';
    expect(withHead(s, head).title, 'real question');
  });

  test('withHead trims the title to 80 chars and tolerates no user line', () {
    final s = parseListing('1795180295.5 /p/abc.jsonl\n', now).single;
    final long = 'x' * 200;
    final t = withHead(
      s,
      '{"type":"user","message":{"role":"user","content":"$long"}}\n',
    ).title!;
    expect(t.length, 80);
    expect(withHead(s, '{"type":"mode"}\n').title, isNull);
  });

  test('shellQuote escapes a single quote', () {
    expect(shellQuote("/a/it's.jsonl"), r"'/a/it'\''s.jsonl'");
    expect(headCommand("/a/it's.jsonl"), r"head -c 65536 '/a/it'\''s.jsonl'");
  });

  test('listSessionsCommand lists jsonl files with mtime', () {
    expect(listSessionsCommand, contains(r"-printf '%T@ %p\n'"));
    expect(listSessionsCommand, contains('.claude/projects'));
  });
}
