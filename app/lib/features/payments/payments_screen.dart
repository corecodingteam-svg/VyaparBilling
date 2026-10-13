import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/status.dart';
import '../../data/models/invoice.dart' show paymentModes;
import '../../data/models/payment.dart';
import '../../shared/data_table_view.dart';
import '../../shared/export.dart';
import '../../shared/format.dart';
import '../../shared/period.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../integrations/integrations_screens.dart';
import 'bloc/payments_bloc.dart';
import 'payment_form_dialog.dart';

/// List of payments received (or made) with period filter and total.
class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key, required this.kind});
  final PaymentKind kind;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => PaymentsBloc(ctx.read(), ctx.read(), kind.type)..add(const PaymentsRequested()),
    child: _PaymentsView(kind: kind),
  );
}

class _PaymentsView extends StatelessWidget {
  const _PaymentsView({required this.kind});
  final PaymentKind kind;

  Future<void> _delete(BuildContext context, Payment p) async {
    final bloc = context.read<PaymentsBloc>();
    final ok = await confirmDelete(
      context,
      title: 'Delete ${kind.title.toLowerCase()}',
      message: 'Delete receipt ${p.number} of ${money(p.amount)} from ${p.partyName}?',
    );
    if (ok) bloc.add(PaymentDeleted(p.id));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PaymentsBloc, PaymentsState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error && b.payments.isNotEmpty,
      listener: (context, state) => showError(context, state.error!),
      builder: (context, state) {
        final bloc = context.read<PaymentsBloc>();
        return PullToRefresh(onRefresh: () => context.reloadBloc<PaymentsBloc, PaymentsEvent, PaymentsState>(const PaymentsRequested()), child: ListView(
          padding: const EdgeInsets.all(AppSpace.md),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(kind.title, style: AppText.title),
                ),
                ExportMenu(table: () => TableExport(
                  title: kind.title,
                  subtitle: '${displayDate(state.range.from)} to ${displayDate(state.range.to)}',
                  headers: ['Date', 'Number', 'Party', 'Mode', kind.amountLabel],
                  rows: [for (final p in state.visible) [displayDate(p.paymentDate), p.number, p.partyName, p.paymentMode, p.amount]],
                )),
                const SizedBox(width: AppSpace.sm),
                FilledButton.icon(
                  onPressed: () => showPaymentForm(context, kind),
                  icon: const Icon(Icons.add),
                  label: Text('Add ${kind.title}'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            PeriodFilterBar(range: state.range, onChanged: (r) => bloc.add(PaymentsPeriodChanged(r))),
            const SizedBox(height: AppSpace.md),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppSize.dialogSm),
                child: AmountSummaryCard(title: 'Total Amount', amount: money(state.total), details: {kind.amountLabel: money(state.total)}),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.md, AppSpace.md),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Transactions', style: AppText.subtitle),
                        ),
                        SizedBox(
                          width: AppSize.fieldMd,
                          child: TextField(textInputAction: TextInputAction.search, 
                            onChanged: (v) => bloc.add(PaymentsSearchChanged(v)),
                            decoration: const InputDecoration(hintText: 'Search party or number', prefixIcon: Icon(Icons.search)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _body(context, state),
                ],
              ),
            ),
          ],
        ));
      },
    );
  }

  Widget _body(BuildContext context, PaymentsState state) {
    if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpace.huge),
        child: LoadingView(),
      );
    }
    if (state.status == LoadStatus.failure && state.payments.isEmpty) {
      return SizedBox(
        height: AppSize.stateHeight,
        child: ErrorRetry(error: state.error ?? 'Could not load', onRetry: () => context.read<PaymentsBloc>().add(const PaymentsRequested())),
      );
    }
    final rows = state.visible;
    if (rows.isEmpty) {
      return SizedBox(
        height: AppSize.stateHeight,
        child: EmptyState(
          icon: Icons.payments_outlined,
          title: state.payments.isEmpty ? 'No transactions to show' : 'No matching transactions',
          message: state.payments.isEmpty ? 'No payments were recorded in this period.' : null,
          action: state.payments.isEmpty
              ? FilledButton.icon(onPressed: () => showPaymentForm(context, kind), icon: const Icon(Icons.add), label: Text('Add ${kind.title}'))
              : null,
        ),
      );
    }
    if (!isWide(context)) {
      return Column(
        children: [
          for (final p in rows) ...[
            const Divider(),
            ListTile(
              title: Text(p.partyName, overflow: TextOverflow.ellipsis),
              subtitle: Text('#${p.number} · ${displayDate(p.paymentDate)} · ${paymentModes[p.paymentMode]}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(money(p.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                  _menu(context, p),
                ],
              ),
              onTap: () => showPaymentForm(context, kind, payment: p),
            ),
          ],
        ],
      );
    }
    return PagedDataTable(
      searchable: false, // this page has its own search box above
      initialSortColumn: 0,
      initialSortAscending: false,
      columns: [
        const TableColumnSpec('Date'),
        const TableColumnSpec('Ref. no.'),
        const TableColumnSpec('Party Name'),
        TableColumnSpec(kind.amountLabel, numeric: true),
        const TableColumnSpec('Linked to invoices', numeric: true),
        const TableColumnSpec('Payment Type'),
        const TableColumnSpec('Actions', sortable: false),
      ],
      rows: [
        for (final p in rows)
          TableRowData(
            onTap: () => showPaymentForm(context, kind, payment: p),
            sort: [p.paymentDate, int.tryParse(p.number) ?? p.number, p.partyName, p.amount, p.linkedAmount, paymentModes[p.paymentMode] ?? p.paymentMode, null],
            cells: [
              Text(displayDate(p.paymentDate)),
              Text(p.number),
              Text(p.partyName),
              Text(money(p.amount)),
              Text(p.linkedAmount == 0 ? '-' : (p.unlinkedAmount == 0 ? 'Fully' : money(p.linkedAmount))),
              Text(paymentModes[p.paymentMode] ?? p.paymentMode),
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Receipt / Print',
                  icon: const Icon(Icons.print_outlined, size: AppIconSize.md),
                  onPressed: () => context.push('${kind.basePath}/${p.id}/receipt'),
                ),
                _menu(context, p),
              ]),
            ],
          ),
      ],
    );
  }

  Widget _menu(BuildContext context, Payment p) => PopupMenuButton<String>(
    tooltip: 'More',
    icon: const Icon(Icons.more_vert, size: AppIconSize.md),
    onSelected: (v) => switch (v) {
      'edit' => showPaymentForm(context, kind, payment: p),
      'receipt' => context.push('${kind.basePath}/${p.id}/receipt'),
      'send' => showSendDialog(
        context,
        title: 'Send receipt ${p.number}',
        phone: null,
        manualMessage: 'Dear ${p.partyName}, we received ${money(p.amount)} (receipt ${p.number}). Thank you!',
        send: (repo, channel, phone) => repo.sendPayment(p.id, channel, phone: phone),
      ),
      _ => _delete(context, p),
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'edit', child: Text('View/Edit')),
      const PopupMenuItem(value: 'receipt', child: Text('Receipt / Print')),
      if (kind == PaymentKind.paymentIn) const PopupMenuItem(value: 'send', child: Text('Send receipt')),
      const PopupMenuItem(value: 'delete', child: Text('Delete')),
    ],
  );
}
