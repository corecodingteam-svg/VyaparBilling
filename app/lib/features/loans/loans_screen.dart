import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/status.dart';
import '../../data/models/loan.dart';
import '../../shared/data_table_view.dart';
import '../../shared/export.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'loans_bloc.dart';

const _numeric = TextInputType.numberWithOptions(decimal: true);

/// "Cash" or one of the bank accounts — where loan money is received into or paid from.
class _MoneyAccountField extends StatelessWidget {
  const _MoneyAccountField({required this.label, required this.state, required this.onChanged});
  final String label;
  final LoanFormState state;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
        key: ValueKey('acct-${state.bankAccountId}-${state.accounts.length}'),
        initialValue: state.accounts.any((a) => a.id == state.bankAccountId) ? state.bankAccountId : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: null, child: Text('Cash')),
          for (final a in state.accounts) DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      );
}

// ---------------------------------------------------------------- loan account dialog

Future<void> showLoanForm(BuildContext context, {LoanAccount? loan}) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider(
        create: (_) => LoanFormCubit(context.read(), context.read(), loan: loan)..load(),
        child: const _LoanDialog(),
      ),
    );

class _LoanDialog extends StatefulWidget {
  const _LoanDialog();

  @override
  State<_LoanDialog> createState() => _LoanDialogState();
}

/// Stateful only to own the text controllers; all other state lives in [LoanFormCubit].
class _LoanDialogState extends State<_LoanDialog> {
  final _formKey = GlobalKey<FormState>();
  late final LoanAccount? _loan = context.read<LoanFormCubit>().loan;
  late final _name = TextEditingController(text: _loan?.name);
  late final _lender = TextEditingController(text: _loan?.lender);
  late final _number = TextEditingController(text: _loan?.accountNumber);
  late final _opening = TextEditingController(text: (_loan?.openingBalance ?? 0) == 0 ? '' : numText(_loan!.openingBalance));
  late final _rate = TextEditingController(text: numText(_loan?.interestRate));
  late final _term = TextEditingController(text: _loan?.termMonths?.toString() ?? '');
  late final _description = TextEditingController(text: _loan?.description);

  @override
  void dispose() {
    for (final c in [_name, _lender, _number, _opening, _rate, _term, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!validateForm(context, _formKey, report: showError)) return;
    context.read<LoanFormCubit>().saveAccount({
      'name': _name.text.trim(),
      'lender': _lender.text.trim(),
      'accountNumber': _number.text.trim(),
      'openingBalance': parseNum(_opening.text) ?? 0,
      'interestRate': parseNum(_rate.text),
      'termMonths': int.tryParse(_term.text.trim()),
      'description': _description.text.trim(),
    });
  }

  String? _optionalNumber(String? v) => (v ?? '').trim().isNotEmpty && parseNum(v!) == null ? 'Enter a valid number' : null;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LoanFormCubit>();
    return BlocConsumer<LoanFormCubit, LoanFormState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == SubmitStatus.failure) showError(context, s.error!);
        if (s.status == SubmitStatus.success) {
          showSuccess(context, 'Loan account saved');
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) => AlertDialog(
        title: Text(_loan == null ? 'Add Loan Account' : 'Edit Loan Account'),
        content: Form(autovalidateMode: AutovalidateMode.onUserInteraction, 
          key: _formKey,
          child: SizedBox(
            width: AppSize.dialogLg,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: AppSpace.xs),
                TextFormField(
                  controller: _name,
                  autofocus: _loan == null,
                  decoration: const InputDecoration(labelText: 'Account Name *'),
                  validator: Validators.required('Loan name'),
                ),
                const SizedBox(height: AppSpace.md),
                Row(children: [
                  Expanded(child: TextFormField(controller: _lender, decoration: const InputDecoration(labelText: 'Lender Bank'))),
                  const SizedBox(width: AppSpace.md),
                  Expanded(child: TextFormField(controller: _number, decoration: const InputDecoration(labelText: 'Account Number'))),
                ]),
                const SizedBox(height: AppSpace.md),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextFormField(
                      controller: _opening,
                      keyboardType: _numeric,
                      decoration: const InputDecoration(labelText: 'Current Loan Balance', prefixText: '₹ '),
                      validator: _optionalNumber,
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(child: DateField(label: 'Balance As Of', value: state.date, onChanged: cubit.dateChanged)),
                ]),
                const SizedBox(height: AppSpace.md),
                _MoneyAccountField(label: 'Loan Received In', state: state, onChanged: cubit.bankAccountChanged),
                const SizedBox(height: AppSpace.md),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rate,
                      keyboardType: _numeric,
                      decoration: const InputDecoration(labelText: 'Interest Rate', suffixText: '% per annum'),
                      validator: Validators.number('Interest rate', nonNegative: true, max: 100),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: TextFormField(
                      controller: _term,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Term Duration', suffixText: 'months'),
                      validator: Validators.number('Term', positive: true, whole: true),
                    ),
                  ),
                ]),
                const SizedBox(height: AppSpace.md),
                TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description')),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: state.status == SubmitStatus.submitting ? null : _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- loan transaction dialog

/// Adds an entry of [kind] to [loan], or changes [txn] when one is given.
Future<void> showLoanTxnForm(BuildContext context, LoanAccount loan, String kind, {LoanTxn? txn}) => showDialog<void>(
      context: context,
      builder: (_) => BlocProvider(
        create: (_) => LoanFormCubit(context.read(), context.read(), kind: kind, txn: txn)..load(),
        child: _LoanTxnDialog(loan: loan),
      ),
    );

class _LoanTxnDialog extends StatefulWidget {
  const _LoanTxnDialog({required this.loan});
  final LoanAccount loan;

  @override
  State<_LoanTxnDialog> createState() => _LoanTxnDialogState();
}

/// Stateful only to own the text controllers; all other state lives in [LoanFormCubit].
class _LoanTxnDialogState extends State<_LoanTxnDialog> {
  final _formKey = GlobalKey<FormState>();
  late final LoanTxn? _txn = context.read<LoanFormCubit>().txn;
  late final _principal = TextEditingController(text: _txn == null || _txn.principal == 0 ? '' : numText(_txn.principal));
  late final _interest = TextEditingController(text: _txn == null || _txn.interest == 0 ? '' : numText(_txn.interest));
  late final _description = TextEditingController(text: _txn?.description);

  /// What can be repaid: the outstanding loan, plus this entry's own principal when it is being edited.
  num get _payable => widget.loan.balance + (_txn?.kind == 'payment' ? _txn!.principal : 0);

  @override
  void dispose() {
    _principal.dispose();
    _interest.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    if (!validateForm(context, _formKey, report: showError)) return;
    context.read<LoanFormCubit>().saveTransaction(
          widget.loan.id,
          principal: parseNum(_principal.text) ?? 0,
          interest: parseNum(_interest.text) ?? 0,
          description: _description.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LoanFormCubit>();
    return BlocConsumer<LoanFormCubit, LoanFormState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == SubmitStatus.failure) showError(context, s.error!);
        if (s.status == SubmitStatus.success) {
          showSuccess(context, 'Saved');
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        final isPayment = state.kind == 'payment';
        return AlertDialog(
          title: Text(_txn == null ? loanTxnKinds[state.kind]! : 'Edit ${_txn.type}'),
          content: Form(autovalidateMode: AutovalidateMode.onUserInteraction, 
            key: _formKey,
            child: SizedBox(
              width: AppSize.dialogMd,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${widget.loan.name} · outstanding ${money(widget.loan.balance)}'),
                  const SizedBox(height: AppSpace.lg),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: TextFormField(
                        controller: _principal,
                        autofocus: _txn == null,
                        keyboardType: _numeric,
                        decoration: InputDecoration(
                          labelText: switch (state.kind) { 'payment' => 'Principal Amount', 'increase' => 'Increase Loan By *', _ => 'Charge Amount *' },
                          prefixText: '₹ ',
                        ),
                        validator: (v) {
                          final n = parseNum(v ?? '');
                          if ((v ?? '').trim().isNotEmpty && n == null) return 'Amount must be a number';
                          if (isPayment) {
                            if ((n ?? 0) + (parseNum(_interest.text) ?? 0) <= 0) return 'Enter the principal repaid or the interest paid';
                            return (n ?? 0) > _payable ? 'Amount cannot be more than the ${money(_payable)} outstanding' : null;
                          }
                          return (n ?? 0) <= 0 ? 'Amount must be greater than 0' : null;
                        },
                      ),
                    ),
                    if (isPayment) ...[
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: TextFormField(
                          controller: _interest,
                          keyboardType: _numeric,
                          decoration: const InputDecoration(labelText: 'Interest Amount', prefixText: '₹ '),
                          validator: Validators.number('Amount', nonNegative: false),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: AppSpace.md),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: DateField(label: 'Date', value: state.date, onChanged: cubit.dateChanged)),
                    if (state.kind != 'charge') ...[
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: _MoneyAccountField(label: isPayment ? 'Paid From' : 'Received In', state: state, onChanged: cubit.bankAccountChanged),
                      ),
                    ],
                  ]),
                  const SizedBox(height: AppSpace.md),
                  TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description')),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: state.status == SubmitStatus.submitting ? null : _save, child: const Text('Save')),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- screen

/// Loan accounts with outstanding balances; the selected loan's history beside (wide) or on a pushed page (phones).
class LoanAccountsScreen extends StatelessWidget {
  const LoanAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => LoansBloc(ctx.read(), ctx.read())..add(const LoansRequested()),
        child: const _LoansView(),
      );
}

class _LoansView extends StatelessWidget {
  const _LoansView();

  void _open(BuildContext context, LoanAccount l) {
    final bloc = context.read<LoansBloc>()..add(LoanSelected(l.id));
    if (isWide(context)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: BlocBuilder<LoansBloc, LoansState>(
          builder: (ctx, s) => Scaffold(appBar: AppBar(title: Text(s.selected?.name ?? l.name)), body: const _LoanDetail()),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return BlocConsumer<LoansBloc, LoansState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error && b.status == LoadStatus.success,
      listener: (context, state) => showError(context, state.error!),
      builder: (context, state) {
        if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) return const LoadingView();
        if (state.status == LoadStatus.failure && state.loans.isEmpty) {
          return ErrorRetry(error: state.error ?? 'Could not load', onRetry: () => context.read<LoansBloc>().add(const LoansRequested()));
        }
        final add = FilledButton.icon(
          onPressed: () => showLoanForm(context),
          icon: const Icon(Icons.add),
          label: const Text('Add Loan A/C'),
        );
        final header = Row(children: [
          const Text('Loan Accounts', style: AppText.title),
          const SizedBox(width: AppSpace.lg),
          if (state.loans.isNotEmpty) Text(money(state.totalOutstanding), style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.w700, color: AppColors.moneyOut)),
          const Spacer(),
          if (state.loans.isNotEmpty) ...[
            ExportMenu(table: () => TableExport(
              title: 'Loan accounts',
              headers: ['Account', 'Lender', 'Account number', 'Interest %', 'Term (months)', 'Outstanding'],
              rows: [for (final l in state.loans) [l.name, l.lender, l.accountNumber, l.interestRate, l.termMonths, l.balance]],
            )),
            const SizedBox(width: AppSpace.sm),
          ],
          add,
        ]);
        final list = Card(
          clipBehavior: Clip.antiAlias,
          child: state.loans.isEmpty
              ? EmptyState(
                  icon: Icons.account_balance_outlined,
                  title: 'No loan accounts yet',
                  message: 'Track loans you have taken, their repayments and interest.',
                  action: add,
                )
              : Column(children: [
                  Container(
                    color: AppColors.background,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
                    child: const Row(children: [
                      Expanded(child: Text('Account Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.small))),
                      Text('Balance', style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.small)),
                    ]),
                  ),
                  Expanded(
                    child: PullToRefresh(onRefresh: () => context.reloadBloc<LoansBloc, LoansEvent, LoansState>(const LoansRequested()), child: ListView.separated(
                      itemCount: state.loans.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (_, i) {
                        final l = state.loans[i];
                        return ListTile(
                          selected: wide && l.id == state.selectedId,
                          selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                          title: Text(l.name, overflow: TextOverflow.ellipsis),
                          subtitle: (l.lender ?? '').isEmpty ? null : Text(l.lender!),
                          trailing: Text(money(l.balance), style: const TextStyle(color: AppColors.moneyOut, fontWeight: FontWeight.w600)),
                          onTap: () => _open(context, l),
                        );
                      },
                    )),
                  ),
                ]),
        );
        return Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(children: [
            header,
            const SizedBox(height: AppSpace.md),
            Expanded(
              child: wide && state.loans.isNotEmpty
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(width: AppSize.listPane, child: list),
                      const SizedBox(width: AppSpace.md),
                      const Expanded(child: _LoanDetail()),
                    ])
                  : list,
            ),
          ]),
        );
      },
    );
  }
}

class _LoanDetail extends StatelessWidget {
  const _LoanDetail();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoansBloc, LoansState>(builder: (context, state) {
      final loan = state.selected;
      if (loan == null) return const SizedBox.shrink();
      final bloc = context.read<LoansBloc>();
      return PullToRefresh(onRefresh: () => context.reloadBloc<LoansBloc, LoansEvent, LoansState>(const LoansRequested()), child: ListView(padding: EdgeInsets.zero, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(loan.name, style: AppText.title, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    tooltip: 'Edit loan',
                    icon: Icon(Icons.edit_outlined, color: AppColors.primary, size: AppIconSize.md),
                    onPressed: () => showLoanForm(context, loan: loan),
                  ),
                  IconButton(
                    tooltip: 'Delete loan',
                    icon: const Icon(Icons.delete_outline, size: AppIconSize.md),
                    onPressed: () async {
                      if (await confirmDelete(context, title: 'Delete loan account', message: 'Delete "${loan.name}"?')) bloc.add(LoanDeleted(loan.id));
                    },
                  ),
                ]),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(onPressed: () => showLoanTxnForm(context, loan, 'payment'), child: const Text('Make Payment')),
                  OutlinedButton(onPressed: () => showLoanTxnForm(context, loan, 'increase'), child: const Text('Take More Loan')),
                  OutlinedButton(onPressed: () => showLoanTxnForm(context, loan, 'charge'), child: const Text('Charges On Loan')),
                ]),
              ]),
              const SizedBox(height: AppSpace.sm),
              Wrap(spacing: 40, runSpacing: 12, children: [
                InfoField('Balance Amount', money(loan.balance), valueColor: AppColors.moneyOut),
                if ((loan.lender ?? '').isNotEmpty) InfoField('Lender Bank', loan.lender!),
                if ((loan.accountNumber ?? '').isNotEmpty) InfoField('Account Number', loan.accountNumber!),
                if (loan.interestRate != null) InfoField('Interest Rate', '${numText(loan.interestRate)}% p.a.'),
                if (loan.termMonths != null) InfoField('Term', '${loan.termMonths} months'),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(padding: EdgeInsets.all(AppSpace.lg), child: Text('Transactions', style: AppText.subtitle)),
            if (state.txnStatus != LoadStatus.success)
              const SizedBox(height: AppSize.stateHeight, child: LoadingView())
            else
              PagedDataTable(
              searchHint: 'Search entries',
              initialSortColumn: 1,
              initialSortAscending: false,
              columns: const [
                TableColumnSpec('Type'),
                TableColumnSpec('Date'),
                TableColumnSpec('Principal', numeric: true),
                TableColumnSpec('Interest', numeric: true),
                TableColumnSpec('Total Amount', numeric: true),
                TableColumnSpec('Balance', numeric: true),
                TableColumnSpec('', sortable: false),
              ],
              rows: [
                for (final t in state.txns)
                  TableRowData(
                    search: '${t.type} ${displayDate(t.date)}',
                    sort: [t.type, t.date, t.principal, t.interest, t.total, t.balance, null],
                    cells: [
                      Text(t.type),
                      Text(displayDate(t.date)),
                      Text(money(t.principal)),
                      Text(t.interest == 0 ? '-' : money(t.interest)),
                      Text(money(t.total), style: TextStyle(color: t.kind == 'payment' ? AppColors.moneyIn : AppColors.moneyOut)),
                      Text(money(t.balance)),
                      t.id == null
                          ? const SizedBox.shrink()
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined, size: AppIconSize.sm),
                                onPressed: () => showLoanTxnForm(context, loan, t.kind, txn: t),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline, size: AppIconSize.md),
                                onPressed: () async {
                                  if (await confirmDelete(context, title: 'Delete entry', message: 'Delete this "${t.type}" of ${money(t.total)}?')) {
                                    bloc.add(LoanTxnDeleted(t.id!));
                                  }
                                },
                              ),
                            ]),
                    ],
                  ),
              ],
            ),
          ]),
        ),
      ]));
    });
  }
}
