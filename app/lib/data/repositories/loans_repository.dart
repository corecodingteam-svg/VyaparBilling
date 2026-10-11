import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/loan.dart';

class LoansRepository {
  LoansRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  // Loans move cash and bank balances too.
  void _changed() {
    _bus.publish(DataTopic.loans);
    _bus.publish(DataTopic.accounts);
  }

  Future<List<LoanAccount>> list() async =>
      [for (final j in await _api.get<List<dynamic>>('/loan-accounts')) LoanAccount.fromJson(j as Map<String, dynamic>)];

  Future<List<LoanTxn>> transactions(String id) async =>
      [for (final j in await _api.get<List<dynamic>>('/loan-accounts/$id/transactions')) LoanTxn.fromJson(j as Map<String, dynamic>)];

  Future<LoanAccount> save(String? id, Map<String, dynamic> body) async {
    final json = id == null
        ? await _api.post<Map<String, dynamic>>('/loan-accounts', body)
        : await _api.patch<Map<String, dynamic>>('/loan-accounts/$id', body);
    _changed();
    return LoanAccount.fromJson(json);
  }

  Future<void> delete(String id) async {
    await _api.delete('/loan-accounts/$id');
    _changed();
  }

  Future<void> addTransaction(String loanId, Map<String, dynamic> body) async {
    await _api.post<dynamic>('/loan-accounts/$loanId/transactions', body);
    _changed();
  }

  Future<void> updateTransaction(String id, Map<String, dynamic> body) async {
    await _api.put<dynamic>('/loan-transactions/$id', body);
    _changed();
  }

  Future<void> deleteTransaction(String id) async {
    await _api.delete('/loan-transactions/$id');
    _changed();
  }
}
