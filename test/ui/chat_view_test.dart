import 'package:claude_mobile/state/session_controller.dart';
import 'package:claude_mobile/ui/chat_screen.dart';
import 'package:claude_mobile/ui/permission_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';

const assistantText =
    '{"type":"assistant","message":{"id":"m1","content":[{"type":"text","text":"Hi there"}]}}';
const toolUse =
    '{"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls -la"}}]}}';
const toolResult =
    '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"secret-output"}]}}';
const permLine =
    '{"type":"control_request","request_id":"req-9","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"touch a"},"description":"d","tool_use_id":"t9"}}';

void main() {
  late FakeSsh ssh;
  late SessionController controller;

  setUp(() {
    ssh = FakeSsh();
    controller = SessionController(ssh, sessionId: 'abc', cwd: '/w');
  });

  Future<void> pump(WidgetTester t, {bool recentlyActive = false}) =>
      t.pumpWidget(
        MaterialApp(
          home: ChatView(
            controller: controller,
            title: 'my session',
            recentlyActive: recentlyActive,
          ),
        ),
      );

  Future<void> feed(WidgetTester t, List<String> lines) async {
    lines.forEach(ssh.channels.last.out.add);
    await t.pump();
    await t.pump();
  }

  testWidgets('renders user and assistant items', (t) async {
    await controller.start();
    await pump(t);
    await t.enterText(find.byType(TextField), 'hello claude');
    await t.tap(find.byTooltip('Send'));
    await feed(t, [assistantText]);
    expect(find.text('hello claude'), findsOneWidget);
    expect(find.text('Hi there'), findsOneWidget);
    expect(ssh.channels.single.written.single, contains('hello claude'));
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('does not send an empty message', (t) async {
    await controller.start();
    await pump(t);
    await t.enterText(find.byType(TextField), '   ');
    await t.tap(find.byTooltip('Send'));
    expect(ssh.channels.single.written, isEmpty);
  });

  testWidgets('tool items are collapsed until tapped', (t) async {
    await controller.start();
    await pump(t);
    await feed(t, [toolUse, toolResult]);
    expect(find.textContaining('Bash'), findsOneWidget);
    expect(find.textContaining('secret-output'), findsNothing);
    await t.tap(find.textContaining('Bash'));
    await t.pumpAndSettle();
    expect(find.textContaining('secret-output'), findsOneWidget);
  });

  testWidgets('shows PermissionCard when pending and approve answers', (
    t,
  ) async {
    await controller.start();
    await pump(t);
    expect(find.byType(PermissionCard), findsNothing);
    await feed(t, [permLine]);
    expect(find.byType(PermissionCard), findsOneWidget);
    await t.tap(find.text('Approve'));
    await t.pump();
    expect(find.byType(PermissionCard), findsNothing);
    expect(ssh.channels.single.written.single, contains('"allow"'));
  });

  testWidgets('a recentlyActive session shows the open-elsewhere banner', (
    t,
  ) async {
    await controller.start();
    await pump(t, recentlyActive: true);
    expect(find.textContaining('open elsewhere'), findsOneWidget);
  });

  testWidgets('no banner for a quiet session', (t) async {
    await controller.start();
    await pump(t);
    expect(find.textContaining('open elsewhere'), findsNothing);
  });

  testWidgets('offers Reconnect after the connection drops', (t) async {
    await controller.start();
    await pump(t);
    expect(find.text('Reconnect'), findsNothing);
    await ssh.channels.single.drop();
    await t.pump();
    await t.pump();
    expect(find.text('Connection lost'), findsOneWidget);
    await t.tap(find.text('Reconnect'));
    await t.pump();
    await t.pump();
    expect(ssh.opened.length, 2);
    expect(find.text('Reconnect'), findsNothing);
  });
}
