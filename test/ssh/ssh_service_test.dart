import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:claude_mobile/ssh/ssh_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test('backoff doubles then caps at 30s', () {
    expect(backoff(0), const Duration(seconds: 1));
    expect(backoff(1), const Duration(seconds: 2));
    expect(backoff(2), const Duration(seconds: 4));
    expect(backoff(4), const Duration(seconds: 16));
    expect(backoff(5), const Duration(seconds: 30));
    expect(backoff(60), const Duration(seconds: 30));
  });

  group('ByteLineChannel', () {
    test('emits complete lines from split byte chunks', () async {
      final out = StreamController<Uint8List>();
      final ch = ByteLineChannel(
        stdout: out.stream,
        write: (_) {},
        close: () async {},
        done: Completer<void>().future,
      );
      final lines = <String>[];
      final sub = ch.lines.listen(lines.add);
      out.add(Uint8List.fromList(utf8.encode('{"a":')));
      out.add(Uint8List.fromList(utf8.encode('1}\n{"b":2}\npart')));
      await pumpEventQueue();
      expect(lines, ['{"a":1}', '{"b":2}']);
      await sub.cancel();
    });

    test('decodes a multi-byte character split across chunks', () async {
      final out = StreamController<Uint8List>();
      final ch = ByteLineChannel(
        stdout: out.stream,
        write: (_) {},
        close: () async {},
        done: Completer<void>().future,
      );
      final lines = <String>[];
      final sub = ch.lines.listen(lines.add);
      final bytes = utf8.encode('café\n');
      out.add(Uint8List.fromList(bytes.sublist(0, 4))); // cuts 'é' in two
      out.add(Uint8List.fromList(bytes.sublist(4)));
      await pumpEventQueue();
      expect(lines, ['café']);
      await sub.cancel();
    });

    test('writeLine sends utf8 bytes; lines closes when stdout ends', () async {
      final out = StreamController<Uint8List>();
      final written = <int>[];
      final ch = ByteLineChannel(
        stdout: out.stream,
        write: written.addAll,
        close: () async {},
        done: Completer<void>().future,
      );
      ch.writeLine('{"é":1}\n');
      expect(utf8.decode(written), '{"é":1}\n');
      var closed = false;
      ch.lines.listen((_) {}, onDone: () => closed = true);
      await out.close();
      await pumpEventQueue();
      expect(closed, true);
    });
  });

  group('checkHostKey', () {
    final fp = Uint8List.fromList([1, 2, 255]);

    test('pins the fingerprint on first use', () async {
      final kv = MemoryStore();
      expect(await checkHostKey(kv, 'p1', 'ssh-ed25519', fp), true);
      expect(kv.data['hostkey:p1'], 'ssh-ed25519 0102ff');
    });

    test('accepts the same fingerprint again', () async {
      final kv = MemoryStore();
      await checkHostKey(kv, 'p1', 'ssh-ed25519', fp);
      expect(await checkHostKey(kv, 'p1', 'ssh-ed25519', fp), true);
    });

    test('rejects a changed fingerprint and keeps the pinned one', () async {
      final kv = MemoryStore();
      await checkHostKey(kv, 'p1', 'ssh-ed25519', fp);
      final other = Uint8List.fromList([9, 9, 9]);
      expect(await checkHostKey(kv, 'p1', 'ssh-ed25519', other), false);
      expect(kv.data['hostkey:p1'], 'ssh-ed25519 0102ff');
    });
  });
}
