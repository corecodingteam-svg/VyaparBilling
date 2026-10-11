import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/status.dart';
import '../../data/models/dashboard_summary.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/bloc/auth_bloc.dart';
import '../company/firm_cubit.dart';
import 'dashboard_cubit.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => DashboardCubit(ctx.read(), ctx.read())..load(),
      child: BlocBuilder<DashboardCubit, DashboardState>(builder: (context, state) {
        final s = state.summary;
        if (s == null) {
          return state.status == LoadStatus.failure
              ? ErrorRetry(error: state.error!, onRetry: context.read<DashboardCubit>().load)
              : const Center(child: CircularProgressIndicator());
        }
        final cards = [
          _StatCard(
            title: 'Total Receivable',
            amount: money(s.receivable),
            caption: s.receivableParties == 0 ? "You don't have any receivables as of now." : 'From ${s.receivableParties} ${s.receivableParties == 1 ? 'Party' : 'Parties'}',
            icon: Icons.south,
            color: receiveGreen,
            onTap: () => context.go('/parties'),
          ),
          _StatCard(
            title: 'Total Payable',
            amount: money(s.payable),
            caption: s.payableParties == 0 ? "You don't have any payables as of now." : 'To ${s.payableParties} ${s.payableParties == 1 ? 'Party' : 'Parties'}',
            icon: Icons.north,
            color: payRed,
            onTap: () => context.go('/parties'),
          ),
          // Salesmen do not see the business's cash and bank position.
          if (!(context.select((AuthBloc b) => b.state.user?.isSalesman ?? false)))
          _StatCard(
            title: 'Cash In Hand',
            amount: money(s.cashInHand),
            caption: 'Bank balance: ${money(s.bankBalance)}',
            icon: Icons.account_balance_wallet_outlined,
            color: brandBlue,
            onTap: () => context.go('/cash-in-hand'),
          ),
          if (settingsOf(context, listen: true).stockMaintenance)
          _StatCard(
            title: 'Low Stock Items',
            amount: '${s.lowStockItems}',
            caption: s.lowStockItems == 0 ? 'All items are above their minimum stock.' : 'Items at or below minimum stock',
            icon: Icons.inventory_2_outlined,
            color: Colors.orange.shade700,
            onTap: () => context.go('/items'),
          ),
        ];
        return ListView(padding: const EdgeInsets.all(12), children: [
          LayoutBuilder(
            builder: (_, c) {
              // 4 across on wide screens, 2×2 on tablets, stacked on phones.
              final perRow = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
              final width = (c.maxWidth - (perRow - 1) * 12) / perRow;
              return Wrap(spacing: 12, runSpacing: 12, children: [for (final w in cards) SizedBox(width: width, child: w)]);
            },
          ),
          const SizedBox(height: 12),
          _SalesCard(summary: s),
        ]);
      }),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.amount, required this.caption, required this.icon, required this.color, required this.onTap});

  final String title;
  final String amount;
  final String caption;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 6),
                  Text(amount, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Text(caption, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                ]),
              ),
              CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
            ]),
          ),
        ),
      );
}

/// "Total Sale" for the current month with a day-by-day line chart.
class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.summary});
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.parse(summary.salesFrom);
    final days = DateTime.parse(summary.salesTo).difference(start).inDays + 1;
    final spots = [
      for (var d = 0; d < days; d++)
        FlSpot(d.toDouble(), (summary.dailySales[isoDate(start.add(Duration(days: d)))] ?? 0).toDouble()),
    ];
    final maxY = spots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    final compact = NumberFormat.compact(locale: 'en_IN');
    final dayLabel = DateFormat('d MMM');
    const axisStyle = TextStyle(fontSize: 11, color: Colors.black54);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 24, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Total Sale', style: TextStyle(color: Colors.black54))),
            Chip(
              label: const Text('This Month'),
              backgroundColor: brandBlue.withValues(alpha: 0.08),
              side: BorderSide.none,
              shape: const StadiumBorder(),
            ),
          ]),
          Text(money(summary.salesTotal), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          SizedBox(
            height: 260,
            child: LineChart(LineChartData(
              minY: 0,
              maxY: maxY == 0 ? 100 : maxY * 1.2,
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox.shrink() : Text(compact.format(v), style: axisStyle),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 3,
                    reservedSize: 26,
                    getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(dayLabel.format(start.add(Duration(days: v.toInt()))), style: axisStyle),
                    ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touched) => [
                    for (final t in touched)
                      LineTooltipItem(
                        '${dayLabel.format(start.add(Duration(days: t.x.toInt())))}\n${money(t.y)}',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: brandBlue,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: brandBlue.withValues(alpha: 0.12)),
                ),
              ],
            )),
          ),
        ]),
      ),
    );
  }
}
