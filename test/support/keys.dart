import 'dart:io';

/// Throwaway SSH keys made with `ssh-keygen`, so that no key lives in git.
class TestKeys {
  TestKeys._(this.plain, this.encrypted);

  static const passphrase = 'correct horse';

  /// An unprotected private key.
  final String plain;

  /// The same key, protected by [passphrase].
  final String encrypted;

  static TestKeys generate() {
    final dir = Directory.systemTemp.createTempSync('claude_mobile_keys');
    try {
      final path = '${dir.path}/key';
      _keygen(['-q', '-t', 'ed25519', '-N', '', '-f', path]);
      final plain = File(path).readAsStringSync();
      _keygen(['-q', '-p', '-N', passphrase, '-f', path]);
      return TestKeys._(plain, File(path).readAsStringSync());
    } finally {
      dir.deleteSync(recursive: true);
    }
  }

  static void _keygen(List<String> args) {
    final r = Process.runSync('ssh-keygen', args);
    if (r.exitCode != 0) throw StateError('ssh-keygen failed: ${r.stderr}');
  }
}
