import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/expense.dart';

class ExpensesRepository {
  ExpensesRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  Future<List<ExpenseCategory>> categories() async =>
      [for (final j in await _api.get<List<dynamic>>('/expense-categories')) ExpenseCategory.fromJson(j as Map<String, dynamic>)];

  Future<ExpenseCategory> saveCategory(String? id, String name) async {
    final json = id == null
        ? await _api.post<Map<String, dynamic>>('/expense-categories', {'name': name})
        : await _api.patch<Map<String, dynamic>>('/expense-categories/$id', {'name': name});
    _bus.publish(DataTopic.expenses);
    return ExpenseCategory.fromJson(json);
  }

  Future<void> deleteCategory(String id) async {
    await _api.delete('/expense-categories/$id');
    _bus.publish(DataTopic.expenses);
  }

  List<ExpenseItemDef> _defs(List<dynamic> json) => [for (final j in json) ExpenseItemDef.fromJson(j as Map<String, dynamic>)];

  /// Reusable expense items with the total spent on each.
  Future<List<ExpenseItemDef>> itemDefs() async => _defs(await _api.get<List<dynamic>>('/expense-items'));

  Future<List<ExpenseItemDef>> saveItemDef(String? id, Map<String, dynamic> body) async {
    final json = id == null ? await _api.post<List<dynamic>>('/expense-items', body) : await _api.put<List<dynamic>>('/expense-items/$id', body);
    _bus.publish(DataTopic.expenses);
    return _defs(json);
  }

  Future<void> deleteItemDef(String id) async {
    await _api.delete('/expense-items/$id');
    _bus.publish(DataTopic.expenses);
  }

  Future<List<ExpenseSummary>> list({required String categoryId}) async => [
        for (final j in await _api.get<List<dynamic>>('/expenses', query: {'categoryId': categoryId}))
          ExpenseSummary.fromJson(j as Map<String, dynamic>),
      ];

  Future<Expense> get(String id) async => Expense.fromJson(await _api.get<Map<String, dynamic>>('/expenses/$id'));

  Future<Expense> save(String? id, Map<String, dynamic> body) async {
    final json = id == null
        ? await _api.post<Map<String, dynamic>>('/expenses', body)
        : await _api.put<Map<String, dynamic>>('/expenses/$id', body);
    _bus.publish(DataTopic.expenses);
    _bus.publish(DataTopic.accounts);
    return Expense.fromJson(json);
  }

  Future<void> delete(String id) async {
    await _api.delete('/expenses/$id');
    _bus.publish(DataTopic.expenses);
    _bus.publish(DataTopic.accounts);
  }
}
