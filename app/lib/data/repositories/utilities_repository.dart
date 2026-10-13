import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../models/app_user.dart';
import '../models/extras.dart';
import '../models/invoice.dart';
import '../../shared/format.dart';

/// Reminders, quick search, and the housekeeping tools: set-up checklist, data check, closing the
/// books, starting a new year, backup and restore.
class UtilitiesRepository {
  UtilitiesRepository(this._api, this._bus);
  final ApiClient _api;
  final ChangeBus _bus;

  Future<List<PaymentReminder>> paymentReminders() async =>
      [for (final j in await _api.get<List<dynamic>>('/reminders/payments')) PaymentReminder.fromJson(j as Map<String, dynamic>)];

  Future<List<ServiceReminder>> serviceReminders() async =>
      [for (final j in await _api.get<List<dynamic>>('/reminders/services')) ServiceReminder.fromJson(j as Map<String, dynamic>)];

  Future<void> markServiceDone(String id) => _api.post<dynamic>('/reminders/services/$id/done');

  Future<List<SearchHit>> search(String text) async {
    final j = await _api.get<Map<String, dynamic>>('/search', query: {'q': text});
    return [
      for (final p in j['parties'] as List) SearchHit(kind: 'party', id: p['id'] as String, title: p['name'] as String, subtitle: (p['phone'] as String?) ?? 'Party'),
      for (final i in j['items'] as List)
        SearchHit(
          kind: 'item',
          type: i['stockQty'] == null ? 'service' : 'product',
          id: i['id'] as String,
          title: i['name'] as String,
          subtitle: ['Item', money(i['salePrice'] as num?), if (i['stockQty'] != null) 'Stock ${qty(i['stockQty'] as num)}'].join(' · '),
        ),
      for (final d in j['invoices'] as List)
        SearchHit(
          kind: 'invoice',
          id: d['id'] as String,
          type: d['type'] as String,
          title: '${InvoiceKind.of(d['type'] as String).singular} ${d['number']}'.trim(),
          subtitle: '${d['partyName']} · ${displayDate(d['date'] as String)} · ${money(d['total'] as num?)}',
        ),
    ];
  }

  Future<List<SetupStep>> setup() async =>
      [for (final j in (await _api.get<Map<String, dynamic>>('/utilities/setup'))['steps'] as List) SetupStep.fromJson(j as Map<String, dynamic>)];

  List<VerifyCheck> _checks(Map<String, dynamic> json) => [for (final j in json['checks'] as List) VerifyCheck.fromJson(j as Map<String, dynamic>)];

  Future<List<VerifyCheck>> verify() async => _checks(await _api.get<Map<String, dynamic>>('/utilities/verify'));

  Future<List<VerifyCheck>> fix() async {
    final checks = _checks(await _api.post<Map<String, dynamic>>('/utilities/verify/fix'));
    for (final t in [DataTopic.items, DataTopic.invoices, DataTopic.payments, DataTopic.parties]) {
      _bus.publish(t);
    }
    return checks;
  }

  /// Locks everything dated on or before [date]; null re-opens the books.
  Future<void> closeBooks(String? date) async {
    await _api.post<dynamic>('/utilities/close-books', {'date': date});
    _bus.publish(DataTopic.firm);
  }

  /// Creates next year's company from this one's closing balances.
  Future<Company> startNewYear({required String name, required String startDate}) async =>
      Company.fromJson(await _api.post<Map<String, dynamic>>('/utilities/new-year', {'name': name, 'startDate': startDate}));

  /// Everything in the current company, as one JSON document.
  Future<Map<String, dynamic>> backup() => _api.get<Map<String, dynamic>>('/backup');

  // ---- backups kept on the server, and Google Drive

  Future<List<ServerBackup>> serverBackups() async =>
      [for (final j in await _api.get<List<dynamic>>('/backups')) ServerBackup.fromJson(j as Map<String, dynamic>)];

  /// Makes a backup now; returns the updated list.
  Future<List<ServerBackup>> createServerBackup() async =>
      [for (final j in await _api.post<List<dynamic>>('/backups')) ServerBackup.fromJson(j as Map<String, dynamic>)];

  /// (file name, contents) of a stored backup.
  Future<(String, Map<String, dynamic>)> readServerBackup(String id) async {
    final j = await _api.get<Map<String, dynamic>>('/backups/$id');
    return (j['fileName'] as String, j['backup'] as Map<String, dynamic>);
  }

  Future<void> deleteServerBackup(String id) => _api.delete('/backups/$id');

  Future<DriveStatus> driveStatus() async => DriveStatus.fromJson(await _api.get<Map<String, dynamic>>('/backups/drive/status'));

  /// The Google page where the user allows copies of backups to be put in their Drive.
  Future<String> driveAuthUrl() async => (await _api.get<Map<String, dynamic>>('/backups/drive/auth-url'))['url'] as String;

  Future<void> driveDisconnect() => _api.delete('/backups/drive');

  /// Restores a backup as a new company.
  Future<Company> restore(Map<String, dynamic> backup, {String? name}) async =>
      Company.fromJson(await _api.post<Map<String, dynamic>>('/firms/restore', {'backup': backup, 'name': ?name}));
}
