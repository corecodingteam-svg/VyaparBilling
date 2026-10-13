import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/status.dart';
import '../../data/models/cash_bank.dart';
import '../../data/repositories/cash_bank_repository.dart';
import '../../shared/format.dart';
import '../../shared/submit_dialog.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'bloc/cash_bank_form_cubits.dart';

const _numeric = TextInputType.numberWithOptions(decimal: true);

// ---------------------------------------------------------------- bank account

Future<void> showBankAccountForm(BuildContext context, {BankAccount? account}) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider(
        create: (_) => BankAccountFormCubit(context.read(), account),
        child: const _BankAccountDialog(),
      ),
    );

class _BankAccountDialog extends StatefulWidget {
  const _BankAccountDialog();

  @override
  State<_BankAccountDialog> createState() => _BankAccountDialogState();
}

/// Stateful only to own the text controllers; all other state lives in [BankAccountFormCubit].
class _BankAccountDialogState extends State<_BankAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final BankAccount? _account = context.read<BankAccountFormCubit>().account;
  late final _name = TextEditingController(text: _account?.name);
  late final _opening = TextEditingController(text: (_account?.openingBalance ?? 0) == 0 ? '' : numText(_account!.openingBalance));
  late final _number = TextEditingController(text: _account?.accountNumber);
  late final _ifsc = TextEditingController(text: _account?.ifsc);
  late final _bank = TextEditingController(text: _account?.bankName);
  late final _holder = TextEditingController(text: _account?.holderName);
  late final _upi = TextEditingController(text: _account?.upiId);

  @override
  void dispose() {
    for (final c in [_name, _opening, _number, _ifsc, _bank, _holder, _upi]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!validateForm(context, _formKey, report: showError)) return;
    context.read<BankAccountFormCubit>().save({
      'name': _name.text.trim(),
      'openingBalance': parseNum(_opening.text) ?? 0,
      'accountNumber': _number.text.trim(),
      'ifsc': _ifsc.text.trim(),
      'bankName': _bank.text.trim(),
      'holderName': _holder.text.trim(),
      'upiId': _upi.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BankAccountFormCubit>();
    return BlocConsumer<BankAccountFormCubit, BankAccountFormState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == SubmitStatus.failure) showError(context, s.error!);
        if (s.status == SubmitStatus.success) {
          showSuccess(context, 'Bank account saved');
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) => AlertDialog(
        title: Text(cubit.editing ? 'Edit Bank Account' : 'Add Bank Account'),
        content: Form(autovalidateMode: AutovalidateMode.onUserInteraction, 
          key: _formKey,
          child: SizedBox(
            width: AppSize.dialogLg,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: AppSpace.xs),
                TextFormField(
                  controller: _name,
                  autofocus: !cubit.editing,
                  decoration: const InputDecoration(labelText: 'Account Display Name *'),
                  validator: Validators.required('Account name'),
                ),
                const SizedBox(height: AppSpace.md),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: TextFormField(
                      controller: _opening,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Opening Balance', prefixText: '₹ '),
                      validator: Validators.number('Amount', nonNegative: false),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(child: DateField(label: 'As of Date', value: state.openingDate, onChanged: cubit.openingDateChanged)),
                ]),
                const SizedBox(height: AppSpace.sm),
                if (!state.showMore)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(onPressed: cubit.showMoreFields, icon: const Icon(Icons.add), label: const Text('Add more fields')),
                  )
                else ...[
                  const SizedBox(height: AppSpace.sm),
                  Row(children: [
                    Expanded(child: TextFormField(controller: _number, decoration: const InputDecoration(labelText: 'Account Number'))),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: TextFormField(
                        controller: _ifsc,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'IFSC Code'),
                        validator: Validators.pattern('IFSC code', RegExp(r'^[A-Za-z]{4}0[A-Za-z0-9]{6}$'), '11 characters: 4 letters, a zero, then 6 letters or digits'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppSpace.md),
                  Row(children: [
                    Expanded(child: TextFormField(controller: _bank, decoration: const InputDecoration(labelText: 'Bank Name'))),
                    const SizedBox(width: AppSpace.md),
                    Expanded(child: TextFormField(controller: _holder, decoration: const InputDecoration(labelText: 'Account Holder Name'))),
                  ]),
                  const SizedBox(height: AppSpace.md),
                  TextFormField(controller: _upi, decoration: const InputDecoration(labelText: 'UPI ID')),
                ],
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: state.status == SubmitStatus.submitting ? null : _save,
            child: const Text('Save Details'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- adjustments & transfers

const cashAdjustmentKinds = ['cash_add', 'cash_reduce'];
const bankAdjustmentKinds = ['bank_to_cash', 'cash_to_bank', 'bank_to_bank', 'bank_add', 'bank_reduce'];

/// Dialog for one of [kinds]; [initialKind] and [bankAccountId] preselect the choice.
/// With [editId] it changes that existing adjustment or transfer instead of adding one.
Future<void> showAdjustmentDialog(BuildContext context, {required List<String> kinds, String? initialKind, String? bankAccountId, String? editId}) {
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) {
        final cubit = AdjustmentFormCubit(context.read(), kinds: kinds, bankAccountId: bankAccountId, editId: editId)..load();
        if (initialKind != null) cubit.kindChanged(initialKind);
        return cubit;
      },
      child: const _AdjustmentDialog(),
    ),
  );
}

class _AdjustmentDialog extends StatefulWidget {
  const _AdjustmentDialog();

  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

/// Stateful only to own the text controllers; all other state lives in [AdjustmentFormCubit].
class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!validateForm(context, _formKey, report: showError)) return;
    context.read<AdjustmentFormCubit>().submit(amount: parseNum(_amount.text)!, description: _description.text);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdjustmentFormCubit>();
    final cashOnly = cubit.kinds.every((k) => k.startsWith('cash_') && k != 'cash_to_bank');
    return BlocConsumer<AdjustmentFormCubit, AdjustmentFormState>(
      listenWhen: (a, b) => a.status != b.status || a.loadStatus != b.loadStatus,
      listener: (context, s) {
        // Editing: the stored values arrive after the dialog opens.
        if (s.loadStatus == LoadStatus.success && cubit.editing && _amount.text.isEmpty) {
          _amount.text = s.initialAmount;
          _description.text = s.initialDescription;
        }
        if (s.loadStatus == LoadStatus.failure) showError(context, s.error ?? 'Could not load');
        if (s.status == SubmitStatus.failure) showError(context, s.error!);
        if (s.status == SubmitStatus.success) {
          showSuccess(context, 'Saved');
          Navigator.of(context).pop();
        }
      },
      builder: (context, s) {
        Widget accountField(String label, String? value, ValueChanged<String?> onChanged) => DropdownButtonFormField<String?>(
              key: ValueKey('$label-$value-${s.accounts.length}'),
              initialValue: s.accounts.any((a) => a.id == value) ? value : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
              items: [for (final a in s.accounts) DropdownMenuItem(value: a.id, child: Text('${a.name}  (${money(a.balance)})'))],
              onChanged: onChanged,
            );

        return AlertDialog(
          title: Text(cubit.editing ? 'Edit ${adjustmentKinds[s.kind] ?? 'Adjustment'}' : (cashOnly ? 'Adjust Cash' : 'Deposit / Withdraw / Transfer')),
          content: Form(autovalidateMode: AutovalidateMode.onUserInteraction, 
            key: _formKey,
            child: SizedBox(
              width: AppSize.dialogMd,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: AppSpace.xs),
                  if (cashOnly)
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'cash_add', label: Text('Add Cash'), icon: Icon(Icons.add)),
                        ButtonSegment(value: 'cash_reduce', label: Text('Reduce Cash'), icon: Icon(Icons.remove)),
                      ],
                      selected: {s.kind},
                      onSelectionChanged: (v) => cubit.kindChanged(v.first),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey('kind-${s.kind}'),
                      initialValue: s.kind,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: [for (final k in cubit.kinds) DropdownMenuItem(value: k, child: Text(adjustmentKinds[k]!))],
                      onChanged: (v) => cubit.kindChanged(v!),
                    ),
                  if (s.needsBank) ...[
                    const SizedBox(height: AppSpace.md),
                    accountField(
                      switch (s.kind) { 'cash_to_bank' => 'To Account', 'bank_add' || 'bank_reduce' => 'Account', _ => 'From Account' },
                      s.bankAccountId,
                      cubit.bankAccountChanged,
                    ),
                  ],
                  if (s.isTransfer) ...[
                    const SizedBox(height: AppSpace.md),
                    accountField('To Account', s.toBankAccountId, cubit.toBankAccountChanged),
                  ],
                  const SizedBox(height: AppSpace.md),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amount,
                        autofocus: !cubit.editing,
                        keyboardType: _numeric,
                        decoration: const InputDecoration(labelText: 'Amount *', prefixText: '₹ '),
                        validator: Validators.number('Amount', required: true, positive: true),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(child: DateField(label: 'Date', value: s.date, onChanged: cubit.dateChanged)),
                  ]),
                  const SizedBox(height: AppSpace.md),
                  TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description')),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: s.status == SubmitStatus.submitting || s.loadStatus != LoadStatus.success ? null : _submit,
              child: Text(cubit.editing ? 'Update' : 'Save'),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- cheque deposit

/// Asks which bank account a cheque went through, then marks it deposited/withdrawn.
Future<void> showChequeDepositDialog(BuildContext context, MoneyTxn cheque, List<BankAccount> accounts) {
  final repo = context.read<CashBankRepository>();
  // The dropdown's own FormField state holds the choice; this just carries it to the action.
  String? accountId = accounts.length == 1 ? accounts.single.id : null;
  return showSubmitDialog<bool>(
    context,
    title: cheque.amount >= 0 ? 'Deposit Cheque' : 'Withdraw Cheque',
    action: () async {
      await repo.depositCheque(cheque, accountId!);
      return true;
    },
    fields: (_) => [
      Text('${cheque.type} · ${cheque.name} · ${money(cheque.amount.abs())}'),
      const SizedBox(height: AppSpace.lg),
      DropdownButtonFormField<String?>(
        initialValue: accountId,
        isExpanded: true,
        decoration: InputDecoration(labelText: cheque.amount >= 0 ? 'Deposit To' : 'Withdraw From'),
        items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
        onChanged: (v) => accountId = v,
        validator: Validators.choose('bank account'),
      ),
    ],
  );
}
