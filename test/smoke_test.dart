import 'package:claude_mobile/main.dart';
import 'package:claude_mobile/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
