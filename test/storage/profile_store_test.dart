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
}
