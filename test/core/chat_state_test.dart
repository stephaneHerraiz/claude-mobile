import 'package:claude_mobile/core/chat_state.dart';
import 'package:claude_mobile/core/events.dart';
import 'package:flutter_test/flutter_test.dart';

const perm = PermissionRequest('req1', 'toolu_1', 'Bash', {
  'command': 'touch a',
}, 'Create a');

ChatState run(List<ClaudeEvent> events, [ChatState? from]) =>
    events.fold(from ?? ChatState.empty(), reduce);

void main() {
  test('SystemInit records the session id', () {
    expect(run([const SystemInit('sid', '/w', 'm')]).sessionId, 'sid');
  });

  test('addUserMessage appends a UserItem and marks busy', () {
    final s = addUserMessage(ChatState.empty(), 'hello');
    expect((s.items.single as UserItem).text, 'hello');
    expect(s.busy, true);
  });

  test('StreamDelta appends to a streaming AssistantTextItem', () {
    final s = run([const StreamDelta('Hel'), const StreamDelta('lo')]);
    final item = s.items.single as AssistantTextItem;
    expect(item.text, 'Hello');
    expect(item.streaming, true);
  });

  test('final AssistantMessage replaces the streaming draft', () {
    final s = run([
      const StreamDelta('Hel'),
      const StreamDelta('lo'),
      const AssistantMessage('m1', [TextBlock('Hello')]),
    ]);
    final item = s.items.single as AssistantTextItem;
    expect(item.text, 'Hello');
    expect(item.streaming, false);
  });

  test('ToolUseBlock adds a running ToolItem, ToolResult marks it done', () {
    var s = run([
      const AssistantMessage('m1', [
        ToolUseBlock('toolu_1', 'Bash', {'command': 'ls'}),
      ]),
    ]);
    var tool = s.items.single as ToolItem;
    expect(tool.name, 'Bash');
    expect(tool.status, ToolStatus.running);

    s = reduce(s, const ToolResult('toolu_1', 'a.txt', false));
    tool = s.items.single as ToolItem;
    expect(tool.status, ToolStatus.done);
    expect(tool.output, 'a.txt');
  });

  test('ToolResult with isError marks the tool as error', () {
    final s = run([
      const AssistantMessage('m1', [ToolUseBlock('t', 'Bash', {})]),
      const ToolResult('t', 'denied', true),
    ]);
    expect((s.items.single as ToolItem).status, ToolStatus.error);
  });

  test('ToolResult for an unknown tool id leaves the state unchanged', () {
    final s = run([const ToolResult('nope', 'x', false)]);
    expect(s.items, isEmpty);
  });

  test('PermissionRequest sets pending, permissionAnswered clears it', () {
    var s = run([perm]);
    expect(s.pending!.requestId, 'req1');
    s = permissionAnswered(s);
    expect(s.pending, isNull);
  });

  test('ResultEvent clears busy and pending and records cost', () {
    var s = addUserMessage(ChatState.empty(), 'go');
    s = run([perm, const ResultEvent(false, 'Done.', 0.04)], s);
    expect(s.busy, false);
    expect(s.pending, isNull);
    expect(s.costUsd, closeTo(0.04, 1e-9));
    expect(s.items.length, 1);
  });

  test('ResultEvent with isError appends a notice with its text', () {
    final s = run([const ResultEvent(true, 'Not logged in', 0)]);
    expect((s.items.single as NoticeItem).text, 'Not logged in');
  });

  test('connectionLost clears pending and busy and appends a notice', () {
    var s = addUserMessage(ChatState.empty(), 'go');
    s = run([
      const AssistantMessage('m1', [ToolUseBlock('t', 'Bash', {})]),
      perm,
      const StreamDelta('par'),
    ], s);
    s = connectionLost(s);
    expect(s.pending, isNull);
    expect(s.busy, false);
    expect((s.items.last as NoticeItem).text, 'Connection lost');
    expect(
      s.items.whereType<ToolItem>().single.status,
      ToolStatus.error,
      reason: 'a tool still running when the link dropped is not running',
    );
    expect(s.items.whereType<AssistantTextItem>().single.streaming, false);
  });

  test('reduce does not mutate the previous state', () {
    final before = run([const StreamDelta('a')]);
    final snapshot = List.of(before.items);
    reduce(before, const StreamDelta('b'));
    expect(before.items, snapshot);
    expect((before.items.single as AssistantTextItem).text, 'a');
  });

  test('UnknownEvent leaves the state unchanged', () {
    final s = ChatState.empty();
    expect(identical(reduce(s, const UnknownEvent({})), s), true);
  });
}
