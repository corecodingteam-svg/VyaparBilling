import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The app lock's PIN, kept on this device only (it is not sent anywhere and is not part of a company).
/// Only a salted hash is stored. This is a lock against someone picking up an unlocked device, not
/// against someone who can read the device's storage.
class PasscodeStore {
  PasscodeStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'app_lock_pin';

  static String hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<bool> hasPin() async => (await _storage.read(key: _key)) != null;

  Future<void> setPin(String pin) async {
    final salt = base64UrlEncode(List.generate(16, (_) => Random.secure().nextInt(256)));
    await _storage.write(key: _key, value: '$salt:${hash(pin, salt)}');
  }

  Future<bool> check(String pin) async {
    final stored = await _storage.read(key: _key);
    if (stored == null) return true;
    final i = stored.indexOf(':');
    return hash(pin, stored.substring(0, i)) == stored.substring(i + 1);
  }

  Future<void> clear() => _storage.delete(key: _key);
}
