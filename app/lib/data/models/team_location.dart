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
        paymentsToday = ((j['paymentsToday'] as num?) ?? 0).toInt();

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

  bool get hasPosition => latitude != null && longitude != null;

  @override
  List<Object?> get props => [userId, fullName, role, latitude, longitude, accuracy, recordedAt, context, pointsToday, salesToday, paymentsToday];
}

/// One recorded position on a user's day.
class TrailPoint extends Equatable {
  TrailPoint.fromJson(Map<String, dynamic> j)
      : latitude = (j['latitude'] as num).toDouble(),
        longitude = (j['longitude'] as num).toDouble(),
        accuracy = (j['accuracy'] as num?)?.toDouble(),
        recordedAt = DateTime.parse(j['recordedAt'] as String).toLocal(),
        context = j['context'] as String,
        ref = j['ref'] as String?;

  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime recordedAt;
  final String context;

  /// The sale or payment saved here, e.g. "INV-12 · Ravi".
  final String? ref;

  @override
  List<Object?> get props => [latitude, longitude, accuracy, recordedAt, context, ref];
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
