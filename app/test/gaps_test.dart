// The fifth batch: linking payments from an invoice, credit-limit modes, expense supplier state,
// search results for payments and expenses, receipt printer extras, zones on the team map.
import 'dart:typed_data';

import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/data/models/extras.dart';
import 'package:billing_app/data/models/firm.dart';
import 'package:billing_app/data/models/invoice.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/data/models/party.dart';
import 'package:billing_app/data/models/team_location.dart';
import 'package:billing_app/core/status.dart';
import 'package:billing_app/features/expenses/bloc/expense_form_cubit.dart';
import 'package:billing_app/features/invoices/bloc/invoice_form_cubit.dart';
import 'package:billing_app/features/payments/link_payments_dialog.dart';
import 'package:billing_app/features/printing/pdf_documents.dart';
import 'package:billing_app/features/printing/thermal/direct_print.dart';
import 'package:billing_app/features/printing/thermal/escpos.dart';
import 'package:billing_app/features/printing/thermal/raster.dart';
import 'package:billing_app/features/search/quick_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'support/fakes.dart';

/// Whether [needle] occurs in [haystack] as a run of bytes.
bool hasBytes(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var j = 0;
    while (j < needle.length && haystack[i + j] == needle[j]) {
      j++;
    }
    if (j == needle.length) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('linking payments from the invoice', () {
    test('shows what is already linked, fills oldest first, and saves the amounts', () async {
      final repo = FakePaymentsRepository();
      final c = LinkPaymentsCubit(repo, 'i1');
      await c.load();
      expect([c.state.due, c.state.linked, c.state.remaining, c.state.amounts], [1000, 200, 800, {'p2': '200'}]);

      c.fill();
      expect(c.state.amounts, {'p1': '600', 'p2': '400'});
      expect([c.state.remaining, c.state.problem], [0, isNull]);

      await c.save();
      expect([repo.linked, c.state.saved], [{'p1': 600, 'p2': 400}, true]);
      await c.close();
    });

    test('refuses more than the invoice needs or the payment has', () async {
      final repo = FakePaymentsRepository();
      final c = LinkPaymentsCubit(repo, 'i1');
      await c.load();
      c.amountChanged('p1', '650');
      expect(c.state.problem, contains('Receipt 7 only has'));
      c.amountChanged('p1', '600');
      c.amountChanged('p2', '500');
      expect(c.state.problem, contains('more than is left to pay'));
      await c.save();
      expect(repo.linked, isNull);
      await c.close();
    });
  });

  group('credit limit', () {
    Future<InvoiceFormCubit> form(InvoiceKind kind, {String mode = 'warn'}) async {
      final bus = ChangeBus();
      final cubit = InvoiceFormCubit(
        invoices: FakeInvoicesRepository(bus),
        parties: FakePartiesRepository([Party.fromJson({...partyJson('a', 'Test Customer', 500), 'creditLimit': 1000})], bus),
        items: FakeItemsRepository([Item.fromJson(itemJson('i1', 'Sample Item'))], bus),
        accounts: FakeCashBankRepository(),
        firm: FakeFirmRepository(settings: {'creditLimitMode': mode}),
        accounting: FakeAccountingRepository(),
        bus: bus,
        kind: kind,
      );
      await cubit.load();
      cubit.partySelected(cubit.state.parties.first);
      final uid = cubit.state.lines.first.uid;
      cubit
        ..itemSelected(uid, cubit.state.items.first)
        ..lineQtyChanged(uid, '10');
      return cubit;
    }

    test('an order or a challan that would go past the limit warns too', () async {
      for (final kind in [InvoiceKind.of('sale_order'), InvoiceKind.of('delivery_challan')]) {
        final c = await form(kind);
        expect(c.state.creditLimitWarning, contains('would owe'), reason: kind.type);
        await c.close();
      }
      final estimate = await form(InvoiceKind.of('estimate'));
      expect(estimate.state.creditLimitWarning, isNull);
      await estimate.close();
    });

    test('in "refuse" mode the sale is not saved and says why, without asking', () async {
      final c = await form(InvoiceKind.sale, mode: 'block');
      await c.save(andNew: false);
      expect([c.state.submitStatus, c.state.creditPrompt], [SubmitStatus.failure, 0]);
      expect(c.state.error, contains('Take a payment first'));
      await c.save(andNew: false, overLimitConfirmed: true);
      expect(c.state.submitStatus, SubmitStatus.failure); // confirming does not get round it
      await c.close();
    });
  });

  test('expense: a supplier GSTIN sets the supplier state, and both are saved', () async {
    final repo = FakeExpensesRepository();
    final c = ExpenseFormCubit(repo, FakeCashBankRepository(), ChangeBus(), categoryId: 'x4');
    await c.load();
    c.supplierGstinChanged('29aaaaa1111a1z6');
    expect([c.state.supplierGstin, c.state.supplierState], ['29AAAAA1111A1Z6', '29']);
    c.supplierStateChanged('07');
    expect(c.state.supplierState, '07');
    c.supplierGstinChanged('zz'); // not a state code: the chosen state is kept
    expect(c.state.supplierState, '07');
    await c.close();
  });

  test('search results for payments and expenses open the right screen', () {
    expect(searchHitPath(const SearchHit(kind: 'payment', id: 'p1', title: '', type: 'in')), '/payment-in/p1/receipt');
    expect(searchHitPath(const SearchHit(kind: 'payment', id: 'p2', title: '', type: 'out')), '/payment-out/p2/receipt');
    expect(searchHitPath(const SearchHit(kind: 'expense', id: 'e1', title: '')), '/expenses/e1/edit');
  });

  group('receipt printer extras', () {
    final firm = Firm.fromJson(firmJson(settings: {'upiId': 'shop@upi', 'upiQrOnInvoice': true}));
    Invoice bill([Map<String, dynamic> extra = const {}]) => Invoice.fromJson({...gstInvoiceJson(), 'balance': 1000, ...extra});

    test('a code page is selected and accented letters are sent as its bytes', () {
      final plain = EscPos(columns: 32)..text('Café ₹5');
      expect(String.fromCharCodes(plain.toBytes().skip(2)), contains('Cafe Rs.5'));
      final cp = EscPos(columns: 32, codePage: 'cp437')..text('Café ₹5');
      expect(hasBytes(cp.toBytes(), [0x1B, 0x74, 0x00]), isTrue); // ESC t 0
      expect(hasBytes(cp.toBytes(), [0x43, 0x61, 0x66, 0x82, 0x20, 0x52, 0x73, 0x2E, 0x35]), isTrue); // é is 0x82 in CP437
      final w = EscPos(columns: 32, codePage: 'cp1252')..text('É€');
      expect(hasBytes(w.toBytes(), [0x1B, 0x74, 16]) && hasBytes(w.toBytes(), [0xC9, 0x80]), isTrue);
    });

    test('lines still fit the paper with a code page', () {
      final p = EscPos(columns: 32, codePage: 'cp858')..pair('Crème brûlée', '12.00');
      final lines = String.fromCharCodes(p.toBytes()).split('\n').where((l) => l.contains('12.00'));
      expect(lines.single.replaceAll(RegExp(r'[\x00-\x1F].'), '').length, lessThanOrEqualTo(34));
    });

    test('the drawer is kicked last, only when asked', () {
      final without = buildReceiptBytes(bill(), firm);
      final with_ = buildReceiptBytes(bill(), firm, options: const ReceiptOptions(openDrawer: true));
      expect(hasBytes(without, [0x1B, 0x70]), isFalse);
      expect(with_.sublist(with_.length - 10), [0x1B, 0x70, 0x00, 0x19, 0xFA, 0x1B, 0x70, 0x01, 0x19, 0xFA]);
    });

    test('a UPI QR is printed for what is due, an e-invoice QR otherwise, and none when switched off', () {
      final store = [0x1D, 0x28, 0x6B];
      final upi = buildReceiptBytes(bill(), firm);
      expect(String.fromCharCodes(upi), allOf(contains('upi://pay?pa=shop%40upi'), contains('am=1000.00'), contains('Scan to pay')));
      expect(hasBytes(upi, [...store, 0x03, 0x00, 0x31, 0x51, 0x30]), isTrue); // "print the stored code"
      expect(hasBytes(buildReceiptBytes(bill(), firm, options: const ReceiptOptions(qr: false)), store), isFalse);
      expect(hasBytes(buildReceiptBytes(bill({'balance': 0}), firm), store), isFalse);
      final irn = buildReceiptBytes(bill({'balance': 0, 'einvoiceStatus': 'generated', 'irn': 'a' * 64, 'signedQr': 'jwt.signed.qr'}), firm);
      expect(String.fromCharCodes(irn), allOf(contains('jwt.signed.qr'), contains('E-invoice QR')));
    });

    test('the stored length of a QR counts its data plus three', () {
      final p = EscPos(columns: 32)..qr('A' * 300);
      expect(hasBytes(p.toBytes(), [0x1D, 0x28, 0x6B, 303 & 0xFF, 303 >> 8, 0x31, 0x50, 0x30, 0x41]), isTrue);
    });

    test('a logo becomes a one-bit raster: dark is ink, light and transparent are paper', () {
      final picture = img.Image(width: 16, height: 2, numChannels: 4);
      img.fill(picture, color: img.ColorRgba8(255, 255, 255, 255));
      for (var x = 0; x < 8; x++) {
        picture.setPixelRgba(x, 0, 0, 0, 0, 255); // black
        picture.setPixelRgba(x, 1, 0, 0, 0, 0); // black but fully transparent
      }
      final mono = toMonoImage(Uint8List.fromList(img.encodePng(picture)))!;
      expect([mono.widthBytes, mono.height, mono.data], [2, 2, [0xFF, 0x00, 0x00, 0x00]]);
      final bytes = (EscPos(columns: 32)..image(mono)).toBytes();
      expect(hasBytes(bytes, [0x1D, 0x76, 0x30, 0x00, 2, 0, 2, 0, 0xFF, 0x00, 0x00, 0x00]), isTrue);
      expect(toMonoImage(Uint8List.fromList([1, 2, 3])), isNull);
      // A big logo is scaled down to fit.
      final wide = toMonoImage(Uint8List.fromList(img.encodePng(img.Image(width: 1000, height: 400))), maxWidth: 200)!;
      expect(wide.widthBytes * 8, lessThanOrEqualTo(200));
      expect(buildReceiptBytes(bill(), firm, options: ReceiptOptions(logo: mono)).sublist(2, 5), [0x1B, 0x61, 0x01]); // centred, first thing printed
    });

    test('printer preferences survive being stored, and bad data falls back to the defaults', () {
      const p = PrinterPrefs(codePage: 'cp858', openDrawer: true, logo: true, qr: false);
      expect(PrinterPrefs.fromJson(p.toJson()), p);
      expect(PrinterPrefs.fromJson(null), const PrinterPrefs());
      expect(PrinterPrefs.fromJson('{"codePage":"klingon"}').codePage, 'ascii');
    });
  });

  test('invoice PDF prints item pictures when given them', () async {
    final picture = Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 40)));
    final firm = Firm.fromJson(firmJson());
    final json = gstInvoiceJson();
    final lines = [for (final l in json['lines'] as List) {...l as Map<String, dynamic>, 'imageFileId': 'f1'}];
    final inv = Invoice.fromJson({...json, 'lines': lines});
    final plain = await buildInvoicePdf(inv, firm);
    final withPictures = await buildInvoicePdf(inv, firm, options: PrintOptions(itemImages: {'f1': picture}));
    expect(withPictures.length, greaterThan(plain.length));
    // A picture that cannot be read never stops the invoice printing.
    expect((await buildInvoicePdf(inv, firm, options: PrintOptions(itemImages: {'f1': Uint8List.fromList([1, 2, 3])}))).length, greaterThan(1000));
  });

  test('team positions and trails carry their zone and distance', () {
    final m = TeamMemberLocation.fromJson({'userId': 'u', 'fullName': 'Sam', 'role': 'salesman', 'latitude': 18.5, 'longitude': 73.8, 'zone': 'Shop', 'distanceKmToday': 12.4});
    expect([m.zone, m.distanceKmToday], ['Shop', 12.4]);
    final old = TeamMemberLocation.fromJson({'userId': 'u', 'fullName': 'Sam', 'role': 'salesman'});
    expect([old.zone, old.distanceKmToday], [null, 0]);
    final d = DaySummary.fromJson({'distanceKm': 4.36, 'visits': [{'zone': 'Shop', 'from': '2026-10-13T04:00:00.000Z', 'to': '2026-10-13T05:00:00.000Z'}]});
    expect([d.distanceKm, d.visits.single.zone, d.visits.single.to.difference(d.visits.single.from).inMinutes], [4.36, 'Shop', 60]);
  });

  test('the new settings survive a round trip', () {
    const s = FirmSettings(creditLimitMode: 'block', itemImagesOnInvoice: true);
    expect(FirmSettings.fromJson(s.toJson()), s);
    expect(const FirmSettings().creditLimitMode, 'warn');
  });
}
