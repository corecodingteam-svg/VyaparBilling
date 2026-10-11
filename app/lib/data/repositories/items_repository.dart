import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/item.dart';

/// Items, categories and units.
class ItemsRepository {
  ItemsRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  Future<List<Item>> list(String type) async => [
        for (final j in await _api.get<List<dynamic>>('/items', query: {'type': type})) Item.fromJson(j as Map<String, dynamic>),
      ];

  Future<List<StockMovement>> movements(String id) async => [
        for (final j in await _api.get<List<dynamic>>('/items/$id/movements')) StockMovement.fromJson(j as Map<String, dynamic>),
      ];

  Future<Item> save(String? id, Map<String, dynamic> body) async {
    final json = id == null
        ? await _api.post<Map<String, dynamic>>('/items', body)
        : await _api.patch<Map<String, dynamic>>('/items/$id', body);
    _bus.publish(DataTopic.items);
    return Item.fromJson(json);
  }

  Future<void> delete(String id) async {
    await _api.delete('/items/$id');
    _bus.publish(DataTopic.items);
  }

  Future<void> adjust(String id, Map<String, dynamic> body) async {
    await _api.post<dynamic>('/items/$id/adjust', body);
    _bus.publish(DataTopic.items);
  }

  /// Batches of the item that still have stock; in one store when [godownId] is given ('main' = main store).
  Future<List<ItemBatch>> batches(String id, {String? godownId}) async => [
        for (final j in await _api.get<List<dynamic>>('/items/$id/batches', query: {'godownId': ?godownId})) ItemBatch.fromJson(j as Map<String, dynamic>),
      ];

  /// Serial numbers of the item that are in stock.
  Future<List<String>> serials(String id) async => [for (final s in await _api.get<List<dynamic>>('/items/$id/serials')) s as String];

  Future<List<GodownStock>> stockByGodown(String id) async => [
        for (final j in await _api.get<List<dynamic>>('/items/$id/godowns'))
          GodownStock(godownId: j['godownId'] as String?, name: j['name'] as String, quantity: j['quantity'] as num),
      ];

  // ---- godowns

  List<Godown> _godowns(List<dynamic> json) => [for (final j in json) Godown.fromJson(j as Map<String, dynamic>)];

  /// The main store first, then every godown.
  Future<List<Godown>> godowns() async => _godowns(await _api.get<List<dynamic>>('/godowns'));

  Future<List<GodownStock>> godownStock(String? id) async => [
        for (final j in await _api.get<List<dynamic>>('/godowns/${id ?? 'main'}/stock'))
          GodownStock(itemId: j['itemId'] as String, name: j['name'] as String, unit: j['unit'] as String?, quantity: j['quantity'] as num, value: j['value'] as num),
      ];

  Future<List<Godown>> saveGodown(String? id, {required String name, String? address}) async {
    final body = {'name': name, 'address': address ?? ''};
    final json = id == null ? await _api.post<List<dynamic>>('/godowns', body) : await _api.put<List<dynamic>>('/godowns/$id', body);
    _bus.publish(DataTopic.items);
    return _godowns(json);
  }

  Future<void> deleteGodown(String id) async {
    await _api.delete('/godowns/$id');
    _bus.publish(DataTopic.items);
  }

  /// Moves stock between two stores (null = main store).
  Future<void> transferStock(Map<String, dynamic> body) async {
    await _api.post<dynamic>('/godowns/transfer', body);
    _bus.publish(DataTopic.items);
  }

  Future<List<Category>> categories() async =>
      [for (final j in await _api.get<List<dynamic>>('/categories')) Category.fromJson(j as Map<String, dynamic>)];

  Future<Category> saveCategory(String? id, String name) async {
    final json = id == null
        ? await _api.post<Map<String, dynamic>>('/categories', {'name': name})
        : await _api.patch<Map<String, dynamic>>('/categories/$id', {'name': name});
    _catalogChanged();
    return Category.fromJson(json);
  }

  Future<void> deleteCategory(String id) async {
    await _api.delete('/categories/$id');
    _catalogChanged();
  }

  Future<List<Unit>> units() async =>
      [for (final j in await _api.get<List<dynamic>>('/units')) Unit.fromJson(j as Map<String, dynamic>)];

  Future<Unit> createUnit(String name, String shortName) async {
    final json = await _api.post<Map<String, dynamic>>('/units', {'name': name, 'shortName': shortName});
    _bus.publish(DataTopic.catalog);
    return Unit.fromJson(json);
  }

  Future<void> deleteUnit(String id) async {
    await _api.delete('/units/$id');
    _bus.publish(DataTopic.catalog);
  }

  void _catalogChanged() {
    _bus.publish(DataTopic.catalog);
    _bus.publish(DataTopic.items);
  }
}
