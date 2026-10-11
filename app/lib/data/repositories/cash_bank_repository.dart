import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/cash_bank.dart';

class CashBankRepository {
  CashBankRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  List<MoneyTxn> _txns(List<dynamic> json) => [for (final j in json) MoneyTxn.fromJson(j as Map<String, dynamic>)];

  Future<List<BankAccount>> accounts() async =>
      [for (final j in await _api.get<List<dynamic>>('/bank-accounts')) BankAccount.fromJson(j as Map<String, dynamic>)];

  Future<List<MoneyTxn>> accountTransactions(String id) async => _txns(await _api.get<List<dynamic>>('/bank-accounts/$id/transactions'));

  Future<BankAccount> saveAccount(String? id, Map<String, dynamic> body) async {
    final json = id == null
        ? await _api.post<Map<String, dynamic>>('/bank-accounts', body)
        : await _api.patch<Map<String, dynamic>>('/bank-accounts/$id', body);
    _bus.publish(DataTopic.accounts);
    return BankAccount.fromJson(json);
  }

  Future<void> deleteAccount(String id) async {
    await _api.delete('/bank-accounts/$id');
    _bus.publish(DataTopic.accounts);
  }

  /// Cash-in-hand balance and its transactions (newest first).
  Future<(num, List<MoneyTxn>)> cash() async {
    final json = await _api.get<Map<String, dynamic>>('/cash-in-hand');
    return (json['balance'] as num, _txns(json['transactions'] as List));
  }

  Future<void> createAdjustment(Map<String, dynamic> body) async {
    await _api.post<dynamic>('/fund-adjustments', body);
    _bus.publish(DataTopic.accounts);
  }

  /// The stored adjustment, for editing: kind, bankAccountId, toBankAccountId, amount, date, description.
  Future<Map<String, dynamic>> adjustment(String id) => _api.get<Map<String, dynamic>>('/fund-adjustments/$id');

  Future<void> updateAdjustment(String id, Map<String, dynamic> body) async {
    await _api.put<dynamic>('/fund-adjustments/$id', body);
    _bus.publish(DataTopic.accounts);
  }

  Future<void> deleteAdjustment(String id) async {
    await _api.delete('/fund-adjustments/$id');
    _bus.publish(DataTopic.accounts);
  }

  Future<List<MoneyTxn>> cheques() async => _txns(await _api.get<List<dynamic>>('/cheques'));

  Future<void> depositCheque(MoneyTxn cheque, String bankAccountId) async {
    await _api.post<dynamic>('/cheques/${cheque.source}/${cheque.id}/deposit', {'bankAccountId': bankAccountId});
    _bus.publish(DataTopic.accounts);
  }

  Future<void> reopenCheque(MoneyTxn cheque) async {
    await _api.post<dynamic>('/cheques/${cheque.source}/${cheque.id}/reopen');
    _bus.publish(DataTopic.accounts);
  }
}
