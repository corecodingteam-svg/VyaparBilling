import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/gst_states.dart';
import '../../data/models/firm.dart';
import '../../data/models/invoice.dart';
import '../../data/models/payment.dart';
import '../../data/models/report.dart';
import '../../shared/amount_words.dart';
import '../../shared/format.dart';
import '../reports/report_format.dart';

const _line = PdfColor.fromInt(0xFF3A3F55);
const _shade = PdfColor.fromInt(0xFFF1F4F9);

/// Roboto is bundled so PDFs can show the ₹ sign and work offline.
Future<pw.ThemeData> _theme() async => pw.ThemeData.withFont(
  base: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
  bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
);

pw.Widget _firmHeader(Firm firm) => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.all(10),
  decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(firm.name, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      if ((firm.address ?? '').isNotEmpty) pw.Text(firm.address!),
      pw.Wrap(
        spacing: 16,
        children: [
          if ((firm.phone ?? '').isNotEmpty) pw.Text('Phone: ${firm.phone}'),
          if ((firm.email ?? '').isNotEmpty) pw.Text('Email: ${firm.email}'),
          if ((firm.gstin ?? '').isNotEmpty) pw.Text('GSTIN: ${firm.gstin}'),
          if (firm.stateCode != null) pw.Text('State: ${gstStates[firm.stateCode]}'),
        ],
      ),
    ],
  ),
);

pw.Widget _labelled(String label, String value) => pw.RichText(
  text: pw.TextSpan(
    children: [
      pw.TextSpan(text: '$label: '),
      pw.TextSpan(
        text: value,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
    ],
  ),
);

/// Two titled boxes side by side. A table keeps them the same height whatever each one holds.
pw.Widget _boxes(List<(String, List<pw.Widget>)> boxes) => pw.Table(
  border: pw.TableBorder.all(color: _line),
  children: [
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: _shade),
      children: [
        for (final (title, _) in boxes)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ),
      ],
    ),
    pw.TableRow(
      children: [
        for (final (_, children) in boxes)
          pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: children),
          ),
      ],
    ),
  ],
);

/// What a printed document needs beyond the document itself: the look chosen in settings and the
/// uploaded images. Everything is optional; the defaults print the plain classic layout.
class PrintOptions {
  const PrintOptions({this.theme, this.accent, this.logo, this.signature, this.partyFields = const [], this.currencySymbol, this.itemImages = const {}});

  /// Reads the theme and colour from the firm's settings.
  factory PrintOptions.of(
    Firm firm, {
    Uint8List? logo,
    Uint8List? signature,
    List<(String, String)> partyFields = const [],
    String? currencySymbol,
    String? theme,
    Map<String, Uint8List> itemImages = const {},
  }) => PrintOptions(
    theme: theme ?? firm.settings.invoiceTheme,
    accent: _hex(firm.settings.themeColor),
    logo: logo,
    signature: signature,
    partyFields: partyFields,
    currencySymbol: currencySymbol,
    itemImages: itemImages,
  );

  /// classic | modern | minimal
  final String? theme;
  final PdfColor? accent;
  final Uint8List? logo;
  final Uint8List? signature;

  /// Item pictures to print beside the item names, by file id.
  final Map<String, Uint8List> itemImages;

  /// The party's additional fields marked "print on invoices", as (name, value).
  final List<(String, String)> partyFields;

  /// Symbol of the document's foreign currency (falls back to its code).
  final String? currencySymbol;
}

PdfColor _hex(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return v == null || hex.length != 7 ? const PdfColor.fromInt(0xFF1E5EFF) : PdfColor.fromInt(0xFF000000 | v);
}

pw.Widget? _image(Uint8List? bytes, {double? width, double? height}) {
  if (bytes == null) return null;
  try {
    return pw.Image(pw.MemoryImage(bytes), width: width, height: height, fit: pw.BoxFit.contain);
  } catch (_) {
    return null; // an image the PDF library cannot read must not stop the invoice printing
  }
}

pw.Widget _signature(Firm firm, [Uint8List? signature]) => pw.Align(
  alignment: pw.Alignment.centerRight,
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [pw.Text('For ${firm.name}'), _image(signature, height: 44) ?? pw.SizedBox(height: 36), pw.Text(firm.settings.signatureLabel)],
  ),
);

/// How one invoice theme draws the parts that differ between themes.
class _InvoiceStyle {
  _InvoiceStyle(this.theme, this.accent);
  final String theme;
  final PdfColor accent;

  bool get classic => theme == 'classic';
  bool get modern => theme == 'modern';

  pw.TextStyle get _bold => pw.TextStyle(fontWeight: pw.FontWeight.bold);

  pw.Widget _firmLines(Firm firm, {PdfColor? color, pw.CrossAxisAlignment align = pw.CrossAxisAlignment.start}) {
    final style = pw.TextStyle(color: color, fontSize: 10);
    return pw.Column(
      crossAxisAlignment: align,
      children: [
        if ((firm.address ?? '').isNotEmpty) pw.Text(firm.address!, style: style),
        pw.Wrap(
          spacing: 14,
          children: [
            if ((firm.phone ?? '').isNotEmpty) pw.Text('Phone: ${firm.phone}', style: style),
            if ((firm.email ?? '').isNotEmpty) pw.Text('Email: ${firm.email}', style: style),
          ],
        ),
        pw.Wrap(
          spacing: 14,
          children: [
            if ((firm.gstin ?? '').isNotEmpty) pw.Text('GSTIN: ${firm.gstin}', style: style),
            if (firm.stateCode != null) pw.Text('State: ${gstStates[firm.stateCode]}', style: style),
          ],
        ),
      ],
    );
  }

  /// Title, business name and details, and the logo.
  List<pw.Widget> header(Firm firm, String title, Uint8List? logo) {
    final logoImage = _image(logo, width: 64, height: 64);
    if (modern) {
      return [
        pw.Container(
          color: accent,
          padding: const pw.EdgeInsets.all(14),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null) ...[
                pw.Container(color: PdfColors.white, padding: const pw.EdgeInsets.all(3), child: logoImage),
                pw.SizedBox(width: 12),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      firm.name,
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    ),
                    pw.SizedBox(height: 3),
                    _firmLines(firm, color: PdfColors.white),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Text(
                title.toUpperCase(),
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 1),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
      ];
    }
    if (!classic) {
      return [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(title.toUpperCase(), style: pw.TextStyle(fontSize: 22, color: accent, letterSpacing: 2)),
                  pw.SizedBox(height: 8),
                  pw.Text(firm.name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  _firmLines(firm, color: PdfColors.grey700),
                ],
              ),
            ),
            ?logoImage,
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 1.5, color: accent),
        pw.SizedBox(height: 12),
      ];
    }
    return [
      pw.Center(
        child: pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      ),
      pw.SizedBox(height: 8),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoImage != null) ...[logoImage, pw.SizedBox(width: 12)],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(firm.name, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  _firmLines(firm),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// Titled blocks side by side: party, shipping address, document details.
  pw.Widget boxes(List<(String, List<pw.Widget>)> boxes) {
    if (classic) return _boxes(boxes);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < boxes.length; i++) ...[
          if (i > 0) pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  boxes[i].$1.toUpperCase(),
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: accent, letterSpacing: 0.6),
                ),
                pw.SizedBox(height: 3),
                ...boxes[i].$2,
              ],
            ),
          ),
        ],
      ],
    );
  }

  pw.TableBorder get tableBorder => classic
      ? pw.TableBorder.all(color: _line, width: 0.6)
      : pw.TableBorder(
          horizontalInside: const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          bottom: const pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          top: modern ? pw.BorderSide.none : pw.BorderSide(color: accent, width: 1),
        );

  pw.BoxDecoration get tableHeader => pw.BoxDecoration(color: classic ? _shade : (modern ? accent : null));
  pw.TextStyle get tableHeaderText =>
      pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: modern ? PdfColors.white : (classic ? null : accent));

  /// The grand total line.
  pw.Widget total(String label, String value) {
    final row = pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: modern ? PdfColors.white : null),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: modern ? PdfColors.white : (classic ? null : accent)),
        ),
      ],
    );
    if (modern) return pw.Container(color: accent, padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5), child: row);
    return pw.Column(
      children: [
        pw.Divider(color: classic ? _line : accent, height: 6),
        pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: row),
      ],
    );
  }

  pw.Widget heading(String text) => pw.Text(
    text,
    style: classic ? _bold : pw.TextStyle(fontWeight: pw.FontWeight.bold, color: accent),
  );
}

/// An invoice (or estimate, order, challan, return) in the chosen theme: business header with
/// logo, party and shipping address, line items (with HSN and GST when used), totals, how it was
/// paid, a tax summary by rate, the amount in words, terms and the signature.
Future<Uint8List> buildInvoicePdf(
  Invoice inv,
  Firm firm, {
  PdfPageFormat format = PdfPageFormat.a4,
  PrintOptions options = const PrintOptions(),
}) async {
  final kind = InvoiceKind.of(inv.type);
  final style = _InvoiceStyle(options.theme ?? 'classic', options.accent ?? const PdfColor.fromInt(0xFF1E5EFF));
  final hasDiscount = inv.lines.any((l) => l.discountAmount > 0);
  final hasTax = inv.totalTax > 0;
  final hasHsn = inv.lines.any((l) => (l.hsnCode ?? '').isNotEmpty);
  // A taxed sale by a GST-registered business is a "Tax Invoice".
  final title = kind.isSale && hasTax && (firm.gstin ?? '').isNotEmpty ? 'Tax Invoice' : kind.documentTitle;
  final doc = pw.Document(theme: await _theme(), title: '${kind.singular} ${inv.number}');

  // A document made out in another currency prints every figure in it; the books keep it in rupees.
  final rate = inv.currencyCode != null && (inv.exchangeRate ?? 0) > 0 ? inv.exchangeRate! : null;
  final symbol = options.currencySymbol ?? inv.currencyCode ?? '';
  String m(num? v) => rate == null || v == null ? money(v) : '$symbol ${(v / rate).toStringAsFixed(2)}';
  String fx(num? exact, num? rupees) => rate == null ? money(rupees) : (exact != null ? '$symbol ${exact.toStringAsFixed(2)}' : m(rupees));
  final hasCess = inv.cess > 0;

  pw.Widget totalRow(String label, String value, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
        pw.Text(value, style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
      ],
    ),
  );

  // Tax grouped by rate, for the summary table.
  final byRate = <num, List<num>>{}; // rate → [taxable, cgst, sgst, igst]
  for (final l in inv.lines.where((l) => l.gstRate > 0)) {
    final t = byRate.putIfAbsent(l.gstRate, () => [0, 0, 0, 0]);
    t[0] += l.taxableValue;
    t[1] += l.cgst;
    t[2] += l.sgst;
    t[3] += l.igst;
  }
  final rates = byRate.keys.toList()..sort();

  final headers = [
    '#',
    'Item name',
    if (hasHsn) 'HSN/SAC',
    'Quantity',
    'Unit',
    'Price/Unit',
    if (hasDiscount) 'Discount',
    if (hasTax) 'GST',
    'Amount',
  ];
  final tableStyle = (
    border: style.tableBorder,
    header: style.tableHeaderText,
    cell: const pw.TextStyle(fontSize: 10),
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  );
  final shipping = (inv.shippingAddress ?? '').trim();

  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => [
        ...style.header(firm, title, options.logo),
        style.boxes([
          (
            kind.pdfPartyTitle,
            [
              pw.Text(inv.partyName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              if ((inv.billingAddress ?? '').isNotEmpty) pw.Text(inv.billingAddress!),
              if ((inv.phone ?? '').isNotEmpty) pw.Text('Contact No.: ${inv.phone}'),
              if ((inv.partyGstin ?? '').isNotEmpty) pw.Text('GSTIN: ${inv.partyGstin}'),
              for (final (name, value) in options.partyFields) pw.Text('$name: $value'),
            ],
          ),
          if (shipping.isNotEmpty) ('Ship To', [pw.Text(shipping)]),
          (
            '${kind.documentTitle} Details',
            [
              if (inv.number.isNotEmpty) _labelled(kind.numberLabel, inv.number),
              _labelled('Date', displayDate(inv.invoiceDate)),
              if (inv.dueDate != null) _labelled('Due Date', displayDate(inv.dueDate)),
              if (inv.stateOfSupply != null) _labelled('Place of supply', '${inv.stateOfSupply}-${gstStates[inv.stateOfSupply] ?? ''}'),
            ],
          ),
        ]),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          border: tableStyle.border,
          headerStyle: tableStyle.header,
          headerDecoration: style.tableHeader,
          cellStyle: tableStyle.cell,
          cellPadding: tableStyle.padding,
          columnWidths: {0: const pw.FixedColumnWidth(26), 1: const pw.FlexColumnWidth(4)},
          cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.centerLeft, for (var i = 2; i < headers.length; i++) i: pw.Alignment.centerRight},
          headers: headers,
          data: [
            for (var i = 0; i < inv.lines.length; i++)
              [
                '${i + 1}',
                _withPicture(options.itemImages[inv.lines[i].imageFileId], tableStyle.cell, [
                  inv.lines[i].name,
                  // Batch, expiry, MRP and serial numbers, when the line has them.
                  [
                    if ((inv.lines[i].batchNo ?? '').isNotEmpty) 'Batch ${inv.lines[i].batchNo}',
                    if (inv.lines[i].expiryDate != null) 'Exp ${displayDate(inv.lines[i].expiryDate)}',
                    if (inv.lines[i].mrp != null) 'MRP ${money(inv.lines[i].mrp)}',
                  ].join(' · '),
                  if ((inv.lines[i].serialNos ?? '').isNotEmpty) 'SN: ${inv.lines[i].serialNos}',
                ].where((t) => t.isNotEmpty).join('\n')),
                if (hasHsn) inv.lines[i].hsnCode ?? '',
                qty(inv.lines[i].quantity),
                inv.lines[i].unit ?? '',
                fx(inv.lines[i].fxPrice, inv.lines[i].price),
                if (hasDiscount) inv.lines[i].discountAmount > 0 ? '${m(inv.lines[i].discountAmount)} (${numText(inv.lines[i].discountPct)}%)' : '',
                if (hasTax)
                  inv.lines[i].gstRate > 0 || inv.lines[i].cess > 0
                      ? '${m(inv.lines[i].tax)} (${numText(inv.lines[i].gstRate + inv.lines[i].cessRate)}%)'
                      : '',
                fx(inv.lines[i].fxAmount, inv.lines[i].amount),
              ],
          ],
        ),
        if (hasTax && inv.pricesIncludeTax)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Text('Unit prices are inclusive of GST.', style: const pw.TextStyle(fontSize: 9)),
          ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (rate == null) ...[
                    style.heading('${kind.documentTitle} Amount In Words'),
                    pw.Text(amountInWords(inv.total)),
                  ] else ...[
                    style.heading('Currency'),
                    pw.Text('Amounts are in ${inv.currencyCode}. 1 ${inv.currencyCode} = ${money(rate)}'),
                    pw.Text('Booked in INR: ${money(inv.total)}'),
                  ],
                  if ((inv.description ?? '').isNotEmpty) ...[pw.SizedBox(height: 8), style.heading('Description'), pw.Text(inv.description!)],
                ],
              ),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              flex: 2,
              child: pw.Column(
                children: [
                  totalRow(hasTax ? 'Taxable Amount' : 'Sub Total', m(hasTax ? inv.taxableAmount : inv.subtotal)),
                  if (inv.discountAmount > 0)
                    totalRow(
                      'Discount${inv.discountPct > 0 && inv.discountPct == inv.discountPct.roundToDouble() ? ' (${numText(inv.discountPct)}%)' : ''}',
                      m(inv.discountAmount),
                    ),
                  if (inv.cgst > 0) totalRow('CGST', m(inv.cgst)),
                  if (inv.sgst > 0) totalRow('SGST', m(inv.sgst)),
                  if (inv.igst > 0) totalRow('IGST', m(inv.igst)),
                  if (hasCess) totalRow('Cess', m(inv.cess)),
                  for (final (name, amount) in inv.charges) totalRow(name, m(amount)),
                  if (inv.tcsAmount > 0) totalRow('TCS (${numText(inv.tcsRate)}%)', m(inv.tcsAmount)),
                  if (inv.roundOff != 0) totalRow('Round off', rate == null ? numText(inv.roundOff) : m(inv.roundOff)),
                  style.total('Total', fx(inv.fxTotal, inv.total)),
                  if (inv.tdsAmount > 0) totalRow('TDS (${numText(inv.tdsRate)}%) held back', m(inv.tdsAmount)),
                  if (inv.loyaltyAmount > 0) totalRow('Loyalty points (${inv.loyaltyRedeemed})', m(inv.loyaltyAmount)),
                  if (kind.hasPayment) ...[
                    // Paid in parts: one line per part; otherwise the single amount.
                    if (inv.payments.length > 1)
                      for (final p in inv.payments) totalRow('${kind.paidLabel} (${paymentModes[p.mode] ?? p.mode})', fx(p.fxAmount, p.amount))
                    else
                      totalRow(kind.paidLabel, fx(inv.fxReceived, inv.received)),
                    if (inv.linkedAmount > 0) totalRow('${kind.paidLabel} later', m(inv.linkedAmount)),
                    totalRow('Balance', fx(inv.fxBalance, inv.balance), bold: true),
                    if (inv.received > 0 && inv.payments.length <= 1) totalRow('Payment Mode', inv.paymentLabel),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (rates.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          style.heading('Tax Summary'),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            border: tableStyle.border,
            headerStyle: tableStyle.header,
            headerDecoration: style.tableHeader,
            cellStyle: tableStyle.cell,
            cellPadding: tableStyle.padding,
            cellAlignment: pw.Alignment.centerRight,
            headers: [
              'GST Rate',
              'Taxable Amount',
              if (inv.interState) 'IGST' else ...['CGST', 'SGST'],
              'Total Tax',
            ],
            data: [
              for (final r in rates)
                [
                  '${numText(r)}%',
                  m(byRate[r]![0]),
                  if (inv.interState) m(byRate[r]![3]) else ...[m(byRate[r]![1]), m(byRate[r]![2])],
                  m(byRate[r]![1] + byRate[r]![2] + byRate[r]![3]),
                ],
            ],
          ),
        ],
        if (firm.settings.invoiceTerms.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          style.heading('Terms and Conditions'),
          pw.Text(firm.settings.invoiceTerms, style: const pw.TextStyle(fontSize: 10)),
        ],
        ..._paymentAndIrn(inv, firm),
        pw.SizedBox(height: 28),
        _signature(firm, options.signature),
      ],
    ),
  );
  return doc.save();
}

/// An item-name cell: just the text, or the item's picture with the text beside it.
Object _withPicture(Uint8List? picture, pw.TextStyle style, String text) {
  final image = _image(picture, width: 34, height: 34);
  if (image == null) return text;
  return pw.Row(children: [image, pw.SizedBox(width: 6), pw.Expanded(child: pw.Text(text, style: style))]);
}

/// A UPI QR for what is still due (when the company switched it on and has a UPI ID), and the IRN with its signed QR once registered.
List<pw.Widget> _paymentAndIrn(Invoice inv, Firm firm) {
  final upi = firm.settings.upiQrOnInvoice && firm.settings.upiId.isNotEmpty && inv.balance > 0 && !inv.isForeign && inv.type == 'sale';
  final irn = inv.einvoiceStatus == 'generated' && inv.irn != null;
  if (!upi && !irn) return const [];
  pw.Widget qr(String data, String caption) => pw.Column(children: [
        pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: data, width: 78, height: 78),
        pw.SizedBox(height: 3),
        pw.Text(caption, style: const pw.TextStyle(fontSize: 8)),
      ]);
  return [
    pw.SizedBox(height: 14),
    pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      if (upi)
        qr(
          'upi://pay?pa=${Uri.encodeComponent(firm.settings.upiId)}&pn=${Uri.encodeComponent(firm.name)}&am=${inv.balance.toStringAsFixed(2)}&cu=INR&tn=${Uri.encodeComponent('Invoice ${inv.number}')}',
          'Scan to pay ${money(inv.balance)}',
        ),
      if (upi && irn) pw.SizedBox(width: 24),
      if (irn) ...[
        if (inv.signedQr != null) qr(inv.signedQr!, 'E-invoice QR'),
        pw.SizedBox(width: 12),
        pw.Expanded(child: pw.Text('IRN: ${inv.irn}${inv.ackNo == null ? '' : '\nAck no.: ${inv.ackNo}'}', style: const pw.TextStyle(fontSize: 8))),
      ],
    ]),
  ];
}

/// The same document as a narrow receipt for 58 mm or 80 mm thermal roll printers. The page is as
/// long as the receipt needs to be.
Future<Uint8List> buildThermalReceiptPdf(Invoice inv, Firm firm, {int? widthMm, Uint8List? logo}) async {
  final kind = InvoiceKind.of(inv.type);
  final width = widthMm ?? firm.settings.thermalWidth;
  final narrow = width <= 58;
  final size = narrow ? 7.5 : 9.0;
  final base = pw.TextStyle(fontSize: size);
  final bold = pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold);
  final hasTax = inv.totalTax > 0;
  final title = kind.isSale && hasTax && (firm.gstin ?? '').isNotEmpty ? 'Tax Invoice' : kind.documentTitle;
  final doc = pw.Document(theme: await _theme(), title: '${kind.singular} ${inv.number}');

  pw.Widget rule() => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Divider(height: 1, thickness: 0.6, borderStyle: pw.BorderStyle.dashed, color: PdfColors.black),
  );
  pw.Widget pair(String label, String value, {bool strong = false}) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: pw.Text(label, style: strong ? bold : base)),
      pw.SizedBox(width: 6),
      pw.Text(value, style: strong ? bold : base),
    ],
  );
  pw.Widget centred(String text, [pw.TextStyle? style]) => pw.Text(text, textAlign: pw.TextAlign.center, style: style ?? base);
  final logoImage = _image(logo, height: narrow ? 28 : 36);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(width * PdfPageFormat.mm, double.infinity, marginAll: (narrow ? 3 : 4) * PdfPageFormat.mm),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          if (logoImage != null) pw.Center(child: logoImage),
          centred(firm.name, pw.TextStyle(fontSize: size + 3, fontWeight: pw.FontWeight.bold)),
          if ((firm.address ?? '').isNotEmpty) centred(firm.address!),
          if ((firm.phone ?? '').isNotEmpty) centred('Ph: ${firm.phone}'),
          if ((firm.gstin ?? '').isNotEmpty) centred('GSTIN: ${firm.gstin}'),
          rule(),
          centred(title, bold),
          if (inv.number.isNotEmpty) pair('No: ${inv.number}', displayDate(inv.invoiceDate)) else pair('Date', displayDate(inv.invoiceDate)),
          pair(kind.partyLabel, inv.partyName),
          if ((inv.phone ?? '').isNotEmpty) pair('Phone', inv.phone!),
          rule(),
          pair('Item  (Qty x Rate)', 'Amount', strong: true),
          rule(),
          for (final l in inv.lines) ...[
            pw.Text(l.name, style: base),
            pair(
              '  ${qty(l.quantity)}${l.unit == null ? '' : ' ${l.unit}'} x ${numText(l.price)}'
              '${l.discountAmount > 0 ? '  -${numText(l.discountAmount)}' : ''}${l.gstRate > 0 ? '  GST ${numText(l.gstRate)}%' : ''}',
              numText(l.amount),
            ),
          ],
          rule(),
          pair('Items: ${inv.lines.length}', 'Qty: ${qty(inv.lines.fold<num>(0, (s, l) => s + l.quantity))}'),
          if (hasTax) pair('Taxable', money(inv.taxableAmount)),
          if (inv.discountAmount > 0) pair('Discount', money(inv.discountAmount)),
          if (inv.cgst > 0) pair('CGST', money(inv.cgst)),
          if (inv.sgst > 0) pair('SGST', money(inv.sgst)),
          if (inv.igst > 0) pair('IGST', money(inv.igst)),
          if (inv.cess > 0) pair('Cess', money(inv.cess)),
          for (final (name, amount) in inv.charges) pair(name, money(amount)),
          if (inv.tcsAmount > 0) pair('TCS', money(inv.tcsAmount)),
          if (inv.roundOff != 0) pair('Round off', numText(inv.roundOff)),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL',
                style: pw.TextStyle(fontSize: size + 2, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                money(inv.total),
                style: pw.TextStyle(fontSize: size + 2, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          if (kind.hasPayment) ...[
            if (inv.payments.length > 1)
              for (final p in inv.payments) pair('${kind.paidLabel} (${paymentModes[p.mode] ?? p.mode})', money(p.amount))
            else if (inv.received > 0)
              pair('${kind.paidLabel} (${inv.paymentLabel})', money(inv.received)),
            if (inv.linkedAmount > 0) pair('${kind.paidLabel} later', money(inv.linkedAmount)),
            if (inv.tdsAmount > 0) pair('TDS held back', money(inv.tdsAmount)),
            if (inv.loyaltyAmount > 0) pair('Points redeemed (${inv.loyaltyRedeemed})', money(inv.loyaltyAmount)),
            if (inv.balance > 0) pair('Balance', money(inv.balance), strong: true),
            if (inv.loyaltyEarned > 0) centred('You earned ${inv.loyaltyEarned} points on this bill', pw.TextStyle(fontSize: size - 1)),
          ],
          rule(),
          if (firm.settings.invoiceTerms.isNotEmpty) ...[
            centred(firm.settings.invoiceTerms, pw.TextStyle(fontSize: size - 1)),
            pw.SizedBox(height: 3),
          ],
          centred('Thank you!', bold),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Payment receipt (Payment-In) / payment voucher (Payment-Out).
Future<Uint8List> buildPaymentPdf(
  Payment p,
  Firm firm, {
  PdfPageFormat format = PdfPageFormat.a4,
  PrintOptions options = const PrintOptions(),
}) async {
  final kind = PaymentKind.of(p.type);
  final doc = pw.Document(theme: await _theme(), title: '${kind.title} ${p.number}');
  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(p.type == 'in' ? 'Payment Receipt' : 'Payment Voucher', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 8),
          _firmHeader(firm),
          _boxes([
            (p.type == 'in' ? 'Received From' : 'Paid To', [pw.Text(p.partyName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
            (
              'Receipt Details',
              [_labelled('Receipt No.', p.number), _labelled('Date', displayDate(p.paymentDate)), _labelled('Payment Mode', p.paymentLabel)],
            ),
          ]),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _line)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(kind.amountLabel, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                      p.currencyCode == null ? money(p.amount) : '${options.currencySymbol ?? p.currencyCode} ${p.amount.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                if (p.currencyCode != null) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('At 1 ${p.currencyCode} = ${money(p.exchangeRate)}: ${money(p.baseAmount)}'),
                  if (p.fxGain != 0) pw.Text(p.fxGain > 0 ? 'Exchange gain ${money(p.fxGain)}' : 'Exchange loss ${money(-p.fxGain)}'),
                ],
                pw.SizedBox(height: 6),
                if (p.currencyCode == null) pw.Text('Amount In Words: ${amountInWords(p.amount)}'),
                if ((p.description ?? '').isNotEmpty) ...[pw.SizedBox(height: 6), pw.Text('Description: ${p.description}')],
              ],
            ),
          ),
          if (p.allocations.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(p.type == 'in' ? 'Received against invoices' : 'Paid against bills', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: _line, width: 0.6),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: _shade),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
              headers: ['Date', 'Number', 'Total', 'This payment'],
              data: [
                for (final a in p.allocations) [a.invoiceDate == null ? '' : displayDate(a.invoiceDate), a.number, money(a.total), money(a.amount)],
                if (p.unlinkedAmount > 0) ['', 'On account / advance', '', money(p.unlinkedAmount)],
              ],
            ),
          ],
          pw.SizedBox(height: 28),
          _signature(firm, options.signature),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Any report as a printable table: landscape when it has many columns.
Future<Uint8List> buildReportPdf(ReportData report, Firm firm) async {
  final doc = pw.Document(theme: await _theme(), title: report.title);
  final format = report.columns.length > 6 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(28),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 9)),
      ),
      build: (_) => [
        pw.Text(firm.name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.Text(report.title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.Text(report.subtitle, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _shade),
              children: [
                for (final c in report.columns)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                    child: pw.Text(
                      c.label,
                      textAlign: c.numeric ? pw.TextAlign.right : pw.TextAlign.left,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                    ),
                  ),
              ],
            ),
            for (final row in report.rows)
              pw.TableRow(
                children: [
                  for (final c in report.columns)
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                      child: pw.Text(
                        reportCell(row[c.key], c.type),
                        textAlign: c.numeric ? pw.TextAlign.right : pw.TextAlign.left,
                        style: pw.TextStyle(fontSize: 9, fontWeight: row['_bold'] == true ? pw.FontWeight.bold : null),
                      ),
                    ),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Wrap(
          spacing: 24,
          runSpacing: 4,
          children: [
            for (final f in report.summary)
              pw.RichText(
                text: pw.TextSpan(
                  style: const pw.TextStyle(fontSize: 10),
                  children: [
                    pw.TextSpan(text: '${f.label}: '),
                    pw.TextSpan(
                      text: reportCell(f.value, f.type),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}
