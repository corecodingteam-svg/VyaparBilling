import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'license_checker.dart';
import 'trusted_clock.dart';

/// Secret-ish storage: the platform keychain / keystore on a phone or computer.
abstract class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformSecureStore implements SecureValueStore {
  PlatformSecureStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemorySecureStore implements SecureValueStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Everything the licence check keeps on the device: this installation's id, the certificate, the clock state, and what the
/// server last said. The certificate and verdict are kept per business; the id and the clock belong to the device.
class LicenseVault {
  LicenseVault(this._store);
  final SecureValueStore _store;

  /// A random id made once per installation; it is what a certificate is bound to.
  Future<String> installationId() async {
    final existing = await _store.read('license.installation');
    if (existing != null && existing.length >= 16) return existing;
    final r = Random.secure();
    final id = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
    await _store.write('license.installation', id);
    return id;
  }

  Future<String?> certificate(String customerId) => _store.read('license.cert.$customerId');
  Future<void> saveCertificate(String customerId, String token) => _store.write('license.cert.$customerId', token);
  Future<void> deleteCertificate(String customerId) => _store.delete('license.cert.$customerId');

  Future<ClockState> clock() async => ClockState.fromText(await _store.read('license.clock'));
  Future<void> saveClock(ClockState s) => _store.write('license.clock', s.toJsonText());

  /// The highest licence version this device has seen for the business: an older certificate is refused.
  Future<int> highestVersion(String customerId) async => int.tryParse(await _store.read('license.version.$customerId') ?? '') ?? 0;
  Future<void> saveHighestVersion(String customerId, int v) => _store.write('license.version.$customerId', '$v');

  Future<ServerVerdict?> verdict(String customerId) async {
    final text = await _store.read('license.verdict.$customerId');
    if (text == null) return null;
    final i = text.indexOf('|');
    final status = LicenseStatus.values.where((s) => s.name == text.substring(0, i)).firstOrNull;
    return status == null ? null : (status: status, message: text.substring(i + 1));
  }

  Future<void> saveVerdict(String customerId, ServerVerdict v) => _store.write('license.verdict.$customerId', '${v.status.name}|${v.message}');
  Future<void> clearVerdict(String customerId) => _store.delete('license.verdict.$customerId');
}
