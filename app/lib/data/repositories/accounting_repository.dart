import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/accounting.dart';

/// Own ledger accounts, journal entries and currencies.
class AccountingRepository {
  AccountingRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  List<LedgerAccount> _accounts(List<dynamic> json) => [for (final j in json) LedgerAccount.fromJson(j as Map<String, dynamic>)];
  List<Currency> _currencies(List<dynamic> json) => [for (final j in json) Currency.fromJson(j as Map<String, dynamic>)];

  // Journal lines can sit on cash or a bank account.
  void _changed() {
    _bus.publish(DataTopic.journals);
    _bus.publish(DataTopic.accounts);
  }

  Future<List<LedgerAccount>> ledgerAccounts() async => _accounts(await _api.get<List<dynamic>>('/ledger-accounts'));

  Future<List<LedgerAccount>> saveLedgerAccount(String? id, {required String name, required String type}) async {
    final body = {'name': name, 'type': type};
    final json = id == null ? await _api.post<List<dynamic>>('/ledger-accounts', body) : await _api.put<List<dynamic>>('/ledger-accounts/$id', body);
    _bus.publish(DataTopic.journals);
    return _accounts(json);
  }

  Future<void> deleteLedgerAccount(String id) async {
    await _api.delete('/ledger-accounts/$id');
    _bus.publish(DataTopic.journals);
  }

  Future<List<JournalEntry>> journals() async =>
      [for (final j in await _api.get<List<dynamic>>('/journals')) JournalEntry.fromJson(j as Map<String, dynamic>)];

  Future<JournalEntry> journal(String id) async => JournalEntry.fromJson(await _api.get<Map<String, dynamic>>('/journals/$id'));

  Future<String> nextJournalNumber() async => (await _api.get<Map<String, dynamic>>('/journals/next-number'))['number'] as String;

  Future<JournalEntry> saveJournal(String? id, Map<String, dynamic> body) async {
    final json = id == null ? await _api.post<Map<String, dynamic>>('/journals', body) : await _api.put<Map<String, dynamic>>('/journals/$id', body);
    _changed();
    return JournalEntry.fromJson(json);
  }

  Future<void> deleteJournal(String id) async {
    await _api.delete('/journals/$id');
    _changed();
  }

  Future<List<Currency>> currencies() async => _currencies(await _api.get<List<dynamic>>('/currencies'));

  Future<List<Currency>> saveCurrency({required String code, required String symbol, required num rate}) async =>
      _currencies(await _api.put<List<dynamic>>('/currencies', {'code': code, 'symbol': symbol, 'rate': rate}));

  Future<void> deleteCurrency(String id) => _api.delete('/currencies/$id');
}
