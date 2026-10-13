import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/status.dart';
import '../../data/models/invoice.dart';
import '../../shared/data_table_view.dart';
import '../../shared/export.dart';
import '../../shared/format.dart';
import '../../shared/period.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../integrations/integrations_screens.dart';
import '../payments/link_payments_dialog.dart';
import '../company/firm_cubit.dart';
import 'bloc/invoices_bloc.dart';

/// List of sale invoices (or purchase bills) with period filter and totals.
class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key, required this.kind});
  final InvoiceKind kind;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => InvoicesBloc(ctx.read(), ctx.read(), kind.type)..add(const InvoicesRequested()),
        child: _InvoicesView(kind: kind),
      );
}

class _InvoicesView extends StatelessWidget {
  const _InvoicesView({required this.kind});
  final InvoiceKind kind;

  Future<void> _delete(BuildContext context, InvoiceSummary inv) async {
    final bloc = context.read<InvoicesBloc>();
    final ok = await confirmDelete(
      context,
      title: 'Delete ${kind.singular.toLowerCase()}',
      message: 'Delete ${inv.number.isEmpty ? 'this ${kind.singular.toLowerCase()}' : '${kind.singular.toLowerCase()} ${inv.number}'} '
          'for ${inv.partyName}?${kind.isQuote ? '' : ' Stock and party balance will be restored.'}',
    );
    if (ok) bloc.add(InvoiceDeleted(inv.id));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InvoicesBloc, InvoicesState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error && b.invoices.isNotEmpty,
      listener: (context, state) => showError(context, state.error!),
      builder: (context, state) {
        final bloc = context.read<InvoicesBloc>();
        return PullToRefresh(onRefresh: () => context.reloadBloc<InvoicesBloc, InvoicesEvent, InvoicesState>(const InvoicesRequested()), child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          Row(children: [
            Expanded(child: Text(kind.title, style: AppText.title)),
            ExportMenu(table: () => TableExport(
              title: kind.title,
              subtitle: '${displayDate(state.range.from)} to ${displayDate(state.range.to)}',
              headers: ['Date', 'Number', 'Party', 'Total', kind.paidLabel, kind.unpaidLabel],
              rows: [for (final i in state.visible) [displayDate(i.invoiceDate), i.number, i.partyName, i.total, i.received, i.balance]],
            )),
            const SizedBox(width: AppSpace.sm),
            FilledButton.icon(
              onPressed: () => context.push('${kind.basePath}/new'),
              icon: const Icon(Icons.add),
              label: Text('Add ${kind.singular}'),
            ),
          ]),
          const SizedBox(height: AppSpace.md),
          PeriodFilterBar(range: state.range, onChanged: (r) => bloc.add(InvoicesPeriodChanged(r))),
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSize.dialogSm),
              child: kind.isQuote
                  ? AmountSummaryCard(
                      title: 'Total ${kind.title}',
                      amount: money(state.total),
                      details: {'Converted': money(state.total - state.openTotal), 'Open': money(state.openTotal)},
                    )
                  : AmountSummaryCard(
                      title: 'Total ${kind.singular} Amount',
                      amount: money(state.total),
                      details: {kind.paidLabel: money(state.received), kind.unpaidLabel: money(state.balance)},
                    ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.md, AppSpace.md),
                child: Row(children: [
                  const Expanded(child: Text('Transactions', style: AppText.subtitle)),
                  SizedBox(
                    width: AppSize.fieldMd,
                    child: TextField(textInputAction: TextInputAction.search, 
                      onChanged: (v) => bloc.add(InvoicesSearchChanged(v)),
                      decoration: const InputDecoration(hintText: 'Search party or number', prefixIcon: Icon(Icons.search)),
                    ),
                  ),
                ]),
              ),
              _body(context, state),
            ]),
          ),
        ]));
      },
    );
  }

  Widget _body(BuildContext context, InvoicesState state) {
    if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) {
      return const SizedBox(height: AppSize.stateHeight, child: LoadingView());
    }
    if (state.status == LoadStatus.failure && state.invoices.isEmpty) {
      return SizedBox(
        height: AppSize.stateHeight,
        child: ErrorRetry(error: state.error ?? 'Could not load', onRetry: () => context.read<InvoicesBloc>().add(const InvoicesRequested())),
      );
    }
    final rows = state.visible;
    if (rows.isEmpty) {
      return SizedBox(
        height: AppSize.stateHeight,
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: state.invoices.isEmpty ? 'No transactions to show' : 'No matching transactions',
          message: state.invoices.isEmpty ? 'Nothing was billed in this period.' : null,
          action: state.invoices.isEmpty
              ? FilledButton.icon(
                  onPressed: () => context.push('${kind.basePath}/new'),
                  icon: const Icon(Icons.add),
                  label: Text('Add ${kind.singular}'),
                )
              : null,
        ),
      );
    }
    if (!isWide(context)) {
      return Column(children: [
        for (final inv in rows) ...[
          const Divider(),
          ListTile(
            title: Text(inv.partyName, overflow: TextOverflow.ellipsis),
            subtitle: Text('${inv.number.isEmpty ? '' : '#${inv.number} · '}${displayDate(inv.invoiceDate)} · ${inv.paymentLabel}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(inv.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                if (kind.isQuote)
                  _StatusText(inv, fontSize: AppFont.small)
                else if (inv.balance > 0)
                  Text('Bal ${money(inv.balance)}', style: const TextStyle(color: AppColors.moneyOut, fontSize: AppFont.small)),
              ]),
              _menu(context, inv),
            ]),
            onTap: () => context.push('${kind.basePath}/${inv.id}/preview'),
          ),
        ],
      ]);
    }
    return PagedDataTable(
      searchable: false, // this page has its own search box above
      initialSortColumn: 0,
      initialSortAscending: false,
      columns: [
        const TableColumnSpec('Date'),
        TableColumnSpec(kind.numberColumn),
        const TableColumnSpec('Party Name'),
        if (!kind.isQuote) const TableColumnSpec('Transaction'),
        if (!kind.isQuote) const TableColumnSpec('Payment Type'),
        const TableColumnSpec('Amount', numeric: true),
        if (kind.isQuote) const TableColumnSpec('Status') else TableColumnSpec(kind.unpaidLabel, numeric: true),
        const TableColumnSpec('Actions', sortable: false),
      ],
      rows: [
        for (final inv in rows)
          TableRowData(
            onTap: () => context.push('${kind.basePath}/${inv.id}/edit'),
            sort: [
              inv.invoiceDate,
              int.tryParse(inv.number) ?? inv.number,
              inv.partyName,
              if (!kind.isQuote) kind.singular,
              if (!kind.isQuote) inv.paymentLabel,
              inv.total,
              if (kind.isQuote) (inv.isOpen ? 'Open' : 'Converted') else inv.balance,
              null,
            ],
            cells: [
              Text(displayDate(inv.invoiceDate)),
              Text(inv.number),
              Text(inv.partyName),
              if (!kind.isQuote) Text(kind.singular),
              if (!kind.isQuote) Text(inv.paymentLabel),
              Text(money(inv.total)),
              if (kind.isQuote) _StatusText(inv) else Text(money(inv.balance), style: TextStyle(color: inv.balance > 0 ? AppColors.moneyOut : null)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (inv.isOpen) _ConvertButton(kind: kind, onConvert: (target) => _convert(context, inv, target)),
                IconButton(
                  tooltip: 'Preview / Print',
                  icon: const Icon(Icons.print_outlined, size: AppIconSize.md),
                  onPressed: () => context.push('${kind.basePath}/${inv.id}/preview'),
                ),
                _menu(context, inv),
              ]),
            ],
          ),
      ],
    );
  }

  Widget _menu(BuildContext context, InvoiceSummary inv) => PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert, size: AppIconSize.md),
        onSelected: (v) {
          final target = InvoiceKind.maybeOf(v);
          if (target != null) return _convert(context, inv, target);
          switch (v) {
            case 'converted':
              context.push('${InvoiceKind.of(inv.convertedType ?? 'sale').basePath}/${inv.convertedInvoiceId}/edit');
            case 'edit':
              context.push('${kind.basePath}/${inv.id}/edit');
            case 'preview':
              context.push('${kind.basePath}/${inv.id}/preview');
            case 'link':
              showLinkPaymentsDialog(context, invoiceId: inv.id, title: 'Link payments · ${kind.singular} ${inv.number}');
            case 'send':
              showSendDialog(
                context,
                title: 'Send ${kind.singular} ${inv.number}',
                phone: null,
                manualMessage: 'Dear ${inv.partyName}, your ${kind.singular.toLowerCase()} ${inv.number} for ${money(inv.total)} is ready. Balance due: ${money(inv.balance)}.',
                send: (repo, channel, phone) => repo.sendInvoice(inv.id, channel, phone: phone),
              );
            case 'einvoice':
              showEinvoiceDialog(context, invoiceId: inv.id, number: inv.number);
            case 'paylink':
              showPaymentLinkDialog(context, invoiceId: inv.id, number: inv.number, phone: null, customer: inv.partyName);
            default:
              _delete(context, inv);
          }
        },
        itemBuilder: (_) => [
          if (inv.isOpen)
            for (final target in kind.convertTargets) PopupMenuItem(value: target.type, child: Text('Convert to ${target.singular}')),
          if (inv.convertedInvoiceId != null)
            PopupMenuItem(value: 'converted', child: Text('Open ${InvoiceKind.of(inv.convertedType ?? 'sale').singular}')),
          const PopupMenuItem(value: 'edit', child: Text('View/Edit')),
          const PopupMenuItem(value: 'preview', child: Text('Preview / Print')),
          if (const ['sale', 'purchase', 'credit_note', 'debit_note'].contains(kind.type) && inv.partyId != null && !inv.isForeign)
            const PopupMenuItem(value: 'link', child: Text('Link payments')),
          if (kind.type == 'sale') const PopupMenuItem(value: 'send', child: Text('Send to customer')),
          if (kind.type == 'sale' && inv.partyId != null && inv.balance > 0) const PopupMenuItem(value: 'paylink', child: Text('Payment link')),
          if (settingsOf(context).einvoiceEnabled && (kind.type == 'sale' || kind.type == 'credit_note'))
            PopupMenuItem(value: 'einvoice', child: Text(inv.einvoiceStatus == 'generated' ? 'E-invoice / e-way bill ✓' : 'E-invoice / e-way bill')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );

  /// Opens a new [target] document pre-filled from [source]; saving it marks the source converted.
  void _convert(BuildContext context, InvoiceSummary source, InvoiceKind target) =>
      context.push('${target.basePath}/new?from=${source.id}');
}

/// "Convert to Sale" button, or a "Convert" menu when the document can become more than one thing.
class _ConvertButton extends StatelessWidget {
  const _ConvertButton({required this.kind, required this.onConvert});
  final InvoiceKind kind;
  final ValueChanged<InvoiceKind> onConvert;

  @override
  Widget build(BuildContext context) {
    final targets = kind.convertTargets;
    if (targets.length == 1) {
      return TextButton(onPressed: () => onConvert(targets.single), child: Text('Convert to ${targets.single.singular}'));
    }
    return PopupMenuButton<InvoiceKind>(
      tooltip: 'Convert',
      onSelected: onConvert,
      itemBuilder: (_) => [for (final t in targets) PopupMenuItem(value: t, child: Text('Convert to ${t.singular}'))],
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Convert', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          Icon(Icons.arrow_drop_down, color: AppColors.primary),
        ]),
      ),
    );
  }
}

/// "Open" (orange) / "Converted" (green) for quotation-like documents.
class _StatusText extends StatelessWidget {
  const _StatusText(this.invoice, {this.fontSize});
  final InvoiceSummary invoice;
  final double? fontSize;

  @override
  Widget build(BuildContext context) => Text(
        invoice.isOpen ? 'Open' : 'Converted',
        style: TextStyle(color: invoice.isOpen ? AppColors.warningText : AppColors.successText, fontWeight: FontWeight.w600, fontSize: fontSize),
      );
}
