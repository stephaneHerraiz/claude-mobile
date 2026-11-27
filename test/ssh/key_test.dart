import 'package:remote_harness/ssh/key.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/keys.dart';

void main() {
  late TestKeys keys;
  setUpAll(() => keys = TestKeys.generate());

  List<int> publicPart(String pem) =>
      SSHKeyPair.fromPem(pem).single.toPublicKey().encode();

  test('an unprotected key is kept as is', () {
    expect(unlockKey('  ${keys.plain}\n', ''), keys.plain.trim());
  });

  test('a protected key is unlocked into the same key, unprotected', () {
    final unlocked = unlockKey(keys.encrypted, TestKeys.passphrase);
    expect(SSHKeyPair.isEncryptedPem(unlocked), isFalse);
    expect(publicPart(unlocked), publicPart(keys.plain));
  });

  test('a protected key without its passphrase asks for it', () {
    expect(
      () => unlockKey(keys.encrypted, ''),
      throwsA(
        isA<KeyError>()
            .having((e) => e.needsPassphrase, 'needsPassphrase', isTrue)
            .having((e) => e.message, 'message', contains('passphrase')),
      ),
    );
  });

  test('a wrong passphrase is reported as such', () {
    expect(
      () => unlockKey(keys.encrypted, 'nope'),
      throwsA(
        isA<KeyError>()
            .having((e) => e.needsPassphrase, 'needsPassphrase', isTrue)
            .having((e) => e.message, 'message', 'Wrong passphrase.'),
      ),
    );
  });

  for (final (name, text) in [
    ('free text', 'PEMDATA'),
    ('a public key', 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFake me@pc'),
    (
      'a truncated key',
      '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----',
    ),
  ]) {
    test('$name is not accepted as a private key', () {
      expect(
        () => unlockKey(text, ''),
        throwsA(
          isA<KeyError>().having(
            (e) => e.needsPassphrase,
            'needsPassphrase',
            isFalse,
          ),
        ),
      );
    });
  }
}
