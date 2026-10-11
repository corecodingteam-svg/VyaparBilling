import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'format.dart';

enum Period { thisMonth, lastMonth, thisQuarter, thisYear, custom }

const periodLabels = {
  Period.thisMonth: 'This Month',
  Period.lastMonth: 'Last Month',
  Period.thisQuarter: 'This Quarter',
  Period.thisYear: 'This Financial Year',
  Period.custom: 'Custom',
};

/// An inclusive date range ('YYYY-MM-DD') chosen through a [Period] preset or custom dates.
class PeriodRange extends Equatable {
  const PeriodRange(this.period, this.from, this.to);

  factory PeriodRange.of(Period period, [DateTime? now]) {
    final n = now ?? DateTime.now();
    DateTime start, end;
    switch (period) {
      case Period.thisMonth || Period.custom:
        start = DateTime(n.year, n.month, 1);
        end = DateTime(n.year, n.month + 1, 0);
      case Period.lastMonth:
        start = DateTime(n.year, n.month - 1, 1);
        end = DateTime(n.year, n.month, 0);
      case Period.thisQuarter:
        final q = (n.month - 1) ~/ 3;
        start = DateTime(n.year, q * 3 + 1, 1);
        end = DateTime(n.year, q * 3 + 4, 0);
      case Period.thisYear:
        // Indian financial year: 1 April – 31 March.
        final fy = n.month >= 4 ? n.year : n.year - 1;
        start = DateTime(fy, 4, 1);
        end = DateTime(fy + 1, 3, 31);
    }
    return PeriodRange(period, isoDate(start), isoDate(end));
  }

  final Period period;
  final String from;
  final String to;

  @override
  List<Object?> get props => [period, from, to];
}

/// "Filter by: [This Month ▾] [📅 01/10/2026 To 31/10/2026]".
class PeriodFilterBar extends StatelessWidget {
  const PeriodFilterBar({super.key, required this.range, required this.onChanged});
  final PeriodRange range;
  final ValueChanged<PeriodRange> onChanged;

  Future<void> _pickCustom(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: DateTime.parse(range.from), end: DateTime.parse(range.to)),
    );
    if (picked != null) onChanged(PeriodRange(Period.custom, isoDate(picked.start), isoDate(picked.end)));
  }

  @override
  Widget build(BuildContext context) {
    final chipColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.08);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 8, children: [
          const Text('Filter by:', style: TextStyle(fontWeight: FontWeight.w500)),
          DecoratedBox(
            decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Period>(
                  value: range.period,
                  isDense: true,
                  borderRadius: BorderRadius.circular(8),
                  items: [for (final e in periodLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (p) {
                    if (p == Period.custom) {
                      _pickCustom(context);
                    } else if (p != null) {
                      onChanged(PeriodRange.of(p));
                    }
                  },
                ),
              ),
            ),
          ),
          ActionChip(
            avatar: const Icon(Icons.calendar_month_outlined, size: 18),
            backgroundColor: chipColor,
            side: BorderSide.none,
            shape: const StadiumBorder(),
            label: Text('${displayDate(range.from)}  To  ${displayDate(range.to)}'),
            onPressed: () => _pickCustom(context),
          ),
        ]),
      ),
    );
  }
}

/// Summary tile: "Total Sales Amount ₹ 1,000 · Received ₹ 500 | Balance ₹ 500".
class AmountSummaryCard extends StatelessWidget {
  const AmountSummaryCard({super.key, required this.title, required this.amount, this.details = const {}});
  final String title;
  final String amount;
  final Map<String, String> details;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: TextStyle(color: muted)),
          const SizedBox(height: 4),
          Text(amount, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 16, children: [
              for (final e in details.entries)
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${e.key}: ', style: TextStyle(color: muted)),
                  TextSpan(text: e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
                ])),
            ]),
          ],
        ]),
      ),
    );
  }
}
