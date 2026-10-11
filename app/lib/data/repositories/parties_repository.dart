import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/party.dart';

class PartiesRepository {
  PartiesRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  Future<List<Party>> list() async =>
      [for (final j in await _api.get<List<dynamic>>('/parties')) Party.fromJson(j as Map<String, dynamic>)];

  List<PartyGroup> _groups(List<dynamic> json) => [for (final j in json) PartyGroup.fromJson(j as Map<String, dynamic>)];

  Future<List<PartyGroup>> groups() async => _groups(await _api.get<List<dynamic>>('/party-groups'));

  Future<List<PartyGroup>> saveGroup(String? id, String name) async {
    final json = id == null ? await _api.post<List<dynamic>>('/party-groups', {'name': name}) : await _api.patch<List<dynamic>>('/party-groups/$id', {'name': name});
    _bus.publish(DataTopic.parties);
    return _groups(json);
  }

  Future<void> deleteGroup(String id) async {
    await _api.delete('/party-groups/$id');
    _bus.publish(DataTopic.parties);
  }

  Future<Party> get(String id) async => Party.fromJson(await _api.get<Map<String, dynamic>>('/parties/$id'));

  Future<List<PartyTxn>> transactions(String id) async =>
      [for (final j in await _api.get<List<dynamic>>('/parties/$id/transactions')) PartyTxn.fromJson(j as Map<String, dynamic>)];

  Future<Party> save(String? id, Map<String, dynamic> body) async {
    final json = id == null
        ? await _api.post<Map<String, dynamic>>('/parties', body)
        : await _api.patch<Map<String, dynamic>>('/parties/$id', body);
    _bus.publish(DataTopic.parties);
    return Party.fromJson(json);
  }

  Future<void> delete(String id) async {
    await _api.delete('/parties/$id');
    _bus.publish(DataTopic.parties);
  }
}
