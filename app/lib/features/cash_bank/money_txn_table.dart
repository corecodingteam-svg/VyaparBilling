import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/cash_bank.dart';
import '../../data/models/invoice.dart';
import '../../data/models/payment.dart';
import '../../data/repositories/payments_repository.dart';
import '../../shared/data_table_view.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../payments/payment_form_dialog.dart';
import 'cash_bank_dialogs.dart';

/// Opens the invoice, payment or expense behind a money movement. Adjustments have nothing to open.
Future<void> openMoneyTxn(BuildContext context, MoneyTxn t) async {
  final invoiceKind = InvoiceKind.maybeOf(t.source);
  if (invoiceKind != null) {
    context.push('${invoiceKind.basePath}/${t.id}/edit');
    return;
  }
  switch (t.source) {
    case 'expense':
      context.push('/expenses/${t.id}/edit');
    case 'payment_in' || 'payment_out':
      try {
        final payment = await context.read<PaymentsRepository>().get(t.id);
        if (context.mounted) showPaymentForm(context, PaymentKind.of(payment.type), payment: payment);
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
  }
}

bool _canOpen(MoneyTxn t) => t.source != 'adjustment' && t.source != 'opening';

/// Type / Name / Date / Amount table of money movements (green in, red out).
class MoneyTxnTable extends StatelessWidget {
  const MoneyTxnTable({super.key, required this.txns, this.onDeleteAdjustment, this.trailing});

  final List<MoneyTxn> txns;

  /// Enables "Delete" on manual adjustments/transfers.
  final ValueChanged<MoneyTxn>? onDeleteAdjustment;

  /// Extra per-row cell (e.g. cheque status and actions).
  final ({String header, Widget Function(MoneyTxn) build})? trailing;

  Widget _amount(MoneyTxn t) =>
      Text(money(t.amount.abs()), style: TextStyle(color: t.amount < 0 ? AppColors.moneyOut : AppColors.moneyIn, fontWeight: FontWeight.w600));

  Widget? _menu(BuildContext context, MoneyTxn t) {
    if (_canOpen(t)) {
      return IconButton(tooltip: 'Open', icon: const Icon(Icons.open_in_new, size: AppIconSize.sm), onPressed: () => openMoneyTxn(context, t));
    }
    if (t.source == 'adjustment' && onDeleteAdjustment != null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined, size: AppIconSize.sm),
          // Every kind is offered so a cash adjustment can be corrected into a transfer and back.
          onPressed: () => showAdjustmentDialog(context, kinds: adjustmentKinds.keys.toList(), editId: t.id),
        ),
        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline, size: AppIconSize.md), onPressed: () => onDeleteAdjustment!(t)),
      ]);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!isWide(context)) {
      return Column(children: [
        for (final t in txns) ...[
          const Divider(),
          ListTile(
            title: Text(t.type),
            subtitle: Text([if (t.name.isNotEmpty) t.name, displayDate(t.date)].join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                _amount(t),
                if (trailing != null) trailing!.build(t),
              ]),
              ?_menu(context, t),
            ]),
            onTap: _canOpen(t) ? () => openMoneyTxn(context, t) : null,
          ),
        ],
      ]);
    }
    return PagedDataTable(
      searchHint: 'Search transactions',
      initialSortColumn: 2,
      initialSortAscending: false,
      columns: [
        const TableColumnSpec('Type'),
        const TableColumnSpec('Name'),
        const TableColumnSpec('Date'),
        const TableColumnSpec('Amount', numeric: true),
        if (trailing != null) TableColumnSpec(trailing!.header, sortable: false),
        const TableColumnSpec('', sortable: false),
      ],
      rows: [
        for (final t in txns)
          TableRowData(
            onTap: _canOpen(t) ? () => openMoneyTxn(context, t) : null,
            search: '${t.type} ${t.name} ${displayDate(t.date)}',
            sort: [t.type, t.name, t.date, t.amount, if (trailing != null) null, null],
            cells: [
              Text(t.type),
              Text(t.name),
              Text(displayDate(t.date)),
              _amount(t),
              if (trailing != null) trailing!.build(t),
              _menu(context, t) ?? const SizedBox.shrink(),
            ],
          ),
      ],
    );
  }
}
