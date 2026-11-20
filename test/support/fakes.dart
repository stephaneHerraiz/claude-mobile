import 'package:claude_mobile/storage/profile_store.dart';

class MemoryStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String k) async => data[k];

  @override
  Future<void> write(String k, String v) async => data[k] = v;

  @override
  Future<void> delete(String k) async => data.remove(k);
}
