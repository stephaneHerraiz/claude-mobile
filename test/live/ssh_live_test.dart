// Runs the real SSH stack against a real server. Skipped unless LIVE_SSH_HOST
// is set; `tool/live_rig/start.sh` prints the variables for a local rig.
import 'dart:async';
import 'dart:io';

import 'package:claude_mobile/core/chat_state.dart';
import 'package:claude_mobile/core/history.dart';
import 'package:claude_mobile/ssh/profile.dart';
import 'package:claude_mobile/ssh/ssh_service.dart';
import 'package:claude_mobile/state/session_controller.dart';
import 'package:claude_mobile/state/session_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Future<void> until(
  SessionController c,
  bool Function(ChatState s) ready,
) async {
  if (ready(c.value)) return;
  final done = Completer<void>();
  void check() {
    if (ready(c.value) && !done.isCompleted) done.complete();
  }

  c.addListener(check);
  try {
    await done.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('Timed out. Items: ${c.value.items}'),
    );
  } finally {
    c.removeListener(check);
  }
}

void main() {
  final env = Platform.environment;
  final host = env['LIVE_SSH_HOST'];
  final skip = host == null ? 'LIVE_SSH_HOST is not set' : null;

  late Profile profile;
  late String key;
  late String cwd;
  late MemoryStore store;
  late DartSsh2Service ssh;

  setUp(() async {
    if (host == null) return;
    profile = Profile(
      id: 'live',
      name: 'live',
      host: host,
      port: int.parse(env['LIVE_SSH_PORT'] ?? '22'),
      user: env['LIVE_SSH_USER']!,
    );
    key = File(env['LIVE_SSH_KEY']!).readAsStringSync();
    cwd = env['LIVE_SSH_CWD']!;
    store = MemoryStore();
    ssh = DartSsh2Service(store);
    await ssh.connect(profile, key);
  });

  tearDown(() async {
    if (host != null) await ssh.disconnect();
  });

  test('pins the host key at first connection', () {
    expect(ssh.isConnected, isTrue);
    expect(store.data['hostkey:live'], isNotEmpty);
  }, skip: skip);

  test('refuses a server whose key differs from the pinned one', () async {
    store.data['hostkey:live'] = 'ssh-ed25519 00';
    await expectLater(
      DartSsh2Service(store).connect(profile, key),
      throwsA(isA<HostKeyMismatch>()),
    );
  }, skip: skip);

  test('reaches the server through a jump host', () async {
    final viaJump = Profile(
      id: 'hop',
      name: 'hop',
      host: host!,
      port: profile.port,
      user: profile.user,
      jump: JumpHost(
        host: host,
        port: int.parse(env['LIVE_SSH_JUMP_PORT']!),
        user: profile.user,
      ),
    );
    final hop = DartSsh2Service(store);
    addTearDown(hop.disconnect);
    await hop.connect(viaJump, key);
    expect(await hop.run('echo through'), 'through\n');
    // Two different servers answered, each pinned under its own entry.
    expect(store.data['hostkey:hop'], store.data['hostkey:live']);
    expect(store.data['hostkey:hop:jump'], isNotNull);
    expect(store.data['hostkey:hop:jump'], isNot(store.data['hostkey:hop']));

    final c = SessionController(hop, sessionId: null, cwd: cwd);
    addTearDown(c.dispose);
    await c.start();
    c.send('a.txt');
    await until(c, (s) => s.pending != null);
    c.approve();
    await until(c, (s) => !s.busy && s.costUsd > 0);
    expect(c.value.items.whereType<ToolItem>().single.status, ToolStatus.done);
  }, skip: skip);

  test('refuses a jump host whose key changed', () async {
    store.data['hostkey:hop:jump'] = 'ssh-ed25519 00';
    final viaJump = Profile(
      id: 'hop',
      name: 'hop',
      host: host!,
      port: profile.port,
      user: profile.user,
      jump: JumpHost(
        host: host,
        port: int.parse(env['LIVE_SSH_JUMP_PORT']!),
        user: profile.user,
      ),
    );
    final hop = DartSsh2Service(store);
    await expectLater(
      hop.connect(viaJump, key),
      throwsA(isA<HostKeyMismatch>()),
    );
    expect(hop.isConnected, isFalse);
  }, skip: skip);

  test('lists sessions with their title and directory', () async {
    final sessions = await loadSessions(ssh, DateTime.now());
    final s = sessions.firstWhere((s) => s.id.startsWith('11111111'));
    expect(s.cwd, '/tmp/demo');
    expect(s.title, 'Fix the login bug');
    final history = parseHistory(await ssh.run(historyCommand(s.path)));
    expect(history.whereType<UserItem>().single.text, 'Fix the login bug');
    expect(history.whereType<AssistantTextItem>().single.text, 'On it.');
  }, skip: skip);

  test('runs a turn and relays an approval', () async {
    final c = SessionController(ssh, sessionId: null, cwd: cwd);
    addTearDown(c.dispose);
    await c.start();
    expect(c.send('a.txt'), isTrue);
    await until(c, (s) => s.pending != null);
    expect(c.value.pending!.input['command'], 'touch a.txt');
    c.approve();
    await until(c, (s) => !s.busy && s.costUsd > 0);

    final items = c.value.items;
    expect(items.whereType<NoticeItem>(), isEmpty, reason: '$items');
    final tool = items.whereType<ToolItem>().single;
    expect(tool.status, ToolStatus.done);
    expect(tool.output, 'ok');
    expect(items.whereType<AssistantTextItem>().map((i) => i.text), [
      'Working',
      'Done.',
    ]);
    expect(c.value.sessionId, isNotNull);
  }, skip: skip);

  test('relays a refusal, then runs a second turn', () async {
    final c = SessionController(ssh, sessionId: null, cwd: cwd);
    addTearDown(c.dispose);
    await c.start();
    c.send('a.txt');
    await until(c, (s) => s.pending != null);
    c.deny('Not now');
    await until(c, (s) => !s.busy && s.costUsd > 0);
    expect(c.value.items.whereType<ToolItem>().single.status, ToolStatus.error);

    c.send('b.txt');
    await until(c, (s) => s.pending != null);
    c.approve();
    await until(c, (s) => !s.busy && s.costUsd == 0.02);
    expect(c.value.items.whereType<NoticeItem>(), isEmpty);
  }, skip: skip);

  test('reports a dropped connection and resumes the session', () async {
    final c = SessionController(ssh, sessionId: null, cwd: cwd);
    addTearDown(c.dispose);
    await c.start();
    c.send('a.txt');
    await until(c, (s) => s.pending != null);
    final session = c.value.sessionId;

    await ssh.disconnect();
    await until(c, (s) => s.items.any((i) => i is NoticeItem));
    expect(c.connected, isFalse);
    expect(c.value.pending, isNull);

    final again = DartSsh2Service(store);
    addTearDown(again.disconnect);
    await again.connect(profile, key);
    await c.reconnect(ssh: again);
    c.send('b.txt');
    await until(c, (s) => s.pending != null);
    expect(c.value.sessionId, session);
  }, skip: skip);

  test('says so when the directory does not exist', () async {
    final c = SessionController(ssh, sessionId: null, cwd: '/no/such/dir');
    addTearDown(c.dispose);
    await c.start();
    await until(c, (s) => s.items.any((i) => i is NoticeItem));
    final notice = c.value.items.whereType<NoticeItem>().first;
    expect(notice.text, contains('/no/such/dir'));
  }, skip: skip);
}
