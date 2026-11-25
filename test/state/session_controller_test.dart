import 'dart:convert';

import 'package:claude_mobile/core/chat_state.dart';
import 'package:claude_mobile/state/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const initLine =
    '{"type":"system","subtype":"init","cwd":"/w","session_id":"sid-1","model":"m"}';
const permLine =
    '{"type":"control_request","request_id":"req-9","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"touch a"},"description":"d","tool_use_id":"t1"}}';
const resultLine =
    '{"type":"result","subtype":"success","is_error":false,"result":"Done.","total_cost_usd":0.01}';

void main() {
  late FakeSsh ssh;

  setUp(() => ssh = FakeSsh());

  SessionController make({String? sessionId}) => SessionController(
    ssh,
    sessionId: sessionId,
    cwd: "/home/me/my proj",
    newId: () => 'new-uuid',
  );

  group('buildCommand', () {
    test('includes every transport flag and resumes', () {
      final c = SessionController.buildCommand(resumeId: 'abc');
      for (final flag in [
        'claude -p',
        '--input-format stream-json',
        '--output-format stream-json',
        '--verbose',
        '--include-partial-messages',
        '--permission-prompt-tool stdio',
        "--resume 'abc'",
      ]) {
        expect(c, contains(flag));
      }
      expect(c, isNot(contains('--session-id')));
    });

    test('uses --session-id for a new session', () {
      final c = SessionController.buildCommand(newId: 'u-1');
      expect(c, contains("--session-id 'u-1'"));
      expect(c, isNot(contains('--resume')));
    });
  });

  group('session name', () {
    test('a new session is started under its name', () {
      final c = SessionController.buildCommand(newId: 'u-1', name: "it's mine");
      expect(c, contains(r"--name 'it'\''s mine'"));
    });

    test('a session without a name gets no --name', () {
      expect(
        SessionController.buildCommand(newId: 'u-1'),
        isNot(contains('--name')),
      );
      expect(
        SessionController.buildCommand(newId: 'u-1', name: '  '),
        isNot(contains('--name')),
      );
    });

    test('resuming never renames the session', () {
      final c = SessionController.buildCommand(resumeId: 'abc', name: 'x');
      expect(c, isNot(contains('--name')));
    });

    test('the name is given at the first start only', () async {
      final c = SessionController(
        ssh,
        sessionId: null,
        cwd: '/w',
        newId: () => 'new-uuid',
        name: 'deploy fix',
      );
      await c.start();
      expect(ssh.opened.single, contains('--name'));
      expect(ssh.opened.single, contains('deploy fix'));
      ssh.channels.last.out.add(initLine);
      await Future<void>.delayed(Duration.zero);
      await c.reconnect();
      expect(ssh.opened.last, contains('--resume'));
      expect(ssh.opened.last, isNot(contains('--name')));
    });
  });

  group('model', () {
    test('buildCommand adds --model only when one is chosen', () {
      expect(
        SessionController.buildCommand(resumeId: 'abc', model: 'opus'),
        endsWith("--resume 'abc' --model 'opus'"),
      );
      expect(
        SessionController.buildCommand(resumeId: 'abc'),
        isNot(contains('--model')),
      );
    });

    test('setModel re-attaches to the same session with the model', () async {
      final c = make(sessionId: 'abc');
      await c.start();
      await c.setModel('opus');
      expect(ssh.opened, hasLength(2));
      expect(ssh.opened.last, contains('--resume'));
      expect(ssh.opened.last, contains('--model'));
      expect(ssh.opened.last, contains('opus'));
      expect(c.model, 'opus');
    });

    test('setModel to the current model does nothing', () async {
      final c = make(sessionId: 'abc');
      await c.start();
      await c.setModel(null);
      expect(ssh.opened, hasLength(1));
    });

    test('setModel(null) goes back to the default', () async {
      final c = make(sessionId: 'abc');
      await c.start();
      await c.setModel('haiku');
      await c.setModel(null);
      expect(ssh.opened.last, isNot(contains('--model')));
    });
  });

  test('start opens the command in the cwd through a login shell', () async {
    final c = make(sessionId: 'abc');
    await c.start();
    final cmd = ssh.opened.single;
    expect(cmd, startsWith('bash -lc '));
    expect(cmd, contains('cd '));
    expect(cmd, contains('my proj'));
    expect(cmd, contains('--resume'));
    expect(cmd, contains('abc'));
    expect(c.connected, true);
  });

  test('start without a session id creates one', () async {
    final c = make();
    await c.start();
    expect(ssh.opened.single, contains('--session-id'));
    expect(ssh.opened.single, contains('new-uuid'));
  });

  test('send writes the user message and marks busy', () async {
    final c = make(sessionId: 'abc');
    await c.start();
    c.send('hello');
    expect(jsonDecode(ssh.channels.single.written.single), {
      'type': 'user',
      'message': {'role': 'user', 'content': 'hello'},
    });
    expect(c.value.busy, true);
    expect((c.value.items.single as UserItem).text, 'hello');
  });

  test('send while disconnected writes nothing and adds a notice', () async {
    final c = make(sessionId: 'abc');
    c.send('hello');
    expect(ssh.channels, isEmpty);
    expect(c.value.items.single, isA<NoticeItem>());
    expect(c.value.busy, false);
  });

  test('approve answers the pending request with its id', () async {
    final c = make(sessionId: 'abc');
    await c.start();
    ssh.channels.single.out.add(permLine);
    await pumpEventQueue();
    expect(c.value.pending!.requestId, 'req-9');

    c.approve();
    final reply = jsonDecode(ssh.channels.single.written.single) as Map;
    expect(reply['response']['request_id'], 'req-9');
    expect(reply['response']['response']['behavior'], 'allow');
    expect(reply['response']['response']['updatedInput'], {
      'command': 'touch a',
    });
    expect(c.value.pending, isNull);
  });

  test('deny answers with behavior deny', () async {
    final c = make(sessionId: 'abc');
    await c.start();
    ssh.channels.single.out.add(permLine);
    await pumpEventQueue();
    c.deny();
    final reply = jsonDecode(ssh.channels.single.written.single) as Map;
    expect(reply['response']['response']['behavior'], 'deny');
    expect(reply['response']['request_id'], 'req-9');
    expect(c.value.pending, isNull);
  });

  test('approve without a pending request writes nothing', () async {
    final c = make(sessionId: 'abc');
    await c.start();
    c.approve();
    c.deny();
    expect(ssh.channels.single.written, isEmpty);
  });

  test('channel dropping mid-request clears pending and disconnects', () async {
    final c = make(sessionId: 'abc');
    await c.start();
    c.send('go');
    ssh.channels.single.out.add(permLine);
    await pumpEventQueue();
    await ssh.channels.single.drop();
    await pumpEventQueue();
    expect(c.value.pending, isNull);
    expect(c.value.busy, false);
    expect(c.connected, false);
    expect((c.value.items.last as NoticeItem).text, 'Connection lost');
    c.approve();
    expect(ssh.channels.single.written.length, 1, reason: 'only the message');
  });

  test(
    'reconnect resumes with the id from SystemInit, answers nothing',
    () async {
      final c = make();
      await c.start();
      ssh.channels.single.out.add(initLine);
      ssh.channels.single.out.add(permLine);
      await pumpEventQueue();
      await ssh.channels.single.drop();
      await pumpEventQueue();

      await c.reconnect();
      expect(ssh.opened.length, 2);
      expect(ssh.opened.last, contains('--resume'));
      expect(ssh.opened.last, contains('sid-1'));
      expect(ssh.channels.last.written, isEmpty);
      expect(c.connected, true);
    },
  );

  test('events from a replaced channel are ignored', () async {
    final c = make(sessionId: 'abc');
    await c.start();
    final old = ssh.channels.single;
    await c.reconnect();
    expect(old.closed, true);
    expect(c.connected, true, reason: 'closing the old channel is not a drop');
    expect(c.value.items.whereType<NoticeItem>(), isEmpty);
  });

  test('a failing start reports the error and stays disconnected', () async {
    ssh.openError = StateError('Not connected');
    final c = make(sessionId: 'abc');
    await c.start();
    expect(c.connected, false);
    expect(
      (c.value.items.single as NoticeItem).text,
      contains('Not connected'),
    );
  });

  test('non-JSON output lines are ignored', () async {
    final c = make(sessionId: 'abc');
    await c.start();
    ssh.channels.single.out.add('Welcome to my server');
    ssh.channels.single.out.add(resultLine);
    await pumpEventQueue();
    expect(c.value.items, isEmpty);
    expect(c.value.costUsd, closeTo(0.01, 1e-9));
  });

  test('process exiting with stderr shows it', () async {
    final c = make(sessionId: 'abc');
    await c.start();
    ssh.channels.single.stderrText = 'bash: claude: command not found\n';
    await ssh.channels.single.drop();
    await pumpEventQueue();
    expect(
      c.value.items.whereType<NoticeItem>().map((n) => n.text),
      contains('bash: claude: command not found'),
    );
  });

  test(
    'the remote command quotes a cwd with a space and an apostrophe',
    () async {
      String q(String s) => "'${s.replaceAll("'", r"'\''")}'";
      final c = SessionController(
        ssh,
        sessionId: 'abc',
        cwd: "/home/me/it's mine",
        newId: () => 'n',
      );
      await c.start();
      const claude =
          'claude -p --input-format stream-json --output-format stream-json '
          '--verbose --include-partial-messages --permission-prompt-tool stdio '
          "--resume 'abc'";
      // What bash -lc must receive once the outer quoting is undone.
      const inner = r"cd '/home/me/it'\''s mine' && " + claude;
      expect(ssh.opened.single, 'bash -lc ${q(inner)}');
    },
  );

  test('two starts at once open a single remote process', () async {
    final c = make(sessionId: 'abc');
    await Future.wait([c.start(), c.start(), c.reconnect()]);
    expect(ssh.opened.length, 1);
    expect(c.connected, true);
  });

  test('send reports whether the message left', () async {
    final c = make(sessionId: 'abc');
    expect(c.send('lost'), false);
    await c.start();
    expect(c.send('sent'), true);
  });

  test('approving answers queued requests one at a time, in order', () async {
    final c = make(sessionId: 'abc');
    await c.start();
    ssh.channels.single.out.add(permLine);
    ssh.channels.single.out.add(permLine.replaceAll('req-9', 'req-10'));
    await pumpEventQueue();
    c.approve();
    expect(c.value.pending!.requestId, 'req-10');
    c.deny();
    final ids = [
      for (final w in ssh.channels.single.written)
        (jsonDecode(w) as Map)['response']['request_id'],
    ];
    expect(ids, ['req-9', 'req-10']);
    expect(c.value.pending, isNull);
  });

  test(
    'reattaching drops the request the old process was waiting on',
    () async {
      final c = make(sessionId: 'sid-1');
      await c.start();
      ssh.channels.last.out.add(permLine);
      await Future<void>.delayed(Duration.zero);
      expect(c.value.pending, isNotNull);

      await c.reconnect();
      expect(ssh.channels.length, 2);
      // The new process knows nothing of that request: answering it would
      // write an unknown id, and it would hide the next real request.
      expect(c.value.pending, isNull);
      expect(c.value.busy, isFalse);
      expect(c.value.items.whereType<NoticeItem>(), isEmpty);
    },
  );
}
