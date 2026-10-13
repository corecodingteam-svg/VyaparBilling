import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../data/models/report.dart';
import '../../shared/theme.dart';
import '../../shared/value_cubit.dart';
import 'report_format.dart';

enum ChartKind { bar, line, pie }

/// One bar / point / slice: every row of the report with this [label] added up.
class ChartPoint {
  const ChartPoint(this.label, this.value);
  final String label;
  final num value;
}

/// What a report's chart shows: the rows grouped by [labelColumn], adding up [valueColumn].
class ChartSpec {
  const ChartSpec({required this.labelColumn, required this.valueColumns, required this.valueColumn, required this.points, required this.byDate, required this.hiddenCount});
  final ReportColumn labelColumn;
  final List<ReportColumn> valueColumns;
  final ReportColumn valueColumn;
  final List<ChartPoint> points;
  final bool byDate;

  /// Rows beyond the biggest few, left off so the chart stays readable.
  final int hiddenCount;

  bool get canPie => points.length <= 8 && points.every((p) => p.value > 0);
}

const _labelHints = ['party', 'name', 'item', 'category', 'account', 'particular', 'user', 'type', 'hsn', 'sac', 'description', 'head'];
const _valueHints = ['total', 'amount', 'balance', 'value', 'closing', 'net', 'taxable', 'profit', 'sale', 'quantity'];
const maxChartPoints = 15;

/// Picks a sensible chart for any report from its columns: group by the most descriptive text column (or the
/// date), add up a number column. Returns null when there is nothing worth charting (fewer than two groups).
ChartSpec? deriveChart(ReportData data, {String? valueKey}) {
  final numeric = [for (final c in data.columns) if (c.numeric) c];
  final labels = [for (final c in data.columns) if (!c.numeric) c];
  if (numeric.isEmpty || labels.isEmpty) return null;

  ReportColumn? hinted;
  for (final hint in _labelHints) {
    hinted = labels.where((c) => c.type != 'date' && (c.key.toLowerCase().contains(hint) || c.label.toLowerCase().contains(hint))).firstOrNull;
    if (hinted != null) break;
  }
  final labelCol = hinted ?? labels.first;

  ReportColumn? value = valueKey == null ? null : numeric.where((c) => c.key == valueKey).firstOrNull;
  if (value == null) {
    for (final hint in _valueHints) {
      value = numeric.where((c) => c.key.toLowerCase().contains(hint) || c.label.toLowerCase().contains(hint)).firstOrNull;
      if (value != null) break;
    }
    value ??= numeric.first;
  }

  final sums = <String, num>{};
  for (final row in data.rows) {
    if (row['_bold'] == true) continue;
    final v = row[value.key];
    if (v is! num) continue;
    final label = reportCell(row[labelCol.key], labelCol.type).trim();
    if (label.isEmpty || label == '-') continue;
    sums[label] = (sums[label] ?? 0) + v;
  }
  if (sums.length < 2) return null;

  final byDate = labelCol.type == 'date';
  var points = [for (final e in sums.entries) ChartPoint(e.key, e.value)];
  var hidden = 0;
  if (byDate) {
    // Dates display as dd/mm/yyyy; sort by the real date.
    final iso = <String, String>{for (final row in data.rows) if (row[labelCol.key] is String) reportCell(row[labelCol.key], 'date'): row[labelCol.key] as String};
    points.sort((a, b) => (iso[a.label] ?? '').compareTo(iso[b.label] ?? ''));
  } else {
    points.sort((a, b) => b.value.abs().compareTo(a.value.abs()));
  }
  if (points.length > maxChartPoints) {
    hidden = points.length - maxChartPoints;
    if (byDate) {
      points = points.sublist(points.length - maxChartPoints);
    } else {
      points = points.sublist(0, maxChartPoints);
    }
  }
  if (points.every((p) => p.value == 0)) return null;
  return ChartSpec(labelColumn: labelCol, valueColumns: numeric, valueColumn: value, points: points, byDate: byDate, hiddenCount: hidden);
}

/// The group a report row belongs to in [spec]'s chart, or null if it is a total/heading row.
String? chartLabelOf(ChartSpec spec, Map<String, dynamic> row) {
  if (row['_bold'] == true) return null;
  final label = reportCell(row[spec.labelColumn.key], spec.labelColumn.type).trim();
  return label.isEmpty ? null : label;
}

/// Which value column the chart adds up (several can be offered), and the selected bar.
class ChartChoice {
  const ChartChoice({this.valueKey, this.kind, this.selected});
  final String? valueKey;
  final ChartKind? kind;

  /// The label of the clicked bar, point or slice; the table highlights its rows.
  final String? selected;

  ChartChoice copyWith({String? valueKey, ChartKind? kind, Object? selected = _keep}) =>
      ChartChoice(valueKey: valueKey ?? this.valueKey, kind: kind ?? this.kind, selected: identical(selected, _keep) ? this.selected : selected as String?);
  static const _keep = Object();
}

class ChartChoiceCubit extends ValueCubit<ChartChoice> {
  ChartChoiceCubit() : super(const ChartChoice());
}

/// A chart of the report above its table. Click a bar, point or slice to pick it: the matching rows light up in the table
/// and a summary appears; click it again (or Clear) to let go.
class ReportChartCard extends StatelessWidget {
  const ReportChartCard({super.key, required this.data});
  final ReportData data;

  @override
  Widget build(BuildContext context) => BlocBuilder<ChartChoiceCubit, ChartChoice>(
        builder: (context, choice) {
          final spec = deriveChart(data, valueKey: choice.valueKey);
          if (spec == null) return const SizedBox.shrink();
          final cubit = context.read<ChartChoiceCubit>();
          var kind = choice.kind ?? (spec.byDate ? ChartKind.line : ChartKind.bar);
          if (kind == ChartKind.pie && !spec.canPie) kind = ChartKind.bar;
          final selected = spec.points.any((p) => p.label == choice.selected) ? choice.selected : null;
          void pick(String? label) => cubit.set(choice.copyWith(selected: label == choice.selected ? null : label));
          final matching = selected == null ? const <Map<String, dynamic>>[] : [for (final r in data.rows) if (chartLabelOf(spec, r) == selected) r];

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: AppSpace.md, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${spec.valueColumn.label} by ${spec.labelColumn.label}', style: AppText.subtitle),
                  if (spec.valueColumns.length > 1)
                    DropdownButton<String>(
                      value: spec.valueColumn.key,
                      underline: const SizedBox.shrink(),
                      items: [for (final c in spec.valueColumns) DropdownMenuItem(value: c.key, child: Text(c.label))],
                      onChanged: (k) => cubit.set(choice.copyWith(valueKey: k, selected: null)),
                    ),
                  SegmentedButton<ChartKind>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      const ButtonSegment(value: ChartKind.bar, icon: Icon(Icons.bar_chart, size: AppIconSize.sm), tooltip: 'Bars'),
                      const ButtonSegment(value: ChartKind.line, icon: Icon(Icons.show_chart, size: AppIconSize.sm), tooltip: 'Line'),
                      ButtonSegment(value: ChartKind.pie, icon: const Icon(Icons.pie_chart_outline, size: AppIconSize.sm), tooltip: spec.canPie ? 'Share' : 'Share (needs 8 or fewer positive values)', enabled: spec.canPie),
                    ],
                    selected: {kind},
                    onSelectionChanged: (s) => cubit.set(choice.copyWith(kind: s.first, selected: null)),
                  ),
                ]),
                if (spec.hiddenCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Text(spec.byDate ? 'Showing the latest $maxChartPoints of ${maxChartPoints + spec.hiddenCount} dates.' : 'Showing the biggest $maxChartPoints of ${maxChartPoints + spec.hiddenCount}.', style: AppText.helper),
                  ),
                const SizedBox(height: AppSpace.md),
                SizedBox(
                  height: AppSize.chartHeight,
                  child: switch (kind) {
                    ChartKind.bar => _Bars(spec: spec, selected: selected, onPick: pick),
                    ChartKind.line => _Line(spec: spec, selected: selected, onPick: pick),
                    ChartKind.pie => _Pie(spec: spec, selected: selected, onPick: pick),
                  },
                ),
                AnimatedSize(
                  duration: AppMotion.fast,
                  alignment: Alignment.topCenter,
                  child: selected == null
                      ? const Padding(padding: EdgeInsets.only(top: AppSpace.sm), child: Text('Click a bar, point or slice to see its rows in the table.', style: AppText.helper))
                      : _Detail(spec: spec, label: selected, rows: matching, onClear: () => pick(selected)),
                ),
              ]),
            ),
          );
        },
      );
}

String _fmt(ReportColumn c, num v) => reportCell(v, c.type);

String _short(String s) => s.length > 12 ? '${s.substring(0, 11)}…' : s;

final _axis = NumberFormat.compact();

class _Detail extends StatelessWidget {
  const _Detail({required this.spec, required this.label, required this.rows, required this.onClear});
  final ChartSpec spec;
  final String label;
  final List<Map<String, dynamic>> rows;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final point = spec.points.firstWhere((p) => p.label == label);
    return Container(
      margin: const EdgeInsets.only(top: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.mdAll),
      child: Row(children: [
        Expanded(
          child: Text(
            '$label  ·  ${spec.valueColumn.label} ${_fmt(spec.valueColumn, point.value)}  ·  ${rows.length} row${rows.length == 1 ? '' : 's'} highlighted in the table',
            style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(onPressed: onClear, child: const Text('Clear')),
      ]),
    );
  }
}

Color _barColor(ChartSpec spec, ChartPoint p, String? selected, int i) {
  if (selected != null) return p.label == selected ? AppColors.primaryDark : AppColors.primary.withValues(alpha: 0.3);
  return p.value < 0 ? AppColors.moneyOut : AppColors.primary;
}

class _Bars extends StatelessWidget {
  const _Bars({required this.spec, required this.selected, required this.onPick});
  final ChartSpec spec;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final pts = spec.points;
    final maxV = pts.map((p) => p.value).fold<num>(0, (a, b) => b > a ? b : a);
    final minV = pts.map((p) => p.value).fold<num>(0, (a, b) => b < a ? b : a);
    return BarChart(
      BarChartData(
        maxY: maxV == 0 ? 1 : maxV * 1.15,
        minY: minV < 0 ? minV * 1.15 : 0,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 48, getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox.shrink() : Text(_axis.format(v), style: AppText.caption))),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= pts.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_short(pts[i].label), style: AppText.caption));
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem('${pts[group.x].label}\n${_fmt(spec.valueColumn, rod.toY)}', const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w600)),
          ),
          touchCallback: (event, response) {
            if (event is FlTapUpEvent && response?.spot != null) onPick(pts[response!.spot!.touchedBarGroupIndex].label);
          },
        ),
        barGroups: [
          for (var i = 0; i < pts.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: pts[i].value.toDouble(), width: pts.length <= 6 ? 40 : (pts.length <= 10 ? 24 : 14), color: _barColor(spec, pts[i], selected, i), borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
            ]),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.spec, required this.selected, required this.onPick});
  final ChartSpec spec;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final pts = spec.points;
    final maxV = pts.map((p) => p.value).fold<num>(0, (a, b) => b > a ? b : a);
    final minV = pts.map((p) => p.value).fold<num>(0, (a, b) => b < a ? b : a);
    return LineChart(
      LineChartData(
        maxY: maxV == 0 ? 1 : maxV * 1.15,
        minY: minV < 0 ? minV * 1.15 : 0,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 48, getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox.shrink() : Text(_axis.format(v), style: AppText.caption))),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: pts.length > 8 ? (pts.length / 6).ceilToDouble() : 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= pts.length || v != i.toDouble()) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_short(pts[i].label), style: AppText.caption));
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => [for (final t in touched) LineTooltipItem('${pts[t.x.toInt()].label}\n${_fmt(spec.valueColumn, t.y)}', const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w600))],
          ),
          touchCallback: (event, response) {
            final spots = response?.lineBarSpots;
            if (event is FlTapUpEvent && spots != null && spots.isNotEmpty) onPick(pts[spots.first.x.toInt()].label);
          },
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i].value.toDouble())],
            isCurved: pts.length > 2,
            preventCurveOverShooting: true,
            color: AppColors.primary,
            barWidth: 2,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, i) => FlDotCirclePainter(
                radius: pts[i].label == selected ? 6 : 3.5,
                color: pts[i].label == selected ? AppColors.primaryDark : AppColors.primary,
                strokeWidth: 2,
                strokeColor: AppColors.surface,
              ),
            ),
            belowBarData: BarAreaData(show: true, color: AppColors.primary.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }
}

class _Pie extends StatelessWidget {
  const _Pie({required this.spec, required this.selected, required this.onPick});
  final ChartSpec spec;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final pts = spec.points;
    final total = pts.fold<num>(0, (a, p) => a + p.value);
    return Row(children: [
      Expanded(
        child: PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 54,
            pieTouchData: PieTouchData(touchCallback: (event, response) {
              final i = response?.touchedSection?.touchedSectionIndex ?? -1;
              if (event is FlTapUpEvent && i >= 0) onPick(pts[i].label);
            }),
            sections: [
              for (var i = 0; i < pts.length; i++)
                PieChartSectionData(
                  value: pts[i].value.toDouble(),
                  color: AppColors.chartPalette[i % AppColors.chartPalette.length],
                  radius: pts[i].label == selected ? 62 : 52,
                  title: '${(pts[i].value / total * 100).round()}%',
                  titleStyle: const TextStyle(color: AppColors.onPrimary, fontSize: AppFont.small, fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(width: AppSpace.lg),
      SizedBox(
        width: AppSize.fieldMd,
        child: ListView(shrinkWrap: true, children: [
          for (var i = 0; i < pts.length; i++)
            InkWell(
              onTap: () => onPick(pts[i].label),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.chartPalette[i % AppColors.chartPalette.length], shape: BoxShape.circle)),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(pts[i].label, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: pts[i].label == selected ? FontWeight.w700 : FontWeight.w400))),
                  Text(_fmt(spec.valueColumn, pts[i].value), style: AppText.small),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }
}
