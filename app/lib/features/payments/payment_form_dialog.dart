import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/status.dart';
import '../../data/models/cash_bank.dart';
import '../../data/models/invoice.dart' show paymentModes;
import '../../data/models/party.dart';
import '../../data/models/payment.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../files/attachments.dart';
import 'bloc/payment_form_cubit.dart';

/// Opens the add/edit payment dialog. Returns the saved payment, or null if cancelled.
Future<Payment?> showPaymentForm(BuildContext context, PaymentKind kind, {Payment? payment, String? partyId}) {
  return showDialog<Payment>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => PaymentFormCubit(context.read(), context.read(), context.read(), kind, payment: payment, partyId: partyId, invoices: context.read())..load(),
        ),
        BlocProvider(create: (_) => AttachmentsCubit(context.read(), ownerType: 'payment', ownerId: payment?.id)..load()),
      ],
      child: const _PaymentFormDialog(),
    ),
  );
}

class _PaymentFormDialog extends StatefulWidget {
  const _PaymentFormDialog();

  @override
  State<_PaymentFormDialog> createState() => _PaymentFormDialogState();
}

/// Stateful only to own the text controllers; all other state lives in [PaymentFormCubit].
class _PaymentFormDialogState extends State<_PaymentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _amount = TextEditingController();
  final _description = TextEditingController();

  PaymentFormCubit get _cubit => context.read<PaymentFormCubit>();

  @override
  void initState() {
    super.initState();
    final p = context.read<PaymentFormCubit>().payment;
    _amount.text = numText(p?.amount);
    _description.text = p?.description ?? '';
  }

  @override
  void dispose() {
    _number.dispose();
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _cubit.save(number: _number.text, amount: parseNum(_amount.text)!, description: _description.text);
  }

  @override
  Widget build(BuildContext context) {
    final kind = _cubit.kind;
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final content = BlocConsumer<PaymentFormCubit, PaymentFormState>(
      listenWhen: (a, b) => a.loadStatus != b.loadStatus || a.submitStatus != b.submitStatus,
      listener: (context, s) async {
        if (s.loadStatus == LoadStatus.success && _number.text.isEmpty) _number.text = s.number;
        if (s.submitStatus == SubmitStatus.failure) showError(context, s.error!);
        if (s.submitStatus == SubmitStatus.success) {
          showSuccess(context, '${kind.title} saved');
          final navigator = Navigator.of(context);
          await context.read<AttachmentsCubit>().commit(s.saved!.id);
          navigator.pop(s.saved);
        }
      },
      builder: (context, state) {
        final busy = state.submitStatus == SubmitStatus.submitting;
        return Column(mainAxisSize: narrow ? MainAxisSize.max : MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
            child: Row(children: [
              Text(kind.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
          const Divider(),
          Flexible(
            child: switch (state.loadStatus) {
              LoadStatus.failure => SizedBox(height: 260, child: ErrorRetry(error: state.error ?? 'Could not load', onRetry: _cubit.load)),
              LoadStatus.success => SingleChildScrollView(padding: const EdgeInsets.all(20), child: _fields(state, narrow)),
              _ => const SizedBox(height: 260, child: Center(child: CircularProgressIndicator())),
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              FilledButton(
                onPressed: busy || state.loadStatus != LoadStatus.success ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_cubit.editing ? 'Update' : 'Save'),
              ),
            ]),
          ),
        ]);
      },
    );
    if (narrow) return Dialog.fullscreen(child: content);
    return Dialog(clipBehavior: Clip.antiAlias, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: content));
  }

  Widget _fields(PaymentFormState state, bool narrow) {
    final kind = _cubit.kind;
    final party = state.party;
    final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Autocomplete<Party>(
        initialValue: TextEditingValue(text: party?.name ?? ''),
        displayStringForOption: (p) => p.name,
        optionsBuilder: (v) {
          final term = v.text.trim().toLowerCase();
          return state.parties.where((p) => term.isEmpty || p.name.toLowerCase().contains(term) || (p.phone ?? '').contains(term));
        },
        onSelected: _cubit.partySelected,
        fieldViewBuilder: (context, controller, focusNode, _) => TextFormField(
          controller: controller,
          focusNode: focusNode,
          onChanged: _cubit.partyTextChanged,
          decoration: const InputDecoration(labelText: 'Party *', suffixIcon: Icon(Icons.arrow_drop_down)),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Select a party' : null,
        ),
        optionsViewBuilder: (context, onSelected, options) => AutocompleteOptions<Party>(
          width: 320,
          options: options,
          onSelected: onSelected,
          title: (p) => p.name,
          trailing: (p) => Text(money(p.balance.abs()), style: TextStyle(color: balanceColor(p.balance), fontWeight: FontWeight.w600)),
        ),
      ),
      if (party != null)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text('BAL: ${money(party.balance.abs())}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: balanceColor(party.balance))),
        ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        key: ValueKey('mode-${state.paymentMode}'),
        initialValue: state.paymentMode,
        decoration: const InputDecoration(labelText: 'Payment Type'),
        items: [for (final e in paymentModes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => _cubit.paymentModeChanged(v!),
      ),
      if (modeUsesBank(state.paymentMode)) ...[
        const SizedBox(height: 14),
        BankAccountField(accounts: [for (final a in state.bankAccounts) (a.id, a.name)], value: state.bankAccountId, onChanged: _cubit.bankAccountChanged),
      ],
      const SizedBox(height: 14),
      TextFormField(
        controller: _description,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
      ),
    ]);
    final right = Column(children: [
      TextFormField(
        controller: _number,
        decoration: const InputDecoration(labelText: 'Receipt No'),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the receipt number' : null,
      ),
      const SizedBox(height: 14),
      DateField(label: 'Date', value: state.date, onChanged: _cubit.dateChanged),
      const SizedBox(height: 14),
      TextFormField(
        controller: _amount,
        autofocus: !_cubit.editing,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.right,
        decoration: InputDecoration(labelText: '${kind.amountLabel} *', prefixText: '₹ '),
        validator: (v) => (parseNum(v ?? '') ?? 0) <= 0 ? 'Enter an amount greater than 0' : null,
        onFieldSubmitted: (_) => _save(),
      ),
    ]);
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        narrow
            ? Column(children: [left, const SizedBox(height: 14), right])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: left),
                const SizedBox(width: 40),
                Expanded(flex: 2, child: right),
              ]),
        // The summary depends on the typed amount, which lives in a controller.
        if (state.links.isNotEmpty) ...[const SizedBox(height: 18), ListenableBuilder(listenable: _amount, builder: (_, _) => _links(state))],
        const SizedBox(height: 14),
        const AttachmentsField(label: 'Attach a file'),
      ]),
    );
  }

  /// The party's unpaid invoices, each with how much of this payment settles it.
  Widget _links(PaymentFormState state) {
    final kind = _cubit.kind;
    final amount = parseNum(_amount.text) ?? 0;
    final unlinked = amount - state.linkedTotal;
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(kind.type == 'in' ? 'Link to unpaid invoices' : 'Link to unpaid bills', style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        TextButton(onPressed: amount > 0 ? () => _cubit.autoLink(amount) : null, child: const Text('Auto link')),
        TextButton(onPressed: state.linkedTotal > 0 ? _cubit.clearLinks : null, child: const Text('Clear')),
      ]),
      Container(
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE3E8EF)), borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Container(
            color: pageBg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Row(children: [
              Expanded(flex: 3, child: Text('DATE', style: head)),
              Expanded(flex: 3, child: Text('NUMBER', style: head)),
              Expanded(flex: 3, child: Text('TOTAL', style: head, textAlign: TextAlign.right)),
              Expanded(flex: 3, child: Text('UNPAID', style: head, textAlign: TextAlign.right)),
              SizedBox(width: 12),
              SizedBox(width: 120, child: Text('THIS PAYMENT', style: head, textAlign: TextAlign.right)),
            ]),
          ),
          for (final l in state.links)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(children: [
                Expanded(flex: 3, child: Text(l.date.isEmpty ? '-' : displayDate(l.date))),
                Expanded(flex: 3, child: Text(l.number, overflow: TextOverflow.ellipsis)),
                Expanded(flex: 3, child: Text(money(l.total), textAlign: TextAlign.right)),
                Expanded(flex: 3, child: Text(money(l.due), textAlign: TextAlign.right, style: const TextStyle(color: payRed))),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    key: ValueKey('link-${l.invoiceId}-${state.linksRev}'),
                    initialValue: l.amount,
                    onChanged: (v) => _cubit.linkAmountChanged(l.invoiceId, v),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                  ),
                ),
              ]),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Linked ${money(state.linkedTotal)}${unlinked > 0 ? '  ·  ${money(unlinked)} stays as an advance / on account' : ''}',
          style: TextStyle(fontSize: 12, color: unlinked < 0 ? payRed : Colors.black54),
        ),
      ),
    ]);
  }
}
