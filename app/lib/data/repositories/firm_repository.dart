import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/firm.dart';

class FirmRepository {
  FirmRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  Future<Firm> get() async => Firm.fromJson(await _api.get<Map<String, dynamic>>('/firm'));

  Future<Firm> update(Map<String, dynamic> body) async {
    final firm = Firm.fromJson(await _api.patch<Map<String, dynamic>>('/firm', body));
    _bus.publish(DataTopic.firm);
    return firm;
  }
}
