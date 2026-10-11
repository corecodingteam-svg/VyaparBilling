// The second feature batch: split payments, credit limit, wholesale price, payment–invoice links,
// expense GST, journals, roles in the menu, settings, quick search and the housekeeping tools.
import 'dart:typed_data';

import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/core/list_cubit.dart';
import 'package:billing_app/core/status.dart';
import 'package:billing_app/data/models/app_user.dart';
import 'package:billing_app/data/models/extras.dart';
import 'package:billing_app/data/models/firm.dart';
import 'package:billing_app/data/models/invoice.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/data/models/party.dart';
import 'package:billing_app/data/models/payment.dart';
import 'package:billing_app/features/accounting/journal_form_cubit.dart';
import 'package:billing_app/features/expenses/bloc/expense_form_cubit.dart';
import 'package:billing_app/features/files/attachments.dart';
import 'package:billing_app/features/invoices/bloc/invoice_form_cubit.dart';
import 'package:billing_app/features/payments/bloc/payment_form_cubit.dart';
import 'package:billing_app/features/printing/pdf_documents.dart';
import 'package:billing_app/features/reminders/reminders_screens.dart';
import 'package:billing_app/features/search/quick_search.dart';
import 'package:billing_app/features/tools/tools_cubits.dart';
import 'package:billing_app/shell/nav.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late FakeInvoicesRepository invoices;

  Future<InvoiceFormCubit> form({
    Map<String, dynamic> settings = const {},
    Map<String, dynamic> party = const {},
    Map<String, dynamic> item = const {},
    List<(String, String, num)> currencies = const [],
    String? invoiceId,
  }) async {
    final bus = ChangeBus();
    invoices = FakeInvoicesRepository(bus);
    final cubit = InvoiceFormCubit(
      invoices: invoices,
      parties: FakePartiesRepository([Party.fromJson({...partyJson('a', 'Test Customer', 500), ...party})], bus),
      items: FakeItemsRepository([Item.fromJson({...itemJson('i1', 'Sample Item'), ...item})], bus),
      accounts: FakeCashBankRepository(),
      firm: FakeFirmRepository(settings: settings),
      accounting: FakeAccountingRepository(currencyList: currencies),
      bus: bus,
      kind: InvoiceKind.sale,
      invoiceId: invoiceId,
    );
    await cubit.load();
    return cubit;
  }

  /// A credit sale to the test customer of [qty] × Sample Item at ₹100.
  void fill(InvoiceFormCubit c, {String qty = '10'}) {
    c.partySelected(c.state.parties.first);
    final uid = c.state.lines.first.uid;
    c
      ..itemSelected(uid, c.state.items.first)
      ..lineQtyChanged(uid, qty);
  }

  group('split payment', () {
    test('parts add up; the first part takes the rest when received in full', () async {
      final c = await form();
      fill(c); // total 1000
      c
        ..receivedChanged('300')
        ..addPart();
      final part = c.state.extraParts.single;
      expect(part.mode, 'bank'); // the next mode not used yet
      c
        ..partModeChanged(part.uid, 'upi')
        ..partBankAccountChanged(part.uid, 'b1')
        ..partAmountChanged(part.uid, '200');
      expect([c.state.receivedValue, c.state.balance], [500, 500]);

      c.receivedInFullToggled(true);
      expect([c.state.firstPartValue, c.state.receivedValue, c.state.balance], [800, 1000, 0]);

      c.receivedInFullToggled(false);
      await c.save(andNew: false);
      expect(invoices.saved.single['payments'], [
        {'mode': 'cash', 'bankAccountId': null, 'amount': 300},
        {'mode': 'upi', 'bankAccountId': 'b1', 'amount': 200},
      ]);
    });

    test('a part needs an amount and a bank account, and parts cannot exceed the total', () async {
      final c = await form();
      fill(c);
      c.addPart();
      final uid = c.state.extraParts.single.uid;
      expect(c.validate(), 'Enter the amount of each payment, or remove the empty one.');
      c
        ..partModeChanged(uid, 'upi')
        ..partBankAccountChanged(uid, null)
        ..partAmountChanged(uid, '100');
      expect(c.validate(), 'Select the bank account.');
      c
        ..partBankAccountChanged(uid, 'b2')
        ..partAmountChanged(uid, '1200');
      expect(c.validate(), 'The payments add up to more than the total.');
      c.removePart(uid);
      expect(c.validate(), isNull);
      await c.save(andNew: false);
      expect(invoices.saved.single.containsKey('payments'), isFalse); // one payment: sent the simple way
    });
  });

  test('credit limit: warns, and saves only after the user confirms', () async {
    final c = await form(party: {'creditLimit': 1000}); // already owes 500
    fill(c); // +1000 on credit
    expect(c.state.creditLimitWarning, contains('over the credit limit'));

    await c.save(andNew: false);
    expect(invoices.saved, isEmpty);
    expect(c.state.creditPrompt, 1);

    await c.save(andNew: false, overLimitConfirmed: true);
    expect(invoices.saved, hasLength(1));

    final paid = await form(party: {'creditLimit': 1000});
    fill(paid);
    paid.receivedChanged('600'); // 500 + 400 stays inside the limit
    expect(paid.state.creditLimitWarning, isNull);
    paid.cashToggled(true);
    expect(paid.state.creditLimitWarning, isNull);
  });

  test('wholesale price applies from the minimum quantity, unless the price was typed', () async {
    final c = await form(item: {'wholesalePrice': 80, 'wholesaleMinQty': 10});
    final uid = c.state.lines.first.uid;
    c.itemSelected(uid, c.state.items.first);
    expect(c.state.lines.first.price, '100');
    c.lineQtyChanged(uid, '10');
    expect([c.state.lines.first.price, c.state.total], ['80', 800]);
    c.lineQtyChanged(uid, '9');
    expect(c.state.lines.first.price, '100');

    c
      ..linePriceChanged(uid, '95') // the user's own price is left alone
      ..lineQtyChanged(uid, '20');
    expect(c.state.lines.first.price, '95');

    final off = await form(item: {'wholesalePrice': 80, 'wholesaleMinQty': 10}, settings: {'wholesalePriceEnabled': false});
    final u = off.state.lines.first.uid;
    off
      ..itemSelected(u, off.state.items.first)
      ..lineQtyChanged(u, '50');
    expect(off.state.lines.first.price, '100');
  });

  test('settings: quantity decimals, due date, shipping address and discount columns', () async {
    final c = await form(settings: {'quantityDecimals': 0, 'dueDatesEnabled': true, 'defaultCreditDays': 10, 'itemWiseDiscount': false});
    fill(c, qty: '2.5');
    expect(c.validate(), 'Row 1: quantity must be a whole number.');
    c.lineQtyChanged(c.state.lines.first.uid, '2');
    expect(c.validate(), isNull);
    expect(c.state.showDiscounts, isFalse);

    c.dateChanged('2026-10-01');
    expect(c.state.dueDate, '2026-10-11'); // follows the invoice date…
    c
      ..dueDateChanged('2026-10-20')
      ..dateChanged('2026-10-05');
    expect(c.state.dueDate, '2026-10-20'); // …until the user sets their own

    c.shippingAddressChanged('Godown 4');
    await c.save(andNew: false);
    expect([invoices.saved.single['dueDate'], invoices.saved.single['shippingAddress']], ['2026-10-20', 'Godown 4']);

    final cash = await form(settings: {'dueDatesEnabled': true});
    cash.cashToggled(true);
    expect(cash.state.showDueDate, isFalse);
  });

  test('currency: amounts are typed in it; the rupee total it will be booked at is shown', () async {
    final c = await form(currencies: [('USD', r'$', 80)]);
    fill(c);
    expect(c.state.baseTotal, isNull);
    c.currencyChanged('USD');
    expect([c.state.exchangeRate, c.state.total, c.state.baseTotal, c.state.currencySymbol], ['80', 1000, 80000, r'$']);
    c.exchangeRateChanged('');
    expect(c.validate(), 'Enter the exchange rate for USD.');
    c.exchangeRateChanged('100');
    await c.save(andNew: false);
    expect([invoices.saved.single['currencyCode'], invoices.saved.single['exchangeRate']], ['USD', 100]);
  });

  test('editing an invoice paid in parts with a linked payment', () async {
    final c = await form();
    invoices.invoices = [
      Invoice.fromJson({
        ...invoiceJson('v9', '9', 'Test Customer', 1000, 500),
        'linkedAmount': 300,
        'balance': 200,
        'payments': [
          {'mode': 'cash', 'bankAccountId': null, 'amount': 300},
          {'mode': 'upi', 'bankAccountId': 'b1', 'amount': 200},
        ],
      }),
    ];
    final bus = ChangeBus();
    final edit = InvoiceFormCubit(
      invoices: invoices,
      parties: FakePartiesRepository([Party.fromJson(partyJson('a', 'Test Customer', 500))], bus),
      items: FakeItemsRepository([Item.fromJson(itemJson('i1', 'Sample Item'))], bus),
      accounts: FakeCashBankRepository(),
      firm: FakeFirmRepository(),
      bus: bus,
      kind: InvoiceKind.sale,
      invoiceId: 'v9',
    );
    await edit.load();
    expect([edit.state.received, edit.state.paymentMode, edit.state.extraParts.single.mode, edit.state.extraParts.single.amount], ['300', 'cash', 'upi', '200']);
    expect([edit.state.receivedValue, edit.state.linkedAmount, edit.state.balance], [500, 300, 200]);
    edit.receivedChanged('600'); // 600 + 200 + 300 linked > 1000
    expect(edit.validate(), contains('already linked'));
    await c.close();
  });

  group('payment linked to invoices', () {
    PaymentFormCubit build(FakePaymentsRepository payments, FakeInvoicesRepository inv, {Payment? payment}) => PaymentFormCubit(
          payments,
          FakePartiesRepository([Party.fromJson(partyJson('a', 'Test Customer', 1500))]),
          FakeCashBankRepository(),
          PaymentKind.paymentIn,
          partyId: 'a',
          payment: payment,
          invoices: inv,
        );

    InvoiceSummary unpaid(String id, String date, num total, num balance) =>
        InvoiceSummary.fromJson({...invoiceJson(id, id, 'Test Customer', total, total - balance), 'invoiceDate': date, 'balance': balance});

    test('auto link fills the oldest invoices first; over-linking is refused', () async {
      final payments = FakePaymentsRepository();
      final inv = FakeInvoicesRepository()..unpaidInvoices = [unpaid('n2', '2026-10-05', 1000, 1000), unpaid('n1', '2026-10-01', 600, 500)];
      final c = build(payments, inv);
      await c.load();
      expect([for (final l in c.state.links) l.invoiceId], ['n1', 'n2']); // oldest first

      c.autoLink(800);
      expect([for (final l in c.state.links) l.amount], ['500', '300']);
      expect(c.state.linkedTotal, 800);

      c.linkAmountChanged('n1', '900');
      await c.save(number: '2', amount: 2000, description: '');
      expect(c.state.error, contains('only has'));
      c.linkAmountChanged('n1', '500');
      await c.save(number: '2', amount: 700, description: '');
      expect(c.state.error, contains('more than the payment'));
      expect(payments.saved, isEmpty);

      await c.save(number: '2', amount: 1000, description: '');
      expect(payments.saved.single['allocations'], [
        {'invoiceId': 'n1', 'amount': 500},
        {'invoiceId': 'n2', 'amount': 300},
      ]);
    });

    test('editing shows the payment\'s own links, even on an invoice it paid off', () async {
      final stored = Payment.fromJson(paymentJson('p9', 600, allocations: [
        {'invoiceId': 'done', 'amount': 400, 'number': '7', 'invoiceDate': '2026-09-01', 'total': 400},
        {'invoiceId': 'n1', 'amount': 200, 'number': 'n1', 'invoiceDate': '2026-10-01', 'total': 600},
      ]));
      final payments = FakePaymentsRepository()..stored['p9'] = stored;
      final inv = FakeInvoicesRepository()..unpaidInvoices = [unpaid('n1', '2026-10-01', 600, 300)];
      final c = build(payments, inv, payment: stored);
      await c.load();
      expect([for (final l in c.state.links) (l.invoiceId, l.amount, l.due)], [('done', '400', 400), ('n1', '200', 500)]);
      c.clearLinks();
      expect(c.state.linkedTotal, 0);
    });
  });

  test('expense: GST on top or inside the price, and saved items fill the row', () async {
    final repo = FakeExpensesRepository();
    final c = ExpenseFormCubit(repo, FakeCashBankRepository(), ChangeBus(), categoryId: 'x1', firm: FakeFirmRepository());
    await c.load();
    expect(c.state.gstEnabled, isTrue);
    final uid = c.state.lines.first.uid;
    c.itemDefSelected(uid, c.state.itemDefs.first); // Diesel ₹90 @18%
    expect([c.state.lines.first.name, c.state.lines.first.price, c.state.lines.first.gstRate], ['Diesel', '90', 18]);
    expect(c.state.lines, hasLength(2));
    c
      ..lineQtyChanged(uid, '10')
      ..roundOffToggled(false);
    expect([c.state.taxableTotal, c.state.taxTotal, c.state.total], [900, 162, 1062]);
    c.pricesIncludeTaxChanged(true);
    expect([c.state.taxableTotal, c.state.taxTotal, c.state.total], [762.71, 137.29, 900]);
    await c.save(andNew: false);
    expect(repo.saved.single['pricesIncludeTax'], isTrue);
    expect(repo.saved.single['lines'], [
      {'name': 'Diesel', 'quantity': 10, 'price': 90, 'gstRate': 18},
    ]);

    final off = ExpenseFormCubit(repo, FakeCashBankRepository(), ChangeBus(), firm: FakeFirmRepository(settings: {'gstEnabled': false}));
    await off.load();
    off.itemDefSelected(off.state.lines.first.uid, off.state.itemDefs.first);
    expect(off.state.lines.first.gstRate, isNull);
  });

  test('journal entry: one side per line, and debits must equal credits', () async {
    final repo = FakeAccountingRepository();
    final c = JournalFormCubit(repo, FakeCashBankRepository());
    await c.load();
    expect([c.state.number, c.state.lines.length], ['2', 2]);
    expect(c.validate(), 'A journal entry needs at least two lines.');
    final [a, b] = [c.state.lines[0].uid, c.state.lines[1].uid];
    c
      ..accountChanged(a, 'ledger:la1')
      ..debitChanged(a, '500')
      ..accountChanged(b, 'bank:b1')
      ..creditChanged(b, '400');
    expect(c.validate(), contains('must be equal'));
    c.debitChanged(b, '100'); // typing the other side clears this one
    expect([c.state.lines[1].debit, c.state.lines[1].credit], ['100', '']);
    c.creditChanged(b, '500');
    expect(c.validate(), isNull);
    await c.save();
    expect(repo.savedJournals.single['lines'], [
      {'ledgerAccountId': 'la1', 'debit': 500},
      {'moneyAccount': 'bank', 'bankAccountId': 'b1', 'credit': 500},
    ]);
  });

  test('attachments: files added to a new transaction are attached once it is saved', () async {
    final files = FakeFilesRepository();
    final c = AttachmentsCubit(files, ownerType: 'invoice');
    await c.add(name: 'bill.png', mimeType: 'image/png', bytes: Uint8List.fromList([1, 2, 3]));
    expect(c.state.items.single.attachmentId, isNull);
    expect(files.attached, isEmpty);
    await c.commit('inv1');
    expect(files.attached, [('invoice', 'inv1', 'file1')]);
    expect(c.state.items, isEmpty);

    final existing = AttachmentsCubit(files, ownerType: 'invoice', ownerId: 'inv1');
    await existing.load();
    expect(existing.state.items.single.attachmentId, 'att0');
    await existing.remove(existing.state.items.single);
    expect(files.attached, isEmpty);
  });

  test('menu: salesmen see only the sale side; optional modules follow settings', () {
    AppUser user(String role) => AppUser(id: 'u', email: 'e', fullName: 'n', firmId: 'f', firmName: 'F', role: role);
    List<String> labels(String role, [FirmSettings s = const FirmSettings()]) => [for (final n in navFor(user(role), s)) n.label];

    expect(labels('salesman'), ['Home', 'Parties', 'Items', 'Sale', 'Reminders', 'Settings']);
    expect(labels('accountant'), containsAll(['Purchase & Expense', 'Cash & Bank', 'Reports', 'Utilities']));
    expect(labels('owner').contains('Accounting'), isFalse);
    expect(labels('owner', const FirmSettings(accountingEnabled: true)), contains('Accounting'));

    List<String> utilities(String role) => [for (final c in navFor(user(role), const FirmSettings()).firstWhere((n) => n.label == 'Utilities').children) c.label];
    expect(utilities('owner'), contains('Backup & Restore'));
    expect(utilities('accountant').contains('Backup & Restore'), isFalse);
  });

  test('settings: defaults, prefixes and what is sent to the server', () {
    final s = FirmSettings.fromJson({'invoicePrefix': 'INV-', 'prefixes': {'estimate': 'EST-', 'sale_order': ''}, 'paymentReminderDays': null});
    expect([s.prefixFor('sale'), s.prefixFor('estimate'), s.prefixFor('sale_order'), s.prefixFor('payment_in')], ['INV-', 'EST-', '', '']);
    expect(s.paymentReminderDays, isNull);
    expect(const FirmSettings().paymentReminderDays, 7);
    expect(FirmSettings.fromJson(const {}).invoiceTheme, 'classic');

    final json = s.copyWith(prefixes: {'sale': 'S/'}, partyFields: [const PartyFieldDef('Licence', showInPrint: true)]).toJson();
    expect((json['prefixes'] as Map)['sale'], 'S/');
    expect((json['prefixes'] as Map)['estimate'], ''); // cleared prefixes are sent as empty so they overwrite
    expect(json['partyFields'], [
      {'name': 'Licence', 'showInPrint': true},
    ]);
  });

  test('quick search waits for a pause, ignores short text and maps results to pages', () async {
    final repo = FakeUtilitiesRepository(hits: const [
      SearchHit(kind: 'party', id: 'a', title: 'Ravi Traders'),
      SearchHit(kind: 'item', id: 'i1', title: 'Ravi Pen', type: 'service'),
      SearchHit(kind: 'invoice', id: 'v1', title: 'Estimate 4 Ravi', type: 'estimate'),
    ]);
    final c = SearchCubit(repo, debounce: const Duration(milliseconds: 10));
    c.queryChanged('r');
    expect(c.state.loading, isFalse);
    c
      ..queryChanged('ra')
      ..queryChanged('rav');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(repo.searches, ['rav']); // only the last text was searched
    expect(c.state.hits, hasLength(3));
    expect([for (final h in c.state.hits) searchHitPath(h)], ['/parties?open=a', '/items?open=i1&type=service', '/estimates/v1/edit']);
    await c.close();
  });

  test('list cubit: loads, reports a failed action once and keeps the rows', () async {
    var rows = [1, 2];
    final c = ListCubit<int>(() async => rows);
    await c.load();
    expect(c.state.items, [1, 2]);
    expect(await c.run(() async => rows = [1, 2, 3]), isTrue);
    expect(c.state.items, [1, 2, 3]);
    expect(await c.run(() async => throw Exception('no')), isFalse);
    expect([c.state.errorRev, c.state.items.length, c.state.status], [1, 3, LoadStatus.success]);
  });

  test('financial year helpers and WhatsApp numbers', () {
    expect(lastFinancialYearEnd(DateTime(2026, 10, 11)), '2026-03-31');
    expect(lastFinancialYearEnd(DateTime(2026, 2, 1)), '2025-03-31');
    expect(financialYearLabel(DateTime(2026, 4, 1)), '2026-27');
    expect(financialYearLabel(DateTime(2027, 1, 15)), '2026-27');
    expect([whatsappNumber('98765 43210'), whatsappNumber('+91-9876543210'), whatsappNumber('12345'), whatsappNumber(null)], ['919876543210', '919876543210', null, null]);
  });

  test('verify: what can be fixed', () async {
    final c = VerifyCubit(FakeUtilitiesRepository());
    await c.check();
    expect([c.state.allOk, c.state.canFix], [false, true]);
  });

  testWidgets('invoice prints in every theme and as a thermal receipt', (t) async {
    final invoice = Invoice.fromJson({
      ...gstInvoiceJson(),
      'shippingAddress': 'Godown 4, Okhla',
      'dueDate': '2026-10-25',
      'linkedAmount': 100,
      'balance': 900,
      'payments': [
        {'mode': 'cash', 'bankAccountId': null, 'amount': 200},
        {'mode': 'upi', 'bankAccountId': 'b1', 'amount': 190},
      ],
    });
    final firm = Firm.fromJson(firmJson(settings: {'invoiceTerms': 'Goods once sold will not be taken back.'}));
    await t.runAsync(() async {
      for (final theme in invoiceThemes.keys) {
        final bytes = await buildInvoicePdf(invoice, firm, options: PrintOptions.of(firm, theme: theme, partyFields: const [('Licence', 'DL-1')]));
        expect(bytes.length, greaterThan(1000), reason: theme);
      }
      for (final width in [58, 80]) {
        expect((await buildThermalReceiptPdf(invoice, firm, widthMm: width)).length, greaterThan(1000));
      }
      final usd = Invoice.fromJson({...gstInvoiceJson(), 'currencyCode': 'USD', 'exchangeRate': 80});
      expect((await buildInvoicePdf(usd, firm, options: const PrintOptions(currencySymbol: r'$'))).length, greaterThan(1000));
    });
  });
}
