import 'package:equatable/equatable.dart';

/// A device activated on a licence.
class LicenseDevice extends Equatable {
  LicenseDevice.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      installationId = j['installationId'] as String,
      name = j['name'] as String?,
      platform = j['platform'] as String?,
      lastSeenAt = DateTime.tryParse('${j['lastSeenAt']}');
  final String id;
  final String installationId;
  final String? name;
  final String? platform;
  final DateTime? lastSeenAt;

  @override
  List<Object?> get props => [id, installationId, name, platform, lastSeenAt];
}

/// A business's licence as the provider sees it.
class TenantLicense extends Equatable {
  TenantLicense.fromJson(Map<String, dynamic> j)
    : status = (j['status'] as String?) ?? 'active',
      statusReason = j['statusReason'] as String?,
      expiresOn = j['expiresOn'] as String?,
      expired = (j['expired'] as bool?) ?? false,
      maxDevices = (j['maxDevices'] as num?)?.toInt() ?? 5,
      version = (j['version'] as num?)?.toInt() ?? 1,
      devices = [for (final d in (j['devices'] as List? ?? const [])) LicenseDevice.fromJson(d as Map<String, dynamic>)];

  /// active | suspended | revoked
  final String status;
  final String? statusReason;

  /// The last working day (YYYY-MM-DD); null = no end.
  final String? expiresOn;
  final bool expired;
  final int maxDevices;
  final int version;
  final List<LicenseDevice> devices;

  @override
  List<Object?> get props => [status, statusReason, expiresOn, expired, maxDevices, version, devices];
}

/// A business on this server, as the provider sees it.
class Tenant extends Equatable {
  Tenant.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      plan = j['plan'] as String,
      features = {for (final e in (j['features'] as Map).entries) '${e.key}': e.value == true},
      license = TenantLicense.fromJson(j['license'] as Map<String, dynamic>),
      members = (j['members'] as num?)?.toInt() ?? 0,
      ownerEmail = j['ownerEmail'] as String?,
      sales30d = (j['sales30d'] as num?)?.toInt() ?? 0;

  final String id;
  final String name;
  final String plan;
  final Map<String, bool> features;
  final TenantLicense license;
  final int members;
  final String? ownerEmail;

  /// Sale bills made in the last 30 days.
  final int sales30d;

  @override
  List<Object?> get props => [id, name, plan, features, license, members, ownerEmail, sales30d];
}

class PlanOption extends Equatable {
  PlanOption.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      label = j['label'] as String,
      features = {for (final e in (j['features'] as Map).entries) '${e.key}': e.value == true};
  final String id;
  final String label;
  final Map<String, bool> features;
  @override
  List<Object?> get props => [id, label, features];
}

class FeatureOption extends Equatable {
  FeatureOption.fromJson(Map<String, dynamic> j) : id = j['id'] as String, label = j['label'] as String;
  final String id;
  final String label;
  @override
  List<Object?> get props => [id, label];
}

/// The plans and switches the server knows about.
class PlatformCatalog extends Equatable {
  PlatformCatalog.fromJson(Map<String, dynamic> j)
    : plans = [for (final p in j['plans'] as List) PlanOption.fromJson(p as Map<String, dynamic>)],
      features = [for (final f in j['features'] as List) FeatureOption.fromJson(f as Map<String, dynamic>)];
  final List<PlanOption> plans;
  final List<FeatureOption> features;
  @override
  List<Object?> get props => [plans, features];
}
