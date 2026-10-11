import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/invoice.dart';

class InvoicesRepository {
  InvoicesRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  Future<List<InvoiceSummary>> list(String type, {required String from, required String to}) async => [
        for (final j in await _api.get<List<dynamic>>('/invoices', query: {'type': type, 'from': from, 'to': to}))
          InvoiceSummary.fromJson(j as Map<String, dynamic>),
      ];

  /// A party's documents of [type] that still have something to pay — for linking a payment to them.
  Future<List<InvoiceSummary>> unpaid(String type, String partyId) async => [
        for (final j in await _api.get<List<dynamic>>('/invoices', query: {'type': type, 'partyId': partyId, 'unpaid': 'true'}))
          InvoiceSummary.fromJson(j as Map<String, dynamic>),
      ];

  Future<Invoice> get(String id) async => Invoice.fromJson(await _api.get<Map<String, dynamic>>('/invoices/$id'));

  Future<String> nextNumber(String type) async =>
      (await _api.get<Map<String, dynamic>>('/invoices/next-number', query: {'type': type}))['number'] as String;

  Future<Invoice> save(String? id, Map<String, dynamic> body) async {
    final json = id == null
        ? await _api.post<Map<String, dynamic>>('/invoices', body)
        : await _api.put<Map<String, dynamic>>('/invoices/$id', body);
    _changed();
    return Invoice.fromJson(json);
  }

  Future<void> delete(String id) async {
    await _api.delete('/invoices/$id');
    _changed();
  }

  // Invoices move stock and party balances.
  void _changed() {
    _bus.publish(DataTopic.invoices);
    _bus.publish(DataTopic.items);
    _bus.publish(DataTopic.parties);
    _bus.publish(DataTopic.accounts);
    _bus.publish(DataTopic.payments);
  }
}
