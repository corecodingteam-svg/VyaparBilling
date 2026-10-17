import 'package:billing_app/core/api_client.dart';
import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/core/offline.dart';
import 'package:billing_app/core/status.dart';
import 'package:billing_app/core/sync_cubit.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/data/models/firm.dart';
import 'package:billing_app/data/models/app_user.dart';
import 'package:billing_app/features/pos/pos_cubit.dart';
import 'package:billing_app/shell/nav.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// An API whose server can be switched off, and which records what it received.
class FakeApi extends ApiClient {
  FakeApi(super.tokens, {required super.queue}) : super();

  var offline = false;
  final received = <PendingSave>[];

  /// Numbers the server says are taken.
  final taken = <String>{};

  @override
  Future<String> scope() async => 'firm1';

  @override
  Future<void> replay(PendingSave p) async {
    if (offline) throw ApiException('Cannot reach the server. Check your internet connection.', offline: true);
    final number = (p.body as Map)['number'];
    if (taken.contains(number)) throw ApiException('Invoice number $number is already used.');
    received.add(p);
  }

  @override
  Future<T> get<T>(String path, {Map<String, dynamic>? query}) async => {'number': '99'} as T;
}

PendingSave save(String id, String number) =>
    PendingSave(id: id, scope: 'firm1', method: 'POST', path: '/invoices', body: {'type': 'sale', 'number': number}, label: 'POS bill $number', createdAt: DateTime(2026, 10, 14, 9));

void main() {
  late MemoryStore store;
  late FakeApi api;
  late DateTime now;
  var refreshed = 0;

  Future<SyncCubit> build({DateTime? lastSync}) async {
    store = MemoryStore();
    if (lastSync != null) await store.write('last-sync|firm1', lastSync.toIso8601String());
    api = FakeApi(TokenStore(), queue: SyncQueue(store));
    refreshed = 0;
    final c = SyncCubit(api, store, ChangeBus(), refresh: () async => refreshed++, clock: () => now, tick: const Duration(hours: 1));
    await c.load();
    return c;
  }

  setUp(() => now = DateTime(2026, 10, 14, 10));

  test('a device that has not synced today is asked to, and "later" asks again after the snooze', () async {
    final c = await build(lastSync: DateTime(2026, 10, 13, 18));
    expect([c.state.dailyDue, c.state.promptDue], [true, true]);
    c.later();
    expect(c.state.promptDue, isFalse);
    expect(c.state.dailyDue, isTrue);
  });

  test('a device that synced earlier today is not asked', () async {
    final c = await build(lastSync: DateTime(2026, 10, 14, 8));
    expect([c.state.dailyDue, c.state.promptDue], [false, false]);
  });

  test('a device that never synced is asked', () async {
    final c = await build();
    expect(c.state.dailyDue, isTrue);
  });

  test('sync sends waiting bills in order, refreshes, and records the day', () async {
    final c = await build();
    await api.queue!.add(save('a' * 16, '5'));
    await api.queue!.add(save('b' * 16, '6'));
    c.noteQueued();
    expect(c.state.waiting, 2);

    await c.sync();
    expect(api.received.map((p) => (p.body as Map)['number']), ['5', '6']);
    expect([c.state.waiting, c.state.dailyDue, c.state.promptDue, refreshed], [0, false, false, 1]);
    expect(c.state.lastResult, '2 saves sent');
    expect(store.read('last-sync|firm1'), isNotNull);
  });

  test('with no connection nothing is lost and the day is not marked as synced', () async {
    final c = await build();
    await api.queue!.add(save('a' * 16, '5'));
    api.offline = true;
    await c.sync();
    expect([c.state.waiting, c.state.dailyDue, c.state.error != null, refreshed], [1, true, true, 0]);
    expect(store.read('last-sync|firm1'), isNull);

    api.offline = false;
    await c.sync();
    expect([c.state.waiting, c.state.dailyDue], [0, false]);
  });

  test('a bill whose number another device took meanwhile is sent again under the next number', () async {
    final c = await build();
    api.taken.add('5');
    await api.queue!.add(save('a' * 16, '5'));
    await c.sync();
    expect(api.received.single.body, containsPair('number', '99'));
    expect(c.state.pending, isEmpty);
  });

  test('a bill the server refuses stays, with the reason, and can be discarded', () async {
    final c = await build();
    api.taken.addAll(['5', '99']);
    await api.queue!.add(save('a' * 16, '5'));
    await c.sync();
    expect(c.state.failed.single.error, contains('already used'));
    expect(c.state.dailyDue, isFalse); // the server was reached
    await c.discard('a' * 16);
    expect(c.state.pending, isEmpty);
  });

  test('POS keeps a bill made offline on the device and starts the next bill', () async {
    final invoices = FakeInvoicesRepository()..offline = true;
    final pos = PosCubit(invoices, FakeItemsRepository([Item.fromJson(itemJson('i1', 'Sample Item'))]), FakeCashBankRepository(), ChangeBus());
    await pos.load();
    pos.add(pos.state.items.first);
    await pos.save(print: true);
    expect([pos.state.submitStatus, pos.state.queued, pos.state.cart, pos.state.printAfterSave], [SubmitStatus.success, true, isEmpty, false]);
  });

  group('POS-only mode', () {
    const owner = AppUser(id: 'u', email: 'o@x.in', fullName: 'O', firmId: 'f', firmName: 'F');
    const cashier = AppUser(id: 'c', email: 'c@x.in', fullName: 'C', firmId: 'f', firmName: 'F', role: 'salesman');

    test('features come from the provider and default to on, except POS only', () {
      final u = AppUser.fromJson({'id': 'u', 'email': 'e@x.in', 'fullName': 'E', 'firm': {'id': 'f', 'name': 'F'}, 'features': {'reports': false, 'posOnly': true}, 'plan': 'pos', 'platformAdmin': true});
      expect([u.posOnly, u.feature('reports'), u.feature('accounting'), u.plan, u.platformAdmin], [true, false, true, 'pos', true]);
      expect(owner.posOnly, isFalse);
    });

    test('only the counter and what serves it are reachable', () {
      expect(posOnlyRedirect('/pos', admin: false), isNull);
      expect(posOnlyRedirect('/sync', admin: false), isNull);
      expect(posOnlyRedirect('/sale-invoices/abc/preview?layout=thermal', admin: false), isNull);
      expect(posOnlyRedirect('/', admin: false), '/pos');
      expect(posOnlyRedirect('/reports', admin: true), '/pos');
      expect(posOnlyRedirect('/settings', admin: false), '/pos');
      expect(posOnlyRedirect('/settings', admin: true), isNull);
      expect(posOnlyRedirect('/items', admin: true), isNull);
    });

    test('the sidebar shrinks to the counter, and admins keep items and settings', () {
      const settings = FirmSettings();
      AppUser posOnly(AppUser u, {bool platform = false}) =>
          AppUser(id: u.id, email: u.email, fullName: u.fullName, firmId: u.firmId, firmName: u.firmName, role: u.role, features: const {'posOnly': true}, platformAdmin: platform);
      expect(navFor(posOnly(cashier), settings).map((s) => s.label), ['POS', 'Sync']);
      expect(navFor(posOnly(owner), settings).map((s) => s.label), ['POS', 'Sync', 'Items', 'Settings']);
      expect(navFor(posOnly(owner, platform: true), settings).map((s) => s.label), ['POS', 'Sync', 'Items', 'Settings', 'Businesses']);
      expect(navFor(owner, settings).length, greaterThan(6));
    });

    test('switches the provider turned off hide their menus', () {
      const settings = FirmSettings(accountingEnabled: true);
      AppUser with_(Map<String, bool> f) => AppUser(id: 'u', email: 'o@x.in', fullName: 'O', firmId: 'f', firmName: 'F', features: f);
      final labels = navFor(with_({'reports': false, 'accounting': false}), settings).map((s) => s.label);
      expect(labels, isNot(contains('Reports')));
      expect(labels, isNot(contains('Accounting')));
      expect(navFor(with_({}), settings).map((s) => s.label), contains('Reports'));
    });

    test('provider staff may reach the businesses page of a POS-only business', () {
      expect(posOnlyRedirect('/platform', admin: true, platformAdmin: true), isNull);
      expect(posOnlyRedirect('/platform', admin: true), '/pos');
    });
  });
}
