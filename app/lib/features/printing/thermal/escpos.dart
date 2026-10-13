import 'dart:typed_data';

import '../../../data/models/firm.dart';
import '../../../data/models/invoice.dart';
import '../../../shared/format.dart';

/// The character sets a printer can be told to use, by the number its ESC t command takes. 'ascii' sends
/// only plain ASCII, which every printer prints the same way.
const receiptCodePages = {'ascii': 'Plain (works on every printer)', 'cp437': 'CP437 (USA, most printers)', 'cp858': 'CP858 (Western Europe, €)', 'cp1252': 'Windows-1252'};

const _escT = {'cp437': 0, 'cp858': 19, 'cp1252': 16};
const _cp437 = 'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑ';
const _cp858 = 'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜø£Ø×ƒáíóúñÑ';

/// Which byte each non-ASCII character is in a code page.
Map<String, int> _table(String codePage) => switch (codePage) {
  'cp437' => {for (var i = 0; i < _cp437.length; i++) _cp437[i]: 0x80 + i},
  'cp858' => {for (var i = 0; i < _cp858.length; i++) _cp858[i]: 0x80 + i, '€': 0xD5},
  'cp1252' => {for (var c = 0xA1; c <= 0xFF; c++) String.fromCharCode(c): c, '€': 0x80},
  _ => const {},
};

/// How a receipt is printed on one particular printer; kept on the device, since it describes the device.
class ReceiptOptions {
  const ReceiptOptions({this.codePage = 'ascii', this.openDrawer = false, this.logo, this.qr = true});

  final String codePage;

  /// Kick the cash drawer plugged into the printer after printing.
  final bool openDrawer;

  /// The company logo as a black-and-white raster, ready to print.
  final MonoImage? logo;

  /// Print the pay-by-UPI or e-invoice QR code when the bill has one.
  final bool qr;
}

/// A one-bit image: [widthBytes] bytes per row, most significant bit leftmost, 1 = black.
class MonoImage {
  const MonoImage(this.widthBytes, this.height, this.data);
  final int widthBytes;
  final int height;
  final List<int> data;
}

/// Builds raw ESC/POS bytes, the command language of nearly every receipt printer.
/// Text is plain ASCII unless a code page is chosen: printers differ in code pages, so anything a page
/// cannot print is replaced rather than sent as junk.
class EscPos {
  EscPos({required this.columns, this.codePage = 'ascii'}) : _chars = _table(codePage) {
    // ESC @ — reset the printer to its defaults.
    _bytes.addAll([0x1B, 0x40]);
    // ESC t n — select the character set the text below is encoded in.
    if (_escT.containsKey(codePage)) _bytes.addAll([0x1B, 0x74, _escT[codePage]!]);
  }

  final String codePage;
  final Map<String, int> _chars;
  late final String _keep = _chars.keys.join();

  /// Characters per line: 32 on 58 mm paper, 48 on 80 mm (with the printer's standard font).
  final int columns;
  final _bytes = <int>[];

  static int columnsFor(int paperWidthMm) => paperWidthMm <= 58 ? 32 : 48;

  /// Replaces what a receipt printer cannot print: ₹ becomes "Rs.", accents are dropped, the rest becomes "?".
  /// Characters in [keep] are left alone (the chosen code page can print them).
  static String ascii(String text, {String keep = ''}) {
    const swaps = {'₹': 'Rs.', '–': '-', '—': '-', '·': '-', '•': '*', '‘': "'", '’': "'", '“': '"', '”': '"', '…': '...', '×': 'x', ' ': ' '};
    final out = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (keep.contains(ch) && ch.trim().isNotEmpty) {
        out.write(ch);
      } else if (swaps.containsKey(ch)) {
        out.write(swaps[ch]);
      } else if (rune >= 0x20 && rune < 0x7F) {
        out.write(ch);
      } else if (rune == 0x0A) {
        out.write('\n');
      } else {
        // Letters with accents lose the accent (é → e); anything else is shown as ?.
        const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝ';
        const to = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY';
        final i = from.indexOf(ch);
        out.write(i >= 0 ? to[i] : '?');
      }
    }
    return out.toString();
  }

  /// Splits [text] into lines of at most [width] characters, at spaces where it can.
  static List<String> wrap(String text, int width, {String keep = ''}) {
    final lines = <String>[];
    for (final paragraph in ascii(text, keep: keep).split('\n')) {
      var line = '';
      for (var word in paragraph.split(' ')) {
        while (word.length > width) {
          if (line.isNotEmpty) {
            lines.add(line);
            line = '';
          }
          lines.add(word.substring(0, width));
          word = word.substring(width);
        }
        if (line.isEmpty) {
          line = word;
        } else if (line.length + 1 + word.length <= width) {
          line = '$line $word';
        } else {
          lines.add(line);
          line = word;
        }
      }
      lines.add(line);
    }
    return lines;
  }

  void _align(int mode) => _bytes.addAll([0x1B, 0x61, mode]); // ESC a n: 0 left, 1 centre, 2 right
  void _bold(bool on) => _bytes.addAll([0x1B, 0x45, on ? 1 : 0]); // ESC E n
  void _size(bool big) => _bytes.addAll([0x1D, 0x21, big ? 0x11 : 0x00]); // GS ! n: double width and height

  /// One or more lines of text.
  void text(String text, {bool center = false, bool bold = false, bool big = false}) {
    // Double-size characters take two columns each.
    final width = big ? columns ~/ 2 : columns;
    _align(center ? 1 : 0);
    _bold(bold);
    _size(big);
    for (final line in wrap(text, width, keep: _keep)) {
      _bytes.addAll([for (final rune in line.runes) _chars[String.fromCharCode(rune)] ?? rune]);
      _bytes.add(0x0A);
    }
    _size(false);
    _bold(false);
    _align(0);
  }

  /// [left] and [right] on one line, the right one pushed to the edge. A long [left] wraps onto more lines.
  void pair(String left, String right, {bool bold = false, bool big = false}) {
    final width = big ? columns ~/ 2 : columns;
    final r = ascii(right, keep: _keep);
    final room = width - r.length - 1;
    final lines = wrap(left, room < 4 ? width : room, keep: _keep);
    for (var i = 0; i < lines.length; i++) {
      final isLast = i == lines.length - 1;
      final String line;
      if (!isLast) {
        line = lines[i];
      } else if (lines[i].length + 1 + r.length <= width) {
        line = lines[i].padRight(width - r.length) + r;
      } else {
        // Does not fit beside the value: the value goes on a line of its own.
        text(lines[i], bold: bold, big: big);
        line = r.padLeft(width);
      }
      text(line, bold: bold, big: big);
    }
  }

  void rule() => text('-' * columns);
  void feed([int lines = 1]) => _bytes.addAll([0x1B, 0x64, lines]); // ESC d n

  /// Feeds the paper past the cutter and cuts it (printers without a cutter ignore this).
  void cut() => _bytes.addAll([0x1D, 0x56, 0x42, 0x00]); // GS V B n

  /// Opens the cash drawer wired to the printer (ESC p: pin 2, then pin 5 for drawers wired the other way).
  void drawer() => _bytes.addAll([0x1B, 0x70, 0x00, 0x19, 0xFA, 0x1B, 0x70, 0x01, 0x19, 0xFA]);

  /// A QR code, centred. [size] is the width of one module in dots (1–16).
  void qr(String data, {int size = 6}) {
    final payload = data.codeUnits.map((c) => c > 0xFF ? 0x3F : c).toList();
    final n = payload.length + 3;
    _align(1);
    _bytes
      ..addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]) // model 2
      ..addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size.clamp(1, 16)]) // module size
      ..addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]) // error correction M
      ..addAll([0x1D, 0x28, 0x6B, n & 0xFF, n >> 8, 0x31, 0x50, 0x30, ...payload]) // store the data
      ..addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]) // print it
      ..add(0x0A);
    _align(0);
  }

  /// A black-and-white picture, centred (GS v 0, which nearly every printer understands).
  void image(MonoImage img) {
    _align(1);
    _bytes
      ..addAll([0x1D, 0x76, 0x30, 0x00, img.widthBytes & 0xFF, img.widthBytes >> 8, img.height & 0xFF, img.height >> 8])
      ..addAll(img.data)
      ..add(0x0A);
    _align(0);
  }

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}

/// A sale, return or purchase as a receipt, laid out like the PDF receipt.
Uint8List buildReceiptBytes(Invoice inv, Firm firm, {int? paperWidthMm, ReceiptOptions options = const ReceiptOptions()}) {
  final kind = InvoiceKind.of(inv.type);
  final p = EscPos(columns: EscPos.columnsFor(paperWidthMm ?? firm.settings.thermalWidth), codePage: options.codePage);
  final hasTax = inv.totalTax > 0;
  final title = kind.isSale && hasTax && (firm.gstin ?? '').isNotEmpty ? 'Tax Invoice' : kind.documentTitle;
  String amount(num v) => numText(v);

  if (options.logo != null) p.image(options.logo!);
  p.text(firm.name, center: true, bold: true, big: true);
  if ((firm.address ?? '').isNotEmpty) p.text(firm.address!, center: true);
  if ((firm.phone ?? '').isNotEmpty) p.text('Ph: ${firm.phone}', center: true);
  if ((firm.gstin ?? '').isNotEmpty) p.text('GSTIN: ${firm.gstin}', center: true);
  p.rule();
  p.text(title, center: true, bold: true);
  p.pair(inv.number.isEmpty ? 'Date' : 'No: ${inv.number}', displayDate(inv.invoiceDate));
  p.pair(kind.partyLabel, inv.partyName);
  if ((inv.phone ?? '').isNotEmpty) p.pair('Phone', inv.phone!);
  p.rule();
  p.pair('Item (Qty x Rate)', 'Amount', bold: true);
  p.rule();
  for (final l in inv.lines) {
    p.text(l.name);
    final extras = [
      if ((l.batchNo ?? '').isNotEmpty) 'B:${l.batchNo}',
      if (l.discountAmount > 0) '-${amount(l.discountAmount)}',
      if (l.gstRate > 0) 'GST ${amount(l.gstRate)}%',
    ];
    p.pair(
      '  ${qty(l.quantity)}${l.unit == null ? '' : ' ${l.unit}'} x ${amount(l.price)}${extras.isEmpty ? '' : '  ${extras.join(' ')}'}',
      amount(l.amount),
    );
    if ((l.serialNos ?? '').isNotEmpty) p.text('  SN: ${l.serialNos}');
  }
  p.rule();
  p.pair('Items: ${inv.lines.length}', 'Qty: ${qty(inv.lines.fold<num>(0, (s, l) => s + l.quantity))}');
  if (hasTax) p.pair('Taxable', money(inv.taxableAmount));
  if (inv.discountAmount > 0) p.pair('Discount', money(inv.discountAmount));
  if (inv.cgst > 0) p.pair('CGST', money(inv.cgst));
  if (inv.sgst > 0) p.pair('SGST', money(inv.sgst));
  if (inv.igst > 0) p.pair('IGST', money(inv.igst));
  if (inv.cess > 0) p.pair('Cess', money(inv.cess));
  for (final (name, value) in inv.charges) {
    p.pair(name, money(value));
  }
  if (inv.tcsAmount > 0) p.pair('TCS', money(inv.tcsAmount));
  if (inv.roundOff != 0) p.pair('Round off', amount(inv.roundOff));
  p.pair('TOTAL', money(inv.total), bold: true, big: true);
  if (kind.hasPayment) {
    if (inv.payments.length > 1) {
      for (final part in inv.payments) {
        p.pair('${kind.paidLabel} (${paymentModes[part.mode] ?? part.mode})', money(part.amount));
      }
    } else if (inv.received > 0) {
      p.pair('${kind.paidLabel} (${inv.paymentLabel})', money(inv.received));
    }
    if (inv.linkedAmount > 0) p.pair('${kind.paidLabel} later', money(inv.linkedAmount));
    if (inv.tdsAmount > 0) p.pair('TDS held back', money(inv.tdsAmount));
    if (inv.loyaltyAmount > 0) p.pair('Points redeemed (${inv.loyaltyRedeemed})', money(inv.loyaltyAmount));
    if (inv.balance > 0) p.pair('Balance', money(inv.balance), bold: true);
    if (inv.loyaltyEarned > 0) p.text('You earned ${inv.loyaltyEarned} points on this bill', center: true);
  }
  p.rule();
  if (firm.settings.invoiceTerms.isNotEmpty) p.text(firm.settings.invoiceTerms, center: true);
  if (options.qr) {
    final s = firm.settings;
    if (kind.isSale && s.upiQrOnInvoice && s.upiId.isNotEmpty && inv.balance > 0 && !inv.isForeign) {
      p.qr('upi://pay?pa=${Uri.encodeComponent(s.upiId)}&pn=${Uri.encodeComponent(firm.name)}&am=${inv.balance.toStringAsFixed(2)}&cu=INR&tn=${Uri.encodeComponent('Invoice ${inv.number}')}');
      p.text('Scan to pay ${money(inv.balance)}', center: true);
    } else if (inv.einvoiceStatus == 'generated' && (inv.signedQr ?? '').isNotEmpty) {
      p.qr(inv.signedQr!, size: 4);
      p.text('E-invoice QR', center: true);
    }
  }
  p.text('Thank you!', center: true, bold: true);
  p.feed(4);
  p.cut();
  if (options.openDrawer) p.drawer();
  return p.toBytes();
}
