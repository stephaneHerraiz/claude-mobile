import 'package:remote_harness/core/history.dart';
import 'package:remote_harness/core/session_listing.dart';
import 'package:remote_harness/ssh/profile.dart';
import 'package:remote_harness/ssh/ssh_service.dart';
import 'package:remote_harness/state/providers.dart';
import 'package:remote_harness/storage/profile_store.dart';
import 'package:remote_harness/ui/chat_screen.dart';
import 'package:remote_harness/ui/sessions_screen.dart';
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

  group('Retry button', () {
    late List<FakeSsh> links;

    Widget failingFirst(Widget home, {void Function(FakeSsh)? first}) {
      links = [];
      return ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(kv),
          sshFactoryProvider.overrideWithValue(() {
            final link = FakeSsh();
            if (links.isEmpty) {
              (first ?? (l) => l.connectError = 'no route')(link);
            }
            links.add(link);
            return link;
          }),
        ],
        child: MaterialApp(home: home),
      );
    }

    testWidgets('opens the chat once the server is reachable', (t) async {
      await t.pumpWidget(
        failingFirst(const ChatScreen(profile: perso, cwd: '/w')),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('no route'), findsOneWidget);

      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(find.byTooltip('Send'), findsOneWidget);
      expect(links.last.opened.single, contains('claude'));
    });

    testWidgets('a chat on a link where nothing answers can be revived', (
      t,
    ) async {
      await t.pumpWidget(
        failingFirst(
          ChatScreen(profile: perso, session: session, cwd: '/w'),
          first: (l) => l.hang = true,
        ),
      );
      // History, then starting Claude, each give up after their time limit.
      await t.pump(const Duration(seconds: 31));
      await t.pump(const Duration(seconds: 21));
      await t.pumpAndSettle();
      expect(find.text('History unavailable'), findsOneWidget);
      expect(find.textContaining('did not answer in time'), findsOneWidget);

      await t.tap(find.text('Reconnect'));
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(find.text('Reconnect'), findsNothing);
      expect(links.length, 2);
      // The abandoned probe on the dead link still has its own limit to run.
      await t.pump(GuardedSsh.runTimeout);
    });

    testWidgets('lists the sessions once the server is reachable', (t) async {
      await t.pumpWidget(failingFirst(const SessionsScreen(profile: perso)));
      await t.pumpAndSettle();
      expect(find.textContaining('no route'), findsOneWidget);

      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(links.length, 2);
    });

    testWidgets('gives up on a session list that never answers', (t) async {
      await t.pumpWidget(
        failingFirst(
          const SessionsScreen(profile: perso),
          first: (l) => l.hang = true,
        ),
      );
      await t.pump(const Duration(seconds: 40));
      await t.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      await t.tap(find.text('Retry'));
      await t.pump(const Duration(seconds: 40));
      await t.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      expect(links.length, 2);
    });
  });

  group('Waking the app', () {
    late List<FakeSsh> links;

    Future<void> openChat(WidgetTester t, {bool firstFails = false}) async {
      links = [];
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            keyValueStoreProvider.overrideWithValue(kv),
            sshFactoryProvider.overrideWithValue(() {
              final link = FakeSsh();
              if (firstFails && links.isEmpty) link.connectError = 'no route';
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

    Future<void> sleepThenWake(WidgetTester t) async {
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        t.binding.handleAppLifecycleStateChanged(state);
      }
      await t.pump();
    }

    testWidgets('replaces a link that died during sleep', (t) async {
      await openChat(t);
      // Nothing told the app: the chat still looks connected.
      links.single.hang = true;
      await sleepThenWake(t);
      // The probe gives up after 5 s.
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();

      expect(links.length, 2);
      expect(links.last.opened.single, contains('claude'));
      expect(find.text('Reconnect'), findsNothing);
      await t.pump(GuardedSsh.runTimeout);
    });

    testWidgets('leaves a healthy session alone', (t) async {
      await openChat(t);
      await sleepThenWake(t);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();

      expect(links.length, 1);
      expect(links.single.opened.length, 1);
    });

    testWidgets('reconnects at once without waiting for the next retry', (
      t,
    ) async {
      await openChat(t);
      links.single.isConnected = false;
      await links.single.channels.last.drop();
      await t.pump();
      expect(find.text('Reconnect'), findsOneWidget);
      // The first automatic retry would only come a second later.
      await sleepThenWake(t);
      await t.pump(const Duration(milliseconds: 100));

      expect(links.length, 2);
      expect(find.text('Reconnect'), findsNothing);
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('retries a chat that had failed to open', (t) async {
      await openChat(t, firstFails: true);
      expect(find.text('Retry'), findsOneWidget);
      await sleepThenWake(t);
      await t.pumpAndSettle();

      expect(find.text('Retry'), findsNothing);
      expect(find.byTooltip('Send'), findsOneWidget);
    });
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
