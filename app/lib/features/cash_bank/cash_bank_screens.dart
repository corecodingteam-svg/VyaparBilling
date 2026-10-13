import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/status.dart';
import '../../data/models/cash_bank.dart';
import '../../shared/data_table_view.dart';
import '../../shared/export.dart';
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
          return const LoadingView();
        }
        if (state.status == LoadStatus.failure && state.accounts.isEmpty) {
          return ErrorRetry(error: state.error ?? 'Could not load', onRetry: () => context.read<BankAccountsBloc>().add(const BankAccountsRequested()));
        }
        final header = Row(children: [
          const Expanded(child: Text('Banks', style: AppText.title)),
          ExportMenu(table: () => TableExport(
            title: 'Banks',
            headers: ['Account', 'Bank', 'Account number', 'IFSC', 'UPI', 'Balance'],
            rows: [for (final a in state.visible) [a.name, a.bankName, a.accountNumber, a.ifsc, a.upiId, a.balance]],
          )),
          const SizedBox(width: AppSpace.sm),
          FilledButton.icon(
            onPressed: () => showBankAccountForm(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Bank'),
          ),
        ]);
        if (state.accounts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(children: [
              header,
              const SizedBox(height: AppSpace.md),
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
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(children: [
            header,
            const SizedBox(height: AppSpace.md),
            Expanded(
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(width: AppSize.listPane, child: list),
                      const SizedBox(width: AppSpace.md),
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
          padding: const EdgeInsets.all(AppSpace.md),
          child: TextField(textInputAction: TextInputAction.search, 
            onChanged: (v) => context.read<BankAccountsBloc>().add(BankAccountsSearchChanged(v)),
            decoration: const InputDecoration(hintText: 'Search by account', prefixIcon: Icon(Icons.search)),
          ),
        ),
          Expanded(
            child: PagedListPane<BankAccount>(
              items: shown,
              headings: const ['Account Name', 'Amount'],
              sortKeys: [(a) => a.name, (a) => a.balance],
              emptyText: 'No matching accounts',
              onRefresh: () => context.reloadBloc<BankAccountsBloc, BankAccountsEvent, BankAccountsState>(const BankAccountsRequested()),
              itemBuilder: (_, a) {
                    return ListTile(
                      selected: highlight && a.id == state.selectedId,
                      selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                      title: Text(a.name, overflow: TextOverflow.ellipsis),
                      trailing: Text(money(a.balance), style: TextStyle(color: a.balance < 0 ? AppColors.moneyOut : AppColors.moneyIn, fontWeight: FontWeight.w600)),
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
      return PullToRefresh(onRefresh: () => context.reloadBloc<BankAccountsBloc, BankAccountsEvent, BankAccountsState>(const BankAccountsRequested()), child: ListView(padding: EdgeInsets.zero, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(account.name, style: AppText.title, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    tooltip: 'Edit account',
                    icon: Icon(Icons.edit_outlined, color: AppColors.primary, size: AppIconSize.md),
                    onPressed: () => showBankAccountForm(context, account: account),
                  ),
                  IconButton(
                    tooltip: 'Delete account',
                    icon: const Icon(Icons.delete_outline, size: AppIconSize.md),
                    onPressed: () => _deleteAccount(context, account),
                  ),
                ]),
                PopupMenuButton<String>(
                  tooltip: 'Deposit / Withdraw',
                  onSelected: (kind) => showAdjustmentDialog(context, kinds: bankAdjustmentKinds, initialKind: kind, bankAccountId: account.id),
                  itemBuilder: (_) => [for (final k in bankAdjustmentKinds) PopupMenuItem(value: k, child: Text(adjustmentKinds[k]!))],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.dangerText), borderRadius: AppRadius.pillAll),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Deposit / Withdraw', style: TextStyle(color: AppColors.dangerText, fontWeight: FontWeight.w600)),
                      Icon(Icons.arrow_drop_down, color: AppColors.danger),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpace.sm),
              Wrap(spacing: 40, runSpacing: 12, children: [
                InfoField('Balance', money(account.balance), valueColor: account.balance < 0 ? AppColors.moneyOut : AppColors.moneyIn),
                if ((account.bankName ?? '').isNotEmpty) InfoField('Bank', account.bankName!),
                if ((account.accountNumber ?? '').isNotEmpty) InfoField('Account Number', account.accountNumber!),
                if ((account.ifsc ?? '').isNotEmpty) InfoField('IFSC', account.ifsc!),
                if ((account.holderName ?? '').isNotEmpty) InfoField('Account Holder', account.holderName!),
                if ((account.upiId ?? '').isNotEmpty) InfoField('UPI ID', account.upiId!),
              ]),
            ]),
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
                if (state.txns.isNotEmpty)
                  ExportMenu(table: () => TableExport(
                    title: '${account.name} transactions',
                    headers: ['Date', 'Type', 'Name', 'Number', 'Mode', 'Amount'],
                    rows: [for (final t in state.txns) [displayDate(t.date), t.type, t.name, t.number, t.paymentMode, t.amount]],
                  )),
              ]),
            ),
            switch (state.txnStatus) {
              LoadStatus.initial || LoadStatus.loading => const SizedBox(height: AppSize.stateHeight, child: LoadingView()),
              LoadStatus.failure => SizedBox(
                  height: AppSize.stateHeight,
                  child: ErrorRetry(error: state.error ?? 'Could not load', onRetry: () => bloc.add(BankAccountSelected(account.id))),
                ),
              LoadStatus.success when state.txns.isEmpty =>
                const SizedBox(height: AppSize.stateHeight, child: EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions to show')),
              LoadStatus.success => MoneyTxnTable(
                  txns: state.txns,
                  onDeleteAdjustment: (t) async {
                    if (await _confirmDeleteAdjustment(context, t)) bloc.add(BankAdjustmentDeleted(t.id));
                  },
                ),
            },
          ]),
        ),
      ]));
    });
  }
}

// ---------------------------------------------------------------- shared list page

/// Header + card with a transaction table, driven by a [MoneyListState] cubit.
class _MoneyListPage<C extends Cubit<MoneyListState>> extends StatelessWidget {
  const _MoneyListPage({required this.title, required this.header, required this.empty, required this.table, required this.onRetry});
  final String title;
  final Widget Function(BuildContext, MoneyListState) header;
  final Widget empty;
  final Widget Function(BuildContext, MoneyListState) table;
  final Future<void> Function() Function(BuildContext) onRetry;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<C, MoneyListState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error && b.status == LoadStatus.success,
      listener: (context, state) => showError(context, state.error!),
      builder: (context, state) => PullToRefresh(onRefresh: onRetry(context), child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        header(context, state),
        const SizedBox(height: AppSpace.md),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.md, AppSpace.md),
              child: Row(children: [
                const Expanded(child: Text('Transactions', style: AppText.subtitle)),
                if (state.txns.isNotEmpty)
                  ExportMenu(table: () => TableExport(
                    title: title,
                    headers: ['Date', 'Type', 'Name', 'Number', 'Mode', 'Amount'],
                    rows: [for (final t in state.txns) [displayDate(t.date), t.type, t.name, t.number, t.paymentMode, t.amount]],
                  )),
              ]),
            ),
            switch (state.status) {
              LoadStatus.initial || LoadStatus.loading => const SizedBox(height: AppSize.stateHeight, child: LoadingView()),
              LoadStatus.failure => SizedBox(height: AppSize.stateHeight, child: ErrorRetry(error: state.error ?? 'Could not load', onRetry: onRetry(context))),
              LoadStatus.success when state.txns.isEmpty => SizedBox(height: AppSize.stateHeight, child: empty),
              LoadStatus.success => table(context, state),
            },
          ]),
        ),
      ])),
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
          title: 'Cash in hand',
          onRetry: (ctx) => ctx.read<CashCubit>().load,
          header: (context, state) => Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Cash In Hand', style: AppText.title),
              const SizedBox(width: AppSpace.lg),
              Text(money(state.balance),
                  style: TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.w700, color: state.balance < 0 ? AppColors.moneyOut : AppColors.moneyIn)),
            ]),
            FilledButton.icon(
              onPressed: () => showAdjustmentDialog(context, kinds: cashAdjustmentKinds),
              icon: const Icon(Icons.tune, size: AppIconSize.sm),
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
          title: 'Cheques',
          onRetry: (ctx) => ctx.read<ChequesCubit>().load,
          header: (context, state) => const Text('Cheque Details', style: AppText.title),
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
                      style: TextStyle(color: t.isOpenCheque ? AppColors.warningText : AppColors.successText, fontWeight: FontWeight.w600, fontSize: AppFont.body),
                    ),
                    const SizedBox(width: AppSpace.sm),
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
