import 'package:equatable/equatable.dart';

/// Where one user was last seen, and how active they were today.
class TeamMemberLocation extends Equatable {
  TeamMemberLocation.fromJson(Map<String, dynamic> j)
      : userId = j['userId'] as String,
        fullName = j['fullName'] as String,
        role = j['role'] as String,
        latitude = (j['latitude'] as num?)?.toDouble(),
        longitude = (j['longitude'] as num?)?.toDouble(),
        accuracy = (j['accuracy'] as num?)?.toDouble(),
        recordedAt = j['recordedAt'] == null ? null : DateTime.parse(j['recordedAt'] as String).toLocal(),
        context = j['context'] as String?,
        pointsToday = ((j['pointsToday'] as num?) ?? 0).toInt(),
        salesToday = ((j['salesToday'] as num?) ?? 0).toInt(),
        paymentsToday = ((j['paymentsToday'] as num?) ?? 0).toInt(),
        zone = j['zone'] as String?,
        distanceKmToday = ((j['distanceKmToday'] as num?) ?? 0).toDouble();

  final String userId;
  final String fullName;
  final String role;
  final double? latitude;
  final double? longitude;

  /// Metres.
  final double? accuracy;
  final DateTime? recordedAt;

  /// ping | sale | payment — what they were doing at that point.
  final String? context;
  final int pointsToday;
  final int salesToday;
  final int paymentsToday;

  /// The zone their latest position is in, if any, and how far they have travelled today.
  final String? zone;
  final double distanceKmToday;

  bool get hasPosition => latitude != null && longitude != null;

  @override
  List<Object?> get props => [userId, fullName, role, latitude, longitude, accuracy, recordedAt, context, pointsToday, salesToday, paymentsToday, zone, distanceKmToday];
}

/// One recorded position on a user's day.
class TrailPoint extends Equatable {
  TrailPoint.fromJson(Map<String, dynamic> j)
      : latitude = (j['latitude'] as num).toDouble(),
        longitude = (j['longitude'] as num).toDouble(),
        accuracy = (j['accuracy'] as num?)?.toDouble(),
        recordedAt = DateTime.parse(j['recordedAt'] as String).toLocal(),
        context = j['context'] as String,
        ref = j['ref'] as String?,
        zone = j['zone'] as String?;

  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime recordedAt;
  final String context;

  /// The sale or payment saved here, e.g. "INV-12 · Ravi".
  final String? ref;

  /// The zone this point is inside, if any.
  final String? zone;

  @override
  List<Object?> get props => [latitude, longitude, accuracy, recordedAt, context, ref, zone];
}

/// A position from the device.
class GeoFix extends Equatable {
  const GeoFix(this.latitude, this.longitude, [this.accuracy]);
  final double latitude;
  final double longitude;
  final double? accuracy;

  @override
  List<Object?> get props => [latitude, longitude, accuracy];
}

/// A named circle on the map (a shop, a warehouse, a customer's area) that positions are checked against.
class Geofence extends Equatable {
  Geofence.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        latitude = (j['latitude'] as num).toDouble(),
        longitude = (j['longitude'] as num).toDouble(),
        radiusM = (j['radiusM'] as num).toInt();

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int radiusM;

  @override
  List<Object?> get props => [id, name, latitude, longitude, radiusM];
}

/// A user's day in summary: how far they went and which zones they spent time in.
class DaySummary extends Equatable {
  DaySummary.fromJson(Map<String, dynamic> j)
      : distanceKm = (j['distanceKm'] as num).toDouble(),
        visits = [
          for (final v in j['visits'] as List)
            (zone: v['zone'] as String, from: DateTime.parse(v['from'] as String).toLocal(), to: DateTime.parse(v['to'] as String).toLocal()),
        ];

  final double distanceKm;
  final List<({String zone, DateTime from, DateTime to})> visits;

  @override
  List<Object?> get props => [distanceKm, visits];
}
