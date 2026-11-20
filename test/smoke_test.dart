import 'package:claude_mobile/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app shows profiles title', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ClaudeMobileApp()));
    expect(find.text('Profiles'), findsOneWidget);
  });
}
