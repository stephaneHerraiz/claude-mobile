import 'package:claude_mobile/core/session_listing.dart';
import 'package:claude_mobile/ssh/profile.dart';
import 'package:claude_mobile/state/providers.dart';
import 'package:claude_mobile/storage/profile_store.dart';
import 'package:claude_mobile/storage/session_cache.dart';
import 'package:claude_mobile/ui/profiles_screen.dart';
import 'package:claude_mobile/ui/sessions_screen.dart';
import 'package:claude_mobile/ui/theme.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';
import '../support/keys.dart';

const perso = Profile(
  id: 'p1',
  name: 'perso',
  host: 'example.org',
  port: 22,
  user: 'me',
);

void main() {
  late MemoryStore kv;
  late FakeSsh ssh;

  late TestKeys keys;
  setUpAll(() => keys = TestKeys.generate());

  setUp(() {
    kv = MemoryStore();
    ssh = FakeSsh();
  });

  Widget app(Widget home) => ProviderScope(
    overrides: [
      keyValueStoreProvider.overrideWithValue(kv),
      sshFactoryProvider.overrideWithValue(() => ssh),
    ],
    child: MaterialApp(home: home),
  );

  testWidgets('profiles screen lists saved profiles', (t) async {
    await ProfileStore(kv).save(perso, privateKeyPem: 'k');
    await t.pumpWidget(app(const ProfilesScreen()));
    await t.pumpAndSettle();
    expect(find.text('Profiles'), findsOneWidget);
    expect(find.text('perso'), findsOneWidget);
    expect(find.text('me@example.org:22'), findsOneWidget);
  });

  testWidgets('profiles are separated by lines', (t) async {
    await ProfileStore(kv).save(perso, privateKeyPem: 'k');
    await ProfileStore(kv).save(
      const Profile(id: 'p2', name: 'pro', host: 'h', port: 22, user: 'u'),
      privateKeyPem: 'k',
    );
    await t.pumpWidget(app(const ProfilesScreen()));
    await t.pumpAndSettle();
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('sessions of a directory are separated by lines', (t) async {
    await ProfileStore(kv).save(perso, privateKeyPem: 'k');
    ssh.runResults = {
      listSessionsCommand:
          '3.0 /p/-a/s1.jsonl\n2.0 /p/-a/s2.jsonl\n1.0 /p/-a/s3.jsonl\n',
      for (final id in ['s1', 's2', 's3'])
        headCommand('/p/-a/$id.jsonl'):
            '{"type":"user","cwd":"/a","message":{"content":"task $id"}}\n'
            '{"type":"ai-title","aiTitle":"Name of $id"}\n',
    };
    await t.pumpWidget(app(const SessionsScreen(profile: perso)));
    await t.pumpAndSettle();
    expect(find.text('Name of s2'), findsOneWidget);
    expect(find.text('task s2'), findsNothing);
    expect(find.byType(Divider), findsNWidgets(2));
  });

  group('deleting a session', () {
    const a = '/h/.claude/projects/-a/s1.jsonl';
    const b = '/h/.claude/projects/-a/s2.jsonl';

    Future<void> openList(WidgetTester t, {String? deleteOutput}) async {
      await ProfileStore(kv).save(perso, privateKeyPem: 'k');
      ssh.runResults = {
        listSessionsCommand: '3.0 $a\n2.0 $b\n',
        for (final (path, name) in [(a, 'First'), (b, 'Second')])
          headCommand(path):
              '{"type":"user","cwd":"/a","message":{"content":"x"}}\n'
              '{"type":"ai-title","aiTitle":"$name"}\n',
        deleteSessionCommand(a): ?deleteOutput,
      };
      await t.pumpWidget(app(const SessionsScreen(profile: perso)));
      await t.pumpAndSettle();
    }

    testWidgets('erases it on the server once confirmed', (t) async {
      await openList(t, deleteOutput: '$deletedMarker\n');
      await t.tap(find.byTooltip('Delete First'));
      await t.pumpAndSettle();
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(ssh.ran, isNot(contains(deleteSessionCommand(a))));

      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      expect(ssh.ran, contains(deleteSessionCommand(a)));
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
      final cached = await SessionCache(kv).read('p1');
      expect(cached.map((s) => s.id), ['s2']);
    });

    testWidgets('does nothing when cancelled', (t) async {
      await openList(t, deleteOutput: '$deletedMarker\n');
      await t.tap(find.byTooltip('Delete First'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(ssh.ran, isNot(contains(deleteSessionCommand(a))));
      expect(find.text('First'), findsOneWidget);
    });

    testWidgets('keeps it and says so when the server did not erase it', (
      t,
    ) async {
      await openList(t);
      await t.tap(find.byTooltip('Delete First'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      expect(find.textContaining('Could not delete'), findsOneWidget);
    });

    testWidgets('warns when the session was active a moment ago', (t) async {
      await ProfileStore(kv).save(perso, privateKeyPem: 'k');
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      ssh.runResults = {
        listSessionsCommand: '$now $a\n',
        headCommand(a):
            '{"type":"user","cwd":"/a","message":{"content":"x"}}\n'
            '{"type":"ai-title","aiTitle":"First"}\n',
      };
      await t.pumpWidget(app(const SessionsScreen(profile: perso)));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Delete First'));
      await t.pumpAndSettle();
      expect(find.textContaining('may be open elsewhere'), findsOneWidget);
    });
  });

  testWidgets('editing a profile prefills it and keeps its key', (t) async {
    await ProfileStore(kv).save(perso, privateKeyPem: 'k');
    await t.pumpWidget(app(const ProfilesScreen()));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Edit perso'));
    await t.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'example.org'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, 'perso'), 'renamed');
    await t.ensureVisible(find.text('Save'));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final saved = (await ProfileStore(kv).list()).single;
    expect(saved.id, 'p1');
    expect(saved.name, 'renamed');
    expect(await ProfileStore(kv).privateKey('p1'), 'k');
  });

  testWidgets('editing with a new key replaces the stored one', (t) async {
    await ProfileStore(kv).save(perso, privateKeyPem: 'k');
    await t.pumpWidget(app(const ProfilesScreen()));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Edit perso'));
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextFormField, 'Private key (PEM)'),
      keys.plain,
    );
    await t.ensureVisible(find.text('Save'));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(await ProfileStore(kv).privateKey('p1'), keys.plain.trim());
  });

  testWidgets('every session is ruled off, across directories too, and its '
      'name stands out more than the directory', (t) async {
    await ProfileStore(kv).save(perso, privateKeyPem: 'k');
    ssh.runResults = {
      listSessionsCommand:
          '3.0 /p/-a/s1.jsonl\n2.0 /p/-b/s2.jsonl\n1.0 /p/-c/s3.jsonl\n',
      for (final (id, dir) in [('s1', 'a'), ('s2', 'b'), ('s3', 'c')])
        headCommand('/p/-$dir/$id.jsonl'):
            '{"type":"user","cwd":"/$dir","message":{"content":"x"}}\n'
            '{"type":"ai-title","aiTitle":"Name of $id"}\n',
    };
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(kv),
          sshFactoryProvider.overrideWithValue(() => ssh),
        ],
        child: MaterialApp(
          theme: terminalTheme,
          home: const SessionsScreen(profile: perso),
        ),
      ),
    );
    await t.pumpAndSettle();
    // One session per directory: still a line between each of the three.
    expect(find.byType(Divider), findsNWidgets(2));

    TextStyle style(String text) =>
        DefaultTextStyle.of(t.element(find.text(text))).style
            .merge(t.widget<Text>(find.text(text)).style);
    final name = style('Name of s1');
    final directory = style('/a');
    expect(name.color, TerminalColors.green);
    expect(name.fontWeight, isNot(FontWeight.bold));
    expect(directory.color, isNot(TerminalColors.green));
    expect(directory.fontSize!, lessThan(name.fontSize!));
  });

  testWidgets('adding a profile stores it with its key', (t) async {
    await t.pumpWidget(app(const ProfilesScreen()));
    await t.pumpAndSettle();
    expect(find.textContaining('No profile'), findsOneWidget);
    await t.tap(find.byTooltip('Add profile'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Name'), 'pro');
    await t.enterText(find.widgetWithText(TextFormField, 'Host'), 'work.test');
    await t.enterText(find.widgetWithText(TextFormField, 'User'), 'steph');
    await t.enterText(
      find.widgetWithText(TextFormField, 'Private key (PEM)'),
      keys.plain,
    );
    await t.ensureVisible(find.text('Save'));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('pro'), findsOneWidget);
    final saved = (await ProfileStore(kv).list()).single;
    expect(saved.host, 'work.test');
    expect(saved.port, 22);
    expect(saved.jump, isNull);
    expect(await ProfileStore(kv).privateKey(saved.id), keys.plain.trim());
  });

  Future<void> fillForm(WidgetTester t) async {
    await t.tap(find.byTooltip('Add profile'));
    await t.pumpAndSettle();
    Future<void> type(String label, String text) =>
        t.enterText(find.widgetWithText(TextFormField, label), text);
    await type('Name', 'pod');
    await type('Host', '10.43.200.23');
    await type('User', 'herraiz');
    await type('Private key (PEM)', keys.plain);
  }

  Future<void> save(WidgetTester t) async {
    await t.ensureVisible(find.text('Save'));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
  }

  testWidgets('a protected key is stored unlocked by its passphrase', (
    t,
  ) async {
    await t.pumpWidget(app(const ProfilesScreen()));
    await t.pumpAndSettle();
    await fillForm(t);
    final keyField = find.widgetWithText(TextFormField, 'Private key (PEM)');
    final passField = find.widgetWithText(
      TextFormField,
      'Key passphrase (if any)',
    );
    await t.enterText(keyField, keys.encrypted);

    await save(t);
    expect(
      find.text('This key is protected: enter its passphrase.'),
      findsOneWidget,
    );
    expect(await ProfileStore(kv).list(), isEmpty);

    await t.enterText(passField, 'nope');
    await save(t);
    expect(find.text('Wrong passphrase.'), findsOneWidget);
    expect(await ProfileStore(kv).list(), isEmpty);

    await t.enterText(passField, TestKeys.passphrase);
    await save(t);
    final saved = (await ProfileStore(kv).list()).single;
    final stored = (await ProfileStore(kv).privateKey(saved.id))!;
    expect(SSHKeyPair.isEncryptedPem(stored), isFalse);
    // The passphrase itself is kept nowhere.
    expect(kv.data.values.join(), isNot(contains(TestKeys.passphrase)));
  });

  testWidgets('text that is not a private key is refused', (t) async {
    await t.pumpWidget(app(const ProfilesScreen()));
    await t.pumpAndSettle();
    await fillForm(t);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Private key (PEM)'),
      'ssh-ed25519 AAAA me@pc',
    );
    await save(t);
    expect(find.textContaining('This is not a private key'), findsOneWidget);
    expect(await ProfileStore(kv).list(), isEmpty);
  });

  testWidgets('saves a profile that goes through a jump host', (t) async {
    await t.pumpWidget(app(const ProfilesScreen()));
    await t.pumpAndSettle();
    await fillForm(t);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Jump host (optional)'),
      'server1.test',
    );
    await t.enterText(
      find.widgetWithText(TextFormField, 'Jump user'),
      'stephane',
    );
    await t.ensureVisible(find.text('Save'));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(
      find.text('herraiz@10.43.200.23:22 via server1.test'),
      findsOneWidget,
    );
    final jump = (await ProfileStore(kv).list()).single.jump!;
    expect(jump.host, 'server1.test');
    expect(jump.port, 22);
    expect(jump.user, 'stephane');
  });

  testWidgets('a jump host without a user is refused', (t) async {
    await t.pumpWidget(app(const ProfilesScreen()));
    await t.pumpAndSettle();
    await fillForm(t);
    await t.enterText(
      find.widgetWithText(TextFormField, 'Jump host (optional)'),
      'server1.test',
    );
    await t.ensureVisible(find.text('Save'));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Required with a jump host'), findsOneWidget);
    expect(await ProfileStore(kv).list(), isEmpty);
  });

  testWidgets('the form refuses a missing host or key', (t) async {
    await t.pumpWidget(app(const ProfilesScreen()));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Add profile'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Save'));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
    expect(find.text('Required with a jump host'), findsNothing);
    expect(await ProfileStore(kv).list(), isEmpty);
  });

  testWidgets('sessions screen groups sessions by cwd', (t) async {
    await ProfileStore(kv).save(perso, privateKeyPem: 'k');
    ssh.runResults = {
      listSessionsCommand:
          '1795180000.0 /p/-a/s1.jsonl\n1795188000.0 /p/-b/s2.jsonl\n',
      headCommand('/p/-a/s1.jsonl'): '{"type":"user","cwd":"/home/me/alpha","message":{"content":"first task"}}\n',
      headCommand('/p/-b/s2.jsonl'): '{"type":"user","cwd":"/home/me/beta","message":{"content":"second task"}}\n',
    };
    await t.pumpWidget(app(const SessionsScreen(profile: perso)));
    await t.pumpAndSettle();
    expect(find.text('/home/me/alpha'), findsOneWidget);
    expect(find.text('/home/me/beta'), findsOneWidget);
    expect(find.text('first task'), findsOneWidget);
    expect(find.text('second task'), findsOneWidget);
  });

  testWidgets('sessions screen shows a connection error with retry', (t) async {
    // No profile saved: the connection provider fails.
    await t.pumpWidget(app(const SessionsScreen(profile: perso)));
    await t.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a refused connection is tried once, not retried in a loop', (
    t,
  ) async {
    await ProfileStore(kv).save(perso, privateKeyPem: 'k');
    ssh.connectError = Exception('auth failed');
    await t.pumpWidget(app(const SessionsScreen(profile: perso)));
    await t.pump(const Duration(seconds: 30));
    await t.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(ssh.connects, 1);
  });

  testWidgets('an old session without a known directory opens on tap', (
    t,
  ) async {
    await ProfileStore(kv).save(perso, privateKeyPem: 'k');
    final lines = [
      for (var i = 0; i < 31; i++) '${1795188000 - i}.0 /p/-x/s$i.jsonl',
    ].join('\n');
    ssh.runResults = {
      listSessionsCommand: '$lines\n',
      for (var i = 0; i < 31; i++)
        headCommand(
          '/p/-x/s$i.jsonl',
        ): '{"type":"user","cwd":"/home/me/x","message":{"content":"task $i"}}\n',
    };
    await t.pumpWidget(app(const SessionsScreen(profile: perso)));
    await t.pumpAndSettle();
    expect(ssh.ran, isNot(contains(headCommand('/p/-x/s30.jsonl'))));
    await t.scrollUntilVisible(find.text('s30'), 300);
    await t.tap(find.text('s30'));
    await t.pumpAndSettle();
    expect(ssh.ran, contains(headCommand('/p/-x/s30.jsonl')));
    expect(ssh.opened.single, contains("--resume"));
    expect(ssh.opened.single, contains('s30'));
    expect(ssh.opened.single, contains('/home/me/x'));
  });

  group('session list cache', () {
    const listing = '1795188000.0 /p/-x/s1.jsonl\n';
    const head =
        '{"type":"user","cwd":"/home/me/x","message":{"content":"fresh title"}}\n';

    SessionInfo cached(String id, String title) => SessionInfo(
      id: id,
      path: '/p/-x/$id.jsonl',
      modified: DateTime(2026, 11, 1),
      cwd: '/home/me/x',
      title: title,
    );

    setUp(() async {
      await ProfileStore(kv).save(perso, privateKeyPem: 'k');
    });

    testWidgets('the server list is written to the cache', (t) async {
      ssh.runResults = {
        listSessionsCommand: listing,
        headCommand('/p/-x/s1.jsonl'): head,
      };
      await t.pumpWidget(app(const SessionsScreen(profile: perso)));
      await t.pumpAndSettle();
      final stored = await SessionCache(kv).read('p1');
      expect(stored.single.id, 's1');
      expect(stored.single.title, 'fresh title');
    });

    testWidgets('the cached list shows while the server is slow, then the '
        'server list replaces it', (t) async {
      await SessionCache(kv).write('p1', [cached('old', 'cached title')]);
      ssh.runResults = {
        listSessionsCommand: listing,
        headCommand('/p/-x/s1.jsonl'): head,
      };
      await t.pumpWidget(app(const SessionsScreen(profile: perso)));
      await t.pump();
      await t.pump();
      expect(find.text('cached title'), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.text('cached title'), findsNothing);
      expect(find.text('fresh title'), findsOneWidget);
    });

    testWidgets('the cached list stays, with the error, when the server '
        'cannot be reached', (t) async {
      await SessionCache(kv).write('p1', [cached('old', 'cached title')]);
      ssh.connectError = Exception('no route');
      await t.pumpWidget(app(const SessionsScreen(profile: perso)));
      await t.pumpAndSettle();
      expect(find.text('cached title'), findsOneWidget);
      expect(find.textContaining('no route'), findsOneWidget);
    });

    testWidgets('an unreadable cache is ignored', (t) async {
      kv.data['sessions:p1'] = 'not json';
      ssh.runResults = {
        listSessionsCommand: listing,
        headCommand('/p/-x/s1.jsonl'): head,
      };
      await t.pumpWidget(app(const SessionsScreen(profile: perso)));
      await t.pumpAndSettle();
      expect(find.text('fresh title'), findsOneWidget);
    });

    testWidgets('a session started in the app is added to the list and the '
        'cache', (t) async {
      ssh.runResults = {
        listSessionsCommand: listing,
        headCommand('/p/-x/s1.jsonl'): head,
      };
      await t.pumpWidget(app(const SessionsScreen(profile: perso)));
      await t.pumpAndSettle();
      await t.tap(find.text('New session'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Directory on the server'),
        '/home/me/new',
      );
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      ssh.channels.single.out.add(
        '{"type":"system","subtype":"init","session_id":"brand-new",'
        '"cwd":"/home/me/new","model":"m"}',
      );
      await t.pumpAndSettle();
      final stored = await SessionCache(kv).read('p1');
      expect(stored.first.id, 'brand-new');
      expect(stored.first.cwd, '/home/me/new');
      expect(stored.map((s) => s.id), contains('s1'));
    });

    testWidgets('a new session can be named, and carries that name', (t) async {
      ssh.runResults = {
        listSessionsCommand: listing,
        headCommand('/p/-x/s1.jsonl'): head,
      };
      await t.pumpWidget(app(const SessionsScreen(profile: perso)));
      await t.pumpAndSettle();
      await t.tap(find.text('New session'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Name (optional)'),
        'deploy fix',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Directory on the server'),
        '/home/me/new',
      );
      await t.tap(find.text('Start'));
      await t.pumpAndSettle();
      // Claude is started under that name, and the chat is titled with it.
      expect(ssh.opened.single, contains('--name'));
      expect(ssh.opened.single, contains('deploy fix'));
      expect(find.text('deploy fix'), findsOneWidget);

      ssh.channels.single.out.add(
        '{"type":"system","subtype":"init","session_id":"brand-new",'
        '"cwd":"/home/me/new","model":"m"}',
      );
      await t.pumpAndSettle();
      final stored = await SessionCache(kv).read('p1');
      expect(stored.first.id, 'brand-new');
      expect(stored.first.title, 'deploy fix');
    });
  });
}
