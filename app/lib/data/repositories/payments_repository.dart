import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/payment.dart';

class PaymentsRepository {
  PaymentsRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  Future<List<Payment>> list(String type, {required String from, required String to}) async => [
        for (final j in await _api.get<List<dynamic>>('/payments', query: {'type': type, 'from': from, 'to': to}))
          Payment.fromJson(j as Map<String, dynamic>),
      ];

  Future<Payment> get(String id) async => Payment.fromJson(await _api.get<Map<String, dynamic>>('/payments/$id'));

  Future<String> nextNumber(String type) async =>
      (await _api.get<Map<String, dynamic>>('/payments/next-number', query: {'type': type}))['number'] as String;

  Future<Payment> save(String? id, Map<String, dynamic> body) async {
    final json = id == null
        ? await _api.post<Map<String, dynamic>>('/payments', body)
        : await _api.put<Map<String, dynamic>>('/payments/$id', body);
    _changed();
    return Payment.fromJson(json);
  }

  Future<void> delete(String id) async {
    await _api.delete('/payments/$id');
    _changed();
  }

  void _changed() {
    _bus.publish(DataTopic.payments);
    // A payment linked to invoices changes what they still owe.
    _bus.publish(DataTopic.invoices);
    _bus.publish(DataTopic.parties);
    _bus.publish(DataTopic.accounts);
  }
}
