import 'package:claude_mobile/core/session_listing.dart';
import 'package:claude_mobile/ssh/profile.dart';
import 'package:claude_mobile/state/providers.dart';
import 'package:claude_mobile/storage/profile_store.dart';
import 'package:claude_mobile/ui/profiles_screen.dart';
import 'package:claude_mobile/ui/sessions_screen.dart';
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
}
