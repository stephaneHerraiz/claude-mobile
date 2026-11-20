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

/// One live SSH connection per profile id, closed when no screen uses it.
final sshConnectionProvider = FutureProvider.autoDispose
    .family<SshService, String>((ref, profileId) async {
      final store = ref.watch(profileStoreProvider);
      final profile = (await store.list()).firstWhere((p) => p.id == profileId);
      final key = await store.privateKey(profileId);
      if (key == null) throw StateError('No private key for ${profile.name}');
      final ssh = ref.watch(sshFactoryProvider)();
      ref.onDispose(ssh.disconnect);
      await ssh.connect(profile, key);
      return ssh;
    });

final sessionListProvider = FutureProvider.autoDispose
    .family<List<SessionInfo>, String>((ref, profileId) async {
      final ssh = await ref.watch(sshConnectionProvider(profileId).future);
      return loadSessions(ssh, DateTime.now());
    });
