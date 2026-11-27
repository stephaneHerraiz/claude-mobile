import 'dart:async';

import 'package:remote_harness/ssh/profile.dart';
import 'package:remote_harness/ssh/ssh_service.dart';
import 'package:remote_harness/storage/profile_store.dart';

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
  // The explicit onCancel matters in widget tests: without it, cancelling the
  // subscription completes on a future outside the test's fake clock, and
  // whatever awaits it (re-attaching a session) never finishes.
  final StreamController<String> out = StreamController<String>(
    onCancel: () async {},
  );
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
    // Not awaited, for the same reason as onCancel above: once the listener
    // is gone, close() completes outside the test's fake clock.
    if (!out.isClosed) unawaited(out.close());
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

  /// A link that died without anyone noticing: commands never answer.
  bool hang = false;

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
    if (hang) return Completer<String>().future;
    if (runError != null) throw runError!;
    return runResults[command] ?? '';
  }

  @override
  Future<LineChannel> open(String command) async {
    if (hang) return Completer<LineChannel>().future;
    if (openError != null) throw openError!;
    opened.add(command);
    final c = FakeChannel();
    channels.add(c);
    return c;
  }

  @override
  Future<void> disconnect() async {}
}
