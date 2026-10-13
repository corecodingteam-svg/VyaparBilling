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
import '../team/tracking_cubit.dart';
import 'bloc/payment_form_cubit.dart';

/// Opens the add/edit payment dialog. Returns the saved payment, or null if cancelled.
Future<Payment?> showPaymentForm(BuildContext context, PaymentKind kind, {Payment? payment, String? partyId}) {
  return showDialog<Payment>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => PaymentFormCubit(
            context.read(),
            context.read(),
            context.read(),
            kind,
            payment: payment,
            partyId: partyId,
            invoices: context.read(),
            accounting: context.read(),
          )..load(),
        ),
        BlocProvider(
          create: (_) => AttachmentsCubit(context.read(), ownerType: 'payment', ownerId: payment?.id)..load(),
        ),
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
    if (!validateForm(context, _formKey, report: showError)) return;
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
          if (_cubit.kind.type == 'in' && !_cubit.editing && context.mounted) context.read<TrackingCubit>().recordSaved('payment', s.saved!.id);
          navigator.pop(s.saved);
        }
      },
      builder: (context, state) {
        final busy = state.submitStatus == SubmitStatus.submitting;
        return Column(
          mainAxisSize: narrow ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.md, AppSpace.sm, AppSpace.md),
              child: Row(
                children: [
                  Text(kind.title, style: AppText.title),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: switch (state.loadStatus) {
                LoadStatus.failure => SizedBox(
                  height: AppSize.stateHeight,
                  child: ErrorRetry(error: state.error ?? 'Could not load', onRetry: _cubit.load),
                ),
                LoadStatus.success => SingleChildScrollView(padding: const EdgeInsets.all(AppSpace.xl), child: _fields(state, narrow)),
                _ => const SizedBox(height: AppSize.stateHeight, child: LoadingView()),
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: busy || state.loadStatus != LoadStatus.success ? null : _save,
                    style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
                    child: busy
                        ? const InlineSpinner()
                        : Text(_cubit.editing ? 'Update' : 'Save'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (narrow) return Dialog.fullscreen(child: content);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: AppSize.dialogForm), child: content),
    );
  }

  Widget _fields(PaymentFormState state, bool narrow) {
    final kind = _cubit.kind;
    final party = state.party;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            validator: Validators.choose<String>('party'),
          ),
          optionsViewBuilder: (context, onSelected, options) => AutocompleteOptions<Party>(
            width: AppSize.fieldLg,
            options: options,
            onSelected: onSelected,
            title: (p) => p.name,
            trailing: (p) => Text(
              money(p.balance.abs()),
              style: TextStyle(color: balanceColor(p.balance), fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (party != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs, left: AppSpace.xs),
            child: Text(
              'BAL: ${money(party.balance.abs())}',
              style: TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.w600, color: balanceColor(party.balance)),
            ),
          ),
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<String>(
          key: ValueKey('mode-${state.paymentMode}'),
          initialValue: state.paymentMode,
          decoration: const InputDecoration(labelText: 'Payment Type'),
          items: [for (final e in paymentModes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => _cubit.paymentModeChanged(v!),
        ),
        if (modeUsesBank(state.paymentMode)) ...[
          const SizedBox(height: AppSpace.md),
          BankAccountField(
            accounts: [for (final a in state.bankAccounts) (a.id, a.name)],
            value: state.bankAccountId,
            onChanged: _cubit.bankAccountChanged,
          ),
        ],
        for (final p in state.extraParts)
          Padding(
            key: ValueKey('part-${p.uid}'),
            padding: const EdgeInsets.only(top: AppSpace.md),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: AppSize.fieldXs,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('part-mode-${p.uid}-${p.mode}'),
                    initialValue: p.mode,
                    decoration: const InputDecoration(labelText: 'Payment Type'),
                    items: [for (final e in paymentModes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => _cubit.partModeChanged(p.uid, v!),
                  ),
                ),
                if (modeUsesBank(p.mode))
                  SizedBox(
                    width: AppSize.fieldSm,
                    child: BankAccountField(
                      accounts: [for (final a in state.bankAccounts) (a.id, a.name)],
                      value: p.bankAccountId,
                      onChanged: (v) => _cubit.partBankAccountChanged(p.uid, v),
                    ),
                  ),
                SizedBox(
                  width: AppSize.fieldXs,
                  child: TextFormField(
                    initialValue: p.amount,
                    onChanged: (v) => _cubit.partAmountChanged(p.uid, v),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(labelText: 'Amount', prefixText: '${state.currencySymbol} '),
                  ),
                ),
                IconButton(tooltip: 'Remove', icon: const Icon(Icons.close, size: AppIconSize.sm), onPressed: () => _cubit.removePart(p.uid)),
              ],
            ),
          ),
        if (state.extraParts.length < paymentModes.length - 1)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _cubit.addPart,
              icon: const Icon(Icons.add, size: AppIconSize.sm),
              label: Text(state.extraParts.isEmpty ? 'Add another payment type (split)' : 'Add another payment type'),
            ),
          ),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          controller: _description,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
        ),
      ],
    );
    final right = Column(
      children: [
        TextFormField(
          controller: _number,
          decoration: const InputDecoration(labelText: 'Receipt No'),
          validator: Validators.required('Receipt number'),
        ),
        const SizedBox(height: AppSpace.md),
        DateField(label: 'Date', value: state.date, onChanged: _cubit.dateChanged),
        if (state.currencies.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('cur-${state.currencyCode}'),
                  initialValue: state.currency?.code,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('₹ INR')),
                    for (final c in state.currencies) DropdownMenuItem(value: c.code, child: Text('${c.symbol} ${c.code}')),
                  ],
                  onChanged: _cubit.currencyChanged,
                ),
              ),
              if (state.currencyCode != null) ...[
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('rate-${state.currencyCode}'),
                    initialValue: state.exchangeRate,
                    onChanged: _cubit.exchangeRateChanged,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: '1 ${state.currencyCode} = ₹'),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: AppSpace.md),
        TextFormField(
          controller: _amount,
          autofocus: !_cubit.editing,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          decoration: InputDecoration(labelText: '${kind.amountLabel} *', prefixText: '${state.currencySymbol} '),
          validator: Validators.number('Amount', required: true, positive: true),
          onFieldSubmitted: (_) => _save(),
        ),
      ],
    );
    return Form(autovalidateMode: AutovalidateMode.onUserInteraction, 
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          narrow
              ? Column(children: [left, const SizedBox(height: AppSpace.md), right])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: left),
                    const SizedBox(width: AppSpace.huge),
                    Expanded(flex: 2, child: right),
                  ],
                ),
          // The summary depends on the typed amount, which lives in a controller.
          if (state.links.isNotEmpty) ...[const SizedBox(height: AppSpace.lg), ListenableBuilder(listenable: _amount, builder: (_, _) => _links(state))],
          const SizedBox(height: AppSpace.md),
          const AttachmentsField(label: 'Attach a file'),
        ],
      ),
    );
  }

  /// The party's unpaid invoices, each with how much of this payment settles it.
  Widget _links(PaymentFormState state) {
    final kind = _cubit.kind;
    final amount = parseNum(_amount.text) ?? 0;
    final unlinked = amount - state.linkedTotal;
    const head = TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.w600, color: AppColors.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                kind.type == 'in' ? 'Link to unpaid invoices' : 'Link to unpaid bills',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(onPressed: amount > 0 ? () => _cubit.autoLink(amount) : null, child: const Text('Auto link')),
            TextButton(onPressed: state.linkedTotal > 0 ? _cubit.clearLinks : null, child: const Text('Clear')),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: AppRadius.mdAll,
          ),
          child: Column(
            children: [
              Container(
                color: AppColors.background,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                child: const Row(
                  children: [
                    Expanded(flex: 3, child: Text('DATE', style: head)),
                    Expanded(flex: 3, child: Text('NUMBER', style: head)),
                    Expanded(
                      flex: 3,
                      child: Text('TOTAL', style: head, textAlign: TextAlign.right),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text('UNPAID', style: head, textAlign: TextAlign.right),
                    ),
                    SizedBox(width: AppSpace.md),
                    SizedBox(
                      width: AppSize.fieldXs,
                      child: Text('THIS PAYMENT', style: head, textAlign: TextAlign.right),
                    ),
                  ],
                ),
              ),
              for (final l in state.links)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text(l.date.isEmpty ? '-' : displayDate(l.date))),
                      Expanded(flex: 3, child: Text(l.number, overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 3, child: Text(money(l.total), textAlign: TextAlign.right)),
                      Expanded(
                        flex: 3,
                        child: Text(
                          money(l.due),
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: AppColors.dangerText),
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      SizedBox(
                        width: AppSize.fieldXs,
                        child: TextFormField(
                          key: ValueKey('link-${l.invoiceId}-${state.linksRev}'),
                          initialValue: l.amount,
                          onChanged: (v) => _cubit.linkAmountChanged(l.invoiceId, v),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.md)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Text(
            'Linked ${money(state.linkedTotal)}${unlinked > 0 ? '  ·  ${money(unlinked)} stays as an advance / on account' : ''}',
            style: TextStyle(fontSize: AppFont.small, color: unlinked < 0 ? AppColors.dangerText : AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}
