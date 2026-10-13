// Split payments everywhere, foreign-currency documents and payments, godowns, batch and serial
// numbers, cess, bill discount, charges, TCS / TDS, loyalty points, party groups and salesmen,
// location tracking and server backups.
import 'dart:async';

import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/core/status.dart';
import 'package:billing_app/data/models/app_user.dart';
import 'package:billing_app/data/models/extras.dart';
import 'package:billing_app/data/models/firm.dart';
import 'package:billing_app/data/models/invoice.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/data/models/party.dart';
import 'package:billing_app/data/models/payment.dart';
import 'package:billing_app/data/models/team_location.dart';
import 'package:billing_app/features/expenses/bloc/expense_form_cubit.dart';
import 'package:billing_app/features/invoices/bloc/invoice_form_cubit.dart';
import 'package:billing_app/features/parties/bloc/parties_bloc.dart';
import 'package:billing_app/features/parties/bloc/party_form_cubit.dart';
import 'package:billing_app/features/payments/bloc/payment_form_cubit.dart';
import 'package:billing_app/features/pos/pos_cubit.dart';
import 'package:billing_app/features/team/team_locations_screen.dart';
import 'package:billing_app/features/team/tracking_cubit.dart';
import 'package:billing_app/features/tools/tools_cubits.dart';
import 'package:billing_app/shared/doc_math.dart';
import 'package:billing_app/shell/nav.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('document maths (the same cases as the server tests)', () {
    test('a bill discount is spread over the lines before tax', () {
      final d = computeDoc(
        const [DocLineInput(gross: 100, discount: 0, gstRate: 18), DocLineInput(gross: 200, discount: 0, gstRate: 18), DocLineInput(gross: 33.33, discount: 0, gstRate: 5)],
        billDiscountAmount: 50,
      );
      expect(d.discountAmount, 50);
      expect(d.lines.fold<num>(0, (s, l) => s + l.billDiscount), closeTo(50, 0.001));
      expect(d.taxable, closeTo(283.33, 0.001));
      expect(d.lines[0].taxable, closeTo(85, 0.001));
      expect(d.lines[0].tax, closeTo(15.3, 0.001));
    });

    test('a percentage wins over an amount', () {
      final d = computeDoc(const [DocLineInput(gross: 1000, discount: 0)], billDiscountPct: 10, billDiscountAmount: 999);
      expect([d.discountAmount, d.total], [100, 900]);
    });

    test('charges come after tax, TCS on the bill value, TDS on the taxable value and leaves the total alone', () {
      final d = computeDoc(const [DocLineInput(gross: 1000, discount: 0, gstRate: 18)], roundOff: true, charges: 50, tcsRate: 1, tdsRate: 2);
      expect([d.subtotal, d.charges, d.tcs, d.total, d.roundOff, d.tds], [1180, 50, 12.3, 1242, -0.3, 20]);
    });

    test('cess is charged on the taxable value, on top of or inside the price', () {
      final out = computeDoc(const [DocLineInput(gross: 1000, discount: 0, gstRate: 28, cessRate: 12)]);
      expect([out.lines.single.taxable, out.lines.single.tax, out.lines.single.cess, out.total], [1000, 280, 120, 1400]);
      final inside = computeDoc(const [DocLineInput(gross: 1400, discount: 0, gstRate: 28, cessRate: 12)], pricesIncludeTax: true);
      expect([inside.lines.single.taxable, inside.lines.single.tax, inside.lines.single.cess, inside.total], [1000, 280, 120, 1400]);
    });
  });

  group('invoice form: the optional parts', () {
    late FakeInvoicesRepository invoices;
    late FakeItemsRepository items;

    Future<InvoiceFormCubit> form({
      Map<String, dynamic> settings = const {},
      Map<String, dynamic> party = const {},
      InvoiceKind kind = InvoiceKind.sale,
      List<(String, String, num)> currencies = const [],
    }) async {
      final bus = ChangeBus();
      invoices = FakeInvoicesRepository(bus);
      items = FakeItemsRepository([Item.fromJson({...itemJson('i1', 'Phone', gstRate: 18), 'cessRate': 1, 'mrp': 130})], bus);
      final c = InvoiceFormCubit(
        invoices: invoices,
        parties: FakePartiesRepository([Party.fromJson({...partyJson('a', 'Test Customer', 500), ...party})], bus),
        items: items,
        accounts: FakeCashBankRepository(),
        firm: FakeFirmRepository(settings: settings),
        accounting: FakeAccountingRepository(currencyList: currencies),
        bus: bus,
        kind: kind,
      );
      await c.load();
      return c;
    }

    void fill(InvoiceFormCubit c, {String qty = '10'}) {
      c.partySelected(c.state.parties.first);
      final uid = c.state.lines.first.uid;
      c
        ..itemSelected(uid, c.state.items.first)
        ..lineQtyChanged(uid, qty);
    }

    test('bill discount, charges and TCS change the total and are sent', () async {
      final c = await form(settings: {'billDiscountEnabled': true, 'additionalChargesEnabled': true, 'tcsEnabled': true, 'defaultRoundOff': false});
      fill(c); // 10 × 100 + 18% = 1180
      c
        ..billDiscountChanged('10') // −100 before tax → 900 + 162 = 1062
        ..addCharge();
      final charge = c.state.extras.charges.single;
      expect(charge.name, 'Shipping'); // the first name from settings
      c
        ..chargeAmountChanged(charge.uid, '50')
        ..tcsRateChanged('1');
      expect([c.state.doc.discountAmount, c.state.doc.subtotal, c.state.doc.tcs, c.state.total], [100, 1062, 11.12, 1123.12]);
      await c.save(andNew: false);
      final body = invoices.saved.single;
      expect([body['discountPct'], body['tcsRate']], [10, 1]);
      expect(body['charges'], [
        {'name': 'Shipping', 'amount': 50},
      ]);
    });

    test('a bill discount can be an amount instead, and is validated', () async {
      final c = await form(settings: {'billDiscountEnabled': true});
      fill(c);
      c
        ..billDiscountModeChanged(false)
        ..billDiscountChanged('80');
      expect(c.state.doc.discountAmount, 80);
      c.billDiscountChanged('abc');
      expect(c.validate(), 'Enter a valid bill discount.');
      c
        ..billDiscountModeChanged(true)
        ..billDiscountChanged('150');
      expect(c.validate(), 'The bill discount must be between 0 and 100%.');
    });

    test('TDS reduces what is left to pay, not the total; cash received is capped by it', () async {
      final c = await form(settings: {'tdsEnabled': true, 'defaultRoundOff': false});
      fill(c); // total 1180, taxable 1000
      c.tdsRateChanged('2'); // 20 held back
      expect([c.state.total, c.state.deductions, c.state.payable, c.state.balance], [1180, 20, 1160, 1160]);
      c.receivedInFullToggled(true);
      expect([c.state.receivedValue, c.state.balance], [1160, 0]);
      await c.save(andNew: false);
      expect([invoices.saved.single['tdsRate'], invoices.saved.single['received']], [2, 1160]);
    });

    test('loyalty points: shows what they are worth, what the bill earns, and refuses too many', () async {
      final c = await form(
        settings: {'loyaltyEnabled': true, 'loyaltyEarnPer': 100, 'loyaltyPointValue': 1, 'defaultRoundOff': false},
        party: {'loyaltyPoints': 50},
      );
      fill(c);
      expect(c.state.showLoyalty, isTrue);
      expect([c.state.loyaltyAvailable, c.state.loyaltyEarned], [50, 11]); // 1180 → 11 points
      c.loyaltyRedeemChanged('30');
      expect([c.state.loyaltyAmount, c.state.deductions, c.state.balance, c.state.loyaltyEarned], [30, 30, 1150, 11]);
      c.loyaltyRedeemChanged('80');
      expect(c.validate(), 'The customer has only 50 loyalty points.');
      c.loyaltyRedeemChanged('30');
      await c.save(andNew: false);
      expect(invoices.saved.single['loyaltyRedeem'], 30);

      final cash = await form(settings: {'loyaltyEnabled': true});
      expect(cash.state.showLoyalty, isFalse); // needs a saved party
    });

    test('serial numbers: one per unit, picked from stock on a sale', () async {
      final c = await form(settings: {'serialTrackingEnabled': true});
      fill(c, qty: '2');
      final uid = c.state.lines.first.uid;
      expect(await c.serialsOf('i1'), ['IM1', 'IM2', 'IM3']);
      c.lineSerialsChanged(uid, 'IM1');
      expect(c.validate(), 'Row 1: enter one serial number per unit (quantity 2, serial numbers 1).');
      c.lineSerialsPicked(uid, ['IM1', 'IM3']);
      expect([c.state.lines.first.serialNos, c.state.lines.first.qty], ['IM1, IM3', '2']);
      expect(c.validate(), isNull);
      c.lineSerialsPicked(uid, ['IM2']); // picking sets the quantity: one per unit
      expect(c.state.lines.first.qty, '1');
      await c.save(andNew: false);
      expect((invoices.saved.single['lines'] as List).single['serialNos'], 'IM2');
    });

    test('batches: picked from stock, with expiry and MRP, sent only when switched on', () async {
      final c = await form(settings: {'batchTrackingEnabled': true, 'mrpEnabled': true, 'godownsEnabled': true});
      fill(c, qty: '5');
      final uid = c.state.lines.first.uid;
      expect(c.state.lines.first.mrp, '130'); // from the item
      c.godownChanged('g1');
      final batches = await c.batchesOf('i1');
      expect(items.lastBatchGodown, 'g1'); // batches of the store chosen on the bill
      c.lineBatchPicked(uid, batches.first);
      final line = c.state.lines.first;
      expect([line.batchNo, line.expiryDate, line.mrp], ['B-77', '2026-11-30', '120']);
      await c.save(andNew: false);
      final sent = (invoices.saved.single['lines'] as List).single as Map;
      expect([sent['batchNo'], sent['expiryDate'], sent['mrp']], ['B-77', '2026-11-30', 120]);
      expect(invoices.saved.single['godownId'], 'g1');

      final off = await form();
      fill(off);
      await off.save(andNew: false);
      final plain = (invoices.saved.single['lines'] as List).single as Map;
      expect(plain.keys, isNot(containsAll(['batchNo', 'mrp'])));
      expect(invoices.saved.single.containsKey('godownId'), isFalse);
    });

    test('the store is only offered with godowns on and more than the main store', () async {
      expect((await form(settings: {'godownsEnabled': true})).state.showGodown, isTrue);
      expect((await form()).state.showGodown, isFalse);
    });

    test('cess is added next to GST when switched on', () async {
      final c = await form(settings: {'cessEnabled': true, 'defaultRoundOff': false});
      fill(c);
      expect(c.state.lines.first.cessRate, 1);
      expect([c.state.doc.taxable, c.state.doc.tax, c.state.doc.cess, c.state.total], [1000, 190, 10, 1190]);
      await c.save(andNew: false);
      expect(((invoices.saved.single['lines'] as List).single as Map)['cessRate'], 1);
    });

    test('a foreign party is billed in its currency: amounts are in it, the rupee total is shown, and it is sent that way', () async {
      final c = await form(party: {'currencyCode': 'USD'}, currencies: [('USD', r'$', 80)], settings: {'defaultRoundOff': false});
      c.partySelected(c.state.parties.first);
      expect([c.state.currencyCode, c.state.exchangeRate], ['USD', '80']);
      final uid = c.state.lines.first.uid;
      c
        ..lineNameChanged(uid, 'Consulting')
        ..lineQtyChanged(uid, '1')
        ..linePriceChanged(uid, '100')
        ..receivedChanged('25');
      expect([c.state.total, c.state.baseTotal, c.fmtOf(c.state.total), c.state.balance], [100, 8000, r'$ 100.00', 75]);
      await c.save(andNew: false);
      final body = invoices.saved.single;
      expect([body['currencyCode'], body['exchangeRate'], body['received']], ['USD', 80, 25]);
    });

    test('credit limit uses rupees for a foreign document', () async {
      final c = await form(party: {'currencyCode': 'USD', 'creditLimit': 5000}, currencies: [('USD', r'$', 80)], settings: {'defaultRoundOff': false});
      c.partySelected(c.state.parties.first);
      final uid = c.state.lines.first.uid;
      c
        ..lineNameChanged(uid, 'Consulting')
        ..lineQtyChanged(uid, '1')
        ..linePriceChanged(uid, '100'); // $100 = ₹8,000 against a limit of ₹5,000
      expect(c.state.creditLimitWarning, contains('over the credit limit'));
    });

    test('a purchase takes TCS and TDS, but a return does not', () async {
      final c = await form(settings: {'tcsEnabled': true, 'tdsEnabled': true}, kind: InvoiceKind.purchase);
      expect([c.state.showTcs, c.state.showTds], [true, true]);
      expect((await form(settings: {'tcsEnabled': true}, kind: InvoiceKind.creditNote)).state.showTcs, isFalse);
    });

    test('editing restores the extras: charges, discount, TCS, loyalty and store', () async {
      final c = await form(settings: {'billDiscountEnabled': true, 'additionalChargesEnabled': true, 'tcsEnabled': true, 'godownsEnabled': true, 'loyaltyEnabled': true});
      invoices.invoices = [
        Invoice.fromJson({
          ...invoiceJson('v9', '9', 'Test Customer', 1000, 500),
          'discountPct': 10,
          'discountAmount': 100,
          'charges': [
            {'name': 'Packaging', 'amount': 30},
          ],
          'tcsRate': 1,
          'tdsRate': 0,
          'godownId': 'g1',
          'loyaltyRedeemed': 20,
          'loyaltyEarned': 5,
          'loyaltyAmount': 20,
          'balance': 480,
        }),
      ];
      final bus = ChangeBus();
      final e = InvoiceFormCubit(
        invoices: invoices,
        parties: FakePartiesRepository([Party.fromJson({...partyJson('a', 'Test Customer', 500), 'loyaltyPoints': 5})], bus),
        items: items,
        accounts: FakeCashBankRepository(),
        firm: FakeFirmRepository(settings: {'billDiscountEnabled': true, 'additionalChargesEnabled': true, 'tcsEnabled': true, 'godownsEnabled': true, 'loyaltyEnabled': true}),
        bus: bus,
        kind: InvoiceKind.sale,
        invoiceId: 'v9',
      );
      await e.load();
      final x = e.state.extras;
      expect([x.billDiscount, x.billDiscountIsPct, x.charges.single.name, x.charges.single.amount, x.tcsRate, x.godownId, x.loyaltyRedeem], ['10', true, 'Packaging', '30', '1', 'g1', '20']);
      // Points this bill used are available again while it is being changed (5 held + 20 redeemed − 5 earned).
      expect(e.state.loyaltyAvailable, 20);
      expect(c.state.loadStatus, LoadStatus.success);
    });
  });

  group('split payments and foreign currency', () {
    test('Payment-In: parts add up to the amount, the first takes the rest, and they are sent', () async {
      final payments = FakePaymentsRepository();
      final c = PaymentFormCubit(payments, FakePartiesRepository([Party.fromJson(partyJson('a', 'Test Customer', 500))]), FakeCashBankRepository(), PaymentKind.paymentIn, partyId: 'a');
      await c.load();
      c.addPart();
      final uid = c.state.extraParts.single.uid;
      expect(c.state.extraParts.single.mode, 'bank');
      c
        ..partModeChanged(uid, 'upi')
        ..partBankAccountChanged(uid, 'b1')
        ..partAmountChanged(uid, '300');
      await c.save(number: '2', amount: 1000, description: '');
      expect(payments.saved.single['parts'], [
        {'mode': 'cash', 'bankAccountId': null, 'amount': 700},
        {'mode': 'upi', 'bankAccountId': 'b1', 'amount': 300},
      ]);

      c.partAmountChanged(uid, '1000');
      await c.save(number: '3', amount: 1000, description: '');
      expect(c.state.error, contains('add up to the whole amount'));
      c
        ..partAmountChanged(uid, '')
        ..partBankAccountChanged(uid, null);
      await c.save(number: '3', amount: 1000, description: '');
      expect(c.state.error, 'Enter the amount of each payment type, or remove the empty one.');
    });

    test('a foreign payment settles only invoices in that currency, and is sent with its rate', () async {
      final payments = FakePaymentsRepository();
      final inv = FakeInvoicesRepository()
        ..unpaidInvoices = [
          InvoiceSummary.fromJson({...invoiceJson('r1', 'R1', 'Acme', 5000, 0, partyId: 'f'), 'balance': 5000}),
          InvoiceSummary.fromJson({...invoiceJson('d1', 'D1', 'Acme', 8000, 2000, partyId: 'f'), 'currencyCode': 'USD', 'fxTotal': 100, 'fxBalance': 75, 'balance': 6000}),
        ];
      final c = PaymentFormCubit(
        payments,
        FakePartiesRepository([Party.fromJson({...partyJson('f', 'Acme Inc', 6000), 'currencyCode': 'USD'})]),
        FakeCashBankRepository(),
        PaymentKind.paymentIn,
        partyId: 'f',
        invoices: inv,
        accounting: FakeAccountingRepository(currencyList: [('USD', r'$', 80)]),
      );
      await c.load();
      expect([for (final l in c.state.links) l.number], ['R1']); // rupee payment: the rupee invoice only
      c.partySelected(c.state.parties.single);
      await Future<void>.delayed(Duration.zero);
      expect([c.state.currencyCode, c.state.exchangeRate, [for (final l in c.state.links) l.number], c.state.links.single.due], ['USD', '80', ['D1'], 75]);
      c.autoLink(75);
      c.exchangeRateChanged('82');
      expect(c.state.baseOf(75), 6150);
      await c.save(number: '9', amount: 75, description: '');
      final body = payments.saved.single;
      expect([body['currencyCode'], body['exchangeRate'], body['amount']], ['USD', 82, 75]);
      expect(body['allocations'], [
        {'invoiceId': 'd1', 'amount': 75},
      ]);
      c.exchangeRateChanged('');
      await c.save(number: '10', amount: 75, description: '');
      expect(c.state.error, 'Enter the exchange rate for USD.');
    });

    test('expense: split payment types', () async {
      final repo = FakeExpensesRepository();
      final c = ExpenseFormCubit(repo, FakeCashBankRepository(), ChangeBus(), categoryId: 'x1');
      await c.load();
      final uid = c.state.lines.first.uid;
      c
        ..lineNameChanged(uid, 'Fuel')
        ..lineQtyChanged(uid, '1')
        ..linePriceChanged(uid, '500')
        ..roundOffToggled(false)
        ..addPart();
      final part = c.state.extraParts.single.uid;
      c
        ..partModeChanged(part, 'upi')
        ..partBankAccountChanged(part, 'b1')
        ..partAmountChanged(part, '400');
      await c.save(andNew: false);
      expect(repo.saved.single['payments'], [
        {'mode': 'cash', 'bankAccountId': null, 'amount': 100},
        {'mode': 'upi', 'bankAccountId': 'b1', 'amount': 400},
      ]);
    });

    test('POS: split payment types', () async {
      final invoices = FakeInvoicesRepository();
      final c = PosCubit(invoices, FakeItemsRepository([Item.fromJson(itemJson('i1', 'Sample Item', gstRate: 18))]), FakeCashBankRepository(), ChangeBus());
      await c.load();
      c
        ..add(c.state.items.first) // ₹118
        ..addPart();
      final uid = c.state.extraParts.single.uid;
      c
        ..partModeChanged(uid, 'upi')
        ..partBankAccountChanged(uid, 'b1')
        ..partAmountChanged(uid, '100');
      await c.save(print: false);
      expect(invoices.saved.single['payments'], [
        {'mode': 'cash', 'bankAccountId': null, 'amount': 18},
        {'mode': 'upi', 'bankAccountId': 'b1', 'amount': 100},
      ]);
      expect(c.state.extraParts, isEmpty); // the next bill starts with one payment type
    });
  });

  group('parties', () {
    test('the form offers groups, salesmen and currencies, and sends the choices', () async {
      final repo = FakePartiesRepository([]);
      final c = PartyFormCubit(repo, null, auth: FakeAuthRepository(), accounting: FakeAccountingRepository(currencyList: [('USD', r'$', 80)]));
      await c.load();
      expect([for (final g in c.state.groups) g.name], ['Retailers', 'Wholesalers']);
      expect([for (final m in c.state.salesmen) m.fullName], ['Sam Salesman']); // only salesmen are offered
      expect(c.state.currencies.single.code, 'USD');
      c
        ..groupChanged('pg1')
        ..salesmanChanged('u3')
        ..currencyChanged('USD');
      await c.save({'name': 'Acme'}, andNew: false);
      expect([repo.saved.single['groupId'], repo.saved.single['assignedUserId'], repo.saved.single['currencyCode']], ['pg1', 'u3', 'USD']);
    });

    test('a salesman cannot list users; the form still works without that choice', () async {
      final c = PartyFormCubit(FakePartiesRepository([]), null, auth: _NoUsersAuth(), accounting: FakeAccountingRepository());
      await c.load();
      expect([c.state.salesmen, c.state.groups.length], [isEmpty, 2]);
    });

    test('the list filters by group', () async {
      final repo = FakePartiesRepository([
        Party.fromJson({...partyJson('a', 'Ravi', 100), 'groupId': 'pg1', 'groupName': 'Retailers'}),
        Party.fromJson({...partyJson('b', 'Mehta', 200), 'groupId': 'pg2', 'groupName': 'Wholesalers'}),
        Party.fromJson(partyJson('c', 'Walk-in', 0)),
      ]);
      final bloc = PartiesBloc(repo, ChangeBus())..add(const PartiesRequested());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.visible, hasLength(3));
      bloc.add(const PartiesGroupChanged('pg2'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.visible.single.name, 'Mehta');
      await bloc.close();
    });
  });

  group('location tracking', () {
    Firm firm(bool on) => Firm.fromJson(firmJson(settings: {'locationTrackingEnabled': on}));

    test('checks in when switched on, stops when switched off, and records where a sale was saved', () async {
      final repo = FakeLocationRepository();
      final firms = StreamController<Firm?>();
      final c = TrackingCubit(repo, firms.stream, interval: const Duration(milliseconds: 40));
      expect(c.state.status, TrackingStatus.off);

      firms.add(firm(true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect([c.state.status, repo.sent.single.$2], [TrackingStatus.active, 'ping']);

      await c.recordSaved('sale', 'inv-1');
      expect(repo.sent.last, (const GeoFix(19.07, 72.87, 10), 'sale', 'inv-1'));

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(repo.sent.where((s) => s.$2 == 'ping').length, greaterThan(2)); // regular check-ins

      firms.add(firm(false));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final count = repo.sent.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect([c.state.status, repo.sent.length], [TrackingStatus.off, count]);
      await c.recordSaved('sale', 'inv-2');
      expect(repo.sent.length, count); // nothing is recorded while it is off
      await c.close();
      await firms.close();
    });

    test('when the device will not share its location the user is told, and nothing is sent', () async {
      final repo = FakeLocationRepository(fix: null);
      final c = TrackingCubit(repo, const Stream.empty(), initial: firm(true));
      await Future<void>.delayed(Duration.zero);
      expect([c.state.status, repo.sent], [TrackingStatus.denied, isEmpty]);
      await c.close();
    });

    test('signing out (no company) switches it off', () async {
      final repo = FakeLocationRepository();
      final firms = StreamController<Firm?>();
      final c = TrackingCubit(repo, firms.stream, initial: firm(true));
      await Future<void>.delayed(Duration.zero);
      expect(c.state.status, TrackingStatus.active);
      firms.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.status, TrackingStatus.off);
      await c.close();
      await firms.close();
    });

    test('times and map links read well', () {
      final now = DateTime(2026, 10, 12, 15, 0);
      expect([agoText(now.subtract(const Duration(seconds: 20)), now: now), agoText(now.subtract(const Duration(minutes: 5)), now: now), agoText(now.subtract(const Duration(hours: 3)), now: now)],
          ['just now', '5 min ago', '3 h ago']);
      expect(mapUri(19.07, 72.87).toString(), 'https://www.google.com/maps/search/?api=1&query=19.07,72.87');
    });
  });

  group('settings, menus and backups', () {
    test('every new setting survives a round trip', () {
      const s = FirmSettings(
        godownsEnabled: true, batchTrackingEnabled: true, serialTrackingEnabled: true, mrpEnabled: true, cessEnabled: true, billDiscountEnabled: true,
        additionalChargesEnabled: true, chargeNames: ['Freight'], tcsEnabled: true, tdsEnabled: true, loyaltyEnabled: true, loyaltyEarnPer: 50, loyaltyPointValue: 2,
        partyGroupsEnabled: true, salesmanOwnDataOnly: false, locationTrackingEnabled: true, autoBackup: 'weekly', autoBackupKeep: 3,
      );
      expect(FirmSettings.fromJson(s.toJson()), s);
      final defaults = FirmSettings.fromJson(const {});
      expect([defaults.salesmanOwnDataOnly, defaults.godownsEnabled, defaults.autoBackup, defaults.chargeNames], [true, false, 'off', ['Shipping', 'Packaging']]);
    });

    test('the menu shows what is switched on', () {
      AppUser user(String role) => AppUser(id: 'u', email: 'e', fullName: 'n', firmId: 'f', firmName: 'F', role: role);
      List<String> utilities(String role, FirmSettings s) => [for (final c in navFor(user(role), s).firstWhere((n) => n.label == 'Utilities').children) c.label];
      const on = FirmSettings(godownsEnabled: true, partyGroupsEnabled: true, locationTrackingEnabled: true);
      expect(utilities('owner', on), containsAll(['Godowns', 'Party Groups', 'Team Locations']));
      expect(utilities('accountant', on), isNot(contains('Team Locations'))); // admins only
      expect(utilities('owner', const FirmSettings()), isNot(contains('Godowns')));
    });

    test('server backups and the Drive link', () async {
      final repo = FakeUtilitiesRepository();
      expect([for (final b in await repo.serverBackups()) (b.kind, b.onDrive, b.driveError)], [('auto', true, null), ('manual', false, 'token expired')]);

      final drive = DriveCubit(repo);
      await drive.load();
      expect([drive.state?.configured, drive.state?.connected], [true, false]);
      repo.drive = const DriveStatus(configured: true, connected: true, email: 'me@example.com');
      await drive.load();
      expect(drive.state?.email, 'me@example.com');
      await drive.disconnect();
      expect(drive.state?.connected, isFalse);
      expect(await drive.authUrl(), startsWith('https://accounts.google.com/'));
    });
  });
}

/// A login that is not allowed to list users, like a salesman's.
class _NoUsersAuth extends FakeAuthRepository {
  @override
  Future<List<Member>> members() async => throw Exception('forbidden');
}

extension on InvoiceFormCubit {
  String fmtOf(num v) => state.fmt(v);
}
