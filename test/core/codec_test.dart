import 'dart:convert';

import 'package:remote_harness/core/codec.dart';
import 'package:remote_harness/core/events.dart';
import 'package:flutter_test/flutter_test.dart';

const initLine =
    '{"type":"system","subtype":"init","cwd":"/work2","session_id":"c93208bf","tools":["Bash"],"model":"claude-sonnet-5-5","permissionMode":"default"}';
const toolUseLine =
    '{"type":"assistant","message":{"model":"claude-sonnet-5-5","id":"msg_1","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"touch hello.txt","description":"Create empty file hello.txt"}}]},"session_id":"c93208bf"}';
const textLine =
    '{"type":"assistant","message":{"id":"msg_2","role":"assistant","content":[{"type":"text","text":"Done."}]},"session_id":"c93208bf"}';
const permLine =
    '{"type":"control_request","request_id":"480dbecf","request":{"subtype":"can_use_tool","tool_name":"Bash","display_name":"Bash","input":{"command":"touch hello.txt","description":"Create empty file hello.txt"},"description":"Create empty file hello.txt","permission_suggestions":[],"blocked_path":"/work2/hello.txt","tool_use_id":"toolu_1"}}';
const toolResultLine =
    '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_1","type":"tool_result","content":"(Bash completed with no output)","is_error":false}]},"session_id":"c93208bf"}';
const toolResultListLine =
    '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_2","type":"tool_result","content":[{"type":"text","text":"line a"},{"type":"text","text":"line b"}],"is_error":true}]}}';
const resultLine =
    '{"type":"result","subtype":"success","is_error":false,"result":"Done.","total_cost_usd":0.0427,"session_id":"c93208bf"}';
const deltaLine =
    '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}},"session_id":"c93208bf"}';

void main() {
  group('parseEvent', () {
    test('parses system init', () {
      final e = parseEvent(initLine) as SystemInit;
      expect(e.sessionId, 'c93208bf');
      expect(e.cwd, '/work2');
      expect(e.model, 'claude-sonnet-5-5');
    });

    test('parses assistant tool_use', () {
      final e = parseEvent(toolUseLine) as AssistantMessage;
      expect(e.id, 'msg_1');
      final b = e.blocks.single as ToolUseBlock;
      expect(b.id, 'toolu_1');
      expect(b.name, 'Bash');
      expect(b.input['command'], 'touch hello.txt');
    });

    test('parses assistant text', () {
      final e = parseEvent(textLine) as AssistantMessage;
      expect((e.blocks.single as TextBlock).text, 'Done.');
    });

    test('parses can_use_tool', () {
      final e = parseEvent(permLine) as PermissionRequest;
      expect(e.requestId, '480dbecf');
      expect(e.toolUseId, 'toolu_1');
      expect(e.toolName, 'Bash');
      expect(e.input['command'], 'touch hello.txt');
      expect(e.description, 'Create empty file hello.txt');
    });

    test('parses tool_result with string content', () {
      final e = parseEvent(toolResultLine) as ToolResult;
      expect(e.toolUseId, 'toolu_1');
      expect(e.content, '(Bash completed with no output)');
      expect(e.isError, false);
    });

    test('parses tool_result with list content', () {
      final e = parseEvent(toolResultListLine) as ToolResult;
      expect(e.content, 'line a\nline b');
      expect(e.isError, true);
    });

    test('parses result', () {
      final e = parseEvent(resultLine) as ResultEvent;
      expect(e.isError, false);
      expect(e.text, 'Done.');
      expect(e.costUsd, closeTo(0.0427, 1e-9));
    });

    test('parses text delta from stream_event', () {
      final e = parseEvent(deltaLine) as StreamDelta;
      expect(e.text, 'Hel');
    });

    test('unknown type yields UnknownEvent', () {
      expect(parseEvent('{"type":"rate_limit_event"}'), isA<UnknownEvent>());
      expect(
        parseEvent('{"type":"system","subtype":"hook_started"}'),
        isA<UnknownEvent>(),
      );
    });

    test('garbage line yields null', () {
      expect(parseEvent('not json'), isNull);
      expect(parseEvent('[1,2]'), isNull);
      expect(parseEvent(''), isNull);
    });

    test('known type with missing fields does not throw', () {
      expect(parseEvent('{"type":"assistant"}'), isA<UnknownEvent>());
      expect(parseEvent('{"type":"control_request"}'), isA<UnknownEvent>());
    });
  });

  test('parseEvents returns every tool_result of one user line', () {
    const line =
        '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"a","type":"tool_result","content":"1"},{"tool_use_id":"b","type":"tool_result","content":"2"}]}}';
    final events = parseEvents(line).cast<ToolResult>();
    expect(events.map((e) => e.toolUseId), ['a', 'b']);
    expect(parseEvents('garbage'), isEmpty);
    expect(parseEvents(resultLine).single, isA<ResultEvent>());
  });

  group('LineBuffer', () {
    test('joins a line split across two chunks', () {
      final b = LineBuffer();
      expect(b.add('{"a":'), isEmpty);
      expect(b.add('1}\n'), ['{"a":1}']);
    });

    test('splits two lines in one chunk and keeps the remainder', () {
      final b = LineBuffer();
      expect(b.add('one\ntwo\nthr'), ['one', 'two']);
      expect(b.add('ee\n'), ['three']);
    });
  });

  group('encoders', () {
    test('encodeUserMessage is one JSON line', () {
      final s = encodeUserMessage('hi\nthere');
      expect(s.endsWith('\n'), true);
      expect(s.trimRight().contains('\n'), false);
      expect(jsonDecode(s), {
        'type': 'user',
        'message': {'role': 'user', 'content': 'hi\nthere'},
      });
    });

    test('encodeAllow echoes request id and input', () {
      final r = parseEvent(permLine) as PermissionRequest;
      final s = encodeAllow(r);
      expect(s.endsWith('\n'), true);
      expect(jsonDecode(s), {
        'type': 'control_response',
        'response': {
          'subtype': 'success',
          'request_id': '480dbecf',
          'response': {
            'behavior': 'allow',
            'updatedInput': {
              'command': 'touch hello.txt',
              'description': 'Create empty file hello.txt',
            },
          },
        },
      });
    });

    test('encodeDeny carries behavior deny and message', () {
      expect(jsonDecode(encodeDeny('480dbecf', 'no')), {
        'type': 'control_response',
        'response': {
          'subtype': 'success',
          'request_id': '480dbecf',
          'response': {'behavior': 'deny', 'message': 'no'},
        },
      });
    });
  });
}
