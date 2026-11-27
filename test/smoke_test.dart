import 'package:claude_mobile/main.dart';
import 'package:claude_mobile/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('app shows profiles title', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(MemoryStore())],
        child: ClaudeMobileApp(authenticate: () async => true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profiles'), findsOneWidget);
  });

  testWidgets('the app is named Remote Harness', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(MemoryStore())],
        child: ClaudeMobileApp(authenticate: () async => true),
      ),
    );
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Remote Harness');
  });

  testWidgets('the terminal look applies whatever the phone setting', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(MemoryStore())],
        child: ClaudeMobileApp(authenticate: () async => true),
      ),
    );
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.text('Profiles')));
    expect(theme.brightness, Brightness.dark);
    expect(theme.textTheme.bodyMedium!.fontFamily, 'monospace');
    expect(theme.scaffoldBackgroundColor.computeLuminance(), lessThan(0.01));
    // Phosphor green: mostly green, and bright enough to read on black.
    final accent = theme.colorScheme.primary;
    expect(accent.g, greaterThan(accent.r));
    expect(accent.g, greaterThan(accent.b));
    expect(accent.computeLuminance(), greaterThan(0.5));
  });
}
