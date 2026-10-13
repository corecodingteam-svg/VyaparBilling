import 'dart:typed_data';

import '../../../data/models/firm.dart';
import '../../../data/models/invoice.dart';
import '../../../shared/format.dart';

/// Builds raw ESC/POS bytes, the command language of nearly every receipt printer.
/// Text is kept to plain ASCII: printers differ in code pages, so anything else would print as junk.
class EscPos {
  EscPos({required this.columns}) {
    // ESC @ — reset the printer to its defaults.
    _bytes.addAll([0x1B, 0x40]);
  }

  /// Characters per line: 32 on 58 mm paper, 48 on 80 mm (with the printer's standard font).
  final int columns;
  final _bytes = <int>[];

  static int columnsFor(int paperWidthMm) => paperWidthMm <= 58 ? 32 : 48;

  /// Replaces what a receipt printer cannot print: ₹ becomes "Rs.", accents are dropped, the rest becomes "?".
  static String ascii(String text) {
    const swaps = {'₹': 'Rs.', '–': '-', '—': '-', '·': '-', '•': '*', '‘': "'", '’': "'", '“': '"', '”': '"', '…': '...', '×': 'x', ' ': ' '};
    final out = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (swaps.containsKey(ch)) {
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
  static List<String> wrap(String text, int width) {
    final lines = <String>[];
    for (final paragraph in ascii(text).split('\n')) {
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
    for (final line in wrap(text, width)) {
      _bytes.addAll(line.codeUnits);
      _bytes.add(0x0A);
    }
    _size(false);
    _bold(false);
    _align(0);
  }

  /// [left] and [right] on one line, the right one pushed to the edge. A long [left] wraps onto more lines.
  void pair(String left, String right, {bool bold = false, bool big = false}) {
    final width = big ? columns ~/ 2 : columns;
    final r = ascii(right);
    final room = width - r.length - 1;
    final lines = wrap(left, room < 4 ? width : room);
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

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}

/// A sale, return or purchase as a receipt, laid out like the PDF receipt.
Uint8List buildReceiptBytes(Invoice inv, Firm firm, {int? paperWidthMm}) {
  final kind = InvoiceKind.of(inv.type);
  final p = EscPos(columns: EscPos.columnsFor(paperWidthMm ?? firm.settings.thermalWidth));
  final hasTax = inv.totalTax > 0;
  final title = kind.isSale && hasTax && (firm.gstin ?? '').isNotEmpty ? 'Tax Invoice' : kind.documentTitle;
  String amount(num v) => numText(v);

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
  p.text('Thank you!', center: true, bold: true);
  p.feed(4);
  p.cut();
  return p.toBytes();
}
