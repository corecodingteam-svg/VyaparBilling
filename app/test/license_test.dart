import 'dart:convert';

import 'package:billing_app/core/api_client.dart';
import 'package:billing_app/core/license/license_certificate.dart';
import 'package:billing_app/core/license/license_checker.dart';
import 'package:billing_app/core/license/license_cubit.dart';
import 'package:billing_app/core/license/license_info.dart';
import 'package:billing_app/core/license/license_vault.dart';
import 'package:billing_app/core/license/trusted_clock.dart';
import 'package:billing_app/data/repositories/license_repository.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';


/// Made by the server's own code (Node, Ed25519) with a throwaway key: proves the app reads what the server signs.
const _serverPublicKey = 'cwpKuGf5UIJT98lxdiyi9/QUqSyuJxhPwC9Ga0pfvxk=';
const _serverToken = 'eyJ2IjoxLCJraWQiOiJrMSIsImxpY2Vuc2VfaWQiOiJsaWMtMSIsImN1c3RvbWVyX2lkIjoiY3VzdC0xIiwiaW5zdGFsbGF0aW9uX2lkIjoiaW5zdC0wMTIzNDU2Nzg5YWJjZGVmIiwicHJvZHVjdF9pZCI6ImJpbGxpbmciLCJwbGFuIjoiZnVsbCIsInN0YXR1cyI6ImFjdGl2ZSIsImlzc3VlZF9hdCI6IjIwMjYtMTAtMDFUMDA6MDA6MDAuMDAwWiIsInZhbGlkX2Zyb20iOiIyMDI2LTEwLTAxVDAwOjAwOjAwLjAwMFoiLCJleHBpcmVzX2F0IjoiMjAyNi0xMC0yMFQxODozMDowMC4wMDBaIiwiZXhwaXJlc19vbiI6IjIwMjYtMTAtMjAiLCJtYXhfZGV2aWNlcyI6NSwibGljZW5zZV92ZXJzaW9uIjozLCJzZXJ2ZXJfdGltZXN0YW1wIjoiMjAyNi0xMC0xNVQwODowMDowMC4wMDBaIiwiY2hlY2tpbl9ieSI6bnVsbCwiZmVhdHVyZXMiOnsicG9zT25seSI6ZmFsc2UsInJlcG9ydHMiOnRydWV9LCJzdXBwb3J0X2NvbnRhY3QiOiJoZWxwQGV4YW1wbGUuY29tIn0.EY_F6ESIqzynMt5VwovVefj2_7w75pnq2x_7pW2VkJYsnCbPmAPzDYu2fSLPoLddVNHAqIgZKbeWTtTd2WOyCg';

const _inst = 'inst-0123456789abcdef';
const _cust = 'cust-1';

final _algorithm = Ed25519();

DateTime utc(int d, [int h = 0, int m = 0]) => DateTime.utc(2026, 10, d, h, m);

/// A server with its own key pair, issuing certificates like the real one.
class TestServer {
  late final SimpleKeyPair keys;
  late final String publicKey;

  static Future<TestServer> create() async {
    final s = TestServer();
    s.keys = await _algorithm.newKeyPair();
    s.publicKey = base64.encode((await s.keys.extractPublicKey()).bytes);
    return s;
  }

  Future<String> mint({
    String installation = _inst,
    String customer = _cust,
    String product = 'billing',
    DateTime? issuedAt,
    DateTime? validFrom,
    DateTime? expiresAt,
    bool noExpiry = false,
    int version = 1,
    DateTime? checkinBy,
    String status = 'active',
  }) async {
    final issued = issuedAt ?? utc(1);
    final end = noExpiry ? null : (expiresAt ?? utc(20, 18, 30)); // "until 20 Oct" in India = 21 Oct 00:00 IST
    final payload = {
      'v': 1, 'kid': 'k1', 'license_id': 'lic-1', 'customer_id': customer, 'installation_id': installation, 'product_id': product, 'plan': 'full', 'status': status,
      'issued_at': issued.toIso8601String(), 'valid_from': (validFrom ?? utc(1)).toIso8601String(), 'expires_at': end?.toIso8601String(),
      'expires_on': end == null ? null : '2026-10-20', 'max_devices': 5, 'license_version': version, 'server_timestamp': issued.toIso8601String(),
      'checkin_by': checkinBy?.toIso8601String(), 'features': {'posOnly': false}, 'support_contact': 'help@example.com',
    };
    final body = utf8.encode(jsonEncode(payload));
    final sig = await _algorithm.sign(body, keyPair: keys);
    return '${base64Url.encode(body).replaceAll('=', '')}.${base64Url.encode(sig.bytes).replaceAll('=', '')}';
  }
}

void main() {
  late TestServer server;
  late LicenseVerifier verifier;

  setUp(() async {
    server = await TestServer.create();
    verifier = LicenseVerifier(server.publicKey);
  });

  Future<LicenseDecision> check(
    String? token, {
    required DateTime now,
    ClockState clock = const ClockState(),
    int highest = 0,
    ClockTamperPolicy policy = ClockTamperPolicy.requireOnlineValidation,
    ServerVerdict? verdict,
    String installation = _inst,
  }) async {
    final cert = token == null ? null : await verifier.verify(token);
    return checkLicense(
      certificate: cert,
      installationId: installation,
      customerId: _cust,
      clockState: clock,
      deviceNow: now,
      highestVersionSeen: highest,
      policy: policy,
      serverVerdict: verdict,
      signatureOk: token == null || cert != null,
    );
  }

  group('signature', () {
    test('a certificate made by the server code (Node) verifies and reads back', () async {
      final cert = await LicenseVerifier(_serverPublicKey).verify(_serverToken);
      expect(cert, isNotNull);
      expect([cert!.licenseId, cert.customerId, cert.version, cert.expiresOn, cert.plan], ['lic-1', 'cust-1', 3, '2026-10-20', 'full']);
      expect(cert.expiresAt, utc(20, 18, 30));
      expect(cert.features['reports'], isTrue);
    });

    test('a build with no valid public key accepts nothing', () async {
      expect(await LicenseVerifier('').verify(_serverToken), isNull);
      expect(await LicenseVerifier('not base64!').verify(_serverToken), isNull);
    });

    test('the same certificate does not verify under another key', () async {
      expect(await verifier.verify(_serverToken), isNull);
    });

    test('changing the payload (a longer expiry) breaks the signature', () async {
      final token = await server.mint();
      final parts = token.split('.');
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[0])))) as Map<String, dynamic>;
      payload['expires_at'] = '2099-01-01T00:00:00.000Z';
      final forged = '${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.${parts[1]}';
      expect(await verifier.verify(forged), isNull);
      expect(await verifier.verify('garbage'), isNull);
      expect(await verifier.verify('a.b.c'), isNull);
    });

    test('a certificate that fails the signature is "invalid", never accepted', () async {
      final d = await check('x.y', now: utc(5));
      expect(d.status, LicenseStatus.invalid);
    });
  });

  group('expiry, offline', () {
    test('valid until 20 Oct; server went offline on 15 Oct; opened on 21 Oct → License Expired with the date', () async {
      final token = await server.mint(issuedAt: utc(15, 6)); // last time the server was reached
      final clock = const TrustedClock().recordServerTime(const ClockState(), utc(15, 6), utc(15, 6));
      expect((await check(token, now: utc(15, 12), clock: clock)).status, LicenseStatus.valid);
      expect((await check(token, now: utc(20, 12), clock: clock)).status, LicenseStatus.valid);
      final d = await check(token, now: utc(21, 9), clock: clock);
      expect(d.status, LicenseStatus.expired);
      expect(d.message, contains('2026-10-20'));
      expect(d.certificate!.expiresOn, '2026-10-20');
      expect(d.allowed, isFalse);
    });

    test('the instant of expires_at is already expired; the instant before is not', () async {
      final token = await server.mint(issuedAt: utc(15), expiresAt: utc(20, 18, 30));
      final clock = const TrustedClock().recordServerTime(const ClockState(), utc(15), utc(15));
      expect((await check(token, now: DateTime.utc(2026, 10, 20, 18, 29, 59, 999), clock: clock)).status, LicenseStatus.valid);
      expect((await check(token, now: utc(20, 18, 30), clock: clock)).status, LicenseStatus.expired);
    });

    test('a licence with no end date never expires', () async {
      final token = await server.mint(noExpiry: true);
      expect((await check(token, now: DateTime.utc(2040, 1, 1))).status, LicenseStatus.valid);
    });

    test('not yet valid before its start date', () async {
      final token = await server.mint(validFrom: utc(10), issuedAt: utc(1));
      expect((await check(token, now: utc(5))).status, LicenseStatus.notYetValid);
    });

    test('no certificate: needs activating', () async {
      expect((await check(null, now: utc(5))).status, LicenseStatus.notActivated);
    });
  });

  group('binding', () {
    test('another device, business or product is refused', () async {
      expect((await check(await server.mint(installation: 'inst-other-0123456789'), now: utc(5))).status, LicenseStatus.invalid);
      expect((await check(await server.mint(customer: 'cust-2'), now: utc(5))).status, LicenseStatus.invalid);
      expect((await check(await server.mint(product: 'clinic'), now: utc(5))).status, LicenseStatus.invalid);
      expect((await check(await server.mint(status: 'suspended'), now: utc(5))).status, LicenseStatus.invalid);
    });

    test('an older certificate than one already seen is refused', () async {
      final token = await server.mint(version: 2);
      expect((await check(token, now: utc(5), highest: 3)).status, LicenseStatus.invalid);
      expect((await check(token, now: utc(5), highest: 2)).status, LicenseStatus.valid);
    });

    test('what the server said (suspended) stands offline until a new certificate arrives', () async {
      final token = await server.mint();
      final d = await check(token, now: utc(5), verdict: (status: LicenseStatus.suspended, message: 'unpaid'));
      expect([d.status, d.message], [LicenseStatus.suspended, 'unpaid']);
    });

    test('too long since the server was reached asks for online validation', () async {
      final token = await server.mint(issuedAt: utc(1), checkinBy: utc(10));
      expect((await check(token, now: utc(9))).status, LicenseStatus.valid);
      expect((await check(token, now: utc(11))).status, LicenseStatus.requiresOnlineValidation);
    });
  });

  group('clock', () {
    const clock = TrustedClock();

    test('while offline "now" is the device clock plus the gap learned from the server', () {
      // The device clock runs 3 days slow when it meets the server.
      final state = clock.recordServerTime(const ClockState(), utc(20, 10), utc(17, 10));
      expect(state.offsetMs, const Duration(days: 3).inMilliseconds);
      expect(clock.read(state, utc(17, 14)).trusted, utc(20, 14));
    });

    test('a rollback is noticed and "now" never goes back below what was already seen', () {
      final state = clock.recordServerTime(const ClockState(), utc(20, 10), utc(20, 10));
      final r = clock.read(state, utc(18, 10)); // device says 18 Oct
      expect(r.rolledBack, isTrue);
      expect(r.trusted, utc(20, 10));
      expect(r.state.tamperDetected, isTrue);
    });

    test('small differences are not a rollback', () {
      final state = clock.recordServerTime(const ClockState(), utc(20, 10), utc(20, 10));
      expect(clock.read(state, utc(20, 9, 58)).rolledBack, isFalse);
    });

    test('deleting the stored state does not reset it: the certificate carries a floor', () {
      final r = clock.read(const ClockState(), utc(14), floor: utc(15, 8));
      expect(r.rolledBack, isTrue);
      expect(r.trusted, utc(15, 8));
    });

    test('turning the clock back never gives more days', () async {
      final token = await server.mint(expiresAt: utc(19, 18, 30)); // until 19 Oct
      var state = clock.recordServerTime(const ClockState(), utc(20, 10), utc(20, 10)); // already 20 Oct, expired
      final d = await check(token, now: utc(18, 10), clock: state, policy: ClockTamperPolicy.warn);
      expect(d.status, LicenseStatus.expired);
      state = d.clock!;
    });

    test('default policy: after a rollback, the server must confirm the date; the flag stays even if the clock is put right', () async {
      final token = await server.mint(issuedAt: utc(1));
      var state = clock.recordServerTime(const ClockState(), utc(10, 10), utc(10, 10));
      final back = await check(token, now: utc(8, 10), clock: state);
      expect(back.status, LicenseStatus.clockTamper);
      expect(back.message, contains('date/time appears to have changed'));
      state = back.clock!;
      expect((await check(token, now: utc(10, 12), clock: state)).status, LicenseStatus.clockTamper); // clock fixed, still flagged
      state = clock.recordServerTime(state, utc(10, 13), utc(10, 12)); // the server confirms the date
      expect((await check(token, now: utc(10, 13), clock: state)).status, LicenseStatus.valid);
    });

    test('warn policy lets the app run with a warning; block policy stops it only while the clock is behind', () async {
      final token = await server.mint(issuedAt: utc(1));
      final state = clock.recordServerTime(const ClockState(), utc(10, 10), utc(10, 10));
      final warn = await check(token, now: utc(8), clock: state, policy: ClockTamperPolicy.warn);
      expect([warn.status, warn.warning != null], [LicenseStatus.valid, true]);
      final blocked = await check(token, now: utc(8), clock: state, policy: ClockTamperPolicy.block);
      expect(blocked.status, LicenseStatus.clockTamper);
      expect((await check(token, now: utc(10, 11), clock: blocked.clock!, policy: ClockTamperPolicy.block)).status, LicenseStatus.valid);
    });
  });

  test('Settings shows days left from the trusted time', () {
    final end = utc(20, 18, 30);
    expect(licenseTimeLeft(end, utc(15, 8)), '5 days left');
    expect(licenseTimeLeft(end, utc(20, 10)), 'Ends today');
    expect(licenseTimeLeft(end, utc(21, 9)), 'Expired today');
    expect(licenseTimeLeft(end, utc(23, 9)), 'Expired 2 days ago');
    expect(licenseTimeLeft(null, utc(1)), 'No end date');
  });

  group('LicenseCubit', () {
    late MemorySecureStore secure;
    late FakeLicenseRepository repo;
    late DateTime deviceNow;

    LicenseCubit build({ClockTamperPolicy policy = ClockTamperPolicy.requireOnlineValidation}) =>
        LicenseCubit(repo, LicenseVault(secure), verifier: verifier, now: () => deviceNow, policy: policy, tick: const Duration(days: 1));

    setUp(() {
      secure = MemorySecureStore();
      repo = FakeLicenseRepository(server);
      deviceNow = utc(15, 8);
    });

    Future<String> installation() => LicenseVault(secure).installationId();

    test('first start activates online once, then runs with no connection at all', () async {
      var c = build();
      await c.start(_cust);
      await pumpEventQueue();
      expect(c.state.status, LicenseStatus.valid);
      expect(repo.activations, 1);
      // What Settings → License shows
      expect(c.state.installationId, await installation());
      expect(c.state.lastServerSync, utc(15, 8));
      expect(c.state.certificate!.expiresOn, '2026-10-20');
      await c.close();

      repo.offline = true; // the server is gone
      c = build();
      await c.start(_cust);
      await pumpEventQueue();
      expect(c.state.status, LicenseStatus.valid);
      await c.close();
    });

    test('offline on 21 Oct: License Expired, the app is not allowed, and no network call was needed for it', () async {
      var c = build();
      await c.start(_cust);
      await pumpEventQueue();
      await c.close();

      repo.offline = true; // the server is gone
      deviceNow = utc(21, 9);
      c = build();
      await c.evaluate0(_cust);
      expect(c.state.status, LicenseStatus.expired);
      expect(c.state.allowed, isFalse);
      expect(c.state.certificate!.expiresOn, '2026-10-20');
      await c.close();
    });

    test('renewing: once the server issues a new certificate, "Check again" lets the app in', () async {
      var c = build();
      await c.start(_cust);
      await pumpEventQueue();
      await c.close();
      deviceNow = utc(21, 9);
      repo.offline = true;
      c = build();
      await c.evaluate0(_cust);
      expect(c.state.status, LicenseStatus.expired);
      repo.offline = false; // renewed on the server, device back online
      repo.expiresAt = utc(31, 18, 30);
      repo.version = 2;
      repo.serverNow = utc(21, 9);
      await c.validateOnline();
      expect(c.state.status, LicenseStatus.valid);
      await c.close();
    });

    test('a rolled-back clock needs the server; without it the app stays locked with the message', () async {
      var c = build();
      await c.start(_cust);
      await pumpEventQueue();
      await c.close();

      repo.offline = true;
      deviceNow = utc(16, 10);
      c = build();
      await c.evaluate0(_cust); // seen on 16 Oct
      await c.close();
      deviceNow = utc(12, 10); // wound back
      c = build();
      await c.evaluate0(_cust);
      expect(c.state.status, LicenseStatus.clockTamper);
      await c.validateOnline();
      expect(c.state.status, LicenseStatus.clockTamper);
      expect(c.state.notice, contains('No internet'));
      expect(c.state.message, contains('date/time appears to have changed'));

      repo.offline = false;
      repo.serverNow = utc(16, 10);
      await c.validateOnline();
      expect(c.state.status, LicenseStatus.valid);
      await c.close();
    });

    test('a revoked licence stays blocked offline until the server issues a new certificate', () async {
      var c = build();
      await c.start(_cust);
      await pumpEventQueue();
      repo.failWith = ApiException('This licence has been revoked.', code: 'LICENSE_REVOKED');
      await c.validateOnline();
      expect(c.state.status, LicenseStatus.revoked);
      await c.close();

      repo.offline = true;
      c = build();
      await c.evaluate0(_cust);
      expect(c.state.status, LicenseStatus.revoked);
      await c.close();
    });

    test('device limit reached is reported and does not install a certificate', () async {
      final c = build();
      repo.failWith = ApiException('This licence allows 1 device and all are in use.', code: 'DEVICE_LIMIT');
      await c.start(_cust);
      await pumpEventQueue();
      expect([c.state.status, c.state.message], [LicenseStatus.deviceLimit, contains('1 device')]);
      expect(await LicenseVault(secure).certificate(_cust), isNull);
      await c.close();
    });

    test('a certificate for another installation sent by the server is not installed', () async {
      final c = build();
      repo.forInstallation = 'inst-someone-else-0123';
      await c.start(_cust);
      await pumpEventQueue();
      expect(c.state.status, LicenseStatus.invalid);
      expect(await LicenseVault(secure).certificate(_cust), isNull);
      await c.close();
      expect(await installation(), isNot('inst-someone-else-0123'));
    });
  });
}

extension on LicenseCubit {
  /// Starts without the background online attempt, to test the offline decision alone.
  Future<void> evaluate0(String customer) async {
    // start() would also try the server; the offline check is what is under test.
    await start(customer);
    await pumpEventQueue();
  }
}

/// Stands in for the server's licence calls.
class FakeLicenseRepository extends LicenseRepository {
  FakeLicenseRepository(this.server) : super(ApiClient(TokenStore()));
  final TestServer server;
  var offline = false;
  var activations = 0;
  var calls = 0;
  DateTime? expiresAt;
  DateTime? serverNow;
  int version = 1;
  String? forInstallation;
  ApiException? failWith;

  Future<LicenseGrant> _issue(String installation) async {
    calls++;
    if (offline) throw ApiException('Cannot reach the server.', offline: true);
    if (failWith != null) throw failWith!;
    final now = serverNow ?? utc(15, 8);
    return LicenseGrant(
      await server.mint(installation: forInstallation ?? installation, issuedAt: now, expiresAt: expiresAt, version: version),
      now,
    );
  }

  @override
  Future<LicenseGrant> activate(String installationId) {
    activations++;
    return _issue(installationId);
  }

  @override
  Future<LicenseGrant> refresh(String installationId) => _issue(installationId);
}
