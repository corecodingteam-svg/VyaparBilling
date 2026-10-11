import '../../core/api_client.dart';
import '../models/dashboard_summary.dart';

class DashboardRepository {
  DashboardRepository(this._api);
  final ApiClient _api;

  Future<DashboardSummary> summary({String? from, String? to}) async => DashboardSummary.fromJson(
        await _api.get<Map<String, dynamic>>('/dashboard', query: {'from': ?from, 'to': ?to}),
      );
}
