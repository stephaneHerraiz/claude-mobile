import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session_listing.dart';
import '../ssh/profile.dart';
import '../ssh/ssh_service.dart';
import '../storage/profile_store.dart';
import 'session_loader.dart';

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => const SecureKeyValueStore(),
);

final profileStoreProvider = Provider<ProfileStore>(
  (ref) => ProfileStore(ref.watch(keyValueStoreProvider)),
);

final profilesProvider = FutureProvider<List<Profile>>(
  (ref) => ref.watch(profileStoreProvider).list(),
);

/// Creates the SSH client used for one profile. Overridden in tests.
final sshFactoryProvider = Provider<SshService Function()>(
  (ref) =>
      () => DartSsh2Service(ref.read(keyValueStoreProvider)),
);

/// Riverpod retries failed providers by default. A refused key retried in a
/// loop looks like an attack to the server; the user retries by hand instead.
Duration? _never(int retryCount, Object error) => null;

/// One live SSH connection per profile id, closed when no screen uses it.
final sshConnectionProvider = FutureProvider.autoDispose
    .family<SshService, String>((ref, profileId) async {
      // Everything taken from ref comes before the first await: the provider
      // may be disposed while connecting.
      final store = ref.watch(profileStoreProvider);
      final ssh = GuardedSsh(ref.watch(sshFactoryProvider)());
      ref.onDispose(ssh.disconnect);
      final profile = (await store.list()).firstWhere((p) => p.id == profileId);
      final key = await store.privateKey(profileId);
      if (key == null) throw StateError('No private key for ${profile.name}');
      await ssh.connect(profile, key);
      return ssh;
    }, retry: _never);

final sessionListProvider = FutureProvider.autoDispose
    .family<List<SessionInfo>, String>((ref, profileId) async {
      final ssh = await ref.watch(sshConnectionProvider(profileId).future);
      return loadSessions(ssh, DateTime.now());
    }, retry: _never);
