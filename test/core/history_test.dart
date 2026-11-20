import 'package:claude_mobile/core/chat_state.dart';
import 'package:claude_mobile/core/history.dart';
import 'package:flutter_test/flutter_test.dart';

const userLine =
    '{"type":"user","cwd":"/w","isSidechain":false,"message":{"role":"user","content":"fix the bug"},"uuid":"u1"}';
const thinkingLine =
    '{"type":"assistant","message":{"id":"m0","role":"assistant","content":[{"type":"thinking","thinking":"hmm"}]}}';
const assistantLine =
    '{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"text","text":"On it."}]}}';
const toolUseLine =
    '{"type":"assistant","message":{"id":"m2","role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}';
const toolResultLine =
    '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"a.txt","is_error":false}]}}';
const metaLine =
    '{"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>x"}}';
const sidechainLine =
    '{"type":"assistant","isSidechain":true,"message":{"id":"s1","content":[{"type":"text","text":"subagent chatter"}]}}';
const textBlockUserLine =
    '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"typed as block"}]}}';

void main() {
  test('parses a user and assistant turn', () {
    final items = parseHistory('$userLine\n$thinkingLine\n$assistantLine\n');
    expect(items.length, 2);
    expect((items[0] as UserItem).text, 'fix the bug');
    final a = items[1] as AssistantTextItem;
    expect(a.text, 'On it.');
    expect(a.streaming, false);
  });

  test('pairs tool_use with its tool_result', () {
    final items = parseHistory('$toolUseLine\n$toolResultLine\n');
    final tool = items.single as ToolItem;
    expect(tool.name, 'Bash');
    expect(tool.status, ToolStatus.done);
    expect(tool.output, 'a.txt');
  });

  test('a tool with no recorded result is not shown as running', () {
    final tool = parseHistory('$toolUseLine\n').single as ToolItem;
    expect(tool.status, isNot(ToolStatus.running));
  });

  test('skips malformed, meta, sidechain and bookkeeping lines', () {
    final items = parseHistory(
      'ype":"user","message":{"content":"cut by tail"}}\n'
      '{"type":"mode"}\n'
      '$metaLine\n$sidechainLine\n$userLine\n'
      '{"type":"user","message":{"role":"us',
    );
    expect((items.single as UserItem).text, 'fix the bug');
  });

  test('reads a user message typed as a text block', () {
    final items = parseHistory('$textBlockUserLine\n');
    expect((items.single as UserItem).text, 'typed as block');
  });

  test('historyCommand reads the end of the quoted file', () {
    expect(
      historyCommand("/a/b's.jsonl"),
      r"tail -c 2000000 '/a/b'\''s.jsonl'",
    );
  });

  test('empty input yields no items', () {
    expect(parseHistory(''), isEmpty);
  });
}
