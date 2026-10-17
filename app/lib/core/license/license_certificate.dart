import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';

/// The public key of the licence server (32 raw bytes, base64). Only a public key can ever be in the app: the server keeps
/// the private one and signs with it. Release builds pass their own with --dart-define=LICENSE_PUBLIC_KEY=...
const licensePublicKey = String.fromEnvironment('LICENSE_PUBLIC_KEY', defaultValue: 'EgEF7J7MERLhPkG9fvMlKlhaj2ZTU2eSIT3yUHNrNWY=');

/// The product this app is; a certificate for another product is refused.
const licenseProductId = 'billing';

/// What the server signed, as read back on the device. Nothing in here is trusted until [LicenseVerifier] has accepted the signature.
class LicenseCertificate extends Equatable {
  const LicenseCertificate({
    required this.licenseId,
    required this.customerId,
    required this.installationId,
    required this.productId,
    required this.plan,
    required this.status,
    required this.issuedAt,
    required this.validFrom,
    required this.expiresAt,
    required this.expiresOn,
    required this.maxDevices,
    required this.version,
    required this.serverTimestamp,
    required this.checkinBy,
    required this.features,
    required this.supportContact,
    required this.token,
  });

  factory LicenseCertificate.fromPayload(Map<String, dynamic> j, String token) {
    DateTime time(String key) => DateTime.parse(j[key] as String).toUtc();
    DateTime? optTime(String key) => j[key] == null ? null : DateTime.parse(j[key] as String).toUtc();
    return LicenseCertificate(
      licenseId: j['license_id'] as String,
      customerId: j['customer_id'] as String,
      installationId: j['installation_id'] as String,
      productId: j['product_id'] as String,
      plan: j['plan'] as String,
      status: j['status'] as String,
      issuedAt: time('issued_at'),
      validFrom: time('valid_from'),
      expiresAt: optTime('expires_at'),
      expiresOn: j['expires_on'] as String?,
      maxDevices: (j['max_devices'] as num).toInt(),
      version: (j['license_version'] as num).toInt(),
      serverTimestamp: time('server_timestamp'),
      checkinBy: optTime('checkin_by'),
      features: {for (final e in ((j['features'] as Map?) ?? const {}).entries) '${e.key}': e.value == true},
      supportContact: j['support_contact'] as String?,
      token: token,
    );
  }

  final String licenseId;
  final String customerId;
  final String installationId;
  final String productId;
  final String plan;
  final String status;
  final DateTime issuedAt;
  final DateTime validFrom;

  /// The first instant the licence no longer works; null = no end.
  final DateTime? expiresAt;

  /// The last working day, to show people (YYYY-MM-DD).
  final String? expiresOn;
  final int maxDevices;
  final int version;

  /// The server's clock when it issued this: a floor the device's idea of "now" may never fall below.
  final DateTime serverTimestamp;

  /// The device must have reached the server by then, or it asks for online validation.
  final DateTime? checkinBy;
  final Map<String, bool> features;
  final String? supportContact;

  /// The signed text as received; kept as it is so it can be verified again at every start.
  final String token;

  @override
  List<Object?> get props => [token];
}

/// Checks a certificate's signature with the server's public key. Needs no connection.
class LicenseVerifier {
  /// A key that is not a valid 32-byte Ed25519 key (e.g. a build with an empty LICENSE_PUBLIC_KEY) accepts nothing.
  LicenseVerifier([String publicKeyBase64 = licensePublicKey]) : _key = _parse(publicKeyBase64);
  final SimplePublicKey? _key;

  static SimplePublicKey? _parse(String text) {
    try {
      final bytes = base64.decode(text.trim());
      return bytes.length == 32 ? SimplePublicKey(bytes, type: KeyPairType.ed25519) : null;
    } catch (_) {
      return null;
    }
  }
  static final _ed25519 = Ed25519();

  /// The certificate if the token is well formed and genuinely signed by the server; otherwise null.
  Future<LicenseCertificate?> verify(String token) async {
    final key = _key;
    final parts = token.split('.');
    if (key == null || parts.length != 2) return null;
    try {
      final body = base64Url.decode(base64Url.normalize(parts[0]));
      final signature = base64Url.decode(base64Url.normalize(parts[1]));
      final ok = await _ed25519.verify(body, signature: Signature(signature, publicKey: key));
      if (!ok) return null;
      final json = jsonDecode(utf8.decode(body));
      if (json is! Map<String, dynamic> || json['v'] != 1) return null;
      return LicenseCertificate.fromPayload(json, token);
    } catch (_) {
      return null;
    }
  }
}
