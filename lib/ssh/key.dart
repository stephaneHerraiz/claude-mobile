import 'package:dartssh2/dartssh2.dart';

/// A pasted private key that cannot be used as it stands.
class KeyError implements Exception {
  const KeyError(this.message, {this.needsPassphrase = false});
  final String message;

  /// True when the fault lies with the passphrase rather than the key.
  final bool needsPassphrase;

  @override
  String toString() => message;
}

/// Checks a pasted private key and returns it without passphrase protection,
/// which is how it is kept in the phone's secure storage.
///
/// Throws a [KeyError] when the text is not a private key, or when it is
/// protected and [passphrase] does not open it.
String unlockKey(String pem, String passphrase) {
  final text = pem.trim();
  final bool encrypted;
  try {
    encrypted = SSHKeyPair.isEncryptedPem(text);
    if (!encrypted) SSHKeyPair.fromPem(text);
  } on Object {
    throw const KeyError(
      'This is not a private key. Paste the whole file, from '
      '"-----BEGIN" to "-----END".',
    );
  }
  if (!encrypted) return text;
  if (passphrase.isEmpty) {
    throw const KeyError(
      'This key is protected: enter its passphrase.',
      needsPassphrase: true,
    );
  }
  try {
    return SSHKeyPair.fromPem(
      text,
      passphrase,
    ).map((pair) => pair.toPem()).join('\n').trim();
  } on Object {
    throw const KeyError('Wrong passphrase.', needsPassphrase: true);
  }
}
