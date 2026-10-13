import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:billing_app/data/models/firm.dart';
import 'package:billing_app/data/models/invoice.dart';
import 'package:billing_app/features/printing/thermal/escpos.dart';
import 'package:billing_app/features/printing/thermal/network_transport.dart';
import 'package:billing_app/features/printing/thermal/transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The text a printer would print: control codes (ESC/GS commands) removed.
List<String> printedLines(Uint8List bytes) {
  final text = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    if (b == 0x1B) {
      // ESC @ is 2 bytes; ESC a/E/d are 3.
      i += bytes[i + 1] == 0x40 ? 1 : 2;
    } else if (b == 0x1D) {
      // GS ! n is 3 bytes; GS V B n is 4.
      i += bytes[i + 1] == 0x56 ? 3 : 2;
    } else {
      text.writeCharCode(b);
    }
  }
  return text.toString().split('\n');
}

void main() {
  group('ESC/POS', () {
    test('starts with a reset, ends with a feed and a cut', () {
      final bytes = (EscPos(columns: 32)..text('Hello')..feed(3)..cut()).toBytes();
      expect(bytes.sublist(0, 2), [0x1B, 0x40]);
      expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      expect(printedLines(bytes), contains('Hello'));
    });

    test('keeps to plain ASCII: rupee sign, accents and symbols', () {
      expect(EscPos.ascii('₹ 1,000 · café – naïve'), 'Rs. 1,000 - cafe - naive');
      expect(EscPos.ascii('日本'), '??');
    });

    test('wraps at the paper width, at spaces where possible, and splits very long words', () {
      expect(EscPos.wrap('Basmati Rice Premium 5kg Pack', 15), ['Basmati Rice', 'Premium 5kg', 'Pack']);
      expect(EscPos.wrap('A' * 20, 8), ['A' * 8, 'A' * 8, 'AAAA']);
      expect(EscPos.wrap('one\ntwo', 10), ['one', 'two']);
    });

    test('puts the value at the right edge, and wraps a long left side', () {
      final lines = printedLines((EscPos(columns: 32)..pair('Sale', '₹ 100.00')).toBytes());
      expect(lines.first, '${'Sale'.padRight(32 - 'Rs. 100.00'.length)}Rs. 100.00');
      expect(lines.first.length, 32);

      final wrapped = printedLines((EscPos(columns: 32)..pair('A very long item description that needs two lines', '999')).toBytes()).where((l) => l.isNotEmpty).toList();
      expect(wrapped.length, greaterThan(1));
      expect(wrapped.last.endsWith('999'), isTrue);
      expect(wrapped.every((l) => l.length <= 32), isTrue);
    });

    test('58 mm paper has 32 columns and 80 mm has 48', () {
      expect([EscPos.columnsFor(58), EscPos.columnsFor(80)], [32, 48]);
    });

    test('a receipt shows the bill: items, discount, charges, TCS, payments, balance and points', () {
      final inv = Invoice.fromJson({
        ...gstInvoiceJson(),
        'discountAmount': 50,
        'charges': [
          {'name': 'Shipping', 'amount': 40},
        ],
        'chargesTotal': 40,
        'tcsAmount': 14,
        'tcsRate': 1,
        'loyaltyEarned': 13,
        'payments': [
          {'mode': 'cash', 'bankAccountId': null, 'amount': 200},
          {'mode': 'upi', 'bankAccountId': 'b1', 'amount': 190},
        ],
      });
      final firm = Firm.fromJson(firmJson());
      for (final width in [58, 80]) {
        final lines = printedLines(buildReceiptBytes(inv, firm, paperWidthMm: width));
        final text = lines.join('\n');
        expect(lines.every((l) => l.length <= EscPos.columnsFor(width)), isTrue, reason: '$width mm lines fit');
        for (final expected in ['Demo Traders', 'Tax Invoice', 'Sample Item', 'Basmati Rice 5kg', 'Discount', 'Shipping', 'TCS', 'TOTAL', 'Cash', 'UPI', 'Balance', '13 points']) {
          expect(text, contains(expected), reason: '$width mm has $expected');
        }
        expect(text, isNot(contains('₹')));
      }
    });
  });

  group('network printer', () {
    test('sends every byte to the printer port, in order', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = BytesBuilder();
      final done = Completer<void>();
      server.listen((s) {
        s.listen(received.add, onDone: done.complete);
      });
      final bytes = Uint8List.fromList(List.generate(10000, (i) => i % 251));
      await NetworkTransport(host: '127.0.0.1', port: server.port).send(bytes);
      await done.future.timeout(const Duration(seconds: 5));
      expect(received.takeBytes(), bytes);
      await server.close();
    });

    test('says so when the printer cannot be reached', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close(); // nothing is listening any more
      await expectLater(
        NetworkTransport(host: '127.0.0.1', port: port, timeout: const Duration(seconds: 2)).send(Uint8List(4)),
        throwsA(isA<PrinterException>().having((e) => e.message, 'message', contains('Could not reach the printer'))),
      );
    });
  });
}
