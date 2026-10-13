import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/gst_states.dart';
import '../../core/status.dart';
import '../../data/models/invoice.dart';
import '../../data/models/party.dart';
import '../../data/models/payment.dart';
import '../../data/repositories/payments_repository.dart';
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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Parties', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => showPartyForm(context),
                style: FilledButton.styleFrom(backgroundColor: payRed),
                icon: const Icon(Icons.add),
                label: const Text('Add Party'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BlocBuilder<PartiesBloc, PartiesState>(
              builder: (context, state) {
                if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) {
                  return const Center(child: CircularProgressIndicator());
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
                    SizedBox(width: 320, child: list),
                    const SizedBox(width: 12),
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
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => context.read<PartiesBloc>().add(PartiesSearchChanged(v)),
              decoration: const InputDecoration(hintText: 'Search party name or phone', prefixIcon: Icon(Icons.search)),
            ),
          ),
          if (state.parties.any((p) => p.groupName != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
          Container(
            color: pageBg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(
              children: [
                Expanded(
                  child: Text('Party Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ),
                Text('Amount', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('No matching parties'))
                : ListView.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) {
                      final p = shown[i];
                      return ListTile(
                        selected: highlight && p.id == state.selectedId,
                        selectedTileColor: brandBlue.withValues(alpha: 0.08),
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
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(party.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          tooltip: 'Edit party',
                          icon: const Icon(Icons.edit_outlined, color: brandBlue),
                          onPressed: () => showPartyForm(context, party: party),
                        ),
                        const SizedBox(width: 4),
                        OutlinedButton.icon(
                          onPressed: () => showPaymentForm(context, PaymentKind.paymentIn, partyId: party.id),
                          icon: const Icon(Icons.south_west, size: 16),
                          label: const Text('Payment-In'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => showPaymentForm(context, PaymentKind.paymentOut, partyId: party.id),
                          icon: const Icon(Icons.north_east, size: 16),
                          label: const Text('Payment-Out'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  switch (state.txnStatus) {
                    LoadStatus.initial || LoadStatus.loading => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    LoadStatus.failure => ErrorRetry(
                      error: state.error ?? 'Could not load transactions',
                      onRetry: () => context.read<PartiesBloc>().add(const PartiesRequested()),
                    ),
                    LoadStatus.success when state.txns.isEmpty => const SizedBox(
                      height: 260,
                      child: EmptyState(
                        icon: Icons.receipt_outlined,
                        title: 'No transactions to show',
                        message: "You haven't added any transactions yet.",
                      ),
                    ),
                    LoadStatus.success => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: const WidgetStatePropertyAll(pageBg),
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Number')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Total'), numeric: true),
                          DataColumn(label: Text('Balance'), numeric: true),
                        ],
                        rows: [
                          for (final t in state.txns)
                            DataRow(
                              onSelectChanged: t.id == null ? null : (_) => _openTxn(context, t),
                              cells: [
                                DataCell(Text(t.type)),
                                DataCell(Text(t.number ?? '-')),
                                DataCell(Text(displayDate(t.date))),
                                DataCell(Text(money(t.total))),
                                DataCell(Text(money(t.balance.abs()), style: TextStyle(color: balanceColor(t.balance)))),
                              ],
                            ),
                        ],
                      ),
                    ),
                  },
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
