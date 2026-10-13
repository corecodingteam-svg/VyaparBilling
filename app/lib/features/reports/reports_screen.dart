import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/status.dart';
import '../../data/models/report.dart';
import '../../data/repositories/firm_repository.dart';
import '../../shared/data_table_view.dart';
import '../../shared/export.dart';
import '../../shared/file_io.dart';
import '../../shared/period.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../printing/pdf_documents.dart';
import '../printing/pdf_preview_screen.dart';
import 'report_chart.dart';
import 'report_cubit.dart';
import 'report_format.dart';

/// `/reports` itself: the reports are listed under Reports in the sidebar, so this only points there.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => const EmptyState(
        icon: Icons.bar_chart_outlined,
        title: 'Reports',
        message: 'Open Reports in the menu and pick a group, then a report.',
      );
}

/// One report: filters, headline figures, the table, and print/export.
class ReportViewScreen extends StatelessWidget {
  const ReportViewScreen({super.key, required this.reportId});
  final String reportId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => ReportCubit(ctx.read(), ctx.read(), ctx.read(), reportId, items: ctx.read())..load(),
        child: BlocProvider(create: (_) => ChartChoiceCubit(), child: const _ReportView()),
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
      final table = reportTable(data);
      await saveBytesFile('${table.fileBase}.xlsx', buildXlsx(table), mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      if (context.mounted) showSuccess(context, 'Exported ${table.fileBase}.xlsx');
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
            : const LoadingView();
      }
      return PullToRefresh(onRefresh: cubit.load, child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'All reports', icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/reports')),
            Flexible(child: Text(def.title, style: AppText.title, overflow: TextOverflow.ellipsis)),
          ]),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: data == null ? null : () => _export(context, data),
              icon: const Icon(Icons.table_view_outlined, size: AppIconSize.sm),
              label: const Text('Export to Excel'),
            ),
            FilledButton.icon(
              onPressed: data == null ? null : () => _print(context, data),
              icon: const Icon(Icons.print_outlined, size: AppIconSize.sm),
              label: const Text('Print / PDF'),
            ),
          ]),
        ]),
        const SizedBox(height: AppSpace.md),
        if (def.hasSelector)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: AppSize.dialogSm,
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
        if (def.hasSelector) const SizedBox(height: AppSpace.md),
        if (def.needsPeriod) ...[
          PeriodFilterBar(range: state.range, onChanged: cubit.rangeChanged),
          const SizedBox(height: AppSpace.md),
        ],
        if (state.status == LoadStatus.failure)
          SizedBox(height: AppSize.stateHeight, child: ErrorRetry(error: state.error ?? 'Could not load', onRetry: cubit.load))
        else if (state.awaitingSelection)
          Card(
            child: SizedBox(
              height: AppSize.stateHeight,
              child: EmptyState(
                icon: Icons.touch_app_outlined,
                title: def.needsParty ? 'Select a party to see its statement' : 'Select ${def.needsItem ? 'an item' : 'a bank account'}',
                message: state.options.isEmpty ? 'You have no ${def.needsParty ? 'parties' : (def.needsItem ? 'products' : 'bank accounts')} yet.' : null,
              ),
            ),
          )
        else if (data == null)
          const SizedBox(height: AppSize.stateHeight, child: LoadingView())
        else ...[
          if (data.summary.isNotEmpty)
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final f in data.summary)
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: AppSize.fieldSm),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(f.label, style: const TextStyle(color: AppColors.textMuted, fontSize: AppFont.body)),
                        const SizedBox(height: AppSpace.xs),
                        Text(reportCell(f.value, f.type), style: AppText.title),
                      ]),
                    ),
                  ),
                ),
            ]),
          const SizedBox(height: AppSpace.md),
          Opacity(
            // Dim the previous result while a new one loads.
            opacity: state.status == LoadStatus.loading ? 0.5 : 1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ReportChartCard(data: data),
              const SizedBox(height: AppSpace.md),
              Card(clipBehavior: Clip.antiAlias, child: _ReportTable(data: data)),
            ]),
          ),
        ],
      ]));
    });
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.data});
  final ReportData data;

  @override
  Widget build(BuildContext context) {
    if (data.rows.isEmpty) {
      return const SizedBox(height: AppSize.stateHeight, child: EmptyState(icon: Icons.inbox_outlined, title: 'No data for this selection'));
    }
    // Rows of the clicked bar / slice in the chart light up; clicking a row picks its group in the chart.
    final choice = context.watch<ChartChoiceCubit>().state;
    final spec = deriveChart(data, valueKey: choice.valueKey);
    final selected = spec != null && spec.points.any((p) => p.label == choice.selected) ? choice.selected : null;
    // In a statement (balance sheet, profit & loss) the headings sit between the figures, so the order must stay.
    final structured = [for (var i = 0; i < data.rows.length - 1; i++) data.rows[i]].any((r) => r['_bold'] == true);
    return PagedDataTable(
      plain: structured,
      searchHint: 'Search this report',
      columnSpacing: 28,
      columns: [for (final col in data.columns) TableColumnSpec(col.label, numeric: col.numeric)],
      rows: [
        for (final row in data.rows)
          () {
            final bold = row['_bold'] == true;
            final label = spec == null ? null : chartLabelOf(spec, row);
            final pickable = label != null && spec!.points.any((p) => p.label == label);
            return TableRowData(
              pinned: bold && !structured, // a totals row keeps its place at the bottom
              selected: selected != null && label == selected,
              color: bold ? AppColors.surfaceMuted : null,
              onTap: pickable ? () => context.read<ChartChoiceCubit>().set(choice.copyWith(selected: label == choice.selected ? null : label)) : null,
              search: [for (final col in data.columns) reportCell(row[col.key], col.type)].join(' '),
              sort: [for (final col in data.columns) col.numeric ? (row[col.key] is num ? row[col.key] : null) : row[col.key]],
              cells: [
                for (final col in data.columns)
                  Text(reportCell(row[col.key], col.type), style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
              ],
            );
          }(),
      ],
    );
  }}
