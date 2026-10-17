import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/api_client.dart';

/// What the licence server sent back: a signed certificate and its own clock.
class LicenseGrant {
  const LicenseGrant(this.certificate, this.serverTime);
  final String certificate;
  final DateTime serverTime;
}

/// The calls that need a connection: getting, renewing and giving back this device's certificate.
class LicenseRepository {
  LicenseRepository(this._api);
  final ApiClient _api;

  static String get _platform => kIsWeb ? 'web' : Platform.operatingSystem;

  LicenseGrant _grant(Map<String, dynamic> j) => LicenseGrant(j['certificate'] as String, DateTime.parse(j['serverTime'] as String).toUtc());

  Future<LicenseGrant> activate(String installationId) async =>
      _grant(await _api.post<Map<String, dynamic>>('/licenses/activate', {'installationId': installationId, 'deviceName': _platform, 'platform': _platform}));

  Future<LicenseGrant> refresh(String installationId) async => _grant(await _api.post<Map<String, dynamic>>('/licenses/refresh', {'installationId': installationId}));

  Future<void> deactivate(String installationId) => _api.post<dynamic>('/licenses/deactivate', {'installationId': installationId});
}
