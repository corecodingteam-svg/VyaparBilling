// Feature sweep through the real repositories against a running backend:
//   flutter test live_api_test/live_sweep_test.dart
// Every step runs on its own so one failure does not hide the next; invalid input must come back as a readable message,
// never "Something went wrong".
import 'dart:io';

import 'package:billing_app/core/api_client.dart';
import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/data/models/tax_statement.dart';
import 'package:billing_app/data/repositories/accounting_repository.dart';
import 'package:billing_app/data/repositories/auth_repository.dart';
import 'package:billing_app/data/repositories/cash_bank_repository.dart';
import 'package:billing_app/data/repositories/expenses_repository.dart';
import 'package:billing_app/data/repositories/firm_repository.dart';
import 'package:billing_app/data/repositories/integrations_repository.dart';
import 'package:billing_app/data/repositories/invoices_repository.dart';
import 'package:billing_app/data/repositories/items_repository.dart';
import 'package:billing_app/data/repositories/loans_repository.dart';
import 'package:billing_app/data/repositories/location_repository.dart';
import 'package:billing_app/data/repositories/parties_repository.dart';
import 'package:billing_app/data/repositories/payments_repository.dart';
import 'package:billing_app/data/repositories/tax_statements_repository.dart';
import 'package:billing_app/data/repositories/utilities_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryTokens extends TokenStore {
  String? _token;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String token) async => _token = token;
  @override
  Future<void> clear() async => _token = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('every feature through the real API', () async {
    final api = ApiClient(_MemoryTokens());
    final bus = ChangeBus();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await AuthRepository(api).register(firmName: 'Sweep $stamp', stateCode: '27', fullName: 'Tester', email: 'sweep$stamp@example.com', password: 'Password123');
    final parties = PartiesRepository(api, bus);
    final items = ItemsRepository(api, bus);
    final invoices = InvoicesRepository(api, bus);
    final payments = PaymentsRepository(api, bus);
    final cashBank = CashBankRepository(api, bus);
    final expenses = ExpensesRepository(api, bus);
    final loans = LoansRepository(api, bus);
    final accounting = AccountingRepository(api, bus);
    final utilities = UtilitiesRepository(api, bus);
    final integrations = IntegrationsRepository(api, bus);
    final taxes = TaxStatementsRepository(api, bus);
    final location = LocationRepository(api);
    final firm = FirmRepository(api, bus);

    final problems = <String>[];
    Future<void> step(String name, Future<void> Function() body) async {
      try {
        await body();
      } catch (e, st) {
        problems.add('$name -> $e${e is ApiException ? '' : '\n$st'}');
      }
    }

    /// The call must fail with a message a person can act on.
    Future<void> rejects(String name, Future<Object?> Function() body, {Pattern? mention}) => step('$name (rejected)', () async {
          try {
            await body();
          } on ApiException catch (e) {
            if (e.message.contains('Something went wrong') || e.message.trim().isEmpty) throw 'generic message "${e.message}"';
            if (mention != null && !e.message.toLowerCase().contains(mention is String ? mention.toLowerCase() : '')) {
              if (mention is RegExp && !mention.hasMatch(e.message)) throw 'message "${e.message}" does not mention $mention';
            }
            return;
          }
          throw 'was accepted but should have been rejected';
        });

    late String partyId, itemId, invoiceId, bankId;
    await step('seed party', () async => partyId = (await parties.save(null, {'name': 'Sweep Customer', 'phone': '9000000001', 'openingBalance': 0})).id);
    await step('seed item', () async => itemId = (await items.save(null, {'name': 'Sweep Item', 'unit': 'PCS', 'salePrice': 100, 'purchasePrice': 60, 'openingQty': 50, 'gstRate': 18})).id);
    await step('seed bank', () async => bankId = (await cashBank.saveAccount(null, {'name': 'Sweep Bank', 'openingBalance': 1000})).id);
    await step('seed invoice', () async {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final inv = await invoices.save(null, {
        'type': 'sale', 'number': '1', 'invoiceDate': today, 'partyId': partyId, 'isCash': false, 'paymentMode': 'cash',
        'lines': [{'itemId': itemId, 'name': 'Sweep Item', 'quantity': 2, 'price': 100, 'gstRate': 18}],
        'received': 0, 'description': '', 'roundOff': false,
      });
      invoiceId = inv.id;
    });

    // ---- reads that every screen makes
    await step('parties list', () async => await parties.list());
    await step('party ledger', () async => await parties.transactions(partyId));
    await step('items list product', () async => await items.list('product'));
    await step('items list service', () async => await items.list('service'));
    await step('item movements', () async => await items.movements(itemId));
    await step('invoices sale', () async => await invoices.list('sale', from: '2000-01-01', to: '2099-01-01'));
    await step('invoice get', () async => await invoices.get(invoiceId));
    await step('payments in', () async => await payments.list('in', from: '2000-01-01', to: '2099-01-01'));
    await step('cash', () async => await cashBank.cash());
    await step('bank accounts', () async => await cashBank.accounts());
    await step('bank txns', () async => await cashBank.accountTransactions(bankId));
    await step('cheques', () async => await cashBank.cheques());
    await step('expenses categories', () async => await expenses.categories());
    await step('loans', () async => await loans.list());
    await step('settings', () async => await firm.get());

    // ---- accounting
    await step('ledger accounts', () async => await accounting.ledgerAccounts());
    await step('journals', () async => await accounting.journals());
    await step('currencies', () async {
      await accounting.saveCurrency(code: 'USD', symbol: r'$', rate: 83);
      expect((await accounting.currencies()).single.code, 'USD');
    });

    // ---- utilities
    await step('payment reminders', () async => await utilities.paymentReminders());
    await step('service reminders', () async => await utilities.serviceReminders());
    await step('search', () async => expect((await utilities.search('Sweep')).isNotEmpty, isTrue));
    await step('setup guide', () async => await utilities.setup());
    await step('verify books', () async => await utilities.verify());
    await step('server backups', () async => await utilities.serverBackups());
    await step('drive status', () async => await utilities.driveStatus());
    await step('backup file', () async => expect((await utilities.backup()).isNotEmpty, isTrue));

    // ---- integrations
    await step('integrations list', () async => expect((await integrations.integrations()).isNotEmpty, isTrue));
    await step('webhook url', () async => await integrations.webhookUrl());
    await step('messages log', () async => await integrations.messages());
    await step('einvoice info', () async => await integrations.einvoice(invoiceId));
    await step('payment links', () async => await integrations.paymentLinks(invoiceId));

    // ---- tax statements
    await step('deductor', () async => await taxes.deductor());
    await step('challans', () async => await taxes.challans('tds', '202627', 'Q2'));
    await step('statement Form 140', () async => await taxes.statement('140', '202627', 'Q2'));
    await rejects('GSTR-9 before a GSTIN is set', () => taxes.gstr9('202627'), mention: 'GSTIN');

    // ---- location
    await step('team latest', () async => await location.latest());
    await step('geofences', () async {
      await location.addGeofence(name: 'Shop', latitude: 19.07, longitude: 72.87, radiusM: 200);
      final zones = await location.geofences();
      expect(zones.single.name, 'Shop');
      await location.removeGeofence(zones.single.id);
    });

    // ---- invalid input must produce readable messages
    await rejects('party without a name', () => parties.save(null, {'name': '', 'openingBalance': 0}));
    await rejects('party with a bad GSTIN', () => parties.save(null, {'name': 'X', 'gstin': '123', 'openingBalance': 0}));
    await rejects('item without a name', () => items.save(null, {'name': '', 'unit': 'PCS', 'salePrice': 1}));
    await rejects('item with a negative price', () => items.save(null, {'name': 'Neg', 'unit': 'PCS', 'salePrice': -5}));
    await rejects('bank without a name', () => cashBank.saveAccount(null, {'name': '', 'openingBalance': 0}));
    await rejects('invoice with no lines', () => invoices.save(null, {
          'type': 'sale', 'number': '9', 'invoiceDate': '2026-10-10', 'partyId': partyId, 'isCash': false, 'paymentMode': 'cash', 'lines': [], 'received': 0, 'description': '',
        }));
    await rejects('invoice for a missing party', () => invoices.save(null, {
          'type': 'sale', 'number': '9', 'invoiceDate': '2026-10-10', 'partyId': '00000000-0000-0000-0000-000000000000', 'isCash': false, 'paymentMode': 'cash',
          'lines': [{'itemId': itemId, 'name': 'Sweep Item', 'quantity': 1, 'price': 100}], 'received': 0, 'description': '',
        }));
    await rejects('payment without an amount', () => payments.save(null, {'type': 'in', 'number': '1', 'partyId': partyId, 'paymentDate': '2026-10-10', 'amount': 0, 'paymentMode': 'cash'}));
    await rejects('currency with a bad code', () => accounting.saveCurrency(code: 'x', symbol: '', rate: 0));
    await rejects('journal that does not balance', () => accounting.saveJournal(null, {
          'date': '2026-10-10', 'description': '', 'lines': [{'accountId': 'x', 'debit': 10, 'credit': 0}],
        }));
    await rejects('challan with a bad BSR code', () => taxes.addChallan(kind: 'tds', taxYear: '202627', quarter: 'Q2', bsrCode: '1', challanNo: '1', depositDate: '2026-10-10', tax: 100));
    await rejects('deductor with a bad PAN', () => taxes.saveDeductor(const Deductor(name: 'A', pan: 'BAD', mobile: '1', email: 'x')));
    await rejects('test message with no provider', () => integrations.testMessage('whatsapp', '9000000001'));
    await rejects('geofence with a huge radius', () => location.addGeofence(name: 'Big', latitude: 200, longitude: 0, radiusM: 0));
    await rejects('server backup restore of nothing', () => utilities.restore({}));

    if (problems.isNotEmpty) {
      fail('${problems.length} problem(s):\n${problems.join('\n')}');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
