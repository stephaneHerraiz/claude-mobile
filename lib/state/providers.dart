import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session_listing.dart';
import '../ssh/profile.dart';
import '../ssh/ssh_service.dart';
import '../storage/profile_store.dart';
import '../storage/session_cache.dart';
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

final sessionCacheProvider = Provider<SessionCache>(
  (ref) => SessionCache(ref.watch(keyValueStoreProvider)),
);

/// A profile's sessions. The cached list is served at once and the server's
/// replaces it as soon as it answers; if the server cannot be reached the
/// cached list stays, next to the error.
final sessionListProvider = AsyncNotifierProvider.autoDispose
    .family<SessionListNotifier, List<SessionInfo>, String>(
      SessionListNotifier.new,
      retry: _never,
    );

class SessionListNotifier extends AsyncNotifier<List<SessionInfo>> {
  SessionListNotifier(this.profileId);
  final String profileId;

  Future<void>? _refreshing;

  @override
  Future<List<SessionInfo>> build() async {
    // Everything taken from ref comes before the first await.
    final cache = ref.read(sessionCacheProvider);
    // Watched, not only read: a new connection rebuilds the list.
    final connection = ref.watch(sshConnectionProvider(profileId).future);
    final cached = await cache.read(profileId);
    if (cached.isEmpty) return _fetch(connection);
    // After the cache is shown: a state set now would be overwritten by it.
    Timer.run(() {
      if (ref.mounted) unawaited(refresh());
    });
    return cached;
  }

  Future<List<SessionInfo>> _fetch(Future<SshService> connection) async {
    final list = await loadSessions(await connection, DateTime.now());
    try {
      await ref.read(sessionCacheProvider).write(profileId, list);
    } on Object {
      // The cache is a convenience: the list is still good.
    }
    return list;
  }

  /// Asks the server again. The list on screen stays until it answers.
  /// Calls made meanwhile share the attempt.
  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    state = const AsyncLoading<List<SessionInfo>>();
    try {
      final list = await _fetch(
        ref.read(sshConnectionProvider(profileId).future),
      );
      if (ref.mounted) state = AsyncData(list);
    } on Object catch (e, st) {
      if (ref.mounted) {
        state = AsyncError<List<SessionInfo>>(e, st);
      }
    }
  }

  /// Puts a session just created at the top of the list and of the cache.
  Future<void> add(SessionInfo session) async {
    final cache = ref.read(sessionCacheProvider);
    final current = state.value ?? await cache.read(profileId);
    final list = [
      session,
      for (final s in current)
        if (s.id != session.id) s,
    ];
    if (ref.mounted) state = AsyncData(list);
    try {
      await cache.write(profileId, list);
    } on Object {
      // See _fetch.
    }
  }
}
