// Exercises the real repositories against a running backend (not part of the normal test run):
//   flutter test live_api_test            # backend must be listening on API_BASE_URL (default localhost:3100)
import 'dart:convert';
import 'dart:io';

import 'package:billing_app/features/cash_bank/bloc/cash_bank_form_cubits.dart';
import 'package:billing_app/features/accounting/journal_form_cubit.dart';
import 'package:billing_app/features/files/attachments.dart';
import 'package:billing_app/features/payments/bloc/payment_form_cubit.dart';
import 'package:billing_app/data/models/cash_bank.dart';
import 'package:billing_app/data/models/firm.dart';
import 'package:billing_app/data/models/payment.dart';
import 'package:billing_app/data/repositories/utilities_repository.dart';
import 'package:billing_app/data/repositories/files_repository.dart';
import 'package:billing_app/data/repositories/accounting_repository.dart';

import 'package:billing_app/core/api_client.dart';
import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/data/repositories/auth_repository.dart';
import 'package:billing_app/data/repositories/cash_bank_repository.dart';
import 'package:billing_app/data/repositories/dashboard_repository.dart';
import 'package:billing_app/data/repositories/expenses_repository.dart';
import 'package:billing_app/features/expenses/bloc/expense_form_cubit.dart';
import 'package:billing_app/data/repositories/firm_repository.dart';
import 'package:billing_app/data/repositories/invoices_repository.dart';
import 'package:billing_app/data/repositories/items_repository.dart';
import 'package:billing_app/data/repositories/loans_repository.dart';
import 'package:billing_app/data/repositories/parties_repository.dart';
import 'package:billing_app/data/repositories/payments_repository.dart';
import 'package:billing_app/data/repositories/reports_repository.dart';
import 'package:billing_app/features/utilities/import_spec.dart';
import 'package:billing_app/features/utilities/utilities_cubits.dart';
import 'package:billing_app/shared/csv.dart';
import 'package:billing_app/features/invoices/bloc/invoice_form_cubit.dart';
import 'package:billing_app/data/models/invoice.dart';
import 'package:billing_app/data/models/report.dart';
import 'package:billing_app/features/printing/pdf_documents.dart';
import 'package:billing_app/data/models/team_location.dart';
import 'package:billing_app/data/repositories/location_repository.dart';
import 'package:billing_app/features/parties/bloc/party_form_cubit.dart';
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
  HttpOverrides.global = null; // allow real network calls in tests

  test('full sale → payment flow through the real API', () async {
    final api = ApiClient(_MemoryTokens());
    final bus = ChangeBus();
    final parties = PartiesRepository(api, bus);
    final items = ItemsRepository(api, bus);
    final invoices = InvoicesRepository(api, bus);
    final payments = PaymentsRepository(api, bus);
    final cashBank = CashBankRepository(api, bus);
    final firmRepo = FirmRepository(api, bus);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final user = await AuthRepository(api)
        .register(firmName: 'Live Test $stamp', stateCode: '07', fullName: 'Tester', email: 'live$stamp@example.com', password: 'Password123');
    expect(user.firmName, 'Live Test $stamp');

    final party = await parties.save(null, {'name': 'Live Customer', 'phone': '9000000001', 'openingBalance': 100});
    final item = await items.save(null, {'name': 'Live Widget', 'unit': 'PCS', 'salePrice': 120, 'purchasePrice': 70, 'openingQty': 20});
    expect((await items.units()).length, greaterThan(10));

    // Drive the real form cubit, as the screen does.
    final form = InvoiceFormCubit(
      invoices: invoices,
      parties: parties,
      items: items,
      accounts: cashBank,
      firm: firmRepo,
      bus: bus,
      kind: InvoiceKind.sale,
    );
    await form.load();
    expect(form.state.number, '1');
    final uid = form.state.lines.first.uid;
    form
      ..partySelected(form.state.parties.single)
      ..itemSelected(uid, form.state.items.single)
      ..lineQtyChanged(uid, '3')
      ..lineDiscountPctChanged(uid, '10')
      ..receivedChanged('100');
    expect(form.state.total, 324);
    await form.save(andNew: false);
    expect(form.state.error, isNull);
    final invoiceId = form.state.savedId!;

    final saved = await invoices.get(invoiceId);
    expect([saved.total, saved.received, saved.balance, saved.lines.single.amount], [324, 100, 224, 324]);
    expect((await items.list('product')).single.stockQty, 17);
    expect((await items.movements(item.id)).first.label, 'Sale');

    // Edit through the cubit: quantity 3 → 5.
    final edit = InvoiceFormCubit(
      invoices: invoices,
      parties: parties,
      items: items,
      accounts: cashBank,
      firm: firmRepo,
      bus: bus,
      kind: InvoiceKind.sale,
      invoiceId: invoiceId,
    );
    await edit.load();
    edit.lineQtyChanged(edit.state.lines.first.uid, '5');
    await edit.save(andNew: false);
    expect(edit.state.error, isNull);
    expect((await invoices.get(invoiceId)).total, 540);
    expect((await items.list('product')).single.stockQty, 15);

    final pay = await payments.save(null, {
      'type': 'in',
      'number': await payments.nextNumber('in'),
      'partyId': party.id,
      'paymentDate': saved.invoiceDate,
      'amount': 200,
      'paymentMode': 'upi',
      'description': '',
    });
    expect(pay.partyName, 'Live Customer');

    // 100 opening + (540 − 100) unpaid − 200 received = 340
    expect((await parties.list()).firstWhere((p) => p.id == party.id).balance, 340);
    final ledger = await parties.transactions(party.id);
    expect(ledger.map((t) => t.kind), ['payment_in', 'sale', 'opening']);
    expect(ledger.first.balance, 340);

    final month = saved.invoiceDate.substring(0, 8);
    final list = await invoices.list('sale', from: '${month}01', to: '${month}28');
    expect(list.single.number, '1');
    expect((await payments.list('in', from: '${month}01', to: '${month}28')).single.amount, 200);

    final dash = await DashboardRepository(api).summary(from: '${month}01', to: '${month}28');
    expect([dash.receivable, dash.salesTotal], [340, 540]);

    final firm = await firmRepo.get();
    expect((await buildInvoicePdf(await invoices.get(invoiceId), firm)).length, greaterThan(1000));
    expect((await buildPaymentPdf(pay, firm)).length, greaterThan(1000));

    // ---- purchase side: stock comes in, we owe the supplier, Payment-Out settles it.
    final supplier = await parties.save(null, {'name': 'Live Supplier'});
    final buy = InvoiceFormCubit(
      invoices: invoices,
      parties: parties,
      items: items,
      accounts: cashBank,
      firm: firmRepo,
      bus: bus,
      kind: InvoiceKind.purchase,
    );
    await buy.load();
    final buyUid = buy.state.lines.first.uid;
    buy
      ..partySelected(buy.state.parties.firstWhere((p) => p.id == supplier.id))
      ..itemSelected(buyUid, buy.state.items.single)
      ..lineQtyChanged(buyUid, '10')
      ..receivedChanged('200');
    expect(buy.state.total, 700); // 10 × purchase price 70
    await buy.save(andNew: false);
    expect(buy.state.error, isNull);
    final bill = await invoices.get(buy.state.savedId!);
    expect([bill.type, bill.number, bill.total, bill.balance], ['purchase', '', 700, 500]);
    expect((await items.list('product')).single.stockQty, 25); // 15 + 10
    expect((await items.movements(item.id)).first.label, 'Purchase');
    expect((await parties.list()).firstWhere((p) => p.id == supplier.id).balance, -500);

    // A second bill with the same (blank) number is allowed for purchases.
    final again = InvoiceFormCubit(
      invoices: invoices,
      parties: parties,
      items: items,
      accounts: cashBank,
      firm: firmRepo,
      bus: bus,
      kind: InvoiceKind.purchase,
    );
    await again.load();
    again
      ..partySelected(again.state.parties.firstWhere((p) => p.id == supplier.id))
      ..itemSelected(again.state.lines.first.uid, again.state.items.single);
    await again.save(andNew: false);
    expect(again.state.error, isNull);
    await invoices.delete(again.state.savedId!);

    final payOut = await payments.save(null, {
      'type': 'out',
      'number': await payments.nextNumber('out'),
      'partyId': supplier.id,
      'paymentDate': bill.invoiceDate,
      'amount': 500,
      'paymentMode': 'bank',
      'description': '',
    });
    expect((await parties.list()).firstWhere((p) => p.id == supplier.id).balance, 0);
    expect((await parties.transactions(supplier.id)).map((t) => t.kind), ['payment_out', 'purchase']);
    expect((await invoices.list('purchase', from: '${month}01', to: '${month}28')).single.balance, 500);
    expect((await payments.list('out', from: '${month}01', to: '${month}28')).single.amount, 500);
    expect((await buildInvoicePdf(bill, firm)).length, greaterThan(1000));
    expect((await buildPaymentPdf(payOut, firm)).length, greaterThan(1000));
    await invoices.delete(bill.id);
    expect((await items.list('product')).single.stockQty, 15);

    // ---- estimate: no stock/balance effect; converting creates a sale and marks it converted.
    final stockBefore = (await items.list('product')).single.stockQty;
    final balanceBefore = (await parties.list()).firstWhere((p) => p.id == party.id).balance;
    final quote = InvoiceFormCubit(
      invoices: invoices,
      parties: parties,
      items: items,
      accounts: cashBank,
      firm: firmRepo,
      bus: bus,
      kind: InvoiceKind.estimate,
    );
    await quote.load();
    expect(quote.state.number, '1'); // estimates have their own number series
    quote
      ..partySelected(quote.state.parties.firstWhere((p) => p.id == party.id))
      ..itemSelected(quote.state.lines.first.uid, quote.state.items.single)
      ..lineQtyChanged(quote.state.lines.first.uid, '2');
    await quote.save(andNew: false);
    expect(quote.state.error, isNull);
    final estimateId = quote.state.savedId!;
    var estimates = await invoices.list('estimate', from: '${month}01', to: '${month}28');
    expect([estimates.single.status, estimates.single.total, estimates.single.received], ['open', 240, 0]);
    expect((await items.list('product')).single.stockQty, stockBefore);
    expect((await parties.list()).firstWhere((p) => p.id == party.id).balance, balanceBefore);
    expect((await parties.transactions(party.id)).any((t) => t.type == 'Estimate'), isFalse);
    expect((await buildInvoicePdf(await invoices.get(estimateId), firm)).length, greaterThan(1000));

    final convert = InvoiceFormCubit(
      invoices: invoices,
      parties: parties,
      items: items,
      accounts: cashBank,
      firm: firmRepo,
      bus: bus,
      kind: InvoiceKind.sale,
      fromDocumentId: estimateId,
    );
    await convert.load();
    expect([convert.state.number, convert.state.partyId, convert.state.total], ['2', party.id, 240]);
    await convert.save(andNew: false);
    expect(convert.state.error, isNull);
    final convertedSaleId = convert.state.savedId!;
    estimates = await invoices.list('estimate', from: '${month}01', to: '${month}28');
    expect([estimates.single.status, estimates.single.convertedInvoiceId], ['converted', convertedSaleId]);
    expect((await items.list('product')).single.stockQty, stockBefore - 2);

    // Converting the same estimate twice is refused.
    final twice = InvoiceFormCubit(
      invoices: invoices,
      parties: parties,
      items: items,
      accounts: cashBank,
      firm: firmRepo,
      bus: bus,
      kind: InvoiceKind.sale,
      fromDocumentId: estimateId,
    );
    await twice.load();
    await twice.save(andNew: false);
    expect(twice.state.error, contains('already converted'));

    // Deleting the sale re-opens the estimate.
    await invoices.delete(convertedSaleId);
    estimates = await invoices.list('estimate', from: '${month}01', to: '${month}28');
    expect(estimates.single.status, 'open');
    expect((await items.list('product')).single.stockQty, stockBefore);
    await invoices.delete(estimateId);

    // ---- order chain: estimate → sale order → sale; each step closes the previous document.
    Future<String> make(InvoiceKind kind, {String? from, String qty = '2', String? received}) async {
      final c = InvoiceFormCubit(
        invoices: invoices,
        parties: parties,
        items: items,
        accounts: cashBank,
        firm: firmRepo,
        bus: bus,
        kind: kind,
        fromDocumentId: from,
      );
      await c.load();
      if (from == null) {
        c
          ..partySelected(c.state.parties.firstWhere((p) => p.id == (kind.purchaseSide ? supplier.id : party.id)))
          ..itemSelected(c.state.lines.first.uid, c.state.items.single)
          ..lineQtyChanged(c.state.lines.first.uid, qty);
      }
      if (received != null) c.receivedChanged(received);
      await c.save(andNew: false);
      expect(c.state.error, isNull, reason: '${kind.type}: ${c.state.error}');
      return c.state.savedId!;
    }

    Future<InvoiceSummary> only(InvoiceKind kind) async => (await invoices.list(kind.type, from: '${month}01', to: '${month}28')).single;
    Future<num> stock() async => (await items.list('product')).single.stockQty;
    Future<num> balanceOf(String id) async => (await parties.list()).firstWhere((p) => p.id == id).balance;

    final stock0 = await stock();
    final custBal0 = await balanceOf(party.id);
    final est = await make(InvoiceKind.estimate);
    final order = await make(InvoiceKind.saleOrder, from: est);
    expect([(await only(InvoiceKind.estimate)).status, (await only(InvoiceKind.estimate)).convertedType], ['converted', 'sale_order']);
    expect((await only(InvoiceKind.saleOrder)).status, 'open');
    expect(await stock(), stock0); // orders don't move stock
    final orderSale = await make(InvoiceKind.sale, from: order);
    expect([(await only(InvoiceKind.saleOrder)).status, (await only(InvoiceKind.saleOrder)).convertedType], ['converted', 'sale']);
    expect(await stock(), stock0 - 2);
    expect(await balanceOf(party.id), custBal0 + 240);

    // A purchase order cannot become a sale; challans and proformas convert to sales.
    final supBal0 = await balanceOf(supplier.id);
    final po = await make(InvoiceKind.purchaseOrder, qty: '4');
    final wrong = InvoiceFormCubit(
      invoices: invoices,
      parties: parties,
      items: items,
      accounts: cashBank,
      firm: firmRepo,
      bus: bus,
      kind: InvoiceKind.sale,
      fromDocumentId: po,
    );
    await wrong.load();
    await wrong.save(andNew: false);
    expect(wrong.state.error, contains('already converted or no longer exists'));
    final poBill = await make(InvoiceKind.purchase, from: po);
    expect((await only(InvoiceKind.purchaseOrder)).convertedType, 'purchase');
    expect(await stock(), stock0 - 2 + 4);
    final challan = await make(InvoiceKind.deliveryChallan, qty: '1');
    final proforma = await make(InvoiceKind.proforma, qty: '1');
    expect(await stock(), stock0 + 2);

    // ---- returns: a credit note brings stock back and reduces what the customer owes; a refund is money out.
    final cashBefore = (await cashBank.cash()).$1;
    final credit = await make(InvoiceKind.creditNote, qty: '1', received: '50'); // 120 returned, 50 refunded in cash
    expect(await stock(), stock0 + 3);
    expect(await balanceOf(party.id), custBal0 + 240 - 70);
    expect((await cashBank.cash()).$1, cashBefore - 50);
    expect((await items.movements(item.id)).first.label, 'Sale Return');
    final debit = await make(InvoiceKind.debitNote, qty: '2', received: '40'); // 140 returned to supplier, 40 received back
    expect(await stock(), stock0 + 1);
    expect(await balanceOf(supplier.id), supBal0 - 280 + 100); // +PO bill 280 owed, −100 for the unpaid part of the return
    expect((await cashBank.cash()).$1, cashBefore - 50 + 40);
    expect((await parties.transactions(party.id)).first.type, 'Credit Note');
    expect((await buildInvoicePdf(await invoices.get(credit), firm)).length, greaterThan(1000));

    for (final id in [credit, debit, poBill, po, challan, proforma, orderSale, order, est]) {
      await invoices.delete(id);
    }
    expect(await stock(), stock0);
    expect([await balanceOf(party.id), await balanceOf(supplier.id)], [custBal0, supBal0]);

    // ---- GST: firm is in Delhi (07). Intra-state → CGST + SGST; another state → IGST.
    final gstItem = await items.save(null, {
      'name': 'GST Widget',
      'hsnCode': '8471',
      'unit': 'PCS',
      'salePrice': 500,
      'purchasePrice': 300,
      'gstRate': 18,
      'openingQty': 10,
    });
    final gstParty = await parties.save(null, {'name': 'GST Buyer', 'gstin': '27AAACR5055K1Z5', 'gstType': 'regular'});
    expect(gstParty.stateCode, '27'); // derived from the GSTIN

    Future<Invoice> gstSale({required String? state, bool inclusive = false}) async {
      final c = InvoiceFormCubit(
        invoices: invoices,
        parties: parties,
        items: items,
        accounts: cashBank,
        firm: firmRepo,
        bus: bus,
        kind: InvoiceKind.sale,
      );
      await c.load();
      if (inclusive) c.pricesIncludeTaxChanged(true);
      c
        ..partySelected(c.state.parties.firstWhere((p) => p.id == gstParty.id))
        ..stateOfSupplyChanged(state)
        ..itemSelected(c.state.lines.first.uid, c.state.items.firstWhere((i) => i.id == gstItem.id))
        ..lineQtyChanged(c.state.lines.first.uid, '2');
      final preview = [c.state.taxableTotal, c.state.taxTotal, c.state.total];
      await c.save(andNew: false);
      expect(c.state.error, isNull);
      final inv = await invoices.get(c.state.savedId!);
      // What the form showed is exactly what the server stored.
      expect(preview, [inv.taxableAmount, inv.totalTax, inv.total]);
      return inv;
    }

    final intra = await gstSale(state: '07');
    expect([intra.interState, intra.taxableAmount, intra.cgst, intra.sgst, intra.igst, intra.total], [false, 1000, 90, 90, 0, 1180]);
    expect([intra.partyGstin, intra.lines.single.hsnCode, intra.lines.single.gstRate], ['27AAACR5055K1Z5', '8471', 18]);
    final inter = await gstSale(state: '27'); // party's state was picked up from its GSTIN
    expect([inter.interState, inter.cgst, inter.sgst, inter.igst, inter.total], [true, 0, 0, 180, 1180]);
    final incl = await gstSale(state: '07', inclusive: true); // 500 excl. → shown as 590 incl.
    expect([incl.pricesIncludeTax, incl.lines.single.price, incl.taxableAmount, incl.totalTax, incl.total], [true, 590, 1000, 180, 1180]);
    expect(await balanceOf(gstParty.id), 3540); // balances use the tax-inclusive totals
    expect((await buildInvoicePdf(intra, firm)).length, greaterThan(1000));
    for (final inv in [intra, inter, incl]) {
      await invoices.delete(inv.id);
    }
    await items.delete(gstItem.id);
    await parties.delete(gstParty.id);

    // ---- expenses
    final expenses = ExpensesRepository(api, bus);
    final cats = await expenses.categories();
    expect(cats.map((c) => c.name), ['Petrol', 'Rent', 'Salary', 'Tea', 'Transport']);
    final tea = cats.firstWhere((c) => c.name == 'Tea');
    final spend = ExpenseFormCubit(expenses, cashBank, bus, categoryId: tea.id);
    await spend.load();
    final spendUid = spend.state.lines.first.uid;
    spend
      ..lineNameChanged(spendUid, 'Office tea')
      ..lineQtyChanged(spendUid, '3')
      ..linePriceChanged(spendUid, '10.4');
    await spend.save(andNew: false);
    expect(spend.state.error, isNull);
    expect((await expenses.categories()).firstWhere((c) => c.id == tea.id).total, 31);
    final teaExpense = (await expenses.list(categoryId: tea.id)).single;
    final full = await expenses.get(teaExpense.id);
    expect([full.subtotal, full.roundOff, full.total, full.lines.single.amount], [31.2, -0.2, 31, 31.2]);
    await expectLater(expenses.deleteCategory(tea.id), throwsA(isA<ApiException>())); // has expenses
    final custom = await expenses.saveCategory(null, 'Courier');
    await expectLater(expenses.saveCategory(null, 'courier'), throwsA(isA<ApiException>())); // duplicate
    await expenses.deleteCategory(custom.id);
    await expenses.delete(teaExpense.id);
    expect((await expenses.categories()).firstWhere((c) => c.id == tea.id).total, 0);
    await expenses.deleteCategory(tea.id); // now empty → allowed
    expect((await expenses.categories()).length, 4);

    // ---- cash & bank. So far: sale received 100 cash, purchase paid 200 cash, payment-in 200 UPI (no
    // account existed), payment-out 500 bank (no account), tea 31 cash and deleted.
    var (cashBalance, cashTxns) = await cashBank.cash();
    expect(cashBalance, 100); // +100 sale; the purchase bill was deleted above
    expect(cashTxns.single.type, 'Sale');

    final hdfc = await cashBank.saveAccount(null, {
      'name': 'HDFC Current',
      'openingBalance': 1000,
      'openingDate': saved.invoiceDate,
      'ifsc': 'hdfc0001234',
    });
    final sbi = await cashBank.saveAccount(null, {'name': 'SBI Savings', 'openingDate': saved.invoiceDate});
    expect([hdfc.balance, hdfc.ifsc, sbi.balance], [1000, 'HDFC0001234', 0]);
    await expectLater(cashBank.saveAccount(null, {'name': 'hdfc current'}), throwsA(isA<ApiException>()));

    // A UPI payment-in into HDFC.
    final upi = await payments.save(null, {
      'type': 'in',
      'number': await payments.nextNumber('in'),
      'partyId': party.id,
      'paymentDate': saved.invoiceDate,
      'amount': 250,
      'paymentMode': 'upi',
      'bankAccountId': hdfc.id,
      'description': '',
    });
    expect(upi.bankAccountId, hdfc.id);
    // Cash never keeps a bank account, whatever the client sends.
    final cashPay = await payments.save(null, {
      'type': 'in',
      'number': await payments.nextNumber('in'),
      'partyId': party.id,
      'paymentDate': saved.invoiceDate,
      'amount': 40,
      'paymentMode': 'cash',
      'bankAccountId': hdfc.id,
      'description': '',
    });
    expect(cashPay.bankAccountId, isNull);

    // Transfers: 300 HDFC → cash, 50 cash → SBI, 200 HDFC → SBI, +5 adjust SBI, 20 cash added.
    for (final a in [
      {'kind': 'bank_to_cash', 'bankAccountId': hdfc.id, 'amount': 300},
      {'kind': 'cash_to_bank', 'bankAccountId': sbi.id, 'amount': 50},
      {'kind': 'bank_to_bank', 'bankAccountId': hdfc.id, 'toBankAccountId': sbi.id, 'amount': 200},
      {'kind': 'bank_add', 'bankAccountId': sbi.id, 'amount': 5},
      {'kind': 'cash_add', 'amount': 20},
    ]) {
      await cashBank.createAdjustment({...a, 'date': saved.invoiceDate, 'description': ''});
    }
    var banks = {for (final b in await cashBank.accounts()) b.name: b.balance};
    expect(banks, {'HDFC Current': 750, 'SBI Savings': 255}); // 1000 + 250 − 300 − 200 ; 50 + 200 + 5
    (cashBalance, cashTxns) = await cashBank.cash();
    expect(cashBalance, 410); // 100 + 40 + 300 − 50 + 20
    final hdfcTxns = await cashBank.accountTransactions(hdfc.id);
    expect(hdfcTxns.map((t) => t.type).toSet(), {'Payment-In', 'Cash Withdraw', 'Transfer Out', 'Opening Balance'});
    expect(hdfcTxns.last.source, 'opening');
    expect((await cashBank.accountTransactions(sbi.id)).firstWhere((t) => t.type == 'Transfer In').name, 'From HDFC Current');

    var dashNow = await DashboardRepository(api).summary();
    expect([dashNow.cashInHand, dashNow.bankBalance], [410, 1005]);

    // Deleting a transfer reverses both legs.
    final transfer = hdfcTxns.firstWhere((t) => t.type == 'Transfer Out');
    await cashBank.deleteAdjustment(transfer.id);
    banks = {for (final b in await cashBank.accounts()) b.name: b.balance};
    expect(banks, {'HDFC Current': 950, 'SBI Savings': 55});

    // Cheque: open until deposited, then it lands in the bank.
    final chequePay = await payments.save(null, {
      'type': 'in',
      'number': await payments.nextNumber('in'),
      'partyId': party.id,
      'paymentDate': saved.invoiceDate,
      'amount': 600,
      'paymentMode': 'cheque',
      'description': '',
    });
    var cheques = await cashBank.cheques();
    expect([cheques.single.status, cheques.single.amount], ['open', 600]);
    expect((await cashBank.accounts()).firstWhere((b) => b.id == sbi.id).balance, 55);
    await cashBank.depositCheque(cheques.single, sbi.id);
    cheques = await cashBank.cheques();
    expect([cheques.single.status, cheques.single.bankAccountId], ['closed', sbi.id]);
    expect((await cashBank.accounts()).firstWhere((b) => b.id == sbi.id).balance, 655);
    await cashBank.reopenCheque(cheques.single);
    expect((await cashBank.accounts()).firstWhere((b) => b.id == sbi.id).balance, 55);
    await payments.delete(chequePay.id);
    expect(await cashBank.cheques(), isEmpty);

    // A sale received by card into HDFC, through the real form.
    final card = InvoiceFormCubit(
      invoices: invoices,
      parties: parties,
      items: items,
      accounts: cashBank,
      firm: firmRepo,
      bus: bus,
      kind: InvoiceKind.sale,
    );
    await card.load();
    expect(card.state.bankAccounts, hasLength(2));
    card
      ..partySelected(card.state.parties.firstWhere((p) => p.id == party.id))
      ..itemSelected(card.state.lines.first.uid, card.state.items.single)
      ..receivedChanged('120')
      ..paymentModeChanged('card');
    await card.save(andNew: false);
    expect(card.state.error, 'Select the bank account.');
    card.bankAccountChanged(hdfc.id);
    await card.save(andNew: false);
    expect(card.state.error, isNull);
    expect((await cashBank.accounts()).firstWhere((b) => b.id == hdfc.id).balance, 1070);
    await expectLater(cashBank.deleteAccount(hdfc.id), throwsA(isA<ApiException>())); // has transactions
    await invoices.delete(card.state.savedId!);
    expect((await cashBank.accounts()).firstWhere((b) => b.id == hdfc.id).balance, 950);

    // ---- loans: 50,000 received into HDFC; an EMI of 4,000 principal + 500 interest from cash;
    // 10,000 more into cash; a 250 charge.
    final loans = LoansRepository(api, bus);
    final hdfcBefore = (await cashBank.accounts()).firstWhere((b) => b.id == hdfc.id).balance;
    final cashBeforeLoan = (await cashBank.cash()).$1;
    final loan = await loans.save(null, {
      'name': 'Shop Loan',
      'lender': 'HDFC',
      'openingBalance': 50000,
      'balanceDate': saved.invoiceDate,
      'bankAccountId': hdfc.id,
      'interestRate': 11.5,
      'termMonths': 36,
    });
    expect([loan.balance, loan.interestRate, loan.termMonths], [50000, 11.5, 36]);
    expect((await cashBank.accounts()).firstWhere((b) => b.id == hdfc.id).balance, hdfcBefore + 50000);
    await loans.addTransaction(loan.id, {'kind': 'payment', 'principal': 4000, 'interest': 500, 'date': saved.invoiceDate});
    await loans.addTransaction(loan.id, {'kind': 'increase', 'principal': 10000, 'date': saved.invoiceDate});
    await loans.addTransaction(loan.id, {'kind': 'charge', 'principal': 250, 'date': saved.invoiceDate, 'bankAccountId': hdfc.id});
    expect((await loans.list()).single.balance, 56250); // 50,000 − 4,000 + 10,000 + 250
    expect((await cashBank.cash()).$1, cashBeforeLoan - 4500 + 10000);
    expect((await cashBank.accounts()).firstWhere((b) => b.id == hdfc.id).balance, hdfcBefore + 50000); // the charge moved no money
    final loanTxns = await loans.transactions(loan.id);
    expect(loanTxns.map((t) => t.kind), ['charge', 'increase', 'payment', 'opening']);
    expect(loanTxns.map((t) => t.balance), [56250, 56000, 46000, 50000]);
    await expectLater(
      loans.addTransaction(loan.id, {'kind': 'payment', 'principal': 99999, 'date': saved.invoiceDate}),
      throwsA(isA<ApiException>()),
    );
    await expectLater(loans.delete(loan.id), throwsA(isA<ApiException>())); // has transactions
    for (final t in loanTxns.where((t) => t.id != null)) {
      await loans.deleteTransaction(t.id!);
    }
    await loans.delete(loan.id);
    expect((await cashBank.cash()).$1, cashBeforeLoan);
    expect((await cashBank.accounts()).firstWhere((b) => b.id == hdfc.id).balance, hdfcBefore);

    // An account with no transactions can be deleted.
    final spare = await cashBank.saveAccount(null, {'name': 'Spare'});
    await cashBank.deleteAccount(spare.id);
    expect((await cashBank.accounts()).length, 2);
    await payments.delete(upi.id);
    await payments.delete(cashPay.id);

    // ---- reports: every report runs, and the figures agree with what the screens showed.
    final reports = ReportsRepository(api);
    final catalog = await reports.catalog();
    expect(catalog.length, greaterThanOrEqualTo(19));
    for (final def in catalog) {
      final data = await reports.run(def.id, from: '${month}01', to: '${month}28', partyId: party.id, bankAccountId: hdfc.id, itemId: item.id);
      expect(data.columns, isNotEmpty, reason: def.id);
      expect((await buildReportPdf(data, firm)).length, greaterThan(500), reason: def.id);
      // Every row only uses declared columns (plus the _bold marker).
      for (final row in data.rows) {
        expect(row.keys.where((k) => k != '_bold').toSet().difference(data.columns.map((c) => c.key).toSet()), isEmpty, reason: def.id);
      }
    }
    num figure(ReportData d, String label) => d.summary.firstWhere((f) => f.label == label).value as num;
    final saleReport = await reports.run('sale', from: '${month}01', to: '${month}28');
    expect([saleReport.rows.single['number'], figure(saleReport, 'Balance')], ['1', 440]);
    final statement = await reports.run('party-statement', partyId: party.id, from: '${month}01', to: '${month}28');
    expect(figure(statement, 'Closing Balance (to receive)'), (await balanceOf(party.id)).abs());
    final cashFlow = await reports.run('cash-flow', from: '${month}01', to: '${month}28');
    expect(figure(cashFlow, 'Closing Cash in hand'), (await cashBank.cash()).$1);
    final bankReport = await reports.run('bank-statement', bankAccountId: hdfc.id, from: '${month}01', to: '${month}28');
    expect(figure(bankReport, 'Closing balance'), (await cashBank.accounts()).firstWhere((b) => b.id == hdfc.id).balance);
    final sheet = await reports.run('balance-sheet');
    expect(figure(sheet, 'Total Assets') - figure(sheet, 'Total Liabilities'), figure(sheet, "Owner's Equity"));
    final stockReport = await reports.run('stock-summary');
    expect(figure(stockReport, 'Stock Value'), 15 * 70);
    await expectLater(reports.run('party-statement'), throwsA(isA<ApiException>())); // needs a party
    await expectLater(reports.run('nope'), throwsA(isA<ApiException>()));

    // ---- utilities: CSV import (with a duplicate and a new category), bulk update.
    final importer = ImportCubit(api, bus, itemImportSpec)
      ..fileChosen(
        toCsv([
          itemImportSpec.headers,
          ['Imported Rice', 'product', 'RICE5', '1006', 'BAG', 'Grains', '650', '520', '5', '40', '10'],
          ['Live Widget', 'product', '', '', '', '', '1', '1', '', '', ''], // already exists
          ['Imported Service', 'service', '', '9968', '', 'Grains', '50', '', '18', '', ''],
          ['Bad Row', 'product', '', '', '', '', 'abc', '', '', '', ''],
        ]),
      );
    expect([importer.state.valid.length, importer.state.invalid.single.line], [3, 5]);
    await importer.import();
    expect(importer.state.created, 2);
    expect(importer.state.serverErrors.single.$1, 3); // reported against line 3 of the file
    expect(importer.state.serverErrors.single.$3, contains('already exists'));
    final imported = (await items.list('all')).firstWhere((i) => i.name == 'Imported Rice');
    expect([imported.categoryName, imported.stockQty, imported.gstRate, imported.itemCode], ['Grains', 40, 5, 'RICE5']);
    expect((await items.categories()).firstWhere((c) => c.name == 'Grains').itemCount, 2);

    final partyImporter = ImportCubit(api, bus, partyImportSpec)
      ..fileChosen('Party Name,Phone,Opening Balance,Balance Type\nImported Party,9811122233,800,pay\nLive Customer,,,\n');
    await partyImporter.import();
    expect([partyImporter.state.created, partyImporter.state.serverErrors.single.$2], [1, 'Live Customer']);
    final importedParty = (await parties.list()).firstWhere((p) => p.name == 'Imported Party');
    expect(importedParty.balance, -800);

    final bulk = BulkUpdateCubit(items, api, bus);
    await bulk.load();
    bulk.edit(imported, (e) => e.copyWith(salePrice: '700', gstRate: () => 12, minStock: '15'));
    await bulk.save();
    expect(bulk.state.error, isNull);
    final updated = (await items.list('all')).firstWhere((i) => i.id == imported.id);
    expect([updated.salePrice, updated.gstRate, updated.minStock, updated.purchasePrice], [700, 12, 15, 520]);
    for (final i in (await items.list('all')).where((i) => i.name.startsWith('Imported'))) {
      await items.delete(i.id);
    }
    await parties.delete(importedParty.id);

    // ---- settings: invoice prefix, defaults, and refusing sales beyond stock.
    var live = await firmRepo.update({
      'settings': {'invoicePrefix': 'INV-', 'defaultCashSale': true, 'blockNegativeStock': true, 'invoiceTerms': 'No returns.'},
    });
    expect([live.settings.invoicePrefix, live.settings.gstEnabled, live.settings.signatureLabel], ['INV-', true, 'Authorized Signatory']);
    expect(await invoices.nextNumber('sale'), 'INV-1'); // a new series starts under the prefix
    expect(await invoices.nextNumber('estimate'), '1'); // other documents are unaffected
    final prefixed = InvoiceFormCubit(
      invoices: invoices,
      parties: parties,
      items: items,
      accounts: cashBank,
      firm: firmRepo,
      bus: bus,
      kind: InvoiceKind.sale,
    );
    await prefixed.load();
    expect([prefixed.state.number, prefixed.state.isCash], ['INV-1', true]);
    prefixed
      ..itemSelected(prefixed.state.lines.first.uid, prefixed.state.items.single)
      ..lineQtyChanged(prefixed.state.lines.first.uid, '999');
    await prefixed.save(andNew: false);
    expect(prefixed.state.error, contains('Not enough stock of Live Widget'));
    expect(await stock(), 15); // nothing was saved
    prefixed.lineQtyChanged(prefixed.state.lines.first.uid, '1');
    await prefixed.save(andNew: false);
    expect(prefixed.state.error, isNull);
    expect(await invoices.nextNumber('sale'), 'INV-2');
    expect((await buildInvoicePdf(await invoices.get(prefixed.state.savedId!), live)).length, greaterThan(1000));
    await invoices.delete(prefixed.state.savedId!);
    await expectLater(
      firmRepo.update({
        'settings': {'invoicePrefix': 'bad prefix!'},
      }),
      throwsA(isA<ApiException>()),
    );
    live = await firmRepo.update({
      'settings': {'invoicePrefix': '', 'defaultCashSale': false, 'blockNegativeStock': false},
    });
    expect(live.settings.invoiceTerms, 'No returns.'); // untouched keys are kept

    // Change password: wrong current password is refused; the new one works for login.
    final auth = AuthRepository(api);
    await expectLater(auth.changePassword(current: 'nope', next: 'NewPassword1'), throwsA(isA<ApiException>()));
    await auth.changePassword(current: 'Password123', next: 'NewPassword1');
    expect((await auth.login(email: 'live$stamp@example.com', password: 'NewPassword1')).email, 'live$stamp@example.com');

    await invoices.delete(invoiceId);
    expect((await items.list('product')).single.stockQty, 20);
    expect((await parties.list()).firstWhere((p) => p.id == party.id).balance, -100); // only opening 100 − payment 200 remains
  });

  test('second batch through the real API: links, split payments, files, journals, companies, backup', () async {
    final api = ApiClient(_MemoryTokens());
    final bus = ChangeBus();
    final auth = AuthRepository(api);
    final parties = PartiesRepository(api, bus);
    final items = ItemsRepository(api, bus);
    final invoices = InvoicesRepository(api, bus);
    final payments = PaymentsRepository(api, bus);
    final cashBank = CashBankRepository(api, bus);
    final firmRepo = FirmRepository(api, bus);
    final files = FilesRepository(api);
    final accounting = AccountingRepository(api, bus);
    final utilities = UtilitiesRepository(api, bus);
    final expenses = ExpensesRepository(api, bus);
    final loans = LoansRepository(api, bus);
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final owner = await auth.register(
      firmName: 'Batch Two $stamp',
      stateCode: '07',
      fullName: 'Owner',
      email: 'b2$stamp@example.com',
      password: 'Password123',
    );
    expect(owner.role, 'owner');
    final hdfc = await cashBank.saveAccount(null, {'name': 'HDFC', 'openingBalance': 1000});
    final party = await parties.save(null, {'name': 'Ravi', 'phone': '9876543210', 'creditLimit': 1000, 'shippingAddress': 'Godown 4'});
    final pen = await items.save(null, {
      'name': 'Pen',
      'unit': 'PCS',
      'salePrice': 100,
      'purchasePrice': 60,
      'openingQty': 100,
      'wholesalePrice': 80,
      'wholesaleMinQty': 10,
    });
    await firmRepo.update({
      'settings': {'dueDatesEnabled': true, 'defaultCreditDays': 0, 'paymentReminderDays': 0, 'gstEnabled': false},
    });

    // ---- split payment, wholesale price, shipping address and the credit-limit confirmation, through the form.
    InvoiceFormCubit newForm() => InvoiceFormCubit(
      invoices: invoices,
      parties: parties,
      items: items,
      accounts: cashBank,
      firm: firmRepo,
      accounting: accounting,
      bus: bus,
      kind: InvoiceKind.sale,
    );
    final form = newForm();
    await form.load();
    final uid = form.state.lines.first.uid;
    form
      ..partySelected(form.state.parties.single)
      ..itemSelected(uid, form.state.items.single)
      ..lineQtyChanged(uid, '20') // wholesale: 20 × 80
      ..dateChanged('2026-01-10') // long overdue, for the reminder below
      ..receivedChanged('300')
      ..addPart();
    final part = form.state.extraParts.single.uid;
    form
      ..partModeChanged(part, 'upi')
      ..partAmountChanged(part, '200');
    expect([form.state.total, form.state.shippingAddress, form.state.extraParts.single.bankAccountId], [1600, 'Godown 4', hdfc.id]);
    expect(form.state.creditLimitWarning, isNotNull); // 1100 unpaid against a limit of 1000
    await form.save(andNew: false);
    expect(form.state.savedId, isNull);
    await form.save(andNew: false, overLimitConfirmed: true);
    expect(form.state.error, isNull);
    var sale = await invoices.get(form.state.savedId!);
    expect(
      [sale.received, sale.balance, sale.paymentLabel, sale.payments.length, sale.shippingAddress, sale.dueDate],
      [500, 1100, 'Cash + UPI', 2, 'Godown 4', '2026-01-10'],
    );
    expect((await cashBank.accounts()).single.balance, 1200);

    // ---- overdue → payment reminder → a payment linked to the invoice.
    final reminder = (await utilities.paymentReminders()).single;
    expect([reminder.name, reminder.overdueAmount, reminder.invoices], ['Ravi', 1100, 1]);
    final pay = PaymentFormCubit(payments, parties, cashBank, PaymentKind.paymentIn, partyId: party.id, invoices: invoices);
    await pay.load();
    expect(pay.state.links.single.due, 1100);
    pay.autoLink(700);
    await pay.save(number: pay.state.number, amount: 1000, description: '');
    expect(pay.state.error, isNull);
    final receipt = await payments.get(pay.state.saved!.id);
    expect([receipt.linkedAmount, receipt.unlinkedAmount, receipt.allocations.single.amount], [700, 300, 700]);
    sale = await invoices.get(sale.id);
    expect([sale.linkedAmount, sale.balance, sale.linkedPayments.single.amount], [700, 400, 700]);
    expect((await parties.get(party.id)).balance, 100); // 1100 unpaid − 1000 received
    expect((await buildPaymentPdf(receipt, await firmRepo.get())).length, greaterThan(1000));
    // The same payment re-opened shows its own link and what the invoice owed without it.
    final editPay = PaymentFormCubit(payments, parties, cashBank, PaymentKind.paymentIn, payment: receipt, invoices: invoices);
    await editPay.load();
    expect([editPay.state.links.single.amount, editPay.state.links.single.due], ['700', 1100]);

    // ---- logo, signature, item image, attachment; every print layout.
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final logo = await files.upload(name: 'logo.png', mimeType: 'image/png', bytes: png);
    var firm = await firmRepo.update({
      'logoFileId': logo.id,
      'signatureFileId': logo.id,
      'settings': {'invoiceTheme': 'modern', 'themeColor': '#0F766E'},
    });
    expect([firm.logoFileId, firm.settings.invoiceTheme], [logo.id, 'modern']);
    expect((await items.save(pen.id, {'imageFileId': logo.id})).imageFileId, logo.id);
    final attachments = AttachmentsCubit(files, ownerType: 'invoice', ownerId: sale.id);
    await attachments.add(name: 'po.png', mimeType: 'image/png', bytes: png);
    expect(attachments.state.items.single.attachmentId, isNotNull);
    expect(await attachments.bytes(attachments.state.items.single), png);
    final logoBytes = await files.bytesOrNull(firm.logoFileId);
    for (final theme in invoiceThemes.keys) {
      final pdf = await buildInvoicePdf(
        sale,
        firm,
        options: PrintOptions.of(firm, logo: logoBytes, signature: logoBytes, theme: theme),
      );
      expect(pdf.length, greaterThan(1000), reason: theme);
    }
    expect((await buildThermalReceiptPdf(sale, firm, logo: logoBytes)).length, greaterThan(1000));

    // ---- currency: the invoice keeps its own rate; the books stay in rupees.
    expect((await accounting.saveCurrency(code: 'USD', symbol: r'$', rate: 80)).single.code, 'USD');
    final usd = newForm();
    await usd.load();
    usd
      ..cashToggled(true)
      ..itemSelected(usd.state.lines.first.uid, usd.state.items.single)
      ..currencyChanged('USD')
      ..linePriceChanged(usd.state.lines.first.uid, '100');
    expect(usd.state.baseTotal, 8000); // the document is typed in dollars: $100 at ₹80
    await usd.save(andNew: false);
    final usdSale = await invoices.get(usd.state.savedId!);
    expect([usdSale.currencyCode, usdSale.exchangeRate, usdSale.total, usdSale.fxTotal], ['USD', 80, 8000, 100]);
    expect((await buildInvoicePdf(usdSale, firm, options: const PrintOptions(currencySymbol: r'$'))).length, greaterThan(1000));

    // ---- expense with GST from a saved expense item.
    await expenses.saveItemDef(null, {'name': 'Courier', 'price': 100, 'gstRate': 18});
    await firmRepo.update({
      'settings': {'gstEnabled': true},
    });
    final exp = ExpenseFormCubit(expenses, cashBank, bus, categoryId: (await expenses.categories()).first.id, firm: firmRepo);
    await exp.load();
    exp
      ..itemDefSelected(exp.state.lines.first.uid, exp.state.itemDefs.single)
      ..roundOffToggled(false);
    await exp.save(andNew: false);
    final savedExpense = await expenses.get(exp.state.savedId!);
    expect([savedExpense.total, savedExpense.taxAmount, savedExpense.lines.single.gstRate], [118, 18, 18]);
    expect((await expenses.itemDefs()).single.total, 118);

    // ---- editing a transfer and a loan entry.
    await cashBank.createAdjustment({'kind': 'cash_add', 'amount': 500, 'date': today});
    final adjustment = (await cashBank.cash()).$2.firstWhere((t) => t.source == 'adjustment');
    final edit = AdjustmentFormCubit(cashBank, kinds: adjustmentKinds.keys.toList(), editId: adjustment.id);
    await edit.load();
    expect([edit.state.kind, edit.state.initialAmount], ['cash_add', '500']);
    edit
      ..kindChanged('cash_to_bank')
      ..bankAccountChanged(hdfc.id);
    await edit.submit(amount: 50, description: 'deposit');
    expect(edit.state.error, isNull);
    expect((await cashBank.accounts()).single.balance, 1250);
    final loan = await loans.save(null, {'name': 'Shop loan', 'openingBalance': 10000, 'balanceDate': today});
    await loans.addTransaction(loan.id, {'kind': 'payment', 'principal': 1000, 'interest': 100, 'date': today});
    final entry = (await loans.transactions(loan.id)).first;
    await loans.updateTransaction(entry.id!, {'kind': 'payment', 'principal': 2500, 'interest': 0, 'date': today});
    expect((await loans.list()).single.balance, 7500);

    // ---- journal entry through its form; the trial balance agrees.
    final furniture = (await accounting.saveLedgerAccount(null, name: 'Furniture', type: 'asset')).single;
    final journal = JournalFormCubit(accounting, cashBank);
    await journal.load();
    journal
      ..accountChanged(journal.state.lines[0].uid, 'ledger:${furniture.id}')
      ..debitChanged(journal.state.lines[0].uid, '400')
      ..accountChanged(journal.state.lines[1].uid, 'bank:${hdfc.id}')
      ..creditChanged(journal.state.lines[1].uid, '400');
    await journal.save();
    expect(journal.state.error, isNull);
    expect([(await accounting.ledgerAccounts()).single.balance, (await cashBank.accounts()).single.balance], [400, 850]);
    final reports = ReportsRepository(api);
    final trial = await reports.run('trial-balance');
    expect(trial.summary[0].value, trial.summary[1].value);
    expect((await reports.run('item-detail', itemId: pen.id)).rows.length, greaterThan(2));
    expect((await reports.run('party-item', from: '2026-01-01', to: '2099-01-01')).rows.single['key'], 'Pen');

    // ---- search, set-up checklist, data check.
    expect((await utilities.search('rav')).map((h) => (h.kind, h.title)), [('party', 'Ravi'), ('invoice', 'Sale 1'), ('payment', 'Payment-In 1')]); // the party, their invoice and their payment
    // One item matches; expenses whose category or note matches are listed after it.
    expect((await utilities.search('pe')).map((h) => h.kind).toSet().difference({'expense'}), {'item'});
    expect((await utilities.setup()).where((s) => s.done).map((s) => s.id), containsAll(['logo', 'party', 'item', 'bank', 'invoice']));
    expect((await utilities.verify()).every((c) => c.ok), isTrue);

    // ---- a salesman's login: sale side only, and their sales carry their name.
    await auth.addMember(fullName: 'Sam', email: 'sam$stamp@example.com', password: 'Password123', role: 'salesman');
    expect((await auth.members()).map((m) => m.role), ['owner', 'salesman']);
    final samApi = ApiClient(_MemoryTokens());
    final sam = await AuthRepository(samApi).login(email: 'sam$stamp@example.com', password: 'Password123');
    expect([sam.role, sam.isSalesman, sam.firmId], ['salesman', true, owner.firmId]);
    await expectLater(ReportsRepository(samApi).catalog(), throwsA(isA<ApiException>()));
    await expectLater(ExpensesRepository(samApi, bus).categories(), throwsA(isA<ApiException>()));
    await expectLater(InvoicesRepository(samApi, bus).list('purchase', from: '2026-01-01', to: '2099-01-01'), throwsA(isA<ApiException>()));
    final samForm = InvoiceFormCubit(
      invoices: InvoicesRepository(samApi, bus),
      parties: PartiesRepository(samApi, bus),
      items: ItemsRepository(samApi, bus),
      accounts: CashBankRepository(samApi, bus),
      firm: FirmRepository(samApi, bus),
      bus: bus,
      kind: InvoiceKind.sale,
    );
    await samForm.load();
    samForm
      ..cashToggled(true)
      ..itemSelected(samForm.state.lines.first.uid, samForm.state.items.single);
    await samForm.save(andNew: false);
    expect(samForm.state.error, isNull);
    final byUser = await reports.run('salesman', from: '2026-01-01', to: '2099-01-01');
    expect(byUser.rows.map((r) => r['name']), ['Owner', 'Sam']);

    // ---- close the books, then re-open.
    await utilities.closeBooks(today);
    expect((await firmRepo.get()).booksLockDate, today);
    await expectLater(cashBank.createAdjustment({'kind': 'cash_add', 'amount': 1, 'date': today}), throwsA(isA<ApiException>()));
    await utilities.closeBooks(null);

    // ---- backup → restore as a new company; start a new year; switch between companies.
    final before = await DashboardRepository(api).summary();
    final backup = await utilities.backup();
    final restored = await utilities.restore(backup, name: 'Restored $stamp');
    final nextYear = await utilities.startNewYear(name: 'Next Year $stamp', startDate: DateTime.now().add(const Duration(days: 1)).toIso8601String().substring(0, 10));
    expect((await auth.companies()).map((c) => c.name), ['Batch Two $stamp', 'Restored $stamp', 'Next Year $stamp']);

    expect((await auth.switchCompany(restored.id)).firmName, 'Restored $stamp');
    final copy = await DashboardRepository(api).summary();
    expect([copy.cashInHand, copy.bankBalance, copy.receivable], [before.cashInHand, before.bankBalance, before.receivable]);
    expect((await utilities.verify()).every((c) => c.ok), isTrue);
    final copiedSale = (await invoices.list('sale', from: '2026-01-01', to: '2099-01-01')).firstWhere((i) => i.total == 1600);
    expect([copiedSale.id == sale.id, copiedSale.balance, copiedSale.linkedAmount], [false, 400, 700]);
    expect((await files.attachments('invoice', copiedSale.id)).single.name, 'po.png');
    expect((await firmRepo.get()).logoFileId, isNotNull);

    expect((await auth.switchCompany(nextYear.id)).firmId, nextYear.id);
    final opening = await DashboardRepository(api).summary();
    expect([opening.cashInHand, opening.bankBalance, opening.receivable], [before.cashInHand, before.bankBalance, before.receivable]);
    expect((await items.list('product')).single.stockQty, 78); // 100 − 20 − 1 − 1
    expect((await loans.list()).single.balance, 7500);
    expect(await invoices.list('sale', from: '2026-01-01', to: '2099-01-01'), isEmpty);
    expect((await accounting.ledgerAccounts()).firstWhere((a) => a.name == 'Furniture').balance, 400);
  });

  test(
    'third batch through the real API: stores, batches, serials, charges, TCS/TDS, points, split and foreign payments, salesmen, locations, backups',
    () async {
      final api = ApiClient(_MemoryTokens());
      final bus = ChangeBus();
      final auth = AuthRepository(api);
      final parties = PartiesRepository(api, bus);
      final items = ItemsRepository(api, bus);
      final invoices = InvoicesRepository(api, bus);
      final payments = PaymentsRepository(api, bus);
      final cashBank = CashBankRepository(api, bus);
      final firmRepo = FirmRepository(api, bus);
      final accounting = AccountingRepository(api, bus);
      final utilities = UtilitiesRepository(api, bus);
      final expenses = ExpensesRepository(api, bus);
      final locations = LocationRepository(api);
      final today = DateTime.now().toIso8601String().substring(0, 10);

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final owner = await auth.register(
        firmName: 'Batch Three $stamp',
        stateCode: '27',
        fullName: 'Owner',
        email: 'b3$stamp@example.com',
        password: 'Password123',
      );
      final hdfc = await cashBank.saveAccount(null, {'name': 'HDFC', 'openingBalance': 0});
      await firmRepo.update({
        'settings': {
          'godownsEnabled': true,
          'batchTrackingEnabled': true,
          'serialTrackingEnabled': true,
          'mrpEnabled': true,
          'cessEnabled': true,
          'billDiscountEnabled': true,
          'additionalChargesEnabled': true,
          'tcsEnabled': true,
          'tdsEnabled': true,
          'loyaltyEnabled': true,
          'partyGroupsEnabled': true,
          'locationTrackingEnabled': true,
          'defaultRoundOff': false,
          'autoBackup': 'daily',
          'autoBackupKeep': 2,
        },
      });
      await accounting.saveCurrency(code: 'USD', symbol: r'$', rate: 80);

      // ---- stores, batches and serial numbers: bought into the warehouse through the form
      final godowns = await items.saveGodown(null, name: 'Warehouse');
      final warehouse = godowns.firstWhere((g) => g.name == 'Warehouse');
      final groups = await parties.saveGroup(null, 'Retailers');
      await parties.save(null, {'name': 'Supplier'});
      final customer = await parties.save(null, {'name': 'Ravi', 'groupId': groups.single.id, 'loyaltyOpening': 50});
      expect([customer.groupName, customer.loyaltyPoints], ['Retailers', 50]);
      final phone = await items.save(null, {'name': 'Phone', 'salePrice': 10000, 'purchasePrice': 8000, 'gstRate': 18, 'cessRate': 1, 'mrp': 12000});
      final syrup = await items.save(null, {'name': 'Syrup', 'salePrice': 100, 'purchasePrice': 60});

      InvoiceFormCubit newForm(InvoiceKind kind) => InvoiceFormCubit(
        invoices: invoices,
        parties: parties,
        items: items,
        accounts: cashBank,
        firm: firmRepo,
        accounting: accounting,
        bus: bus,
        kind: kind,
      );

      final buy = newForm(InvoiceKind.purchase);
      await buy.load();
      expect(buy.state.showGodown, isTrue);
      buy
        ..partySelected(buy.state.parties.firstWhere((p) => p.name == 'Supplier'))
        ..godownChanged(warehouse.id);
      final phoneRow = buy.state.lines.first.uid;
      buy
        ..itemSelected(phoneRow, buy.state.items.firstWhere((i) => i.name == 'Phone'))
        ..lineQtyChanged(phoneRow, '2')
        ..linePriceChanged(phoneRow, '8000')
        ..lineSerialsChanged(phoneRow, 'IM1, IM2');
      final syrupRow = buy.state.lines[1].uid;
      buy
        ..itemSelected(syrupRow, buy.state.items.firstWhere((i) => i.name == 'Syrup'))
        ..lineQtyChanged(syrupRow, '100')
        ..linePriceChanged(syrupRow, '60')
        ..lineBatchChanged(syrupRow, 'B-77')
        ..lineExpiryChanged(syrupRow, '2026-11-30')
        ..tdsRateChanged('1');
      expect(buy.state.doc.cess, 160); // 1% of the phones' ₹16,000
      await buy.save(andNew: false);
      expect(buy.state.error, isNull);
      final purchase = await invoices.get(buy.state.savedId!);
      expect([purchase.godownId, purchase.tdsAmount, purchase.cess], [warehouse.id, 220, 160]);
      expect((await items.batches(syrup.id)).single.quantity, 100);
      expect(await items.serials(phone.id), ['IM1', 'IM2']);
      expect((await items.stockByGodown(syrup.id)).single.name, 'Warehouse');
      await items.transferStock({
        'itemId': syrup.id,
        'fromGodownId': warehouse.id,
        'toGodownId': null,
        'quantity': 30,
        'date': today,
        'batchNo': 'B-77',
      });
      expect({for (final g in await items.stockByGodown(syrup.id)) g.name: g.quantity}, {'Main Store': 30, 'Warehouse': 70});
      expect({for (final g in await items.godowns()) g.name: g.itemCount}['Warehouse'], 2);

      // ---- a sale with discount, a charge, TCS, TDS, points redeemed, a serial and a split payment
      final sale = newForm(InvoiceKind.sale);
      await sale.load();
      sale
        ..partySelected(sale.state.parties.firstWhere((p) => p.name == 'Ravi'))
        ..godownChanged(warehouse.id);
      final r1 = sale.state.lines.first.uid;
      sale
        ..itemSelected(r1, sale.state.items.firstWhere((i) => i.name == 'Phone'))
        ..lineSerialsPicked(r1, ['IM1']);
      final r2 = sale.state.lines[1].uid;
      sale
        ..itemSelected(r2, sale.state.items.firstWhere((i) => i.name == 'Syrup'))
        ..lineQtyChanged(r2, '10')
        ..lineBatchChanged(r2, 'B-77')
        ..billDiscountChanged('10')
        ..addCharge()
        ..chargeAmountChanged(sale.state.extras.charges.single.uid, '100')
        ..tcsRateChanged('1')
        ..tdsRateChanged('1')
        ..loyaltyRedeemChanged('50')
        ..receivedChanged('3000');
      // 11,000 − 10% = 9,900 taxable; GST 1,620 and cess 90 → 11,610; + 100 charge = 11,710; TCS 117.10
      expect([sale.state.doc.taxable, sale.state.total, sale.state.deductions, sale.state.loyaltyEarned], [9900, 11827.1, 149, 117]);
      sale.addPart();
      sale
        ..partModeChanged(sale.state.extraParts.single.uid, 'upi')
        ..partBankAccountChanged(sale.state.extraParts.single.uid, hdfc.id)
        ..partAmountChanged(sale.state.extraParts.single.uid, '2000');
      expect(sale.state.receivedValue, 5000); // 3,000 cash + 2,000 UPI
      await sale.save(andNew: false);
      expect(sale.state.error, isNull);
      final sold = await invoices.get(sale.state.savedId!);
      expect(
        [sold.total, sold.tdsAmount, sold.loyaltyAmount, sold.received, sold.balance, sold.paymentLabel],
        [11827.1, 99, 50, 5000, 6678.1, 'Cash + UPI'],
      );
      expect([sold.tcsAmount, sold.loyaltyEarned, sold.charges.single.$1], [117.1, 117, 'Shipping']);
      expect((await parties.get(customer.id)).loyaltyPoints, 117); // 50 + 117 earned − 50 redeemed
      expect((await parties.get(customer.id)).balance, 6678.1);
      expect(await items.serials(phone.id), ['IM2']);
      expect((await cashBank.accounts()).single.balance, 2000);

      // The same serial cannot be sold twice.
      final again = newForm(InvoiceKind.sale);
      await again.load();
      again
        ..cashToggled(true)
        ..itemSelected(again.state.lines.first.uid, again.state.items.firstWhere((i) => i.name == 'Phone'))
        ..lineSerialsChanged(again.state.lines.first.uid, 'IM1');
      await again.save(andNew: false);
      expect(again.state.error, contains('already been sold'));

      // ---- split Payment-In with a cheque, and a split expense
      final pay = PaymentFormCubit(
        payments,
        parties,
        cashBank,
        PaymentKind.paymentIn,
        partyId: customer.id,
        invoices: invoices,
        accounting: accounting,
      );
      await pay.load();
      pay
        ..addPart()
        ..partModeChanged(pay.state.extraParts.single.uid, 'cheque')
        ..partAmountChanged(pay.state.extraParts.single.uid, '300');
      pay.autoLink(500);
      await pay.save(number: pay.state.number, amount: 500, description: '');
      expect(pay.state.error, isNull);
      final receipt = await payments.get(pay.state.saved!.id);
      expect([receipt.paymentLabel, receipt.parts.length, receipt.linkedAmount], ['Cash + Cheque', 2, 500]);
      final cheque = (await cashBank.cheques()).firstWhere((c) => c.source == 'payment_in');
      expect([cheque.amount, cheque.isOpenCheque], [300, true]);
      await cashBank.depositCheque(cheque, hdfc.id);
      expect((await cashBank.accounts()).single.balance, 2300);

      final cat = (await expenses.categories()).first;
      final exp = ExpenseFormCubit(expenses, cashBank, bus, categoryId: cat.id, firm: firmRepo);
      await exp.load();
      final erow = exp.state.lines.first.uid;
      exp
        ..lineNameChanged(erow, 'Fuel')
        ..lineQtyChanged(erow, '1')
        ..linePriceChanged(erow, '500')
        ..roundOffToggled(false)
        ..addPart();
      exp
        ..partModeChanged(exp.state.extraParts.single.uid, 'upi')
        ..partBankAccountChanged(exp.state.extraParts.single.uid, hdfc.id)
        ..partAmountChanged(exp.state.extraParts.single.uid, '400');
      await exp.save(andNew: false);
      expect(exp.state.error, isNull);
      expect((await expenses.get(exp.state.savedId!)).payments.map((p) => p.mode), ['cash', 'upi']);
      expect((await cashBank.accounts()).single.balance, 1900);

      // ---- a foreign customer: billed in dollars, pays at a different rate, the difference is a gain
      final acme = await parties.save(null, {'name': 'Acme Inc', 'currencyCode': 'USD'});
      final fx = newForm(InvoiceKind.sale);
      await fx.load();
      fx.partySelected(fx.state.parties.firstWhere((p) => p.name == 'Acme Inc'));
      final frow = fx.state.lines.first.uid;
      fx
        ..lineNameChanged(frow, 'Consulting')
        ..lineQtyChanged(frow, '1')
        ..linePriceChanged(frow, '100')
        ..receivedChanged('25');
      expect([fx.state.currencyCode, fx.state.baseTotal, fx.state.balance], ['USD', 8000, 75]);
      await fx.save(andNew: false);
      expect(fx.state.error, isNull);
      final usd = await invoices.get(fx.state.savedId!);
      expect([usd.total, usd.fxTotal, usd.received, usd.fxBalance, usd.balance], [8000, 100, 2000, 75, 6000]);
      final fpay = PaymentFormCubit(payments, parties, cashBank, PaymentKind.paymentIn, partyId: acme.id, invoices: invoices, accounting: accounting);
      await fpay.load();
      fpay.partySelected(fpay.state.parties.firstWhere((p) => p.name == 'Acme Inc'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(fpay.state.links.single.due, 75);
      fpay
        ..autoLink(75)
        ..exchangeRateChanged('82');
      await fpay.save(number: fpay.state.number, amount: 75, description: '');
      expect(fpay.state.error, isNull);
      final fr = await payments.get(fpay.state.saved!.id);
      expect([fr.currencyCode, fr.amount, fr.baseAmount, fr.fxGain], ['USD', 75, 6150, 150]);
      final acme2 = await parties.get(acme.id);
      expect([acme2.balance, acme2.fxBalance], [0, 0]);
      expect((await invoices.get(usd.id)).balance, 0);
      expect((await ReportsRepository(api).run('exchange', from: '2026-01-01', to: '2099-01-01')).summary.single.value, 150);

      // ---- a salesman: only their parties and sales; their location; the owner sees where they are
      await auth.addMember(fullName: 'Sam', email: 'sam$stamp@example.com', password: 'Password123', role: 'salesman');
      final sam = (await auth.members()).firstWhere((m) => m.role == 'salesman');
      final pf = PartyFormCubit(parties, null, auth: auth, accounting: accounting);
      await pf.load();
      expect([pf.state.salesmen.single.fullName, pf.state.groups.single.name, pf.state.currencies.single.code], ['Sam', 'Retailers', 'USD']);
      await parties.save(customer.id, {'assignedUserId': sam.id});

      final samApi = ApiClient(_MemoryTokens());
      final samAuth = AuthRepository(samApi);
      await samAuth.login(email: 'sam$stamp@example.com', password: 'Password123');
      final samParties = PartiesRepository(samApi, bus);
      expect((await samParties.list()).map((p) => p.name), ['Ravi']);
      expect((await InvoicesRepository(samApi, bus).list('sale', from: '2026-01-01', to: '2099-01-01')).map((i) => i.number), [sold.number]);
      final mine = await samParties.save(null, {'name': 'Walk-in Shop'});
      expect(mine.assignedUserId, sam.id);
      final samLocations = LocationRepository(samApi);
      await samLocations.record(const GeoFix(19.07, 72.87, 12));
      await samLocations.record(const GeoFix(19.08, 72.88, 9), context: 'sale', refId: sold.id);
      final here = (await locations.latest()).firstWhere((l) => l.userId == sam.id);
      expect([here.latitude, here.salesToday, here.pointsToday], [19.08, 1, 2]);
      expect((await locations.trail(sam.id, today)).last.ref, contains('Ravi'));
      await expectLater(samLocations.latest(), throwsA(isA<ApiException>()));

      // ---- reports, backups, restore and a new year all agree
      final reports = ReportsRepository(api);
      for (final id in ['godown-stock', 'batch-stock', 'expiry', 'serial', 'tcs', 'tds', 'loyalty', 'trial-balance']) {
        final r = await reports.run(id, from: '2026-01-01', to: '2099-01-01');
        expect(r.rows, isNotEmpty, reason: id);
      }
      final trial = await reports.run('trial-balance');
      expect(trial.summary[0].value, trial.summary[1].value);
      expect((await utilities.verify()).every((c) => c.ok), isTrue);

      var backups = await utilities.createServerBackup();
      expect([backups.single.kind, backups.single.onDrive], ['manual', false]);
      expect((await utilities.driveStatus()).configured, isFalse); // no Google client on this server
      final (_, content) = await utilities.readServerBackup(backups.single.id);
      final restored = await utilities.restore(content, name: 'Restored $stamp');
      final before = await DashboardRepository(api).summary();
      final nextYear = await utilities.startNewYear(name: 'Next $stamp', startDate: DateTime.now().add(const Duration(days: 1)).toIso8601String().substring(0, 10));
      await auth.switchCompany(restored.id);
      final copy = await DashboardRepository(api).summary();
      expect(
        [copy.cashInHand, copy.bankBalance, copy.receivable, copy.payable],
        [before.cashInHand, before.bankBalance, before.receivable, before.payable],
      );
      expect((await utilities.verify()).every((c) => c.ok), isTrue);
      expect((await items.godowns()).map((g) => g.name), ['Main Store', 'Warehouse']);
      await auth.switchCompany(nextYear.id);
      final opening = await DashboardRepository(api).summary();
      expect(
        [opening.cashInHand, opening.bankBalance, opening.receivable, opening.payable],
        [before.cashInHand, before.bankBalance, before.receivable, before.payable],
      );
      final newSyrup = (await items.list('product')).firstWhere((i) => i.name == 'Syrup');
      expect({for (final g in await items.stockByGodown(newSyrup.id)) g.name: g.quantity}, {'Main Store': 30, 'Warehouse': 60}); // 30 moved to the main store; the 10 sold came out of the warehouse
      expect((await items.batches(newSyrup.id)).single.batchNo, 'B-77');
      expect((await parties.list()).firstWhere((p) => p.name == 'Ravi').loyaltyPoints, 117);
      expect(owner.role, 'owner');
    },
  );
}
