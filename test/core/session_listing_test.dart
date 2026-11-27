import 'package:remote_harness/core/session_listing.dart';
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
    expect(
      headCommand("/a/it's.jsonl"),
      startsWith(r"head -c 65536 '/a/it'\''s.jsonl'"),
    );
  });

  test('listSessionsCommand lists jsonl files with mtime', () {
    expect(listSessionsCommand, contains(r"-printf '%T@ %p\n'"));
    expect(listSessionsCommand, contains('.claude/projects'));
  });

  group('session name', () {
    final s = SessionInfo(
      id: 'x',
      path: '/p/x.jsonl',
      modified: DateTime(2026),
    );
    const first =
        '{"type":"user","cwd":"/w","message":{"role":"user","content":"fix the login bug please"}}';
    String ai(String t) => '{"type":"ai-title","aiTitle":"$t","sessionId":"x"}';
    String custom(String t) =>
        '{"type":"custom-title","customTitle":"$t","sessionId":"x"}';

    test('is the name Claude gave the session, the latest one', () {
      final out = [first, ai('Login bug'), ai('Login bug fix')].join('\n');
      expect(withHead(s, out).title, 'Login bug fix');
      expect(withHead(s, out).cwd, '/w');
    });

    test('is the name the user chose, over the one Claude gave', () {
      final out = [first, custom('my name'), ai('Login bug')].join('\n');
      expect(withHead(s, out).title, 'my name');
    });

    test('falls back to the first message when the session has no name', () {
      expect(withHead(s, first).title, 'fix the login bug please');
    });

    test('ignores an empty name', () {
      expect(withHead(s, [first, ai('')].join('\n')).title, startsWith('fix'));
    });

    test('is looked for in the whole file, not only its start', () {
      final command = headCommand('/p/x.jsonl');
      expect(command, contains("grep -a"));
      expect(command, contains('ai-title'));
      expect(command, contains('custom-title'));
      expect(command, contains("'/p/x.jsonl' | tail -n"));
    });
  });

  group('deleteSessionCommand', () {
    const path = '/home/me/.claude/projects/-home-me-app/abc-123.jsonl';

    test('removes the session file and its companion directory', () {
      final command = deleteSessionCommand(path);
      expect(command, contains("rm -f -- '$path'"));
      expect(
        command,
        contains("rm -rf -- '/home/me/.claude/projects/-home-me-app/abc-123'"),
      );
    });

    test('says so only when everything went', () {
      expect(deleteSessionCommand(path), endsWith('&& echo $deletedMarker'));
      expect(sessionDeleted('$deletedMarker\n'), isTrue);
      expect(sessionDeleted(''), isFalse);
      expect(sessionDeleted('rm: cannot remove'), isFalse);
    });

    test('quotes a path with a quote in it', () {
      expect(
        deleteSessionCommand("/h/.claude/projects/-it's/a.jsonl"),
        contains(r"rm -f -- '/h/.claude/projects/-it'\''s/a.jsonl'"),
      );
    });

    for (final bad in [
      '/etc/passwd',
      '/home/me/notes.jsonl',
      '/home/me/.claude/projects/a.jsonl',
      '/home/me/.claude/projects/-app/../../.ssh/x.jsonl',
      '/home/me/.claude/projects/-app/sub/dir/x.jsonl',
      '/home/me/.claude/projects/-app/.jsonl',
      '/home/me/.claude/projects/-app/abc',
      '.claude/projects/-app/abc.jsonl',
      '',
    ]) {
      test('refuses to build a command for "$bad"', () {
        expect(() => deleteSessionCommand(bad), throwsArgumentError);
      });
    }
  });
}
