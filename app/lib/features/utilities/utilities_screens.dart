import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/status.dart';
import '../../data/models/item.dart';
import '../../data/repositories/items_repository.dart';
import '../../shared/csv.dart';
import '../../shared/file_io.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../printing/pdf_preview_screen.dart';
import 'import_spec.dart';
import 'utilities_cubits.dart';

Future<void> _saveCsv(BuildContext context, String fileName, String csv) async {
  try {
    await saveTextFile(fileName, csv);
    if (context.mounted) showSuccess(context, 'Saved $fileName');
  } catch (_) {
    if (context.mounted) showError(context, 'Could not save the file.');
  }
}

Widget _page(String title, List<Widget> children) => ListView(padding: const EdgeInsets.all(12), children: [
      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      ...children,
    ]);

// ---------------------------------------------------------------- import (items / parties)

class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key, required this.spec});
  final ImportSpec spec;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => ImportCubit(ctx.read(), ctx.read(), spec),
        child: const _ImportView(),
      );
}

class _ImportView extends StatelessWidget {
  const _ImportView();

  Future<void> _pick(BuildContext context) async {
    final cubit = context.read<ImportCubit>();
    try {
      final text = await pickCsvFile();
      if (text != null) cubit.fileChosen(text);
    } catch (_) {
      if (context.mounted) showError(context, 'Could not read that file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ImportCubit, ImportState>(
      listenWhen: (a, b) => a.status != b.status && b.status == SubmitStatus.failure,
      listener: (context, s) => showError(context, s.error!),
      builder: (context, state) {
        final cubit = context.read<ImportCubit>();
        final spec = cubit.spec;
        return _page(spec.title, [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('1. Prepare a CSV file with these columns', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final h in spec.headers)
                    Chip(label: Text(h == spec.headers.first ? '$h *' : h), visualDensity: VisualDensity.compact, backgroundColor: pageBg, side: BorderSide.none),
                ]),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _saveCsv(context, spec.fileName, cubit.sampleCsv),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download sample file'),
                ),
                const SizedBox(height: 12),
                const Text('2. Choose your file', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  FilledButton.icon(onPressed: () => _pick(context), icon: const Icon(Icons.upload_file_outlined), label: const Text('Choose CSV file')),
                  if (state.rows.isNotEmpty || state.fileError != null) TextButton(onPressed: cubit.reset, child: const Text('Clear')),
                ]),
                if (state.fileError != null)
                  Padding(padding: const EdgeInsets.only(top: 10), child: Text(state.fileError!, style: const TextStyle(color: payRed))),
              ]),
            ),
          ),
          if (state.rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
                    Text.rich(TextSpan(children: [
                      const TextSpan(text: '3. Review   ', style: TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: '${state.valid.length} ready', style: const TextStyle(color: receiveGreen, fontWeight: FontWeight.w600)),
                      if (state.invalid.isNotEmpty)
                        TextSpan(text: '   ${state.invalid.length} with problems (skipped)', style: const TextStyle(color: payRed, fontWeight: FontWeight.w600)),
                    ])),
                    if (!state.done)
                      FilledButton(
                        onPressed: state.valid.isEmpty || state.status == SubmitStatus.submitting ? null : cubit.import,
                        child: state.status == SubmitStatus.submitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text('Import ${state.valid.length} ${state.valid.length == 1 ? spec.noun : (spec.noun == 'party' ? 'parties' : '${spec.noun}s')}'),
                      ),
                  ]),
                ),
                if (state.done)
                  Container(
                    color: receiveGreen.withValues(alpha: 0.08),
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${state.created} imported${state.serverErrors.isEmpty ? '' : ', ${state.serverErrors.length} rejected'}.',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      for (final (line, name, message) in state.serverErrors)
                        Padding(padding: const EdgeInsets.only(top: 4), child: Text('Line $line · $name: $message', style: const TextStyle(color: payRed))),
                    ]),
                  ),
                const Divider(),
                for (final r in state.rows.take(200))
                  ListTile(
                    dense: true,
                    leading: Icon(r.error == null ? Icons.check_circle_outline : Icons.error_outline, color: r.error == null ? receiveGreen : payRed, size: 20),
                    title: Text(r.name.isEmpty ? '(no name)' : r.name),
                    subtitle: r.error == null ? null : Text(r.error!, style: const TextStyle(color: payRed)),
                    trailing: Text('Line ${r.line}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ),
                if (state.rows.length > 200)
                  Padding(padding: const EdgeInsets.all(12), child: Text('… and ${state.rows.length - 200} more rows', style: const TextStyle(color: Colors.black54))),
              ]),
            ),
          ],
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- export items

/// Item list as CSV, in the same columns the import accepts (so it can be edited and re-imported elsewhere).
String itemsCsv(List<Item> items) => toCsv([
      itemImportSpec.headers,
      for (final i in items)
        [
          i.name, i.type, i.itemCode ?? '', i.hsnCode ?? '', i.unit ?? '', i.categoryName ?? '',
          numText(i.salePrice), numText(i.purchasePrice), numText(i.gstRate), i.isProduct ? numText(i.stockQty) : '', numText(i.minStock),
        ],
    ]);

class ExportItemsScreen extends StatelessWidget {
  const ExportItemsScreen({super.key});

  Future<void> _export(BuildContext context) async {
    try {
      final items = await context.read<ItemsRepository>().list('all');
      if (context.mounted) await _saveCsv(context, 'items.csv', itemsCsv(items));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => _page('Export Items', [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Download all your products and services as a CSV file that opens in Excel or Google Sheets.'),
              const SizedBox(height: 6),
              const Text('The "Opening Stock" column holds each item\'s current stock.', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: () => _export(context), icon: const Icon(Icons.download_outlined), label: const Text('Export Items')),
            ]),
          ),
        ),
      ]);
}

// ---------------------------------------------------------------- bulk update items

class BulkUpdateItemsScreen extends StatelessWidget {
  const BulkUpdateItemsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => BulkUpdateCubit(ctx.read(), ctx.read(), ctx.read())..load(),
        child: const _BulkUpdateView(),
      );
}

class _BulkUpdateView extends StatelessWidget {
  const _BulkUpdateView();

  static const _cell = InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10));

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BulkUpdateCubit, BulkUpdateState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == SubmitStatus.failure) showError(context, s.error!);
        if (s.status == SubmitStatus.success) showSuccess(context, '${s.updated} items updated');
      },
      builder: (context, state) {
        final cubit = context.read<BulkUpdateCubit>();
        if (state.loadStatus == LoadStatus.loading) return const Center(child: CircularProgressIndicator());
        if (state.loadStatus == LoadStatus.failure) return ErrorRetry(error: state.error ?? 'Could not load', onRetry: cubit.load);
        final changed = state.changed.length;
        final busy = state.status == SubmitStatus.submitting;

        Widget number(Item i, String field, String value, ItemEdit Function(ItemEdit, String) set) => SizedBox(
              width: 110,
              child: TextFormField(
                key: ValueKey('${i.id}-$field-${state.rev}'),
                initialValue: value,
                onChanged: (v) => cubit.edit(i, (e) => set(e, v)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                decoration: _cell,
              ),
            );

        return Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
              // Full-width row on wide screens so the title sits left and the actions right.
              SizedBox(
                width: isWide(context) ? 260 : double.infinity,
                child: const Text('Bulk Update Items', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              ),
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 240,
                  child: TextField(onChanged: cubit.searchChanged, decoration: const InputDecoration(hintText: 'Search items', prefixIcon: Icon(Icons.search))),
                ),
                if (changed > 0) TextButton(onPressed: busy ? null : cubit.discard, child: const Text('Discard')),
                FilledButton(
                  onPressed: changed == 0 || busy ? null : cubit.save,
                  child: Text(changed == 0 ? 'No changes' : 'Save $changed ${changed == 1 ? 'change' : 'changes'}'),
                ),
              ]),
            ]),
          ),
          Expanded(
            child: state.items.isEmpty
                ? const EmptyState(icon: Icons.inventory_2_outlined, title: 'No items to update')
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        child: LayoutBuilder(
                          builder: (context, c) => SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: c.maxWidth),
                              child: DataTable(
                                headingRowColor: const WidgetStatePropertyAll(pageBg),
                                dataRowMinHeight: 56,
                                dataRowMaxHeight: 56,
                                columns: const [
                                  DataColumn(label: Text('Item')),
                                  DataColumn(label: Text('Sale Price')),
                                  DataColumn(label: Text('Purchase Price')),
                                  DataColumn(label: Text('Tax Rate')),
                                  DataColumn(label: Text('Min Stock')),
                                ],
                                rows: [
                                  for (final i in state.visible)
                                    DataRow(
                                      color: state.changed.contains(i) ? WidgetStatePropertyAll(brandBlue.withValues(alpha: 0.06)) : null,
                                      cells: [
                                        DataCell(Text(i.name)),
                                        DataCell(number(i, 'sale', state.editOf(i).salePrice, (e, v) => e.copyWith(salePrice: v))),
                                        DataCell(number(i, 'purchase', state.editOf(i).purchasePrice, (e, v) => e.copyWith(purchasePrice: v))),
                                        DataCell(SizedBox(
                                          width: 130,
                                          child: DropdownButtonFormField<num?>(
                                            key: ValueKey('${i.id}-gst-${state.rev}-${state.editOf(i).gstRate}'),
                                            initialValue: gstRateOptions.contains(state.editOf(i).gstRate) ? state.editOf(i).gstRate : null,
                                            isExpanded: true,
                                            decoration: _cell,
                                            items: [
                                              const DropdownMenuItem(value: null, child: Text('None')),
                                              for (final r in gstRateOptions) DropdownMenuItem(value: r, child: Text('GST@${numText(r)}%')),
                                            ],
                                            onChanged: (v) => cubit.edit(i, (e) => e.copyWith(gstRate: () => v)),
                                          ),
                                        )),
                                        DataCell(i.isProduct
                                            ? number(i, 'min', state.editOf(i).minStock, (e, v) => e.copyWith(minStock: v))
                                            : const Text('-', style: TextStyle(color: Colors.black38))),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- barcode generator

/// A4 sheet of barcode labels (3 across), one Code 128 barcode of the item code per label.
Future<pw.Document> buildBarcodeSheet(List<(Item, int)> labels, {required bool showPrice}) async {
  final doc = pw.Document(title: 'Barcode labels');
  final cells = [
    for (final (item, count) in labels)
      for (var n = 0; n < count; n++) item,
  ];
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(24),
    build: (_) => [
      pw.Wrap(spacing: 8, runSpacing: 8, children: [
        for (final item in cells)
          pw.Container(
            width: 176,
            height: 84,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
            child: pw.Column(children: [
              pw.Text(item.name, maxLines: 1, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Expanded(child: pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: item.itemCode!, textStyle: const pw.TextStyle(fontSize: 8))),
              // "Rs." rather than the rupee sign: the built-in PDF font has no glyph for it.
              if (showPrice) pw.Text('Rs. ${item.salePrice.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
            ]),
          ),
      ]),
    ],
  ));
  return doc;
}

class BarcodeGeneratorScreen extends StatelessWidget {
  const BarcodeGeneratorScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(create: (ctx) => BarcodeCubit(ctx.read())..load(), child: const _BarcodeView());
}

class _BarcodeView extends StatelessWidget {
  const _BarcodeView();

  void _preview(BuildContext context, BarcodeState state) {
    final labels = [for (final i in state.items) if (state.labels[i.id] != null) (i, state.labels[i.id]!)];
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      builder: (_) => PdfPreviewScreen(
        title: 'Barcode Labels',
        fallbackPath: '/barcode',
        buildPdf: (_) async => ('barcode-labels.pdf', await (await buildBarcodeSheet(labels, showPrice: state.showPrice)).save()),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BarcodeCubit, BarcodeState>(builder: (context, state) {
      final cubit = context.read<BarcodeCubit>();
      if (state.loadStatus == LoadStatus.loading) return const Center(child: CircularProgressIndicator());
      if (state.loadStatus == LoadStatus.failure) return ErrorRetry(error: state.error ?? 'Could not load', onRetry: cubit.load);
      return _page('Barcode Generator', [
        if (state.items.isEmpty)
          const Card(
            child: SizedBox(
              height: 280,
              child: EmptyState(
                icon: Icons.qr_code_2,
                title: 'No items with an item code',
                message: 'Open an item and use "Assign Code" (or type your own) to print barcodes for it.',
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(value: state.showPrice, onChanged: (v) => cubit.showPriceChanged(v!)),
                    const Text('Print sale price on labels'),
                  ]),
                  FilledButton.icon(
                    onPressed: state.total == 0 ? null : () => _preview(context, state),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: Text(state.total == 0 ? 'Enter label counts' : 'Preview ${state.total} labels'),
                  ),
                ]),
              ),
              const Divider(),
              for (final i in state.items)
                ListTile(
                  title: Text(i.name),
                  subtitle: Text('Code ${i.itemCode} · ${money(i.salePrice)}'),
                  trailing: SizedBox(
                    width: 110,
                    child: TextFormField(
                      key: ValueKey('labels-${i.id}'),
                      initialValue: state.labels[i.id]?.toString() ?? '',
                      onChanged: (v) => cubit.setLabels(i.id, int.tryParse(v.trim()) ?? 0),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(labelText: 'Labels'),
                    ),
                  ),
                ),
            ]),
          ),
      ]);
    });
  }
}
