import 'package:claude_mobile/core/history.dart';
import 'package:claude_mobile/core/session_listing.dart';
import 'package:claude_mobile/ssh/profile.dart';
import 'package:claude_mobile/state/providers.dart';
import 'package:claude_mobile/storage/profile_store.dart';
import 'package:claude_mobile/ui/chat_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';

const perso = Profile(
  id: 'p1',
  name: 'perso',
  host: 'example.org',
  port: 22,
  user: 'me',
);

void main() {
  Object? nextConnectError;
  late MemoryStore kv;
  late FakeSsh ssh;
  final session = SessionInfo(
    id: 'sid-1',
    path: '/p/-w/sid-1.jsonl',
    modified: DateTime(2026, 11, 20),
    cwd: '/w',
    title: 'my session',
  );

  setUp(() async {
    kv = MemoryStore();
    ssh = FakeSsh();
    nextConnectError = null;
    await ProfileStore(kv).save(perso, privateKeyPem: 'k');
  });

  Widget app(Widget home) => ProviderScope(
    overrides: [
      keyValueStoreProvider.overrideWithValue(kv),
      sshFactoryProvider.overrideWithValue(() => ssh),
    ],
    child: MaterialApp(home: home),
  );

  testWidgets('shows the session history then resumes the session', (t) async {
    ssh.runResults = {
      historyCommand(session.path):
          '{"type":"user","message":{"role":"user","content":"earlier question"}}\n'
          '{"type":"assistant","message":{"id":"m","content":[{"type":"text","text":"earlier answer"}]}}\n',
    };
    await t.pumpWidget(
      app(ChatScreen(profile: perso, session: session, cwd: '/w')),
    );
    await t.pumpAndSettle();
    expect(find.text('earlier question'), findsOneWidget);
    expect(find.text('earlier answer'), findsOneWidget);
    expect(ssh.opened.single, contains('--resume'));
    expect(ssh.opened.single, contains('sid-1'));
  });

  testWidgets('history failure still opens a working chat', (t) async {
    ssh.runError = StateError('cat failed');
    await t.pumpWidget(
      app(ChatScreen(profile: perso, session: session, cwd: '/w')),
    );
    await t.pumpAndSettle();
    expect(find.text('History unavailable'), findsOneWidget);
    expect(ssh.opened.length, 1);
    expect(find.byTooltip('Send'), findsOneWidget);
  });

  testWidgets('a new session reads no history and creates an id', (t) async {
    await t.pumpWidget(app(const ChatScreen(profile: perso, cwd: '/w')));
    await t.pumpAndSettle();
    expect(ssh.ran, isEmpty);
    expect(ssh.opened.single, contains('--session-id'));
  });

  testWidgets('a connection failure shows the error and Retry', (t) async {
    await ProfileStore(kv).remove('p1');
    await t.pumpWidget(app(const ChatScreen(profile: perso, cwd: '/w')));
    await t.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });

  group('Reconnect button', () {
    late List<FakeSsh> links;

    /// A chat whose every new SSH connection is a fresh [FakeSsh].
    Future<void> openChat(WidgetTester t) async {
      links = [];
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            keyValueStoreProvider.overrideWithValue(kv),
            sshFactoryProvider.overrideWithValue(() {
              final link = FakeSsh();
              if (links.isNotEmpty) link.connectError = nextConnectError;
              links.add(link);
              return link;
            }),
          ],
          child: const MaterialApp(
            home: ChatScreen(profile: perso, cwd: '/w'),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    Future<void> dropChannel(WidgetTester t, {bool linkDead = true}) async {
      links.last.isConnected = !linkDead;
      await links.last.channels.last.drop();
      await t.pump();
    }

    testWidgets('resumes over a new link when the old one is dead', (t) async {
      await openChat(t);
      await dropChannel(t);
      // Let the automatic retries fail, as without network.
      nextConnectError = StateError('no route');
      await t.pump(const Duration(minutes: 2));
      expect(find.text('Reconnect'), findsOneWidget);

      nextConnectError = null;
      await t.tap(find.text('Reconnect'));
      await t.pumpAndSettle();
      expect(find.text('Reconnect'), findsNothing);
      expect(links.last.opened.single, contains('claude'));
    });

    testWidgets('says why when it fails', (t) async {
      await openChat(t);
      nextConnectError = StateError('no route');
      await dropChannel(t);
      await t.pump(const Duration(minutes: 2));

      await t.tap(find.text('Reconnect'));
      await t.pumpAndSettle();
      expect(find.textContaining('Reconnect failed'), findsOneWidget);
      expect(find.textContaining('no route'), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);
    });

    testWidgets('replaces a link that died without notice', (t) async {
      await openChat(t);
      // `claude` went away and the link looks up, but nothing answers.
      await dropChannel(t, linkDead: false);
      links.last.hang = true;

      await t.tap(find.text('Reconnect'));
      await t.pump();
      expect(find.text('Reconnecting…'), findsOneWidget);
      await t.pump(const Duration(seconds: 30));
      await t.pumpAndSettle();
      expect(links.length, 2);
      expect(find.text('Reconnect'), findsNothing);
      expect(find.text('Reconnecting…'), findsNothing);
    });
  });
}
