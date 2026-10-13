import 'dart:typed_data';

import 'package:billing_app/core/status.dart';
import 'package:billing_app/data/models/firm.dart';
import 'package:billing_app/data/models/integrations.dart';
import 'package:billing_app/data/models/invoice.dart';
import 'package:billing_app/features/integrations/integrations_cubits.dart';
import 'package:billing_app/features/printing/pdf_documents.dart';
import 'package:billing_app/features/printing/thermal/bluetooth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bluetooth printers', () {
    test('picks a writable characteristic, preferring known printer services and no-reply writes', () {
      final pick = pickWriteCharacteristic(const [
        BleServiceInfo('0000180a-0000-1000-8000-00805f9b34fb', [BleCharacteristicInfo('2a29', write: false, writeWithoutResponse: false)]),
        BleServiceInfo('1234', [BleCharacteristicInfo('aaaa', write: true, writeWithoutResponse: false)]),
        BleServiceInfo('000018f0-0000-1000-8000-00805f9b34fb', [
          BleCharacteristicInfo('2af1', write: true, writeWithoutResponse: false),
          BleCharacteristicInfo('2af2', write: true, writeWithoutResponse: true),
        ]),
      ]);
      expect(pick, ('000018f0-0000-1000-8000-00805f9b34fb', '2af2'));
      expect(pickWriteCharacteristic(const [BleServiceInfo('1234', [BleCharacteristicInfo('aaaa', write: true, writeWithoutResponse: false)])]), ('1234', 'aaaa'));
      expect(pickWriteCharacteristic(const [BleServiceInfo('1234', [BleCharacteristicInfo('aaaa', write: false, writeWithoutResponse: false)])]), isNull);
    });

    test('splits data to fit the connection', () {
      final bytes = Uint8List.fromList(List.generate(450, (i) => i % 256));
      final parts = splitBytes(bytes, 180);
      expect(parts.map((p) => p.length), [180, 180, 90]);
      expect(parts.expand((p) => p).toList(), bytes);
      expect([bleChunkSize(23), bleChunkSize(185), bleChunkSize(512), bleChunkSize(5)], [20, 180, 180, 20]);
    });

    test('a chosen printer survives being stored', () {
      const p = BluetoothPrinterInfo(id: 'AA:BB:CC:DD:EE:FF', name: 'MHT-P58', classic: true);
      expect(BluetoothPrinterInfo.fromJson(p.toJson()), p);
      expect(BluetoothPrinterInfo.fromJson(p.toJson()).name, 'MHT-P58');
    });
  });

  group('e-invoice cubit', () {
    test('loads, generates, and lists what is missing', () async {
      final repo = FakeIntegrationsRepository()..einvoiceState = einvoiceInfoJson(problems: ['The customer needs a valid GSTIN.']);
      final c = EinvoiceCubit(repo, 'i1');
      await c.load();
      expect(c.state.info!.einvoiceProblems, ['The customer needs a valid GSTIN.']);
      expect(c.state.info!.portalConnected, isTrue);

      repo.einvoiceState = einvoiceInfoJson();
      await c.generate();
      expect([c.state.info!.hasIrn, c.state.message, c.state.busy], [true, 'E-invoice generated', false]);
      await c.generateEway();
      expect(c.state.info!.ewayBillNo, '331234567890');
      await c.cancel('1', 'Duplicate', onPortal: true);
      expect([c.state.info!.status, repo.calls.last], ['cancelled', 'cancel 1 Duplicate true']);
      await c.close();
    });

    test('a failure is reported once and the screen keeps what it had', () async {
      final repo = FakeIntegrationsRepository();
      final c = EinvoiceCubit(repo, 'i1');
      await c.load();
      final before = c.state.info;
      repo.failure = Exception('x');
      await c.generate();
      expect([c.state.error, c.state.info, c.state.busy], [startsWith('Something went wrong (_Exception)'), before, false]);
      await c.close();
    });

    test('a download that fails is an error, one that works says so', () async {
      final repo = FakeIntegrationsRepository();
      final c = EinvoiceCubit(repo, 'i1');
      await c.load();
      await c.attempt(() async => (await repo.einvoiceJson('i1')), done: 'Saved');
      expect(c.state.message, 'Saved');
      await c.attempt(() async => throw Exception('disk full'));
      expect(c.state.error, isNotNull);
      await c.close();
    });
  });

  group('payment link cubit', () {
    test('makes the link on opening and picks up a payment when checked', () async {
      final repo = FakeIntegrationsRepository();
      final c = PaymentLinkCubit(repo, 'i1');
      await c.load();
      expect([c.state.link!.url, c.state.link!.amount, c.state.link!.paid], ['https://rzp.io/i/abc', 236, false]);
      await c.check();
      expect(c.state.link!.paid, isTrue);
      await c.close();
    });

    test('says why a link could not be made', () async {
      final c = PaymentLinkCubit(FakeIntegrationsRepository()..failure = Exception('no'), 'i1');
      await c.load();
      expect([c.state.status, c.state.link], [LoadStatus.failure, isNull]);
      await c.close();
    });
  });

  group('Google Business Profile cubit', () {
    test('walks from not connected, to choosing a listing, to managing it', () async {
      final repo = FakeIntegrationsRepository();
      final c = GoogleProfileCubit(repo);
      await c.load();
      expect(c.state.stage, GoogleStage.notConnected);

      repo.providers = [for (final j in repo.providers) j['provider'] == 'google_profile' ? integrationJson('google_profile', connected: true) : j];
      await c.load();
      expect([c.state.stage, c.state.locations.single.title, c.state.email], [GoogleStage.pickLocation, 'Acme Traders', 'owner@example.com']);

      await c.choose(c.state.locations.single);
      expect([c.state.stage, c.state.profile!.description, c.state.reviews!.total], [GoogleStage.ready, 'Hardware since 1990', 2]);

      await c.saveProfile('New text', 'https://x.example');
      expect([c.state.profile!.description, c.state.message], ['New text', 'Profile updated']);
      await c.post('Diwali offer', '');
      expect([repo.calls.last, c.state.message], ['post Diwali offer ', 'Posted to your Google listing']);
      await c.reply('r1', 'Thanks Asha');
      expect([repo.calls.contains('reply r1 Thanks Asha'), c.state.message], [true, 'Reply posted']);
      await c.close();
    });

    test('an error from Google is shown, not swallowed', () async {
      final repo = FakeIntegrationsRepository();
      final c = GoogleProfileCubit(repo);
      repo.providers = [for (final j in repo.providers) j['provider'] == 'google_profile' ? integrationJson('google_profile', connected: true, location: 'Acme') : j];
      await c.load();
      repo.failure = Exception('quota');
      await c.post('x', '');
      expect([c.state.error, c.state.busy, c.state.stage], [startsWith('Something went wrong (_Exception)'), false, GoogleStage.ready]);
      await c.close();
    });
  });

  group('models and settings', () {
    test('secrets arrive masked and never as values', () {
      final i = Integration.fromJson(integrationJson('whatsapp', connected: true, stored: '••••1234'));
      final token = i.fields.firstWhere((f) => f.key == 'accessToken');
      expect([i.connected, token.secret, token.stored, token.value], [true, true, '••••1234', '']);
    });

    test('the new settings survive a round trip', () {
      const s = FirmSettings(
        autoSendInvoices: 'whatsapp', autoSendPayments: 'sms', invoiceMessage: 'Hi {customer}', einvoiceEnabled: true, ewayEnabled: true, upiId: 'shop@upi', upiQrOnInvoice: true,
      );
      final back = FirmSettings.fromJson(s.toJson());
      expect(back, s);
      expect([back.autoSendInvoices, back.autoSendPayments, back.upiId, back.einvoiceEnabled, back.paymentMessage], ['whatsapp', 'sms', 'shop@upi', true, defaultPaymentMessage]);
    });
  });

  group('printed invoice', () {
    Invoice invoice({String irn = 'x', Map<String, dynamic> extra = const {}}) =>
        Invoice.fromJson({...gstInvoiceJson(), 'balance': 1000, 'einvoiceStatus': irn == 'x' ? 'none' : 'generated', 'irn': irn == 'x' ? null : irn, 'ackNo': '99', 'signedQr': irn == 'x' ? null : 'jwt.qr', ...extra});
    final firm = Firm.fromJson(firmJson(settings: {'upiId': 'shop@upi', 'upiQrOnInvoice': true}));

    test('adds a UPI QR and the IRN only when they apply', () async {
      final plain = await buildInvoicePdf(invoice(), Firm.fromJson(firmJson()));
      final withUpi = await buildInvoicePdf(invoice(), firm);
      final withBoth = await buildInvoicePdf(invoice(irn: 'a' * 64), firm);
      expect(withUpi.length, greaterThan(plain.length));
      expect(withBoth.length, greaterThan(withUpi.length));
      // Fully paid: nothing to scan for.
      final paid = await buildInvoicePdf(invoice(extra: {'balance': 0}), firm);
      expect(paid.length, lessThan(withUpi.length));
    });
  });
}
