import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// This device's TLS certificate and key. Made once, then kept, so other
/// devices can recognize it by its [fingerprint].
///
/// Transfers between Wisp apps run over HTTPS with this self-made
/// certificate. There's no certificate authority on a home network, so
/// instead each device announces its certificate's fingerprint, and the
/// other side only talks to a server presenting exactly that certificate.
class Identity {
  Identity._(this.certPem, this.keyPem)
    : fingerprint = certFingerprint(CryptoUtils.getBytesFromPEMString(certPem));

  final String certPem;
  final String keyPem;

  /// SHA-256 of the certificate, as 64 hex characters.
  final String fingerprint;

  /// A new certificate and key (elliptic curve P-256, valid for 10 years).
  /// Runs on a background isolate so the UI doesn't stutter.
  static Future<Identity> generate() async {
    final (cert, key) = await Isolate.run(_generatePem);
    return Identity._(cert, key);
  }

  /// A saved identity, or null if it's missing or unusable.
  static Identity? fromPem(String? certPem, String? keyPem) {
    if (certPem == null || keyPem == null) return null;
    try {
      return Identity._(certPem, keyPem)..serverContext; // checks both parse
    } catch (_) {
      return null;
    }
  }

  SecurityContext get serverContext => SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));
}

(String, String) _generatePem() {
  final pair = CryptoUtils.generateEcKeyPair();
  final privateKey = pair.privateKey as ECPrivateKey;
  final publicKey = pair.publicKey as ECPublicKey;
  final csr = X509Utils.generateEccCsrPem(
    {'CN': 'Wisp device'},
    privateKey,
    publicKey,
  );
  return (
    X509Utils.generateSelfSignedCertificate(privateKey, csr, 3650),
    CryptoUtils.encodeEcPrivateKeyToPem(privateKey),
  );
}

String certFingerprint(List<int> der) => sha256.convert(der).toString();

/// The 4-character code both screens show for a transfer, like "4F9A".
///
/// It comes from the receiver's certificate: the sender computes it from
/// the certificate it actually connected to, the receiver from its own. If
/// someone were sitting in between with their own certificate, the two
/// codes would differ. (Four characters catch a casual impostor, not a
/// determined attacker with time to prepare.)
String securityCode(String receiverFingerprint, String sessionId) => sha256
    .convert(utf8.encode('$receiverFingerprint:$sessionId'))
    .toString()
    .substring(0, 4)
    .toUpperCase();

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

bool isFingerprint(Object? value) => value is String && _hex64.hasMatch(value);
