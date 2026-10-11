import '../../core/api_client.dart';
import '../models/report.dart';

class ReportsRepository {
  ReportsRepository(this._api);
  final ApiClient _api;

  Future<List<ReportDef>> catalog() async =>
      [for (final j in await _api.get<List<dynamic>>('/reports')) ReportDef.fromJson(j as Map<String, dynamic>)];

  Future<ReportData> run(String id, {String? from, String? to, String? partyId, String? bankAccountId, String? itemId}) async => ReportData.fromJson(
        await _api.get<Map<String, dynamic>>(
          '/reports/$id',
          query: {'from': ?from, 'to': ?to, 'partyId': ?partyId, 'bankAccountId': ?bankAccountId, 'itemId': ?itemId},
        ),
      );
}
