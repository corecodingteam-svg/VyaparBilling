import 'license_certificate.dart';
import 'trusted_clock.dart';

enum LicenseStatus {
  /// Still working it out.
  checking,

  /// No certificate on this device yet: it has to be activated online once.
  notActivated,

  /// The certificate is not genuine, or is for another device, company or product, or is older than one already seen.
  invalid,
  notYetValid,
  expired,

  /// The device clock was turned back and the policy asks for the server to confirm the date.
  clockTamper,

  /// Too long since the server was reached (see the certificate's check-in date).
  requiresOnlineValidation,

  /// The server said the licence is suspended or revoked.
  suspended,
  revoked,

  /// Every device slot on the licence is taken.
  deviceLimit,
  valid,
}

/// How a certificate stands, worked out on the device alone.
class LicenseDecision {
  const LicenseDecision(this.status, {this.certificate, this.message = '', this.warning, this.clock});
  final LicenseStatus status;
  final LicenseCertificate? certificate;

  /// For the screen that explains why the app is locked.
  final String message;

  /// Set when the app may run but something should be said (a clock rollback under the "warn" policy).
  final String? warning;

  /// The clock state to store after this check.
  final ClockState? clock;

  bool get allowed => status == LicenseStatus.valid;
}

const clockTamperMessage = 'Unable to verify the license because the device date/time appears to have changed. Connect to the internet so the license can be verified, then try again.';

/// What the server last said about the licence, kept so it still applies offline: suspended / revoked / device limit, or null.
typedef ServerVerdict = ({LicenseStatus status, String message});

/// The offline licence check:  signature → binding → (server verdict) → start date → expiry → clock → check-in.
/// It never touches the network. [certificate] must already have passed [LicenseVerifier.verify].
LicenseDecision checkLicense({
  required LicenseCertificate? certificate,
  required String installationId,
  required String? customerId,
  required ClockState clockState,
  required DateTime deviceNow,
  required int highestVersionSeen,
  ServerVerdict? serverVerdict,
  ClockTamperPolicy policy = ClockTamperPolicy.requireOnlineValidation,
  TrustedClock clock = const TrustedClock(),
  String productId = licenseProductId,
  bool signatureOk = true,
}) {
  if (certificate == null) {
    return LicenseDecision(signatureOk ? LicenseStatus.notActivated : LicenseStatus.invalid, message: signatureOk ? 'This device has not been activated yet.' : 'The license on this device is not genuine.');
  }
  LicenseDecision invalid(String why) => LicenseDecision(LicenseStatus.invalid, certificate: certificate, message: why);
  if (certificate.installationId != installationId) return invalid('This license was issued for a different device.');
  if (customerId != null && certificate.customerId != customerId) return invalid('This license belongs to a different business.');
  if (certificate.productId != productId) return invalid('This license is for a different product.');
  if (certificate.status != 'active') return invalid('This license is not active.');
  if (certificate.version < highestVersionSeen) return invalid('This license certificate is out of date. Connect to the internet to update it.');

  // The server said no after this certificate was issued (suspended, revoked): that stands until a new certificate arrives.
  if (serverVerdict != null) return LicenseDecision(serverVerdict.status, certificate: certificate, message: serverVerdict.message);

  final reading = clock.read(clockState, deviceNow, floor: certificate.serverTimestamp);
  final now = reading.trusted;
  LicenseDecision decide(LicenseStatus s, String message, {String? warning}) => LicenseDecision(s, certificate: certificate, message: message, warning: warning, clock: reading.state);

  if (now.isBefore(certificate.validFrom)) return decide(LicenseStatus.notYetValid, 'This license starts on ${certificate.validFrom.toLocal().toString().substring(0, 10)}.');
  final end = certificate.expiresAt;
  // At the first instant of the end time the licence no longer works.
  if (end != null && !now.isBefore(end)) {
    return decide(LicenseStatus.expired, 'Your license expired${certificate.expiresOn == null ? '' : ' on ${certificate.expiresOn}'}.');
  }

  final tampered = reading.state.tamperDetected;
  switch (policy) {
    case ClockTamperPolicy.requireOnlineValidation:
      if (tampered) return decide(LicenseStatus.clockTamper, clockTamperMessage);
    case ClockTamperPolicy.block:
      if (reading.rolledBack) return decide(LicenseStatus.clockTamper, clockTamperMessage);
    case ClockTamperPolicy.warn:
      break;
  }

  final checkin = certificate.checkinBy;
  if (checkin != null && !now.isBefore(checkin)) {
    return decide(LicenseStatus.requiresOnlineValidation, 'This device has not been connected to the license server for a long time. Connect to the internet to validate the license.');
  }
  return decide(
    LicenseStatus.valid,
    '',
    warning: policy == ClockTamperPolicy.warn && tampered ? 'The date or time of this device appears to have been changed.' : null,
  );
}
