import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/status.dart';
import '../../data/models/loan.dart';
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
    if (!_formKey.currentState!.validate()) return;
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
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 4),
                TextFormField(
                  controller: _name,
                  autofocus: _loan == null,
                  decoration: const InputDecoration(labelText: 'Account Name *'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name for this loan' : null,
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: TextFormField(controller: _lender, decoration: const InputDecoration(labelText: 'Lender Bank'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _number, decoration: const InputDecoration(labelText: 'Account Number'))),
                ]),
                const SizedBox(height: 14),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextFormField(
                      controller: _opening,
                      keyboardType: _numeric,
                      decoration: const InputDecoration(labelText: 'Current Loan Balance', prefixText: '₹ '),
                      validator: _optionalNumber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: DateField(label: 'Balance As Of', value: state.date, onChanged: cubit.dateChanged)),
                ]),
                const SizedBox(height: 14),
                _MoneyAccountField(label: 'Loan Received In', state: state, onChanged: cubit.bankAccountChanged),
                const SizedBox(height: 14),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rate,
                      keyboardType: _numeric,
                      decoration: const InputDecoration(labelText: 'Interest Rate', suffixText: '% per annum'),
                      validator: (v) {
                        final n = parseNum(v ?? '');
                        return (v ?? '').trim().isEmpty || (n != null && n >= 0 && n <= 100) ? null : 'Between 0 and 100';
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _term,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Term Duration', suffixText: 'months'),
                      validator: (v) => (v ?? '').trim().isEmpty || (int.tryParse(v!.trim()) ?? 0) > 0 ? null : 'Whole months',
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
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
    if (!_formKey.currentState!.validate()) return;
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
          content: Form(
            key: _formKey,
            child: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${widget.loan.name} · outstanding ${money(widget.loan.balance)}'),
                  const SizedBox(height: 16),
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
                          if ((v ?? '').trim().isNotEmpty && n == null) return 'Enter a valid amount';
                          if (isPayment) {
                            if ((n ?? 0) + (parseNum(_interest.text) ?? 0) <= 0) return 'Enter principal or interest';
                            return (n ?? 0) > _payable ? 'More than the outstanding ${money(_payable)}' : null;
                          }
                          return (n ?? 0) <= 0 ? 'Enter an amount greater than 0' : null;
                        },
                      ),
                    ),
                    if (isPayment) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _interest,
                          keyboardType: _numeric,
                          decoration: const InputDecoration(labelText: 'Interest Amount', prefixText: '₹ '),
                          validator: (v) => (v ?? '').trim().isNotEmpty && parseNum(v!) == null ? 'Enter a valid amount' : null,
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: DateField(label: 'Date', value: state.date, onChanged: cubit.dateChanged)),
                    if (state.kind != 'charge') ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MoneyAccountField(label: isPayment ? 'Paid From' : 'Received In', state: state, onChanged: cubit.bankAccountChanged),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 14),
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
        if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) return const Center(child: CircularProgressIndicator());
        if (state.status == LoadStatus.failure && state.loans.isEmpty) {
          return ErrorRetry(error: state.error ?? 'Could not load', onRetry: () => context.read<LoansBloc>().add(const LoansRequested()));
        }
        final add = FilledButton.icon(
          onPressed: () => showLoanForm(context),
          style: FilledButton.styleFrom(backgroundColor: payRed),
          icon: const Icon(Icons.add),
          label: const Text('Add Loan A/C'),
        );
        final header = Row(children: [
          const Text('Loan Accounts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          if (state.loans.isNotEmpty) Text(money(state.totalOutstanding), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: payRed)),
          const Spacer(),
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
                    color: pageBg,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: const Row(children: [
                      Expanded(child: Text('Account Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                      Text('Balance', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    ]),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: state.loans.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (_, i) {
                        final l = state.loans[i];
                        return ListTile(
                          selected: wide && l.id == state.selectedId,
                          selectedTileColor: brandBlue.withValues(alpha: 0.08),
                          title: Text(l.name, overflow: TextOverflow.ellipsis),
                          subtitle: (l.lender ?? '').isEmpty ? null : Text(l.lender!),
                          trailing: Text(money(l.balance), style: const TextStyle(color: payRed, fontWeight: FontWeight.w600)),
                          onTap: () => _open(context, l),
                        );
                      },
                    ),
                  ),
                ]),
        );
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            header,
            const SizedBox(height: 12),
            Expanded(
              child: wide && state.loans.isNotEmpty
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(width: 320, child: list),
                      const SizedBox(width: 12),
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
      return ListView(padding: EdgeInsets.zero, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(loan.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  IconButton(
                    tooltip: 'Edit loan',
                    icon: const Icon(Icons.edit_outlined, color: brandBlue, size: 20),
                    onPressed: () => showLoanForm(context, loan: loan),
                  ),
                  IconButton(
                    tooltip: 'Delete loan',
                    icon: const Icon(Icons.delete_outline, size: 20),
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
              const SizedBox(height: 8),
              Wrap(spacing: 40, runSpacing: 12, children: [
                InfoField('Balance Amount', money(loan.balance), valueColor: payRed),
                if ((loan.lender ?? '').isNotEmpty) InfoField('Lender Bank', loan.lender!),
                if ((loan.accountNumber ?? '').isNotEmpty) InfoField('Account Number', loan.accountNumber!),
                if (loan.interestRate != null) InfoField('Interest Rate', '${numText(loan.interestRate)}% p.a.'),
                if (loan.termMonths != null) InfoField('Term', '${loan.termMonths} months'),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            if (state.txnStatus != LoadStatus.success)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else
              LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: c.maxWidth),
                    child: DataTable(
                      headingRowColor: const WidgetStatePropertyAll(pageBg),
                      columns: const [
                        DataColumn(label: Text('Type')),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Principal'), numeric: true),
                        DataColumn(label: Text('Interest'), numeric: true),
                        DataColumn(label: Text('Total Amount'), numeric: true),
                        DataColumn(label: Text('Balance'), numeric: true),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final t in state.txns)
                          DataRow(cells: [
                            DataCell(Text(t.type)),
                            DataCell(Text(displayDate(t.date))),
                            DataCell(Text(money(t.principal))),
                            DataCell(Text(t.interest == 0 ? '-' : money(t.interest))),
                            DataCell(Text(money(t.total), style: TextStyle(color: t.kind == 'payment' ? receiveGreen : payRed))),
                            DataCell(Text(money(t.balance))),
                            DataCell(t.id == null
                                ? const SizedBox.shrink()
                                : Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(
                                      tooltip: 'Edit',
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      onPressed: () => showLoanTxnForm(context, loan, t.kind, txn: t),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      icon: const Icon(Icons.delete_outline, size: 20),
                                      onPressed: () async {
                                        if (await confirmDelete(context, title: 'Delete entry', message: 'Delete this "${t.type}" of ${money(t.total)}?')) {
                                          bloc.add(LoanTxnDeleted(t.id!));
                                        }
                                      },
                                    ),
                                  ])),
                          ]),
                      ],
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]);
    });
  }
}
