import 'dart:async';

import 'package:claude_mobile/ssh/profile.dart';
import 'package:claude_mobile/ssh/ssh_service.dart';
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

class FakeChannel implements LineChannel {
  final StreamController<String> out = StreamController<String>();
  final List<String> written = [];
  final Completer<void> _done = Completer<void>();
  bool closed = false;

  @override
  Stream<String> get lines => out.stream;

  @override
  String stderrText = '';

  @override
  void writeLine(String jsonLine) => written.add(jsonLine);

  @override
  Future<void> close() async {
    closed = true;
    if (!out.isClosed) await out.close();
  }

  @override
  Future<void> get done => _done.future;

  /// The remote side went away.
  Future<void> drop() => out.close();
}

class FakeSsh implements SshService {
  final List<String> opened = [];
  final List<String> ran = [];
  final List<FakeChannel> channels = [];
  Map<String, String> runResults = {};
  Object? openError;
  Object? runError;
  Object? connectError;
  int connects = 0;

  @override
  bool isConnected = true;

  @override
  Future<void> connect(Profile p, String privateKeyPem) async {
    connects++;
    if (connectError != null) throw connectError!;
  }

  @override
  Future<String> run(String command) async {
    ran.add(command);
    if (runError != null) throw runError!;
    return runResults[command] ?? '';
  }

  @override
  Future<LineChannel> open(String command) async {
    if (openError != null) throw openError!;
    opened.add(command);
    final c = FakeChannel();
    channels.add(c);
    return c;
  }

  @override
  Future<void> disconnect() async {}
}
