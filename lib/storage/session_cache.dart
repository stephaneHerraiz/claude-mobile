import 'dart:convert';

import '../core/session_listing.dart';
import 'profile_store.dart';

/// The last session list seen for each profile, kept on the device so the
/// list can be shown before the server has answered.
class SessionCache {
  SessionCache(this._kv);
  final KeyValueStore _kv;

  Future<List<SessionInfo>> read(String profileId) async {
    try {
      final raw = await _kv.read(sessionsCacheEntry(profileId));
      if (raw == null) return [];
      return [
        for (final j in jsonDecode(raw) as List)
          SessionInfo.fromJson(j as Map<String, dynamic>),
      ];
    } on Object {
      // Unreadable cache: same as none, the server list replaces it.
      return [];
    }
  }

  Future<void> write(String profileId, List<SessionInfo> sessions) => _kv.write(
    sessionsCacheEntry(profileId),
    jsonEncode([for (final s in sessions) s.toJson()]),
  );
}
