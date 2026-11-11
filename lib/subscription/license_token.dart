import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'license_config.dart';

/// What a verified license says. See the server's README for the claims.
class LicenseClaims {
  const LicenseClaims({
    required this.tier,
    required this.installId,
    required this.issuedAt,
    required this.expires,
    required this.enforce,
    this.trialEnd,
    this.proUntil,
    this.minVersion = '0.0.0',
    this.reason = '',
  });

  final String tier; // free | trial | pro
  final String installId;
  final DateTime issuedAt;
  final DateTime expires;
  final bool enforce;
  final DateTime? trialEnd;
  final DateTime? proUntil;
  final String minVersion;
  final String reason;

  /// The tier is only to be trusted until the license expires.
  bool isFresh(DateTime now) => now.isBefore(expires);
}

/// The 32 raw key bytes inside a PEM public key (Ed25519, SPKI form).
Uint8List publicKeyFromPem(String pem) {
  final body = pem
      .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
      .replaceAll(RegExp(r'\s'), '');
  final der = base64.decode(body);
  // 12 bytes of fixed header, then the 32-byte key.
  const header = [0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03];
  if (der.length != 44 ||
      !List.generate(
        header.length,
        (i) => der[i] == header[i],
      ).every((b) => b)) {
    throw const FormatException('Not an Ed25519 public key');
  }
  return Uint8List.fromList(der.sublist(12));
}

Uint8List _b64url(String s) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));

/// Checks [token] and returns its claims, or null if it is not a genuine
/// license for this app and this install. The expiry is NOT checked here
/// (the caller decides what an old license is still good for); use
/// [LicenseClaims.isFresh].
///
/// Refused: wrong number of parts, any algorithm but EdDSA, a bad signature,
/// another issuer, another app, another install, or unreadable claims.
Future<LicenseClaims?> verifyLicense(
  String token, {
  required String installId,
  Uint8List? publicKey,
  String audience = licenseAudience,
}) async {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;

    final header = jsonDecode(utf8.decode(_b64url(parts[0])));
    if (header is! Map || header['alg'] != 'EdDSA') return null;

    final ok = await Ed25519().verify(
      utf8.encode('${parts[0]}.${parts[1]}'),
      signature: Signature(
        _b64url(parts[2]),
        publicKey: SimplePublicKey(
          publicKey ?? publicKeyFromPem(licensePublicKeyPem),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!ok) return null;

    final c = jsonDecode(utf8.decode(_b64url(parts[1])));
    if (c is! Map) return null;
    if (c['iss'] != 'playlicense') return null;
    final aud = c['aud'];
    if (aud is String
        ? aud != audience
        : !(aud is List && aud.contains(audience))) {
      return null;
    }
    if (c['sub'] != installId) return null;

    final tier = c['tier'];
    if (tier is! String || !const {'free', 'trial', 'pro'}.contains(tier)) {
      return null;
    }
    DateTime? at(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v * 1000) : null;
    final iat = at(c['iat']);
    final exp = at(c['exp']);
    if (iat == null || exp == null) return null;

    return LicenseClaims(
      tier: tier,
      installId: installId,
      issuedAt: iat,
      expires: exp,
      enforce: c['enforce'] == true,
      trialEnd: at(c['trial_end']),
      proUntil: at(c['pro_until']),
      minVersion: c['min_version'] is String
          ? c['min_version'] as String
          : '0.0.0',
      reason: c['reason'] is String ? c['reason'] as String : '',
    );
  } catch (_) {
    return null;
  }
}
