import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/gst_states.dart';
import '../../core/status.dart';
import '../../data/models/invoice.dart';
import '../../data/models/party.dart';
import '../../data/models/payment.dart';
import '../../data/repositories/payments_repository.dart';
import '../../shared/data_table_view.dart';
import '../../shared/export.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../payments/payment_form_dialog.dart';
import 'bloc/parties_bloc.dart';
import 'party_form_dialog.dart';

/// Party list with a detail pane (wide screens) or a pushed detail page (phones).
class PartiesScreen extends StatelessWidget {
  const PartiesScreen({super.key, this.openId});

  /// The party to show first.
  final String? openId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => PartiesBloc(ctx.read(), ctx.read(), openId: openId)..add(const PartiesRequested()),
    child: const _PartiesView(),
  );
}

class _PartiesView extends StatelessWidget {
  const _PartiesView();

  void _open(BuildContext context, Party p) {
    final bloc = context.read<PartiesBloc>()..add(PartySelected(p.id));
    if (isWide(context)) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: bloc,
          child: BlocBuilder<PartiesBloc, PartiesState>(
            builder: (ctx, s) {
              // Party deleted from its own detail page → back to the list.
              if (s.status == LoadStatus.success && !s.parties.any((x) => x.id == p.id)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (ctx.mounted && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                });
              }
              return Scaffold(
                appBar: AppBar(title: Text(s.selected?.name ?? p.name)),
                body: const PartyDetail(),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Parties', style: AppText.title),
              const Spacer(),
              BlocBuilder<PartiesBloc, PartiesState>(
                builder: (context, state) => ExportMenu(table: () => TableExport(
                  title: 'Parties',
                  headers: ['Name', 'Phone', 'GSTIN', 'City', 'Group', 'Balance'],
                  rows: [for (final x in state.visible) [x.name, x.phone, x.gstin, x.city, x.groupName, x.balance]],
                )),
              ),
              const SizedBox(width: AppSpace.sm),
              FilledButton.icon(
                onPressed: () => showPartyForm(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Party'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Expanded(
            child: BlocBuilder<PartiesBloc, PartiesState>(
              builder: (context, state) {
                if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) {
                  return const LoadingView();
                }
                if (state.status == LoadStatus.failure && state.parties.isEmpty) {
                  return ErrorRetry(error: state.error!, onRetry: () => context.read<PartiesBloc>().add(const PartiesRequested()));
                }
                if (state.parties.isEmpty) {
                  return Card(
                    child: EmptyState(
                      icon: Icons.people_outline,
                      title: 'No parties yet',
                      message: 'Add your customers and suppliers to start tracking what they owe.',
                      action: FilledButton.icon(
                        onPressed: () => showPartyForm(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Your First Party'),
                      ),
                    ),
                  );
                }
                final list = _PartyList(state: state, highlight: wide, onTap: (p) => _open(context, p));
                if (!wide) return list;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: AppSize.listPane, child: list),
                    const SizedBox(width: AppSpace.md),
                    const Expanded(child: PartyDetail()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PartyList extends StatelessWidget {
  const _PartyList({required this.state, required this.highlight, required this.onTap});

  final PartiesState state;
  final bool highlight;
  final ValueChanged<Party> onTap;

  @override
  Widget build(BuildContext context) {
    final shown = state.visible;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: TextField(textInputAction: TextInputAction.search, 
              onChanged: (v) => context.read<PartiesBloc>().add(PartiesSearchChanged(v)),
              decoration: const InputDecoration(hintText: 'Search party name or phone', prefixIcon: Icon(Icons.search)),
            ),
          ),
          if (state.parties.any((p) => p.groupName != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
              child: DropdownButtonFormField<String?>(
                key: ValueKey('group-filter-${state.groupId}'),
                initialValue: state.groupId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Group'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All parties')),
                  for (final g in {
                    for (final p in state.parties)
                      if (p.groupId != null) p.groupId!: p.groupName!,
                  }.entries)
                    DropdownMenuItem(value: g.key, child: Text(g.value)),
                ],
                onChanged: (v) => context.read<PartiesBloc>().add(PartiesGroupChanged(v)),
              ),
            ),
          Expanded(
            child: PagedListPane<Party>(
              items: shown,
              headings: const ['Party Name', 'Amount'],
              sortKeys: [(p) => p.name, (p) => p.balance.abs()],
              emptyText: 'No matching parties',
              onRefresh: () => context.reloadBloc<PartiesBloc, PartiesEvent, PartiesState>(const PartiesRequested()),
              itemBuilder: (_, p) {
                      return ListTile(
                        selected: highlight && p.id == state.selectedId,
                        selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                        title: Text(p.name, overflow: TextOverflow.ellipsis),
                        trailing: Text(
                          money(p.balance.abs()),
                          style: TextStyle(color: balanceColor(p.balance), fontWeight: FontWeight.w600),
                        ),
                        onTap: () => onTap(p),
                      );
                    },
            ),
          ),
        ],
      ),
    );
  }
}

/// Selected party's header (contact details, balance) and ledger.
class PartyDetail extends StatelessWidget {
  const PartyDetail({super.key});

  /// Opens the invoice or payment behind a ledger row.
  Future<void> _openTxn(BuildContext context, PartyTxn t) async {
    final invoiceKind = InvoiceKind.maybeOf(t.kind);
    if (invoiceKind != null) {
      context.push('${invoiceKind.basePath}/${t.id}/edit');
      return;
    }
    switch (t.kind) {
      case 'payment_in' || 'payment_out':
        try {
          final payment = await context.read<PaymentsRepository>().get(t.id!);
          if (context.mounted) showPaymentForm(context, PaymentKind.of(payment.type), payment: payment);
        } catch (e) {
          if (context.mounted) showError(context, e);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PartiesBloc, PartiesState>(
      builder: (context, state) {
        final party = state.selected;
        if (party == null) return const SizedBox.shrink();
        return PullToRefresh(onRefresh: () => context.reloadBloc<PartiesBloc, PartiesEvent, PartiesState>(const PartiesRequested()), child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(party.name, style: AppText.title),
                        ),
                        IconButton(
                          tooltip: 'Edit party',
                          icon: Icon(Icons.edit_outlined, color: AppColors.primary),
                          onPressed: () => showPartyForm(context, party: party),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        OutlinedButton.icon(
                          onPressed: () => showPaymentForm(context, PaymentKind.paymentIn, partyId: party.id),
                          icon: const Icon(Icons.south_west, size: AppIconSize.xs),
                          label: const Text('Payment-In'),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        OutlinedButton.icon(
                          onPressed: () => showPaymentForm(context, PaymentKind.paymentOut, partyId: party.id),
                          icon: const Icon(Icons.north_east, size: AppIconSize.xs),
                          label: const Text('Payment-Out'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Wrap(
                      spacing: 40,
                      runSpacing: 12,
                      children: [
                        InfoField('Phone Number', party.phone ?? '-'),
                        InfoField('Email', party.email ?? '-'),
                        InfoField('Billing Address', party.billingAddress ?? '-'),
                        if (party.gstin != null) InfoField('GSTIN', party.gstin!),
                        if (party.stateCode != null) InfoField('State', gstStates[party.stateCode] ?? party.stateCode!),
                        if (party.creditLimit != null) InfoField('Credit Limit', money(party.creditLimit)),
                        InfoField(party.balance >= 0 ? 'To Receive' : 'To Pay', money(party.balance.abs()), valueColor: balanceColor(party.balance)),
                        if (party.currencyCode != null && party.fxBalance != null)
                          InfoField(
                            'In ${party.currencyCode}',
                            '${party.fxBalance! >= 0 ? 'To receive' : 'To pay'} ${party.fxBalance!.abs().toStringAsFixed(2)}',
                          ),
                        if (party.groupName != null) InfoField('Group', party.groupName!),
                        if (party.assignedUserName != null) InfoField('Salesman', party.assignedUserName!),
                        if (party.loyaltyPoints != 0) InfoField('Loyalty Points', '${party.loyaltyPoints}'),
                        for (final f in party.additionalFields) InfoField(f.name, f.value.isEmpty ? '-' : f.value),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(AppSpace.lg),
                    child: Text('Transactions', style: AppText.subtitle),
                  ),
                  switch (state.txnStatus) {
                    LoadStatus.initial || LoadStatus.loading => const Padding(
                      padding: EdgeInsets.all(AppSpace.xxl),
                      child: LoadingView(),
                    ),
                    LoadStatus.failure => ErrorRetry(
                      error: state.error ?? 'Could not load transactions',
                      onRetry: () => context.read<PartiesBloc>().add(const PartiesRequested()),
                    ),
                    LoadStatus.success when state.txns.isEmpty => const SizedBox(
                      height: AppSize.stateHeight,
                      child: EmptyState(
                        icon: Icons.receipt_outlined,
                        title: 'No transactions to show',
                        message: "You haven't added any transactions yet.",
                      ),
                    ),
                    LoadStatus.success => PagedDataTable(
                      searchHint: 'Search transactions',
                      initialSortColumn: 2,
                      initialSortAscending: false,
                      columns: const [
                        TableColumnSpec('Type'),
                        TableColumnSpec('Number'),
                        TableColumnSpec('Date'),
                        TableColumnSpec('Total', numeric: true),
                        TableColumnSpec('Balance', numeric: true),
                      ],
                      rows: [
                        for (final t in state.txns)
                          TableRowData(
                            onTap: t.id == null ? null : () => _openTxn(context, t),
                            search: '${t.type} ${t.number ?? ''} ${displayDate(t.date)}',
                            sort: [t.type, int.tryParse(t.number ?? '') ?? t.number, t.date, t.total, t.balance.abs()],
                            cells: [
                              Text(t.type),
                              Text(t.number ?? '-'),
                              Text(displayDate(t.date)),
                              Text(money(t.total)),
                              Text(money(t.balance.abs()), style: TextStyle(color: balanceColor(t.balance))),
                            ],
                          ),
                      ],
                    ),
                  },
                ],
              ),
            ),
          ],
        ));
      },
    );
  }
}
