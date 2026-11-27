import 'package:remote_harness/ui/lock_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pump(WidgetTester t, Future<bool?> Function() auth) =>
      t.pumpWidget(
        MaterialApp(
          home: LockGate(authenticate: auth, child: const Text('inside')),
        ),
      );

  testWidgets('shows the child after a successful unlock', (t) async {
    await pump(t, () async => true);
    await t.pumpAndSettle();
    expect(find.text('inside'), findsOneWidget);
  });

  testWidgets('stays locked on failure and can retry', (t) async {
    var result = false;
    await pump(t, () async => result);
    await t.pumpAndSettle();
    expect(find.text('inside'), findsNothing);
    result = true;
    await t.tap(find.text('Unlock'));
    await t.pumpAndSettle();
    expect(find.text('inside'), findsOneWidget);
  });

  testWidgets('a device without any lock lets the user in', (t) async {
    await pump(t, () async => null);
    await t.pumpAndSettle();
    expect(find.text('inside'), findsOneWidget);
  });

  testWidgets('an auth error keeps the app locked', (t) async {
    await pump(t, () async => throw StateError('boom'));
    await t.pumpAndSettle();
    expect(find.text('inside'), findsNothing);
    expect(find.text('Unlock'), findsOneWidget);
  });
}
