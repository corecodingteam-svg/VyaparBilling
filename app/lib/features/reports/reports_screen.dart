import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/status.dart';
import '../../data/models/report.dart';
import '../../data/repositories/firm_repository.dart';
import '../../shared/file_io.dart';
import '../../shared/period.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../printing/pdf_documents.dart';
import '../printing/pdf_preview_screen.dart';
import 'report_cubit.dart';
import 'report_format.dart';

const _groupIcons = {
  'Transaction': Icons.receipt_long_outlined,
  'Party': Icons.people_outline,
  'GST': Icons.account_balance_outlined,
  'Item / Stock': Icons.inventory_2_outlined,
  'Business Status': Icons.insights_outlined,
};

/// Index of every report, grouped.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => ReportCatalogCubit(ctx.read())..load(),
      child: BlocBuilder<ReportCatalogCubit, (LoadStatus, List<ReportDef>, String?)>(builder: (context, state) {
        final (status, reports, error) = state;
        if (status == LoadStatus.loading) return const Center(child: CircularProgressIndicator());
        if (status == LoadStatus.failure) {
          return ErrorRetry(error: error ?? 'Could not load', onRetry: context.read<ReportCatalogCubit>().load);
        }
        final groups = <String, List<ReportDef>>{};
        for (final r in reports) {
          groups.putIfAbsent(r.group, () => []).add(r);
        }
        return ListView(padding: const EdgeInsets.all(12), children: [
          const Text('Reports', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          for (final g in groups.entries) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_groupIcons[g.key] ?? Icons.bar_chart, color: brandBlue, size: 20),
                    const SizedBox(width: 8),
                    Text('${g.key} Reports', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final r in g.value)
                      OutlinedButton(
                        onPressed: () => context.go('/reports/${r.id}'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(r.title),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right, size: 18),
                        ]),
                      ),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ]);
      }),
    );
  }
}

/// One report: filters, headline figures, the table, and print/export.
class ReportViewScreen extends StatelessWidget {
  const ReportViewScreen({super.key, required this.reportId});
  final String reportId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => ReportCubit(ctx.read(), ctx.read(), ctx.read(), reportId, items: ctx.read())..load(),
        child: const _ReportView(),
      );
}

class _ReportView extends StatelessWidget {
  const _ReportView();

  void _print(BuildContext context, ReportData data) {
    final firms = context.read<FirmRepository>();
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      builder: (_) => PdfPreviewScreen(
        title: data.title,
        fallbackPath: '/reports/${data.id}',
        buildPdf: (_) async => ('${data.id}.pdf', await buildReportPdf(data, await firms.get())),
      ),
    ));
  }

  Future<void> _export(BuildContext context, ReportData data) async {
    try {
      await saveTextFile('${data.id}.csv', reportCsv(data));
      if (context.mounted) showSuccess(context, 'Exported ${data.id}.csv');
    } catch (e) {
      if (context.mounted) showError(context, 'Could not save the file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReportCubit, ReportState>(builder: (context, state) {
      final cubit = context.read<ReportCubit>();
      final def = state.def;
      final data = state.data;
      if (def == null) {
        return state.status == LoadStatus.failure
            ? ErrorRetry(error: state.error ?? 'Could not load', onRetry: cubit.load)
            : const Center(child: CircularProgressIndicator());
      }
      return ListView(padding: const EdgeInsets.all(12), children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'All reports', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/reports')),
            Flexible(child: Text(def.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          ]),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: data == null ? null : () => _export(context, data),
              icon: const Icon(Icons.table_view_outlined, size: 18),
              label: const Text('Export CSV'),
            ),
            FilledButton.icon(
              onPressed: data == null ? null : () => _print(context, data),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Print / PDF'),
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        if (def.hasSelector)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 340,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('sel-${state.selectedId}-${state.options.length}'),
                    initialValue: state.options.any((o) => o.$1 == state.selectedId) ? state.selectedId : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: def.selectorLabel),
                    items: [
                      if (!def.selectionRequired) const DropdownMenuItem(value: null, child: Text('All parties')),
                      for (final o in state.options) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: cubit.selectionChanged,
                  ),
                ),
              ),
            ),
          ),
        if (def.hasSelector) const SizedBox(height: 12),
        if (def.needsPeriod) ...[
          PeriodFilterBar(range: state.range, onChanged: cubit.rangeChanged),
          const SizedBox(height: 12),
        ],
        if (state.status == LoadStatus.failure)
          SizedBox(height: 280, child: ErrorRetry(error: state.error ?? 'Could not load', onRetry: cubit.load))
        else if (state.awaitingSelection)
          Card(
            child: SizedBox(
              height: 260,
              child: EmptyState(
                icon: Icons.touch_app_outlined,
                title: def.needsParty ? 'Select a party to see its statement' : 'Select ${def.needsItem ? 'an item' : 'a bank account'}',
                message: state.options.isEmpty ? 'You have no ${def.needsParty ? 'parties' : (def.needsItem ? 'products' : 'bank accounts')} yet.' : null,
              ),
            ),
          )
        else if (data == null)
          const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()))
        else ...[
          if (data.summary.isNotEmpty)
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final f in data.summary)
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 180),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(f.label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(reportCell(f.value, f.type), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
            ]),
          const SizedBox(height: 12),
          Opacity(
            // Dim the previous result while a new one loads.
            opacity: state.status == LoadStatus.loading ? 0.5 : 1,
            child: Card(clipBehavior: Clip.antiAlias, child: _ReportTable(data: data)),
          ),
        ],
      ]);
    });
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.data});
  final ReportData data;

  @override
  Widget build(BuildContext context) {
    if (data.rows.isEmpty) {
      return const SizedBox(height: 240, child: EmptyState(icon: Icons.inbox_outlined, title: 'No data for this selection'));
    }
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth),
          child: DataTable(
            headingRowColor: const WidgetStatePropertyAll(pageBg),
            columnSpacing: 28,
            columns: [for (final col in data.columns) DataColumn(label: Text(col.label), numeric: col.numeric)],
            rows: [
              for (final row in data.rows)
                DataRow(
                  color: row['_bold'] == true ? const WidgetStatePropertyAll(Color(0xFFF7F9FC)) : null,
                  cells: [
                    for (final col in data.columns)
                      DataCell(Text(
                        reportCell(row[col.key], col.type),
                        style: row['_bold'] == true ? const TextStyle(fontWeight: FontWeight.w700) : null,
                      )),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
