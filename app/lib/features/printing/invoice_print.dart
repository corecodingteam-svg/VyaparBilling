import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/invoice.dart';
import '../../data/repositories/accounting_repository.dart';
import '../../data/repositories/files_repository.dart';
import '../../data/repositories/firm_repository.dart';
import '../../data/repositories/invoices_repository.dart';
import '../../data/repositories/parties_repository.dart';
import 'pdf_documents.dart';
import 'thermal/direct_print.dart' show PrinterPrefs;
import 'thermal/escpos.dart';
import 'thermal/raster.dart';

/// Layout id of the thermal receipt (the others are the invoice theme names).
const thermalLayout = 'thermal';

/// The invoice as raw ESC/POS bytes for a receipt printer.
Future<Uint8List> renderReceiptBytes(BuildContext context, String invoiceId, [PrinterPrefs prefs = const PrinterPrefs()]) async {
  final files = context.read<FilesRepository>();
  final (invoice, firm) = await (context.read<InvoicesRepository>().get(invoiceId), context.read<FirmRepository>().get()).wait;
  // The logo is optional: a receipt still prints if it cannot be fetched or read.
  final logoBytes = prefs.logo ? await files.bytesOrNull(firm.logoFileId) : null;
  return buildReceiptBytes(
    invoice,
    firm,
    options: ReceiptOptions(
      codePage: prefs.codePage,
      openDrawer: prefs.openDrawer,
      qr: prefs.qr,
      logo: logoBytes == null ? null : toMonoImage(logoBytes, maxWidth: firm.settings.thermalWidth <= 58 ? 200 : 280),
    ),
  );
}

/// Loads everything an invoice prints with — the document, the business, its logo and signature,
/// the party's printable fields and the currency symbol — and renders it in [layout]:
/// an invoice theme, [thermalLayout], or null for the theme saved in settings.
/// Returns (file name, pdf bytes).
Future<(String, Uint8List)> renderInvoice(BuildContext context, String invoiceId, String? layout) async {
  final files = context.read<FilesRepository>();
  final parties = context.read<PartiesRepository>();
  final accounting = context.read<AccountingRepository>();
  final (invoice, firm) = await (context.read<InvoicesRepository>().get(invoiceId), context.read<FirmRepository>().get()).wait;
  final kind = InvoiceKind.of(invoice.type);
  final name = invoice.number.isEmpty ? kind.type : '${kind.type}-${invoice.number}';
  final logo = await files.bytesOrNull(firm.logoFileId);
  if (layout == thermalLayout) return ('$name-receipt.pdf', await buildThermalReceiptPdf(invoice, firm, logo: logo));

  final signature = await files.bytesOrNull(firm.signatureFileId);
  // Optional extras: the invoice still prints if one of them cannot be fetched.
  var partyFields = const <(String, String)>[];
  final printable = {for (final f in firm.settings.partyFields.where((f) => f.showInPrint)) f.name};
  if (invoice.partyId != null && printable.isNotEmpty) {
    try {
      final party = await parties.get(invoice.partyId!);
      partyFields = [
        for (final f in party.additionalFields)
          if (printable.contains(f.name) && f.value.trim().isNotEmpty) (f.name, f.value),
      ];
    } catch (_) {}
  }
  String? symbol;
  if (invoice.currencyCode != null) {
    try {
      symbol = (await accounting.currencies()).where((c) => c.code == invoice.currencyCode).firstOrNull?.symbol;
    } catch (_) {}
  }
  final itemImages = <String, Uint8List>{};
  if (firm.settings.itemImagesOnInvoice) {
    for (final id in {for (final l in invoice.lines) ?l.imageFileId}) {
      final bytes = await files.bytesOrNull(id);
      if (bytes != null) itemImages[id] = bytes;
    }
  }
  final options = PrintOptions.of(firm, logo: logo, signature: signature, partyFields: partyFields, currencySymbol: symbol, theme: layout, itemImages: itemImages);
  return ('$name.pdf', await buildInvoicePdf(invoice, firm, options: options));
}
