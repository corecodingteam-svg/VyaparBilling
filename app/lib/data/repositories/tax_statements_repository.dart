import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/tax_statement.dart';

/// Quarterly TDS (Form 140) and TCS (Form 143) statements, the challans they quote, and the GSTR-9 file.
class TaxStatementsRepository {
  TaxStatementsRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  /// The section and collection codes offered in the app: (TDS sections, TCS codes), code → description.
  Future<(Map<String, String>, Map<String, String>)> codes() async {
    final j = await _api.get<Map<String, dynamic>>('/tax-statements/codes');
    return ((j['tdsSections'] as Map).cast<String, String>(), (j['tcsCodes'] as Map).cast<String, String>());
  }

  Future<List<TaxChallan>> challans(String kind, String taxYear, String quarter) async => [
    for (final j in await _api.get<List<dynamic>>('/tax-statements/challans', query: {'kind': kind, 'taxYear': taxYear, 'quarter': quarter}))
      TaxChallan.fromJson(j as Map<String, dynamic>),
  ];

  Future<void> addChallan({
    required String kind,
    required String taxYear,
    required String quarter,
    required String bsrCode,
    required String challanNo,
    required String depositDate,
    required num tax,
    num interest = 0,
    num fee = 0,
    num other = 0,
  }) => _api.post<dynamic>('/tax-statements/challans', {
    'kind': kind,
    'taxYear': taxYear,
    'quarter': quarter,
    'bsrCode': bsrCode,
    'challanNo': challanNo,
    'depositDate': depositDate,
    'tax': tax,
    'interest': interest,
    'fee': fee,
    'other': other,
  });

  Future<void> removeChallan(String id) => _api.delete('/tax-statements/challans/$id');

  Future<TaxStatement> statement(String form, String taxYear, String quarter) async => TaxStatement.fromJson(
    await _api.get<Map<String, dynamic>>('/tax-statements/statement', query: {'form': form, 'taxYear': taxYear, 'quarter': quarter}),
  );

  /// The GSTR-9 JSON for a financial year such as '2025-26': (file name, JSON).
  Future<(String, Object)> gstr9(String year) async {
    final j = await _api.get<Map<String, dynamic>>('/tax-statements/gstr9', query: {'year': year});
    return (j['fileName'] as String, j['json'] as Object);
  }

  Future<Deductor> deductor() async =>
      Deductor.fromSettings(((await _api.get<Map<String, dynamic>>('/firm'))['settings'] as Map?)?.cast<String, dynamic>() ?? const {});

  Future<void> saveDeductor(Deductor d) async {
    await _api.patch<dynamic>('/firm', {'settings': d.toSettings()});
    _bus.publish(DataTopic.firm);
  }
}
