import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../core/codec.dart';
import '../storage/profile_store.dart';
import 'profile.dart';

/// A remote process seen as newline-delimited text.
abstract class LineChannel {
  /// Complete stdout lines. Closes when the remote process ends or the
  /// connection drops.
  Stream<String> get lines;

  /// Text the process wrote on stderr so far.
  String get stderrText;
  void writeLine(String jsonLine);
  Future<void> close();
  Future<void> get done;
}

abstract class SshService {
  Future<void> connect(Profile p, String privateKeyPem);
  bool get isConnected;

  /// Runs [command] to completion and returns its stdout.
  Future<String> run(String command);

  /// Starts [command] and keeps its stdin/stdout open.
  Future<LineChannel> open(String command);
  Future<void> disconnect();
}

/// The server's key differs from the one pinned at first connection.
class HostKeyMismatch implements Exception {
  const HostKeyMismatch(this.host);
  final String host;

  @override
  String toString() =>
      'Host key for $host changed since the first connection. '
      'Remove and re-add the profile if this is expected.';
}

/// Reconnection delay: 1 s, 2 s, 4 s, … capped at 30 s.
Duration backoff(int attempt) {
  if (attempt >= 5) return const Duration(seconds: 30);
  return Duration(seconds: 1 << (attempt < 0 ? 0 : attempt));
}

/// Trust on first use: pins the host key the first time, then requires it.
Future<bool> checkHostKey(
  KeyValueStore kv,
  String profileId,
  String type,
  Uint8List fingerprint,
) async {
  final hex = fingerprint
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final seen = '$type $hex';
  final pinned = await kv.read(hostKeyEntry(profileId));
  if (pinned == null) {
    await kv.write(hostKeyEntry(profileId), seen);
    return true;
  }
  return pinned == seen;
}

class ByteLineChannel implements LineChannel {
  ByteLineChannel({
    required Stream<List<int>> stdout,
    required this._write,
    required this._close,
    required this.done,
    Stream<List<int>>? stderr,
  }) {
    final buffer = LineBuffer();
    lines = stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .expand(buffer.add);
    stderr
        ?.cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_stderr.write, onError: (_) {});
  }

  final void Function(List<int> bytes) _write;
  final Future<void> Function() _close;
  final StringBuffer _stderr = StringBuffer();

  @override
  late final Stream<String> lines;

  @override
  final Future<void> done;

  @override
  String get stderrText => _stderr.toString();

  @override
  void writeLine(String jsonLine) => _write(utf8.encode(jsonLine));

  @override
  Future<void> close() => _close();
}

class DartSsh2Service implements SshService {
  DartSsh2Service(this._kv);
  final KeyValueStore _kv;
  SSHClient? _client;
  SSHClient? _jump;

  @override
  bool get isConnected =>
      _client != null && !_client!.isClosed && !(_jump?.isClosed ?? false);

  @override
  Future<void> connect(Profile p, String privateKeyPem) async {
    await disconnect();
    final identities = SSHKeyPair.fromPem(privateKeyPem);
    final jump = p.jump;
    try {
      final SSHSocket socket;
      if (jump == null) {
        socket = await _dial(p.host, p.port);
      } else {
        _jump = await _login(
          await _dial(jump.host, jump.port),
          host: jump.host,
          user: jump.user,
          pinId: jumpId(p.id),
          identities: identities,
        );
        socket = await _jump!.forwardLocal(p.host, p.port);
      }
      _client = await _login(
        socket,
        host: p.host,
        user: p.user,
        pinId: p.id,
        identities: identities,
      );
    } on Object {
      await disconnect();
      rethrow;
    }
  }

  static Future<SSHSocket> _dial(String host, int port) =>
      SSHSocket.connect(host, port, timeout: const Duration(seconds: 15));

  Future<SSHClient> _login(
    SSHSocket socket, {
    required String host,
    required String user,
    required String pinId,
    required List<SSHKeyPair> identities,
  }) async {
    var keyRejected = false;
    final client = SSHClient(
      socket,
      username: user,
      identities: identities,
      onVerifyHostKey: (type, fingerprint) async {
        final ok = await checkHostKey(_kv, pinId, type, fingerprint);
        keyRejected = !ok;
        return ok;
      },
    );
    try {
      await client.authenticated;
    } on Object {
      client.close();
      if (keyRejected) throw HostKeyMismatch(host);
      rethrow;
    }
    return client;
  }

  SSHClient get _connected {
    final c = _client;
    if (c == null || c.isClosed) throw StateError('Not connected');
    return c;
  }

  @override
  Future<String> run(String command) async {
    final bytes = await _connected.run(command, stderr: false);
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<LineChannel> open(String command) async {
    final session = await _connected.execute(command);
    return ByteLineChannel(
      stdout: session.stdout,
      stderr: session.stderr,
      write: (bytes) => session.stdin.add(Uint8List.fromList(bytes)),
      close: () async => session.close(),
      done: session.done,
    );
  }

  @override
  Future<void> disconnect() async {
    _client?.close();
    _client = null;
    _jump?.close();
    _jump = null;
  }
}
