import 'package:remote_harness/core/events.dart';
import 'package:remote_harness/ui/permission_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shows tool, command and calls back on each button', (t) async {
    var approved = 0, denied = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PermissionCard(
            request: const PermissionRequest('r', 't', 'Bash', {
              'command': 'touch hello.txt',
              'description': 'Create file',
            }, 'Create file'),
            onApprove: () => approved++,
            onDeny: () => denied++,
          ),
        ),
      ),
    );
    expect(find.textContaining('Bash'), findsOneWidget);
    expect(find.text('touch hello.txt'), findsOneWidget);
    expect(find.text('Create file'), findsOneWidget);
    await t.tap(find.text('Approve'));
    await t.tap(find.text('Deny'));
    expect(approved, 1);
    expect(denied, 1);
  });

  testWidgets('shows the raw input of a tool without a command', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PermissionCard(
            request: const PermissionRequest('r', 't', 'Write', {
              'file_path': '/a/b.txt',
            }, ''),
            onApprove: () {},
            onDeny: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining('/a/b.txt'), findsOneWidget);
  });
}
