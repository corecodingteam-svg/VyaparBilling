import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/auth/bloc/auth_bloc.dart';
import 'file_io.dart';
import 'theme.dart';
import 'widgets.dart';

/// What a list page shows as a table. Cells are [String]s, or [num]s that stay numbers in Excel.
class TableExport {
  const TableExport({required this.title, required this.headers, required this.rows, this.subtitle});
  final String title;
  final String? subtitle;
  final List<String> headers;
  final List<List<Object?>> rows;

  String get fileBase => title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
}

String _colName(int i) {
  var n = i + 1, s = '';
  while (n > 0) {
    s = String.fromCharCode(65 + (n - 1) % 26) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String _xml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

/// Builds a minimal .xlsx workbook (one sheet, bold header row) from [table].
Uint8List buildXlsx(TableExport table) {
  final sheet = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetData>');
  void writeRow(int r, List<Object?> values, {bool header = false}) {
    sheet.write('<row r="$r">');
    for (var c = 0; c < values.length; c++) {
      final ref = '${_colName(c)}$r';
      final v = values[c];
      final style = header ? ' s="1"' : '';
      if (v is num && v.isFinite) {
        sheet.write('<c r="$ref"$style><v>$v</v></c>');
      } else if (v != null && '$v'.isNotEmpty) {
        sheet.write('<c r="$ref"$style t="inlineStr"><is><t xml:space="preserve">${_xml('$v')}</t></is></c>');
      }
    }
    sheet.write('</row>');
  }

  writeRow(1, table.headers, header: true);
  for (var i = 0; i < table.rows.length; i++) {
    writeRow(i + 2, table.rows[i]);
  }
  sheet.write('</sheetData></worksheet>');

  final cleaned = table.title.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
  final sheetName = _xml(cleaned.isEmpty ? 'Sheet1' : cleaned.substring(0, cleaned.length.clamp(1, 31)));
  const header = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  final files = <String, String>{
    '[Content_Types].xml': '$header<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    '_rels/.rels': '$header<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '$header<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="$sheetName" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '$header<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/styles.xml': '$header<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs></styleSheet>',
    'xl/worksheets/sheet1.xml': sheet.toString(),
  };
  final archive = Archive();
  files.forEach((name, text) {
    final data = utf8.encode(text);
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Renders [table] as a PDF: landscape when there are many columns, header repeated on every page.
Future<Uint8List> buildTablePdf(TableExport table, {required String firmName}) async {
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
    bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
  );
  final doc = pw.Document(title: table.title, theme: theme);
  final numeric = [for (var c = 0; c < table.headers.length; c++) table.rows.isNotEmpty && table.rows.every((r) => c < r.length && (r[c] is num || r[c] == null))];
  String text(Object? v) => v is num ? (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2)) : (v ?? '').toString();
  doc.addPage(pw.MultiPage(
    pageFormat: table.headers.length > 6 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    header: (_) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(firmName, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.Text(table.title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        if (table.subtitle != null) pw.Text(table.subtitle!, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ]),
    ),
    footer: (c) => pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
    build: (_) => [
      pw.TableHelper.fromTextArray(
        headers: table.headers,
        data: [for (final r in table.rows) [for (final v in r) text(v)]],
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF7C3AED)),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignments: {for (var c = 0; c < numeric.length; c++) c: numeric[c] ? pw.Alignment.centerRight : pw.Alignment.centerLeft},
        oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF9FAFB)),
        border: pw.TableBorder(horizontalInside: const pw.BorderSide(color: PdfColor.fromInt(0xFFE5E7EB), width: 0.5)),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      ),
      if (table.rows.isEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 16), child: pw.Text('Nothing to show.')),
    ],
  ));
  return doc.save();
}

/// The Export / Print control every list page offers. [build] is called when an option is chosen, so it reads the rows
/// the page shows at that moment.
class ExportMenu extends StatelessWidget {
  const ExportMenu({super.key, required this.table});
  final TableExport Function() table;

  Future<void> _run(BuildContext context, String choice) async {
    try {
      final t = table();
      if (choice == 'xlsx') {
        await saveBytesFile('${t.fileBase}.xlsx', buildXlsx(t), mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        if (context.mounted) showSuccess(context, 'Exported ${t.rows.length} row${t.rows.length == 1 ? '' : 's'} to Excel');
      } else {
        final bytes = await buildTablePdf(t, firmName: context.read<AuthBloc>().state.user?.firmName ?? '');
        await Printing.layoutPdf(name: t.fileBase, onLayout: (_) async => bytes);
      }
    } catch (e) {
      if (context.mounted) showError(context, 'Could not ${choice == 'xlsx' ? 'export' : 'print'}: $e');
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Export or print this list',
        onSelected: (v) => _run(context, v),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'xlsx', child: ListTile(dense: true, leading: Icon(Icons.table_chart_outlined), title: Text('Export to Excel'))),
          PopupMenuItem(value: 'print', child: ListTile(dense: true, leading: Icon(Icons.print_outlined), title: Text('Print'))),
        ],
        icon: const Icon(Icons.file_download_outlined),
        style: IconButton.styleFrom(side: const BorderSide(color: AppColors.border), minimumSize: const Size.square(AppSize.control)),
      );
}
