import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'format.dart';
import 'theme.dart';
import 'value_cubit.dart';
import 'widgets.dart';

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
    final picked = await showCompactRangePicker(context, from: range.from, to: range.to);
    if (picked != null) onChanged(PeriodRange(Period.custom, picked.$1, picked.$2));
  }

  @override
  Widget build(BuildContext context) {
    final chipColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.08);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 8, children: [
          const Text('Filter by:', style: TextStyle(fontSize: AppFont.body, fontWeight: FontWeight.w500)),
          DecoratedBox(
            decoration: BoxDecoration(color: chipColor, borderRadius: AppRadius.pillAll),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Period>(
                  value: range.period,
                  isDense: true,
                  style: const TextStyle(fontSize: AppFont.body, fontWeight: FontWeight.w500, color: AppColors.text),
                  borderRadius: AppRadius.mdAll,
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
            avatar: const Icon(Icons.calendar_month_outlined, size: AppIconSize.sm),
            backgroundColor: chipColor,
            side: BorderSide.none,
            shape: const StadiumBorder(),
            label: Text('${displayDate(range.from)}  To  ${displayDate(range.to)}', style: const TextStyle(fontSize: AppFont.body, fontWeight: FontWeight.w500)),
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
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: TextStyle(color: muted)),
          const SizedBox(height: AppSpace.xs),
          Text(amount, style: AppText.headline),
          if (details.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
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

/// A small "From / To" dialog for choosing a date range (the stock range picker takes over the whole screen).
/// Each date opens the normal compact calendar. Returns ISO dates, or null if cancelled.
Future<(String, String)?> showCompactRangePicker(BuildContext context, {required String from, required String to}) => showDialog<(String, String)>(
      context: context,
      builder: (_) => BlocProvider(create: (_) => ValueCubit<(String, String)>((from, to)), child: const _RangeDialog()),
    );

class _RangeDialog extends StatelessWidget {
  const _RangeDialog();

  @override
  Widget build(BuildContext context) => BlocBuilder<ValueCubit<(String, String)>, (String, String)>(
        builder: (context, range) {
          final cubit = context.read<ValueCubit<(String, String)>>();
          final invalid = range.$2.compareTo(range.$1) < 0;
          return AlertDialog(
            title: const Text('Select period'),
            content: SizedBox(
              width: AppSize.dialogSm,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                DateField(label: 'From', value: range.$1, onChanged: (v) => cubit.set((v, range.$2))),
                const SizedBox(height: AppSpace.md),
                DateField(label: 'To', value: range.$2, onChanged: (v) => cubit.set((range.$1, v))),
                if (invalid) const Padding(padding: EdgeInsets.only(top: AppSpace.sm), child: ErrorText('"To" must be on or after "From".')),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(onPressed: invalid ? null : () => Navigator.pop(context, range), child: const Text('Apply')),
            ],
          );
        },
      );
}
