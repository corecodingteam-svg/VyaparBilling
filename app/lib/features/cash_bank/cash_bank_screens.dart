import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/status.dart';
import '../../data/models/cash_bank.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'bloc/bank_accounts_bloc.dart';
import 'bloc/money_list_cubit.dart';
import 'cash_bank_dialogs.dart';
import 'money_txn_table.dart';

Future<bool> _confirmDeleteAdjustment(BuildContext context, MoneyTxn t) =>
    confirmDelete(context, title: 'Delete entry', message: 'Delete this "${t.type}" of ${money(t.amount.abs())}?');

// ---------------------------------------------------------------- bank accounts

/// Bank accounts with balances; the selected account's transactions beside (wide) or on a pushed page (phones).
class BankAccountsScreen extends StatelessWidget {
  const BankAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => BankAccountsBloc(ctx.read(), ctx.read())..add(const BankAccountsRequested()),
        child: const _BankAccountsView(),
      );
}

class _BankAccountsView extends StatelessWidget {
  const _BankAccountsView();

  void _open(BuildContext context, BankAccount a) {
    final bloc = context.read<BankAccountsBloc>()..add(BankAccountSelected(a.id));
    if (isWide(context)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: BlocBuilder<BankAccountsBloc, BankAccountsState>(
          builder: (ctx, s) => Scaffold(appBar: AppBar(title: Text(s.selected?.name ?? a.name)), body: const _AccountDetail()),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return BlocConsumer<BankAccountsBloc, BankAccountsState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error && b.status == LoadStatus.success,
      listener: (context, state) => showError(context, state.error!),
      builder: (context, state) {
        if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == LoadStatus.failure && state.accounts.isEmpty) {
          return ErrorRetry(error: state.error ?? 'Could not load', onRetry: () => context.read<BankAccountsBloc>().add(const BankAccountsRequested()));
        }
        final header = Row(children: [
          const Expanded(child: Text('Banks', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
          FilledButton.icon(
            onPressed: () => showBankAccountForm(context),
            style: FilledButton.styleFrom(backgroundColor: payRed),
            icon: const Icon(Icons.add),
            label: const Text('Add Bank'),
          ),
        ]);
        if (state.accounts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              header,
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: EmptyState(
                    icon: Icons.account_balance_outlined,
                    title: 'No bank accounts yet',
                    message: 'Add your bank accounts to track UPI, card and bank payments.',
                    action: FilledButton.icon(onPressed: () => showBankAccountForm(context), icon: const Icon(Icons.add), label: const Text('Add Bank')),
                  ),
                ),
              ),
            ]),
          );
        }
        final list = _AccountList(state: state, highlight: wide, onTap: (a) => _open(context, a));
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            header,
            const SizedBox(height: 12),
            Expanded(
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(width: 320, child: list),
                      const SizedBox(width: 12),
                      const Expanded(child: _AccountDetail()),
                    ])
                  : list,
            ),
          ]),
        );
      },
    );
  }
}

class _AccountList extends StatelessWidget {
  const _AccountList({required this.state, required this.highlight, required this.onTap});
  final BankAccountsState state;
  final bool highlight;
  final ValueChanged<BankAccount> onTap;

  @override
  Widget build(BuildContext context) {
    final shown = state.visible;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => context.read<BankAccountsBloc>().add(BankAccountsSearchChanged(v)),
            decoration: const InputDecoration(hintText: 'Search by account', prefixIcon: Icon(Icons.search)),
          ),
        ),
        Container(
          color: pageBg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Row(children: [
            Expanded(child: Text('Account Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
            Text('Amount', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ]),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('No matching accounts'))
              : ListView.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) {
                    final a = shown[i];
                    return ListTile(
                      selected: highlight && a.id == state.selectedId,
                      selectedTileColor: brandBlue.withValues(alpha: 0.08),
                      title: Text(a.name, overflow: TextOverflow.ellipsis),
                      trailing: Text(money(a.balance), style: TextStyle(color: a.balance < 0 ? payRed : receiveGreen, fontWeight: FontWeight.w600)),
                      onTap: () => onTap(a),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _AccountDetail extends StatelessWidget {
  const _AccountDetail();

  Future<void> _deleteAccount(BuildContext context, BankAccount a) async {
    final bloc = context.read<BankAccountsBloc>();
    if (await confirmDelete(context, title: 'Delete bank account', message: 'Delete "${a.name}"?')) bloc.add(BankAccountDeleted(a.id));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BankAccountsBloc, BankAccountsState>(builder: (context, state) {
      final account = state.selected;
      if (account == null) return const SizedBox.shrink();
      final bloc = context.read<BankAccountsBloc>();
      return ListView(padding: EdgeInsets.zero, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(account.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  IconButton(
                    tooltip: 'Edit account',
                    icon: const Icon(Icons.edit_outlined, color: brandBlue, size: 20),
                    onPressed: () => showBankAccountForm(context, account: account),
                  ),
                  IconButton(
                    tooltip: 'Delete account',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _deleteAccount(context, account),
                  ),
                ]),
                PopupMenuButton<String>(
                  tooltip: 'Deposit / Withdraw',
                  onSelected: (kind) => showAdjustmentDialog(context, kinds: bankAdjustmentKinds, initialKind: kind, bankAccountId: account.id),
                  itemBuilder: (_) => [for (final k in bankAdjustmentKinds) PopupMenuItem(value: k, child: Text(adjustmentKinds[k]!))],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(border: Border.all(color: payRed), borderRadius: BorderRadius.circular(20)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Deposit / Withdraw', style: TextStyle(color: payRed, fontWeight: FontWeight.w600)),
                      Icon(Icons.arrow_drop_down, color: payRed),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 40, runSpacing: 12, children: [
                InfoField('Balance', money(account.balance), valueColor: account.balance < 0 ? payRed : receiveGreen),
                if ((account.bankName ?? '').isNotEmpty) InfoField('Bank', account.bankName!),
                if ((account.accountNumber ?? '').isNotEmpty) InfoField('Account Number', account.accountNumber!),
                if ((account.ifsc ?? '').isNotEmpty) InfoField('IFSC', account.ifsc!),
                if ((account.holderName ?? '').isNotEmpty) InfoField('Account Holder', account.holderName!),
                if ((account.upiId ?? '').isNotEmpty) InfoField('UPI ID', account.upiId!),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            switch (state.txnStatus) {
              LoadStatus.initial || LoadStatus.loading => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              LoadStatus.failure => SizedBox(
                  height: 240,
                  child: ErrorRetry(error: state.error ?? 'Could not load', onRetry: () => bloc.add(BankAccountSelected(account.id))),
                ),
              LoadStatus.success when state.txns.isEmpty =>
                const SizedBox(height: 240, child: EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions to show')),
              LoadStatus.success => MoneyTxnTable(
                  txns: state.txns,
                  onDeleteAdjustment: (t) async {
                    if (await _confirmDeleteAdjustment(context, t)) bloc.add(BankAdjustmentDeleted(t.id));
                  },
                ),
            },
          ]),
        ),
      ]);
    });
  }
}

// ---------------------------------------------------------------- shared list page

/// Header + card with a transaction table, driven by a [MoneyListState] cubit.
class _MoneyListPage<C extends Cubit<MoneyListState>> extends StatelessWidget {
  const _MoneyListPage({required this.header, required this.empty, required this.table, required this.onRetry});
  final Widget Function(BuildContext, MoneyListState) header;
  final Widget empty;
  final Widget Function(BuildContext, MoneyListState) table;
  final VoidCallback Function(BuildContext) onRetry;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<C, MoneyListState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error && b.status == LoadStatus.success,
      listener: (context, state) => showError(context, state.error!),
      builder: (context, state) => ListView(padding: const EdgeInsets.all(12), children: [
        header(context, state),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            switch (state.status) {
              LoadStatus.initial || LoadStatus.loading => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              LoadStatus.failure => SizedBox(height: 260, child: ErrorRetry(error: state.error ?? 'Could not load', onRetry: onRetry(context))),
              LoadStatus.success when state.txns.isEmpty => SizedBox(height: 300, child: empty),
              LoadStatus.success => table(context, state),
            },
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- cash in hand

class CashInHandScreen extends StatelessWidget {
  const CashInHandScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => CashCubit(ctx.read(), ctx.read())..load(),
        child: _MoneyListPage<CashCubit>(
          onRetry: (ctx) => ctx.read<CashCubit>().load,
          header: (context, state) => Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Cash In Hand', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              Text(money(state.balance),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: state.balance < 0 ? payRed : receiveGreen)),
            ]),
            FilledButton.icon(
              onPressed: () => showAdjustmentDialog(context, kinds: cashAdjustmentKinds),
              style: FilledButton.styleFrom(backgroundColor: payRed),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Adjust Cash'),
            ),
          ]),
          empty: const EmptyState(
            icon: Icons.payments_outlined,
            title: 'No cash transactions yet',
            message: 'Cash sales, payments and expenses will appear here.',
          ),
          table: (context, state) => MoneyTxnTable(
            txns: state.txns,
            onDeleteAdjustment: (t) async {
              final cubit = context.read<CashCubit>();
              if (await _confirmDeleteAdjustment(context, t)) cubit.deleteAdjustment(t.id);
            },
          ),
        ),
      );
}

// ---------------------------------------------------------------- cheques

class ChequesScreen extends StatelessWidget {
  const ChequesScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => ChequesCubit(ctx.read(), ctx.read())..load(),
        child: _MoneyListPage<ChequesCubit>(
          onRetry: (ctx) => ctx.read<ChequesCubit>().load,
          header: (context, state) => const Text('Cheque Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          empty: const EmptyState(
            icon: Icons.fact_check_outlined,
            title: 'No Cheques to Show',
            message: "You haven't added any cheque transactions yet.",
          ),
          table: (context, state) => MoneyTxnTable(
            txns: state.txns,
            trailing: (
              header: 'Status',
              build: (t) => Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      t.isOpenCheque ? 'Open' : 'Closed',
                      style: TextStyle(color: t.isOpenCheque ? Colors.orange.shade800 : receiveGreen, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    if (t.isOpenCheque)
                      TextButton(
                        onPressed: state.accounts.isEmpty
                            ? () => showError(context, 'Add a bank account first (Cash & Bank → Bank Accounts).')
                            : () => showChequeDepositDialog(context, t, state.accounts),
                        child: Text(t.amount >= 0 ? 'Deposit' : 'Withdraw'),
                      )
                    else
                      TextButton(onPressed: () => context.read<ChequesCubit>().reopen(t), child: const Text('Re-open')),
                  ]),
            ),
          ),
        ),
      );
}
