import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/core/status.dart';
import 'package:billing_app/data/models/invoice.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/data/models/party.dart';
import 'package:billing_app/features/invoices/bloc/invoice_form_cubit.dart';
import 'package:billing_app/shared/amount_words.dart';
import 'package:billing_app/shared/period.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late FakeInvoicesRepository invoices;
  late FakePartiesRepository parties;
  late FakeItemsRepository items;
  var accounts = FakeCashBankRepository();
  var firm = FakeFirmRepository();

  Future<InvoiceFormCubit> build({String? invoiceId, String? fromDocumentId, InvoiceKind kind = InvoiceKind.sale, num? gstRate}) async {
    final bus = ChangeBus();
    invoices = FakeInvoicesRepository(bus);
    parties = FakePartiesRepository([Party.fromJson(partyJson('a', 'Test Customer', 500, phone: '9000000001'))], bus);
    items = FakeItemsRepository([Item.fromJson(itemJson('i1', 'Sample Item', gstRate: gstRate))], bus);
    final cubit = InvoiceFormCubit(invoices: invoices, parties: parties, items: items, accounts: accounts, firm: firm, bus: bus, kind: kind, invoiceId: invoiceId, fromDocumentId: fromDocumentId);
    await cubit.load();
    return cubit;
  }

  test('new invoice starts with the next number and one blank row', () async {
    final c = await build();
    expect(c.state.loadStatus, LoadStatus.success);
    expect(c.state.number, '3');
    expect(c.state.lines, hasLength(1));
    expect(c.state.lines.single.isBlank, isTrue);
  });

  test('add row is refused until the first row has an item', () async {
    final c = await build();
    c.addLine();
    expect(c.state.lines, hasLength(1));
    expect(c.state.submitStatus, SubmitStatus.failure);
    expect(c.state.error, contains('row 1'));
    expect(c.state.issue?.field, 'row:${c.state.lines.first.uid}');

    c.lineNameChanged(c.state.lines.first.uid, 'Widget');
    c.addLine();
    expect(c.state.lines, hasLength(2));
  });

  test('a party added from the form is selected once the dialog closes', () async {
    final c = await build();
    c.addPartyStarted();
    await parties.save(null, {'name': 'Brand New Party', 'openingBalance': 0});
    await c.addPartyFinished();
    expect(c.state.partyName, 'Brand New Party');
    expect(c.state.partyId, isNotNull);
    expect(c.state.parties.map((p) => p.name), contains('Brand New Party'));
  });

  test('picking an item fills price, unit and qty and opens a new row', () async {
    final c = await build();
    c.itemSelected(c.state.lines.first.uid, c.state.items.first);
    final line = c.state.lines.first;
    expect([line.itemId, line.qty, line.unit, line.price], ['i1', '1', 'PCS', '100']);
    expect(line.rowRev, 1);
    expect(c.state.lines, hasLength(2));
    expect(c.state.total, 100);
  });

  test('discount % and amount stay in sync', () async {
    final c = await build();
    final uid = c.state.lines.first.uid;
    c
      ..lineNameChanged(uid, 'Widget')
      ..lineQtyChanged(uid, '3')
      ..linePriceChanged(uid, '120')
      ..lineDiscountPctChanged(uid, '10');
    expect(c.state.lines.first.discountAmount, '36');
    expect(c.state.lines.first.net, 324);

    c.lineQtyChanged(uid, '5'); // % discount follows the new gross
    expect(c.state.lines.first.discountAmount, '60');

    c.lineDiscountAmountChanged(uid, '150'); // typing an amount derives the %
    expect(c.state.lines.first.discountPct, '25');
    expect(c.state.lines.first.net, 450);
    c.lineQtyChanged(uid, '10'); // amount discount stays fixed
    expect(c.state.lines.first.net, 1050);
  });

  test('round off, received and balance', () async {
    final c = await build();
    final uid = c.state.lines.first.uid;
    c
      ..lineNameChanged(uid, 'Widget')
      ..lineQtyChanged(uid, '1')
      ..linePriceChanged(uid, '99.6');
    expect([c.state.subtotal, c.state.total, c.state.roundOffValue], [99.6, 100, 0.4]);
    c.roundOffToggled(false);
    expect(c.state.total, 99.6);
    c.receivedChanged('40');
    expect(c.state.balance, 59.6);
    c.cashToggled(true); // cash sale is fully paid
    expect(c.state.balance, 0);
  });

  test('validation: credit needs a saved party, rows need a quantity', () async {
    final c = await build();
    final uid = c.state.lines.first.uid;
    expect(c.validate(), 'Select a customer.');
    c.partyNameChanged('Somebody New');
    expect(c.validate(), contains('not a saved party'));
    c.partySelected(c.state.parties.first);
    expect(c.state.phone, '9000000001');
    expect(c.validate(), 'Add at least one item.');
    c.lineNameChanged(uid, 'Widget');
    expect(c.validate(), 'Row 1: enter a quantity greater than 0.');
    c
      ..lineQtyChanged(uid, '2')
      ..linePriceChanged(uid, '50')
      ..receivedChanged('500');
    expect(c.validate(), 'Received amount cannot be more than the total.');
    c.receivedChanged('');
    expect(c.validate(), isNull);

    await c.save(andNew: false); // nothing sent while invalid would have been caught above
    expect(c.state.result, InvoiceFormResult.saved);
  });

  test('save sends computed lines, skipping blank rows; save & new resets with the next number', () async {
    final c = await build();
    final uid = c.state.lines.first.uid;
    c
      ..partySelected(c.state.parties.first)
      ..itemSelected(uid, c.state.items.first)
      ..lineQtyChanged(uid, '2')
      ..lineDiscountPctChanged(uid, '5');
    await c.save(andNew: true);
    final body = invoices.saved.single;
    expect(body['partyId'], 'a');
    expect(body['lines'], [
      {'itemId': 'i1', 'name': 'Sample Item', 'quantity': 2, 'unit': 'PCS', 'price': 100, 'discountPct': 5, 'gstRate': null, 'hsnCode': '1001'},
    ]);
    expect(body['received'], 0);
    expect(c.state.result, InvoiceFormResult.savedAndNew);
    expect(c.state.partyId, isNull);
    expect(c.state.lines.single.isBlank, isTrue);
  });

  test('invalid invoice is not sent', () async {
    final c = await build();
    await c.save(andNew: false);
    expect(c.state.submitStatus, SubmitStatus.failure);
    expect(invoices.saved, isEmpty);
  });

  test('editing loads the invoice; typing over an item name unlinks it from stock', () async {
    final c = await build(invoiceId: 'v1');
    expect(c.state.number, '1');
    expect(c.state.partyId, 'a');
    expect(c.state.lines, hasLength(2));
    expect(c.state.lines.first.discountByAmount, isFalse); // 10% of 360 = 36 → percentage discount
    expect(c.state.total, 1000);
    c.lineNameChanged(c.state.lines.first.uid, 'Sample Item (custom)');
    expect(c.state.lines.first.itemId, isNull);
  });

  test('purchase bill: no cash mode, optional bill number, purchase price, party required', () async {
    final c = await build(kind: InvoiceKind.purchase);
    expect(c.state.number, ''); // supplier's bill number is typed in, not auto-numbered
    c.cashToggled(true);
    expect(c.state.isCash, isFalse);

    final uid = c.state.lines.first.uid;
    c.itemSelected(uid, c.state.items.first);
    expect(c.state.lines.first.price, '70'); // purchase price, not the sale price of 100
    expect(c.validate(), 'Select a party.');
    c.partySelected(c.state.parties.first);
    expect(c.validate(), isNull); // empty bill number is fine

    await c.save(andNew: false);
    expect(invoices.saved.single['type'], 'purchase');
    expect(invoices.saved.single['number'], '');
    expect(invoices.saved.single['isCash'], isFalse);
  });

  test('estimate: no payment, own number required, nothing received', () async {
    final c = await build(kind: InvoiceKind.estimate);
    expect(c.state.number, '3');
    final uid = c.state.lines.first.uid;
    c
      ..partySelected(c.state.parties.first)
      ..itemSelected(uid, c.state.items.first)
      ..receivedChanged('50') // ignored: estimates take no payment
      ..lineQtyChanged(uid, '2')
      ..numberChanged('');
    expect(c.state.total, 200); // quoted at the sale price (100), not the purchase price (70)
    expect(c.state.balance, c.state.total);
    expect(c.validate(), 'Enter the ref no.');
    c.numberChanged('Q-1');
    await c.save(andNew: false);
    expect(invoices.saved.single['type'], 'estimate');
    expect(invoices.saved.single['received'], 0);
    expect(invoices.saved.single.containsKey('fromDocumentId'), isFalse);
  });

  test('convert to sale: pre-fills from the estimate with a new sale number and links it on save', () async {
    final c = await build(fromDocumentId: 'e1');
    expect(c.editing, isFalse);
    expect(c.state.number, '3'); // next sale number, not the estimate's "7"
    expect(c.state.partyId, 'a');
    expect(c.state.lines, hasLength(2));
    expect(c.state.total, 1000);
    expect(c.state.received, '');
    await c.save(andNew: false);
    expect(invoices.saved.single['type'], 'sale');
    expect(invoices.saved.single['fromDocumentId'], 'e1');
  });

  test('bank/UPI/card needs a bank account once accounts exist; cash and cheque do not', () async {
    final c = await build();
    final uid = c.state.lines.first.uid;
    c
      ..partySelected(c.state.parties.first)
      ..itemSelected(uid, c.state.items.first)
      ..receivedChanged('50')
      ..paymentModeChanged('upi');
    expect(c.state.bankAccountId, isNull); // two accounts → no automatic choice
    expect(c.validate(), 'Select the bank account.');
    c.receivedChanged(''); // nothing received now → the account doesn't matter
    expect(c.validate(), isNull);
    c
      ..receivedChanged('50')
      ..bankAccountChanged('b2');
    expect(c.validate(), isNull);
    c.paymentModeChanged('card'); // still a bank mode → keeps the account
    expect(c.state.bankAccountId, 'b2');
    c.paymentModeChanged('cash');
    expect(c.state.bankAccountId, isNull);
    c
      ..paymentModeChanged('bank')
      ..bankAccountChanged('b1');
    await c.save(andNew: false);
    expect(invoices.saved.single['bankAccountId'], 'b1');
  });

  test('a single bank account is picked automatically; none at all is allowed', () async {
    accounts = FakeCashBankRepository(bankAccounts: const ['Only Bank']);
    final one = await build();
    one.paymentModeChanged('upi');
    expect(one.state.bankAccountId, 'b1');

    accounts = FakeCashBankRepository(bankAccounts: const []);
    final none = await build();
    none
      ..partySelected(none.state.parties.first)
      ..itemSelected(none.state.lines.first.uid, none.state.items.first)
      ..receivedChanged('10')
      ..paymentModeChanged('upi');
    expect(none.validate(), isNull);
    accounts = FakeCashBankRepository();
  });

  test('document kinds: what each one does', () {
    expect(InvoiceKind.all.map((k) => k.type).toSet(), hasLength(9));
    final quotes = InvoiceKind.all.where((k) => k.isQuote).map((k) => k.type);
    expect(quotes, ['estimate', 'sale_order', 'delivery_challan', 'proforma', 'purchase_order']);
    expect(InvoiceKind.estimate.convertTargets, [InvoiceKind.sale, InvoiceKind.saleOrder]);
    expect(InvoiceKind.purchaseOrder.convertTargets, [InvoiceKind.purchase]);
    expect(InvoiceKind.all.where((k) => !k.usesSalePrice).map((k) => k.type), ['purchase', 'purchase_order', 'debit_note']);
    expect(InvoiceKind.all.where((k) => k.supportsCash), [InvoiceKind.sale]);
    expect(InvoiceKind.creditNote.hasPayment, isTrue);
    expect(InvoiceKind.maybeOf('expense'), isNull);
    expect(InvoiceKind.all.map((k) => k.basePath).toSet(), hasLength(9)); // every kind has its own route
  });

  test('purchase order quotes at the purchase price and takes no payment', () async {
    final c = await build(kind: InvoiceKind.purchaseOrder);
    c
      ..partySelected(c.state.parties.first)
      ..itemSelected(c.state.lines.first.uid, c.state.items.first)
      ..receivedChanged('30');
    expect(c.state.total, 70);
    expect(c.state.receivedValue, 0);
    await c.save(andNew: false);
    expect(invoices.saved.single['type'], 'purchase_order');
  });

  test('GST: item rate fills in, tax is added on top or taken out of inclusive prices', () async {
    final c = await build(gstRate: 18);
    final uid = c.state.lines.first.uid;
    c.itemSelected(uid, c.state.items.first); // sale price 100 excl. tax, GST 18%
    c.lineQtyChanged(uid, '2');
    final line = c.state.lines.first;
    expect([line.gstRate, line.hsnCode], [18, '1001']);
    expect([c.state.taxableTotal, c.state.taxTotal, c.state.total], [200, 36, 236]);

    c.pricesIncludeTaxChanged(true); // the typed 100 is now read as tax-inclusive
    expect([c.state.taxableTotal, c.state.taxTotal, c.state.total], [169.49, 30.51, 200]);

    c.lineGstRateChanged(uid, null);
    expect([c.state.taxTotal, c.state.total], [0, 200]);
  });

  test('GST: an item price is converted to how the document enters prices', () async {
    final c = await build(gstRate: 18);
    c.pricesIncludeTaxChanged(true);
    final uid = c.state.lines.first.uid;
    c.itemSelected(uid, c.state.items.first); // stored 100 excl. → 118 incl.
    expect(c.state.lines.first.price, '118');
    expect([c.state.taxableTotal, c.state.taxTotal, c.state.total], [100, 18, 118]);
    c.partySelected(c.state.parties.first);
    await c.save(andNew: false);
    expect(invoices.saved.single['pricesIncludeTax'], isTrue);
    expect((invoices.saved.single['lines'] as List).single, containsPair('gstRate', 18));
  });

  test('settings: defaults for new documents, and GST switched off', () async {
    firm = FakeFirmRepository(settings: {'defaultRoundOff': false, 'defaultCashSale': true, 'gstEnabled': false});
    final sale = await build(gstRate: 18);
    expect([sale.state.roundOff, sale.state.isCash, sale.state.gstEnabled], [false, true, false]);
    sale.itemSelected(sale.state.lines.first.uid, sale.state.items.first);
    expect(sale.state.lines.first.gstRate, isNull); // the item's 18% is not applied
    expect(sale.state.total, 100);

    final purchase = await build(kind: InvoiceKind.purchase);
    expect(purchase.state.isCash, isFalse); // "cash sale by default" only applies to sales

    final existing = await build(invoiceId: 'v1'); // saved documents keep their own values
    expect([existing.state.isCash, existing.state.roundOff], [false, true]);
    firm = FakeFirmRepository();
  });

  test('amount in words uses the Indian system', () {
    expect(amountInWords(0), 'Zero Rupees only');
    expect(amountInWords(374), 'Three Hundred Seventy Four Rupees only');
    expect(amountInWords(125000.5), 'One Lakh Twenty Five Thousand Rupees and Fifty Paise only');
    expect(amountInWords(10000000), 'One Crore Rupees only');
    expect(amountInWords(1019), 'One Thousand Nineteen Rupees only');
  });

  test('period presets', () {
    final now = DateTime(2026, 10, 10);
    expect(PeriodRange.of(Period.thisMonth, now), const PeriodRange(Period.thisMonth, '2026-10-01', '2026-10-31'));
    expect(PeriodRange.of(Period.lastMonth, now), const PeriodRange(Period.lastMonth, '2026-09-01', '2026-09-30'));
    expect(PeriodRange.of(Period.thisQuarter, now), const PeriodRange(Period.thisQuarter, '2026-10-01', '2026-12-31'));
    expect(PeriodRange.of(Period.thisYear, now), const PeriodRange(Period.thisYear, '2026-04-01', '2027-03-31'));
    expect(PeriodRange.of(Period.thisYear, DateTime(2026, 2, 1)).from, '2025-04-01');
    expect(PeriodRange.of(Period.lastMonth, DateTime(2026, 1, 15)).from, '2025-12-01');
  });
}
