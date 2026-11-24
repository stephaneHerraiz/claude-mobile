import 'package:claude_mobile/ssh/profile.dart';
import 'package:claude_mobile/storage/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const pem = '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END-----';
const perso = Profile(
  id: 'p1',
  name: 'perso',
  host: 'example.org',
  port: 2222,
  user: 'me',
);

void main() {
  late MemoryStore kv;
  late ProfileStore store;

  setUp(() {
    kv = MemoryStore();
    store = ProfileStore(kv);
  });

  test('list is empty on a fresh store', () async {
    expect(await store.list(), isEmpty);
  });

  test('save then list returns the profile', () async {
    await store.save(perso, privateKeyPem: pem);
    final p = (await store.list()).single;
    expect(p.id, 'p1');
    expect(p.name, 'perso');
    expect(p.host, 'example.org');
    expect(p.port, 2222);
    expect(p.user, 'me');
  });

  test('private key is stored apart and never in the profiles JSON', () async {
    await store.save(perso, privateKeyPem: pem);
    expect(await store.privateKey('p1'), pem);
    expect(kv.data['profiles'], isNot(contains('OPENSSH')));
    expect(kv.data['key:p1'], pem);
  });

  test('saving the same id replaces the profile', () async {
    await store.save(perso, privateKeyPem: pem);
    await store.save(
      const Profile(id: 'p1', name: 'pro', host: 'h', port: 22, user: 'u'),
      privateKeyPem: 'other',
    );
    expect((await store.list()).single.name, 'pro');
    expect(await store.privateKey('p1'), 'other');
  });

  test('remove deletes profile, key and pinned host key', () async {
    await store.save(perso, privateKeyPem: pem);
    await kv.write('hostkey:p1', 'fp');
    await store.remove('p1');
    expect(await store.list(), isEmpty);
    expect(await store.privateKey('p1'), isNull);
    expect(kv.data.containsKey('hostkey:p1'), false);
  });

  test('a corrupted profiles entry yields an empty list', () async {
    await kv.write('profiles', 'not json');
    expect(await store.list(), isEmpty);
  });

  const viaJump = Profile(
    id: 'p2',
    name: 'pod',
    host: '10.43.200.23',
    port: 2222,
    user: 'herraiz',
    jump: JumpHost(host: 'server1.test', port: 22, user: 'stephane'),
  );

  test('a jump host survives a save', () async {
    await store.save(viaJump, privateKeyPem: pem);
    final jump = (await store.list()).single.jump!;
    expect(jump.host, 'server1.test');
    expect(jump.port, 22);
    expect(jump.user, 'stephane');
  });

  test('a profile saved before jump hosts existed still loads', () {
    final p = Profile.fromJson({
      'id': 'old',
      'name': 'old',
      'host': 'h',
      'port': 22,
      'user': 'u',
    });
    expect(p.jump, isNull);
    expect(p.toJson().containsKey('jump'), isFalse);
  });

  test('remove also forgets the pinned jump host key', () async {
    await store.save(viaJump, privateKeyPem: pem);
    await kv.write(jumpHostKeyEntry('p2'), 'ssh-ed25519 aa');
    await store.remove('p2');
    expect(kv.data.keys.where((k) => k.contains('p2')), isEmpty);
  });

  group('update', () {
    test('keeps the private key when none is given', () async {
      await store.save(perso, privateKeyPem: pem);
      await store.update(
        const Profile(id: 'p1', name: 'renamed', host: 'example.org', port: 2222, user: 'me'),
      );
      expect((await store.list()).single.name, 'renamed');
      expect(await store.privateKey('p1'), pem);
    });

    test('replaces the key when a new one is given', () async {
      await store.save(perso, privateKeyPem: pem);
      await store.update(perso, privateKeyPem: 'new');
      expect(await store.privateKey('p1'), 'new');
    });

    test('keeps the pinned host key while the address is unchanged', () async {
      await store.save(perso, privateKeyPem: pem);
      await kv.write('hostkey:p1', 'fp');
      await store.update(
        const Profile(id: 'p1', name: 'x', host: 'example.org', port: 2222, user: 'other'),
      );
      expect(kv.data['hostkey:p1'], 'fp');
    });

    test('forgets the pinned host key when host or port changes', () async {
      await store.save(perso, privateKeyPem: pem);
      await kv.write('hostkey:p1', 'fp');
      await store.update(
        const Profile(id: 'p1', name: 'perso', host: 'new.org', port: 2222, user: 'me'),
      );
      expect(kv.data['hostkey:p1'], isNull);
    });

    test('forgets the jump host key when the jump host changes', () async {
      await store.save(perso, privateKeyPem: pem);
      await kv.write('hostkey:p1:jump', 'fp');
      await store.update(
        const Profile(
          id: 'p1', name: 'perso', host: 'example.org', port: 2222, user: 'me',
          jump: JumpHost(host: 'j', port: 22, user: 'u'),
        ),
      );
      expect(kv.data['hostkey:p1:jump'], isNull);
    });

    test('leaves the other profiles alone', () async {
      await store.save(perso, privateKeyPem: pem);
      await store.save(
        const Profile(id: 'p2', name: 'pro', host: 'h', port: 22, user: 'u'),
        privateKeyPem: 'k2',
      );
      await store.update(const Profile(id: 'p1', name: 'again', host: 'example.org', port: 2222, user: 'me'));
      expect((await store.list()).map((p) => p.id), ['p1', 'p2']);
    });
  });
}
