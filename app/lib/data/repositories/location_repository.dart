import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:geolocator/geolocator.dart';

import '../../core/api_client.dart';
import '../models/team_location.dart';

/// Where users are: reading the device's position and sending it to the server.
class LocationRepository {
  LocationRepository(this._api);
  final ApiClient _api;

  /// The device's position, or null when location is off or the user has not allowed it. A first
  /// call asks the user for permission (the browser or phone shows its own prompt).
  Future<GeoFix?> currentFix() async {
    try {
      if (!await _allowed()) return null;
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      return GeoFix(p.latitude, p.longitude, p.accuracy);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _allowed() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    return permission != LocationPermission.denied && permission != LocationPermission.deniedForever;
  }

  /// Positions as the device moves, kept coming while the app is in the background: on Android through a
  /// foreground service (with the notification Android requires), on iOS through background location
  /// updates (with the blue status-bar indicator). Ends at once, without positions, when location is not allowed.
  Stream<GeoFix> backgroundFixes() async* {
    if (!await _allowed()) return;
    final settings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
        intervalDuration: const Duration(minutes: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Billing is recording your location',
          notificationText: 'Your employer turned on location tracking. It stops when you sign out.',
          notificationChannelName: 'Location tracking',
          setOngoing: true,
          enableWakeLock: true,
        ),
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 50,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      ),
      _ => const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50),
    };
    yield* Geolocator.getPositionStream(locationSettings: settings).map((p) => GeoFix(p.latitude, p.longitude, p.accuracy));
  }

  /// Stores a position; the server ignores it while tracking is switched off for the company.
  Future<void> record(GeoFix fix, {String context = 'ping', String? refId}) => _api.post<dynamic>('/locations', {
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        if (fix.accuracy != null) 'accuracy': fix.accuracy,
        'context': context,
        'refId': ?refId,
      });

  Future<List<TeamMemberLocation>> latest() async =>
      [for (final j in await _api.get<List<dynamic>>('/locations/latest')) TeamMemberLocation.fromJson(j as Map<String, dynamic>)];

  Future<List<TrailPoint>> trail(String userId, String date) async =>
      [for (final j in await _api.get<List<dynamic>>('/locations/trail', query: {'userId': userId, 'date': date})) TrailPoint.fromJson(j as Map<String, dynamic>)];
}
