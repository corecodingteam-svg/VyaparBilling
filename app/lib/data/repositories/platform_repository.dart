import '../../core/api_client.dart';
import '../models/platform.dart';

/// Provider-only calls: the businesses on this server and what each may use.
class PlatformRepository {
  PlatformRepository(this._api);
  final ApiClient _api;

  Future<PlatformCatalog> catalog() async => PlatformCatalog.fromJson(await _api.get<Map<String, dynamic>>('/platform/catalog'));

  Future<List<Tenant>> tenants({String? q}) async => [
    for (final j in await _api.get<List<dynamic>>('/platform/tenants', query: {if (q != null && q.trim().isNotEmpty) 'q': q.trim()}))
      Tenant.fromJson(j as Map<String, dynamic>),
  ];

  Future<Tenant> create(Map<String, dynamic> body) async => Tenant.fromJson(await _api.post<Map<String, dynamic>>('/platform/tenants', body));

  Future<Tenant> update(String id, Map<String, dynamic> body) async => Tenant.fromJson(await _api.patch<Map<String, dynamic>>('/platform/tenants/$id', body));

  Future<Tenant> removeDevice(String tenantId, String deviceId) async {
    await _api.delete('/platform/tenants/$tenantId/devices/$deviceId');
    return (await tenants()).firstWhere((t) => t.id == tenantId);
  }

  Future<List<TenantUser>> users(String tenantId) async =>
      [for (final j in await _api.get<List<dynamic>>('/platform/tenants/$tenantId/users')) TenantUser.fromJson(j as Map<String, dynamic>)];

  /// Returns the new password, to hand to the person once.
  Future<String> resetPassword(String tenantId, String userId) async =>
      (await _api.post<Map<String, dynamic>>('/platform/tenants/$tenantId/users/$userId/reset-password'))['password'] as String;

  Future<List<TenantUser>> setDisabled(String tenantId, String userId, bool disabled) async => [
    for (final j in await _api.patch<List<dynamic>>('/platform/tenants/$tenantId/users/$userId', {'disabled': disabled})) TenantUser.fromJson(j as Map<String, dynamic>),
  ];

  Future<List<TenantUser>> setOwner(String tenantId, String userId) async => [
    for (final j in await _api.post<List<dynamic>>('/platform/tenants/$tenantId/owner', {'userId': userId})) TenantUser.fromJson(j as Map<String, dynamic>),
  ];

  Future<List<AuditEntry>> audit({String? firmId}) async => [
    for (final j in await _api.get<List<dynamic>>('/platform/audit', query: {'firmId': firmId, 'limit': 500})) AuditEntry.fromJson(j as Map<String, dynamic>),
  ];
}
