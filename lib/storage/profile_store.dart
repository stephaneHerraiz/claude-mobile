import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../ssh/profile.dart';

abstract class KeyValueStore {
  Future<String?> read(String k);
  Future<void> write(String k, String v);
  Future<void> delete(String k);
}

/// Keychain / Keystore backed store.
class SecureKeyValueStore implements KeyValueStore {
  const SecureKeyValueStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String k) => _storage.read(key: k);

  @override
  Future<void> write(String k, String v) => _storage.write(key: k, value: v);

  @override
  Future<void> delete(String k) => _storage.delete(key: k);
}

String hostKeyEntry(String profileId) => 'hostkey:$profileId';

/// Host keys are pinned under a profile id; the jump host has its own.
String jumpId(String profileId) => '$profileId:jump';
String jumpHostKeyEntry(String profileId) => hostKeyEntry(jumpId(profileId));

class ProfileStore {
  ProfileStore(this._kv);
  final KeyValueStore _kv;

  static const _profilesKey = 'profiles';
  static String _keyEntry(String id) => 'key:$id';

  Future<List<Profile>> list() async {
    final raw = await _kv.read(_profilesKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          Profile.fromJson(j as Map<String, dynamic>),
      ];
    } on Object {
      return [];
    }
  }

  Future<void> save(Profile p, {required String privateKeyPem}) async {
    final others = (await list()).where((o) => o.id != p.id);
    await _kv.write(_keyEntry(p.id), privateKeyPem);
    await _writeProfiles([...others, p]);
  }

  Future<String?> privateKey(String profileId) =>
      _kv.read(_keyEntry(profileId));

  Future<void> remove(String profileId) async {
    await _writeProfiles((await list()).where((p) => p.id != profileId));
    await _kv.delete(_keyEntry(profileId));
    await _kv.delete(hostKeyEntry(profileId));
    await _kv.delete(jumpHostKeyEntry(profileId));
  }

  Future<void> _writeProfiles(Iterable<Profile> profiles) => _kv.write(
    _profilesKey,
    jsonEncode([for (final p in profiles) p.toJson()]),
  );
}
