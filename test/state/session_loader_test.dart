import 'package:claude_mobile/core/session_listing.dart';
import 'package:claude_mobile/state/session_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1795188400 * 1000);

  test('lists sessions and fills cwd and title from each head', () async {
    final ssh = FakeSsh()
      ..runResults = {
        listSessionsCommand:
            '1795180000.0 /p/-a/old.jsonl\n1795188000.0 /p/-b/new.jsonl\n',
        headCommand('/p/-b/new.jsonl'):
            '{"type":"user","cwd":"/b","message":{"role":"user","content":"newest"}}\n',
        headCommand('/p/-a/old.jsonl'):
            '{"type":"user","cwd":"/a","message":{"role":"user","content":"oldest"}}\n',
      };
    final sessions = await loadSessions(ssh, now);
    expect(sessions.map((s) => s.title), ['newest', 'oldest']);
    expect(sessions.map((s) => s.cwd), ['/b', '/a']);
  });

  test('only reads the head of the newest headLimit sessions', () async {
    final ssh = FakeSsh()
      ..runResults = {
        listSessionsCommand:
            '1795180000.0 /p/-a/old.jsonl\n1795188000.0 /p/-b/new.jsonl\n',
      };
    final sessions = await loadSessions(ssh, now, headLimit: 1);
    expect(sessions.length, 2);
    expect(ssh.ran, [listSessionsCommand, headCommand('/p/-b/new.jsonl')]);
  });

  test('no sessions yields an empty list', () async {
    expect(await loadSessions(FakeSsh(), now), isEmpty);
  });
}
