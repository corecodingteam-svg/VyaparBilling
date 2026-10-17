import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/gst_states.dart';
import '../../core/keyboard/keyboard.dart';
import '../../core/status.dart';
import '../../data/models/cash_bank.dart';
import '../../data/models/invoice.dart';
import '../../data/models/item.dart';
import '../../data/models/party.dart';
import '../../shared/format.dart';
import '../../shared/selection_cubit.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../files/attachments.dart';
import '../team/tracking_cubit.dart';
import '../parties/party_form_dialog.dart';
import 'bloc/invoice_form_cubit.dart';

const _numeric = TextInputType.numberWithOptions(decimal: true);

/// Full-screen create/edit form for a sale invoice (or purchase bill).
class InvoiceFormScreen extends StatelessWidget {
  const InvoiceFormScreen({super.key, required this.kind, this.invoiceId, this.fromDocumentId});
  final InvoiceKind kind;
  final String? invoiceId;
  final String? fromDocumentId;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (ctx) => InvoiceFormCubit(
          invoices: ctx.read(),
          parties: ctx.read(),
          items: ctx.read(),
          accounts: ctx.read(),
          firm: ctx.read(),
          accounting: ctx.read(),
          bus: ctx.read(),
          kind: kind,
          invoiceId: invoiceId,
          fromDocumentId: fromDocumentId,
        )..load(),
      ),
      BlocProvider(
        create: (ctx) => AttachmentsCubit(ctx.read(), ownerType: 'invoice', ownerId: invoiceId)..load(),
      ),
    ],
    child: const _InvoiceFormView(),
  );
}

class _InvoiceFormView extends StatelessWidget {
  const _InvoiceFormView();

  void _close(BuildContext context, InvoiceKind kind) => context.canPop() ? context.pop() : context.go(kind.basePath);

  /// Going over a customer's credit limit is allowed, but only knowingly.
  Future<void> _confirmCreditLimit(BuildContext context, InvoiceFormState s) async {
    final cubit = context.read<InvoiceFormCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: AppIconSize.xl),
        title: const Text('Credit limit exceeded'),
        content: Text('${s.creditLimitWarning ?? ''}\n\nSave this ${s.kind.singular.toLowerCase()} anyway?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save Anyway')),
        ],
      ),
    );
    if (ok == true) cubit.save(andNew: s.pendingAndNew, overLimitConfirmed: true);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InvoiceFormCubit, InvoiceFormState>(
      listenWhen: (a, b) =>
          a.creditPrompt != b.creditPrompt ||
          (a.submitStatus != b.submitStatus && (b.submitStatus == SubmitStatus.success || b.submitStatus == SubmitStatus.failure)),
      listener: (context, s) async {
        if (s.submitStatus == SubmitStatus.failure) {
          showError(context, s.error!);
          return;
        }
        if (s.submitStatus != SubmitStatus.success) {
          _confirmCreditLimit(context, s);
          return;
        }
        showSuccess(context, '${s.kind.singular} saved');
        // Files added before the document existed are attached to it now.
        await context.read<AttachmentsCubit>().commit(s.savedId!);
        if (context.mounted && s.kind.isSale && !context.read<InvoiceFormCubit>().editing) context.read<TrackingCubit>().recordSaved('sale', s.savedId!);
        if (!context.mounted || s.result != InvoiceFormResult.saved) return;
        if (s.settings.showInvoicePreview) {
          // Show the printable invoice, replacing the form so Back returns to the list.
          context.pushReplacement('${s.kind.basePath}/${s.savedId}/preview');
        } else {
          _close(context, s.kind);
        }
      },
      builder: (context, state) {
        final cubit = context.read<InvoiceFormCubit>();
        final kind = state.kind;
        final busy = state.submitStatus == SubmitStatus.submitting;
        // Tab goes through the form section by section, then the save buttons, then the top bar.
        return OrderedFocus(child: Scaffold(
          appBar: PreferredSize(preferredSize: const Size.fromHeight(kToolbarHeight), child: FocusSection(order: 7, child: AppBar(
            shape: const Border(bottom: BorderSide(color: AppColors.border)),
            leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => _close(context, kind)),
            titleSpacing: 0,
            title: Row(
              children: [
                Text(kind.singular, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: AppSpace.lg),
                if (kind.supportsCash && state.loadStatus == LoadStatus.success) ...[
                  Text(
                    'Credit',
                    style: TextStyle(fontSize: AppFont.bodyLarge, color: state.isCash ? AppColors.textMuted : AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                  Switch(value: state.isCash, onChanged: cubit.cashToggled),
                  Text(
                    'Cash',
                    style: TextStyle(fontSize: AppFont.bodyLarge, color: state.isCash ? AppColors.primary : AppColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ))),
          body: switch (state.loadStatus) {
            LoadStatus.failure => ErrorRetry(error: state.error ?? 'Could not load', onRetry: cubit.load),
            LoadStatus.success => FocusFirstField(child: _FormBody(state: state)),
            _ => const LoadingView(),
          },
          bottomNavigationBar: state.loadStatus != LoadStatus.success
              ? null
              : FocusSection(order: 6, child: Material(
                  color: AppColors.onPrimary,
                  elevation: 8,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!cubit.editing) ...[
                            OutlinedButton(onPressed: busy ? null : () => cubit.save(andNew: true), child: const Text('Save & New')),
                            const SizedBox(width: AppSpace.md),
                          ],
                          FilledButton(
                            onPressed: busy ? null : () => cubit.save(andNew: false),
                            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                            child: busy
                                ? const InlineSpinner()
                                : Text(cubit.editing ? 'Update' : 'Save'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
        ));
      },
    );
  }
}

class _FormBody extends StatelessWidget {
  const _FormBody({required this.state});
  final InvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    // Every section is built, not only those on screen, so Tab and Enter can reach the ones scrolled out of view.
    return SingleChildScrollView(
      // A new formRev (loaded / reset after Save & New) rebuilds every input with fresh values.
      key: ValueKey('form-${state.formRev}'),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: FocusSection(order: 1, child: FieldHighlight(field: 'party', issue: state.issue, child: _PartySection(state: state)))),
                      const SizedBox(width: AppSpace.huge),
                      Expanded(flex: 2, child: FocusSection(order: 2, child: FieldHighlight(field: 'number', issue: state.issue, child: _DetailsSection(state: state)))),
                    ],
                  )
                : Column(
                    children: [
                      FocusSection(order: 1, child: FieldHighlight(field: 'party', issue: state.issue, child: _PartySection(state: state))),
                      const SizedBox(height: AppSpace.lg),
                      FocusSection(order: 2, child: FieldHighlight(field: 'number', issue: state.issue, child: _DetailsSection(state: state))),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        FocusSection(order: 3, child: FieldHighlight(field: 'items', issue: state.issue, child: _LinesCard(state: state, wide: wide))),
        const SizedBox(height: AppSpace.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: FocusSection(order: 5, child: FieldHighlight(field: 'payments', also: const ['received', 'currency'], issue: state.issue, child: _PaymentSection(state: state)))),
                      const SizedBox(width: AppSpace.huge),
                      Expanded(flex: 2, child: FocusSection(order: 4, child: FieldHighlight(field: 'billDiscount', also: const ['charges', 'tax', 'loyalty'], issue: state.issue, child: _TotalsSection(state: state)))),
                    ],
                  )
                : Column(
                    children: [
                      FocusSection(order: 4, child: FieldHighlight(field: 'billDiscount', also: const ['charges', 'tax', 'loyalty'], issue: state.issue, child: _TotalsSection(state: state))),
                      const SizedBox(height: AppSpace.xl),
                      FocusSection(order: 5, child: FieldHighlight(field: 'payments', also: const ['received', 'currency'], issue: state.issue, child: _PaymentSection(state: state))),
                    ],
                  ),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- header

class _PartySection extends StatelessWidget {
  const _PartySection({required this.state});
  final InvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InvoiceFormCubit>();
    final party = state.party;
    final label = '${state.kind.partyLabel}${state.isCash ? ' (optional)' : ' *'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(
              width: AppSize.fieldLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Autocomplete<Party>(
                    key: ValueKey('party-${state.partyRev}'),
                    initialValue: TextEditingValue(text: state.partyName),
                    displayStringForOption: (p) => p.name,
                    optionsBuilder: (v) {
                      final term = v.text.trim().toLowerCase();
                      return state.parties.where((p) => term.isEmpty || p.name.toLowerCase().contains(term) || (p.phone ?? '').contains(term));
                    },
                    onSelected: cubit.partySelected,
                    fieldViewBuilder: (context, controller, focusNode, _) => TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: cubit.partyNameChanged,
                      decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.arrow_drop_down)),
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
                        'BAL: ${money(party.balance.abs())}${party.creditLimit == null ? '' : '   ·   Credit limit: ${money(party.creditLimit)}'}',
                        style: TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.w600, color: balanceColor(party.balance)),
                      ),
                    ),
                  if (state.creditLimitWarning != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xs, left: AppSpace.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: AppIconSize.xs, color: AppColors.danger),
                          const SizedBox(width: AppSpace.xs),
                          Expanded(
                            child: Text(state.creditLimitWarning!, style: AppText.error),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: AppSize.fieldSm,
              child: TextFormField(
                key: ValueKey('phone-${state.partyRev}'),
                initialValue: state.phone,
                onChanged: cubit.phoneChanged,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone No.'),
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                cubit.addPartyStarted();
                await showPartyForm(context);
                await cubit.addPartyFinished();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Party'),
            ),
          ],
        ),
        if (state.kind.showBillingAddress || state.showShipping) const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (state.kind.showBillingAddress)
              SizedBox(
                width: AppSize.fieldLg,
                child: TextFormField(
                  key: ValueKey('addr-${state.partyRev}'),
                  initialValue: state.billingAddress,
                  onChanged: cubit.billingAddressChanged,
                  minLines: 3,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Billing Address', alignLabelWithHint: true),
                ),
              ),
            if (state.showShipping)
              SizedBox(
                width: AppSize.fieldLg,
                child: TextFormField(
                  key: ValueKey('ship-${state.partyRev}'),
                  initialValue: state.shippingAddress,
                  onChanged: cubit.shippingAddressChanged,
                  minLines: 3,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Shipping Address',
                    hintText: 'Leave blank if same as billing',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.state});
  final InvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InvoiceFormCubit>();
    return Column(
      children: [
        TextFormField(
          initialValue: state.number,
          onChanged: cubit.numberChanged,
          decoration: InputDecoration(labelText: state.kind.numberLabel),
        ),
        const SizedBox(height: AppSpace.md),
        DateField(label: state.kind.dateLabel, value: state.date, onChanged: cubit.dateChanged),
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<String?>(
          key: ValueKey('sos-${state.stateOfSupply}'),
          initialValue: state.stateOfSupply,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'State of supply'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Select')),
            for (final e in gstStates.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: cubit.stateOfSupplyChanged,
        ),
        if (state.showGodown) ...[
          const SizedBox(height: AppSpace.md),
          DropdownButtonFormField<String?>(
            key: ValueKey('godown-${state.extras.godownId}-${state.godowns.length}'),
            initialValue: state.godowns.any((g) => g.id == state.extras.godownId) ? state.extras.godownId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Store'),
            items: [
              for (final g in state.godowns)
                DropdownMenuItem(
                  value: g.id,
                  child: Text(g.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: cubit.godownChanged,
          ),
        ],
        if (state.showDueDate && state.dueDate != null) ...[
          const SizedBox(height: AppSpace.md),
          DateField(label: 'Due Date', value: state.dueDate!, onChanged: cubit.dueDateChanged),
        ],
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
                  onChanged: cubit.currencyChanged,
                ),
              ),
              if (state.currencyCode != null) ...[
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('rate-${state.currencyCode}'),
                    initialValue: state.exchangeRate,
                    onChanged: cubit.exchangeRateChanged,
                    keyboardType: _numeric,
                    decoration: InputDecoration(labelText: '1 ${state.currencyCode} = ₹'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- lines

class _LinesCard extends StatelessWidget {
  const _LinesCard({required this.state, required this.wide});
  final InvoiceFormState state;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InvoiceFormCubit>();
    const head = TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.small);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.gstEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
              child: Row(
                children: [
                  const Text('Prices are entered', style: AppText.body),
                  const SizedBox(width: AppSpace.sm),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<bool>(
                      value: state.pricesIncludeTax,
                      isDense: true,
                      // Based on the theme's style so the app font is kept.
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: AppFont.body, fontWeight: FontWeight.w600, color: AppColors.primary),
                      items: const [
                        DropdownMenuItem(value: false, child: Text('Without Tax')),
                        DropdownMenuItem(value: true, child: Text('With Tax')),
                      ],
                      onChanged: (v) => cubit.pricesIncludeTaxChanged(v!),
                    ),
                  ),
                ],
              ),
            ),
          if (wide)
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
              child: Row(
                children: [
                  const SizedBox(width: AppSpace.xxxl, child: Text('#', style: head)),
                  const Expanded(flex: 6, child: Text('ITEM', style: head)),
                  const Expanded(flex: 2, child: Text('QTY', style: head)),
                  const Expanded(flex: 2, child: Text('UNIT', style: head)),
                  const Expanded(flex: 3, child: Text('PRICE/UNIT', style: head)),
                  if (state.showDiscounts) const Expanded(flex: 2, child: Text('DISC %', style: head)),
                  if (state.showDiscounts) const Expanded(flex: 3, child: Text('DISC AMOUNT', style: head)),
                  if (state.gstEnabled) const Expanded(flex: 3, child: Text('TAX %', style: head)),
                  if (state.gstEnabled)
                    const Expanded(
                      flex: 2,
                      child: Text('TAX', style: head, textAlign: TextAlign.right),
                    ),
                  const Expanded(
                    flex: 3,
                    child: Text('AMOUNT', style: head, textAlign: TextAlign.right),
                  ),
                  const SizedBox(width: AppSpace.huge),
                ],
              ),
            ),
          for (var i = 0; i < state.lines.length; i++)
            FieldHighlight(
              key: ValueKey('line-${state.lines[i].uid}'),
              field: 'row:${state.lines[i].uid}',
              issue: state.issue,
              child: _LineRow(index: i, line: state.lines[i], state: state, wide: wide),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: cubit.addLine, icon: const Icon(Icons.add), label: const Text('ADD ROW')),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'TOTAL   ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: 'Qty ${qty(state.totalQty)}   ${state.showDiscounts ? 'Discount ${state.fmt(state.totalDiscount)}   ' : ''}'),
                      TextSpan(
                        text: state.fmt(state.subtotal),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.index, required this.line, required this.state, required this.wide});
  final int index;
  final LineDraft line;
  final InvoiceFormState state;
  final bool wide;

  static const _cell = InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.md));

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InvoiceFormCubit>();
    final uid = line.uid;

    final item = Autocomplete<Item>(
      initialValue: TextEditingValue(text: line.name),
      displayStringForOption: (i) => i.name,
      optionsBuilder: (v) {
        final term = v.text.trim().toLowerCase();
        return state.items.where((i) => term.isEmpty || i.name.toLowerCase().contains(term) || (i.itemCode ?? '').toLowerCase().contains(term));
      },
      onSelected: (i) => cubit.itemSelected(uid, i),
      fieldViewBuilder: (context, controller, focusNode, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: (v) => cubit.lineNameChanged(uid, v),
        decoration: _cell.copyWith(hintText: 'Item name', labelText: wide ? null : 'Item'),
      ),
      optionsViewBuilder: (context, onSelected, options) => AutocompleteOptions<Item>(
        width: AppSize.dialogMd,
        options: options,
        onSelected: onSelected,
        title: (i) => i.name,
        subtitle: (i) =>
            !i.isProduct ? 'Service' : (state.settings.stockMaintenance ? 'Stock: ${qty(i.stockQty)} ${i.unit ?? ''}' : (i.unit ?? 'Product')),
        trailing: (i) => Text(money(state.kind.usesSalePrice ? i.salePrice : i.purchasePrice)),
      ),
    );

    Widget number(String keySuffix, String value, ValueChanged<String> onChanged, {String? label, String? prefix}) => TextFormField(
      key: ValueKey('$uid-$keySuffix'),
      initialValue: value,
      onChanged: onChanged,
      keyboardType: _numeric,
      textAlign: TextAlign.right,
      decoration: _cell.copyWith(labelText: wide ? null : label, prefixText: prefix),
    );

    final qtyField = number('qty-${line.rowRev}', line.qty, (v) => cubit.lineQtyChanged(uid, v), label: 'Qty');
    final priceField = number('price-${line.rowRev}-${line.priceRev}', line.price, (v) => cubit.linePriceChanged(uid, v), label: 'Price/Unit');
    final pctField = number('pct-${line.rowRev}-${line.pctRev}', line.discountPct, (v) => cubit.lineDiscountPctChanged(uid, v), label: 'Disc %');
    final discField = number(
      'disc-${line.rowRev}-${line.amountRev}',
      line.discountAmount,
      (v) => cubit.lineDiscountAmountChanged(uid, v),
      label: 'Disc Amount',
    );

    final unitNames = {for (final u in state.units) u.shortName, if (line.unit != null) line.unit!};
    final unitField = DropdownButtonFormField<String?>(
      key: ValueKey('$uid-unit-${line.rowRev}-${line.unit}'),
      initialValue: line.unit,
      isExpanded: true,
      decoration: _cell.copyWith(labelText: wide ? null : 'Unit'),
      items: [
        const DropdownMenuItem(value: null, child: Text('NONE')),
        for (final u in unitNames)
          DropdownMenuItem(
            value: u,
            child: Text(u, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => cubit.lineUnitChanged(uid, v),
    );

    final taxField = DropdownButtonFormField<num?>(
      key: ValueKey('$uid-gst-${line.rowRev}-${line.gstRate}'),
      initialValue: gstRateOptions.contains(line.gstRate) ? line.gstRate : null,
      isExpanded: true,
      decoration: _cell.copyWith(labelText: wide ? null : 'Tax %'),
      items: [
        const DropdownMenuItem(value: null, child: Text('NONE')),
        for (final r in gstRateOptions)
          DropdownMenuItem(
            value: r,
            child: Text('GST@${numText(r)}%', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => cubit.lineGstRateChanged(uid, v),
    );
    final taxAmount = Text(
      line.gstRate == null ? '-' : state.fmt(state.taxOf(line)),
      textAlign: TextAlign.right,
      style: const TextStyle(color: AppColors.textMuted, fontSize: AppFont.body),
    );
    final amount = Text(
      state.fmt(state.amountOf(line)),
      textAlign: TextAlign.right,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
    final delete = IconButton(tooltip: 'Remove row', icon: const Icon(Icons.delete_outline, size: AppIconSize.md), onPressed: () => cubit.removeLine(uid));

    final extras = _LineExtras(line: line, state: state);
    if (wide) {
      Widget pad(Widget w) => Padding(padding: const EdgeInsets.only(right: AppSpace.sm), child: w);
      final row = Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text('${index + 1}', style: const TextStyle(color: AppColors.textMuted)),
            ),
            Expanded(flex: 6, child: pad(item)),
            Expanded(flex: 2, child: pad(qtyField)),
            Expanded(flex: 2, child: pad(unitField)),
            Expanded(flex: 3, child: pad(priceField)),
            if (state.showDiscounts) Expanded(flex: 2, child: pad(pctField)),
            if (state.showDiscounts) Expanded(flex: 3, child: pad(discField)),
            if (state.gstEnabled) Expanded(flex: 3, child: pad(taxField)),
            if (state.gstEnabled) Expanded(flex: 2, child: taxAmount),
            Expanded(flex: 3, child: amount),
            SizedBox(width: AppSpace.huge, child: delete),
          ],
        ),
      );
      return Container(
        color: index.isOdd ? AppColors.surfaceMuted : null,
        child: Column(
          children: [
            row,
            if (state.showLineExtras) Padding(padding: const EdgeInsets.fromLTRB(AppSpace.huge, 0, AppSpace.md, AppSpace.sm), child: extras),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.xs, AppSpace.xs),
      child: Column(
        children: [
          Row(
            children: [
              Text('${index + 1}.', style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: item),
              delete,
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: qtyField),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: unitField),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(child: priceField),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    if (state.showDiscounts) Expanded(child: pctField),
                    if (state.showDiscounts) const SizedBox(width: AppSpace.sm),
                    if (state.showDiscounts) Expanded(child: discField),
                    if (state.gstEnabled && state.showDiscounts) const SizedBox(width: AppSpace.sm),
                    if (state.gstEnabled) Expanded(child: taxField),
                  ],
                ),
                if (state.showLineExtras) ...[const SizedBox(height: AppSpace.md), extras],
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: state.gstEnabled
                          ? Text('Tax ${line.gstRate == null ? '-' : state.fmt(state.taxOf(line))}', style: const TextStyle(color: AppColors.textMuted))
                          : const SizedBox.shrink(),
                    ),
                    amount,
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          const Divider(),
        ],
      ),
    );
  }
}

/// Batch, expiry, MRP, serial numbers and cess of one line — only what is switched on in settings.
class _LineExtras extends StatelessWidget {
  const _LineExtras({required this.line, required this.state});
  final LineDraft line;
  final InvoiceFormState state;

  static const _cell = InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.md));

  Future<void> _pickBatch(BuildContext context) async {
    final cubit = context.read<InvoiceFormCubit>();
    final batches = await cubit.batchesOf(line.itemId!);
    if (!context.mounted) return;
    final picked = await showDialog<ItemBatch>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose a batch'),
        children: [
          if (batches.isEmpty) const Padding(padding: EdgeInsets.all(AppSpace.xl), child: Text('No batch of this item has stock.')),
          for (final b in batches)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, b),
              child: ListTile(
                dense: true,
                title: Text('Batch ${b.batchNo}'),
                subtitle: Text(
                  [if (b.expiryDate != null) 'Expires ${displayDate(b.expiryDate)}', if (b.mrp != null) 'MRP ${money(b.mrp)}'].join(' · '),
                ),
                trailing: Text(qty(b.quantity), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
    if (picked != null) cubit.lineBatchPicked(line.uid, picked);
  }

  Future<void> _pickSerials(BuildContext context) async {
    final cubit = context.read<InvoiceFormCubit>();
    final serials = await cubit.serialsOf(line.itemId!);
    if (!context.mounted) return;
    final chosen = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => BlocProvider(
        create: (_) => SelectionCubit<String>(line.serials.toSet()),
        child: BlocBuilder<SelectionCubit<String>, Set<String>>(
          builder: (ctx, picked) => AlertDialog(
            title: Text('Serial numbers in stock (${picked.length} chosen)'),
            content: SizedBox(
              width: AppSize.dialogSm,
              height: 360,
              child: serials.isEmpty
                  ? const Center(child: Text('No serial numbers of this item are in stock.'))
                  : ListView(
                      children: [
                        for (final sn in serials)
                          CheckboxListTile(
                            dense: true,
                            title: Text(sn),
                            value: picked.contains(sn),
                            onChanged: (_) => ctx.read<SelectionCubit<String>>().toggle(sn),
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, picked), child: const Text('Use These')),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    cubit.lineSerialsPicked(line.uid, [
      for (final sn in serials)
        if (chosen.contains(sn)) sn,
    ]);
  }

  Future<void> _pickExpiry(BuildContext context) async {
    final cubit = context.read<InvoiceFormCubit>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: line.expiryDate == null ? now : DateTime.parse(line.expiryDate!),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) cubit.lineExpiryChanged(line.uid, isoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InvoiceFormCubit>();
    final uid = line.uid;
    // On the sale side a batch or serial number is chosen from what is in stock; on the buying side it is typed.
    final fromStock = state.kind.type == 'sale' || state.kind.type == 'debit_note';
    final canPick = line.itemId != null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (state.showBatch) ...[
          SizedBox(
            width: AppSize.fieldSm,
            child: TextFormField(
              key: ValueKey('$uid-batch-${line.rowRev}'),
              initialValue: line.batchNo,
              onChanged: (v) => cubit.lineBatchChanged(uid, v),
              decoration: _cell.copyWith(
                labelText: 'Batch No.',
                suffixIcon: fromStock && canPick
                    ? IconButton(tooltip: 'Pick from stock', icon: const Icon(Icons.list_alt, size: AppIconSize.sm), onPressed: () => _pickBatch(context))
                    : null,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _pickExpiry(context),
            icon: const Icon(Icons.event_outlined, size: AppIconSize.xs),
            label: Text(line.expiryDate == null ? 'Expiry' : 'Expiry ${displayDate(line.expiryDate)}'),
          ),
        ],
        if (state.showMrp)
          SizedBox(
            width: AppSize.fieldXs,
            child: TextFormField(
              key: ValueKey('$uid-mrp-${line.rowRev}'),
              initialValue: line.mrp,
              onChanged: (v) => cubit.lineMrpChanged(uid, v),
              keyboardType: _numeric,
              textAlign: TextAlign.right,
              decoration: _cell.copyWith(labelText: 'MRP', prefixText: '₹ '),
            ),
          ),
        if (state.showCess)
          SizedBox(
            width: AppSize.fieldXs,
            child: TextFormField(
              key: ValueKey('$uid-cess-${line.rowRev}'),
              initialValue: numText(line.cessRate),
              onChanged: (v) => cubit.lineCessRateChanged(uid, v),
              keyboardType: _numeric,
              textAlign: TextAlign.right,
              decoration: _cell.copyWith(labelText: 'Cess %'),
            ),
          ),
        if (state.showSerial)
          SizedBox(
            width: AppSize.dialogSm,
            child: TextFormField(
              key: ValueKey('$uid-serial-${line.rowRev}'),
              initialValue: line.serialNos,
              onChanged: (v) => cubit.lineSerialsChanged(uid, v),
              decoration: _cell.copyWith(
                labelText: 'Serial no. / IMEI',
                hintText: 'one per unit, comma-separated',
                suffixIcon: fromStock && canPick
                    ? IconButton(tooltip: 'Pick from stock', icon: const Icon(Icons.list_alt, size: AppIconSize.sm), onPressed: () => _pickSerials(context))
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- footer

class _PaymentSection extends StatelessWidget {
  const _PaymentSection({required this.state});
  final InvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InvoiceFormCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.kind.hasPayment)
          SizedBox(
            width: AppSize.fieldMd,
            child: DropdownButtonFormField<String>(
              key: ValueKey('mode-${state.paymentMode}'),
              initialValue: state.paymentMode,
              decoration: const InputDecoration(labelText: 'Payment Type'),
              items: [for (final e in paymentModes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => cubit.paymentModeChanged(v!),
            ),
          ),
        if (state.kind.hasPayment && modeUsesBank(state.paymentMode))
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.md),
            child: SizedBox(
              width: AppSize.fieldLg,
              child: BankAccountField(
                accounts: [for (final a in state.bankAccounts) (a.id, a.name)],
                value: state.bankAccountId,
                onChanged: cubit.bankAccountChanged,
              ),
            ),
          ),
        if (state.kind.hasPayment)
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
                      onChanged: (v) => cubit.partModeChanged(p.uid, v!),
                    ),
                  ),
                  if (modeUsesBank(p.mode))
                    SizedBox(
                      width: AppSize.fieldSm,
                      child: BankAccountField(
                        accounts: [for (final a in state.bankAccounts) (a.id, a.name)],
                        value: p.bankAccountId,
                        onChanged: (v) => cubit.partBankAccountChanged(p.uid, v),
                      ),
                    ),
                  SizedBox(
                    width: AppSize.fieldXs,
                    child: TextFormField(
                      initialValue: p.amount,
                      onChanged: (v) => cubit.partAmountChanged(p.uid, v),
                      keyboardType: _numeric,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(labelText: 'Amount', prefixText: '${state.currencySymbol} '),
                    ),
                  ),
                  IconButton(tooltip: 'Remove this payment', icon: const Icon(Icons.close, size: AppIconSize.md), onPressed: () => cubit.removePart(p.uid)),
                ],
              ),
            ),
        if (state.kind.hasPayment && state.extraParts.length < paymentModes.length - 1)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: TextButton.icon(
              onPressed: cubit.addPart,
              icon: const Icon(Icons.add, size: AppIconSize.sm),
              label: Text(state.extraParts.isEmpty ? 'Add another payment type (split payment)' : 'Add another payment type'),
            ),
          ),
        if (state.kind.hasPayment) const SizedBox(height: AppSpace.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSize.dialogMd),
          child: TextFormField(
            initialValue: state.description,
            onChanged: cubit.descriptionChanged,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        const AttachmentsField(label: 'Attach a file'),
      ],
    );
  }
}

class _TotalsSection extends StatelessWidget {
  const _TotalsSection({required this.state});
  final InvoiceFormState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InvoiceFormCubit>();
    final paidLabel = state.kind.paidLabel;
    // In cash mode or "received in full" the amount is fixed: the total, less any other payment parts.
    final locked = state.isCash || state.receivedInFull;
    final split = state.extraParts.isNotEmpty;

    Widget row(Widget label, Widget value) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Row(
        children: [
          Expanded(child: label),
          SizedBox(width: AppSize.fieldSm, child: value),
        ],
      ),
    );

    Widget figure(String label, num value) =>
        row(Padding(padding: const EdgeInsets.only(left: AppSpace.md), child: Text(label)), Text(state.fmt(value), textAlign: TextAlign.right));

    return Column(
      children: [
        if (state.taxTotal > 0) ...[figure('Taxable Amount', state.taxableTotal), figure('Tax (GST)', state.taxTotal)],
        if (state.settings.billDiscountEnabled && state.kind.hasPayment || (state.settings.billDiscountEnabled && state.kind.isQuote))
          row(
            const Padding(padding: EdgeInsets.only(left: AppSpace.md), child: Text('Bill Discount')),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('bd-${state.extras.rev}'),
                    initialValue: state.extras.billDiscount,
                    onChanged: cubit.billDiscountChanged,
                    keyboardType: _numeric,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<bool>(
                    value: state.extras.billDiscountIsPct,
                    items: [
                      const DropdownMenuItem(value: true, child: Text(' %')),
                      DropdownMenuItem(value: false, child: Text(' ${state.currencySymbol}')),
                    ],
                    onChanged: (v) => cubit.billDiscountModeChanged(v!),
                  ),
                ),
              ],
            ),
          ),
        if (state.doc.discountAmount > 0) figure('Discount allowed', state.doc.discountAmount),
        if (state.settings.additionalChargesEnabled) ...[
          for (final c in state.extras.charges)
            Padding(
              key: ValueKey('charge-${c.uid}'),
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: c.name,
                      onChanged: (v) => cubit.chargeNameChanged(c.uid, v),
                      decoration: const InputDecoration(isDense: true, hintText: 'Charge name'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  SizedBox(
                    width: AppSize.fieldXs,
                    child: TextFormField(
                      initialValue: c.amount,
                      onChanged: (v) => cubit.chargeAmountChanged(c.uid, v),
                      keyboardType: _numeric,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ),
                  IconButton(tooltip: 'Remove charge', icon: const Icon(Icons.close, size: AppIconSize.sm), onPressed: () => cubit.removeCharge(c.uid)),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: cubit.addCharge, icon: const Icon(Icons.add, size: AppIconSize.sm), label: const Text('Add charge')),
          ),
        ],
        if (state.showTcs)
          row(
            const Padding(padding: EdgeInsets.only(left: AppSpace.md), child: Text('TCS %')),
            TextFormField(
              key: ValueKey('tcs-${state.extras.rev}'),
              initialValue: state.extras.tcsRate,
              onChanged: cubit.tcsRateChanged,
              keyboardType: _numeric,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(isDense: true),
            ),
          ),
        if (state.doc.tcs > 0) figure('TCS', state.doc.tcs),
        row(
          Row(
            children: [
              Checkbox(value: state.roundOff, onChanged: (v) => cubit.roundOffToggled(v!)),
              const Text('Round Off'),
            ],
          ),
          Text(state.roundOff ? numText(state.roundOffValue) : '-', textAlign: TextAlign.right),
        ),
        row(
          const Padding(
            padding: EdgeInsets.only(left: AppSpace.md),
            child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppFont.subtitle)),
          ),
          InputDecorator(
            decoration: const InputDecoration(filled: true, fillColor: AppColors.background),
            child: Text(
              state.fmt(state.total),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (state.showTds)
          row(
            const Padding(padding: EdgeInsets.only(left: AppSpace.md), child: Text('TDS %')),
            TextFormField(
              key: ValueKey('tds-${state.extras.rev}'),
              initialValue: state.extras.tdsRate,
              onChanged: cubit.tdsRateChanged,
              keyboardType: _numeric,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(isDense: true),
            ),
          ),
        if (state.doc.tds > 0 && state.kind.hasPayment) figure('TDS held back by payer', state.doc.tds),
        if (state.showLoyalty) ...[
          row(
            Padding(padding: const EdgeInsets.only(left: AppSpace.md), child: Text('Redeem points (${state.loyaltyAvailable} available)')),
            TextFormField(
              key: ValueKey('lp-${state.extras.rev}'),
              initialValue: state.extras.loyaltyRedeem,
              onChanged: cubit.loyaltyRedeemChanged,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(isDense: true),
            ),
          ),
          if (state.loyaltyAmount > 0) figure('Points value', state.loyaltyAmount),
          if (state.loyaltyEarned > 0)
            Padding(
              padding: const EdgeInsets.only(left: AppSpace.md, bottom: AppSpace.md),
              child: Text('This bill earns ${state.loyaltyEarned} points', style: AppText.helper),
            ),
        ],
        if (state.baseTotal != null)
          row(
            const Padding(padding: EdgeInsets.only(left: AppSpace.md), child: Text('Booked in ₹')),
            Text(money(state.baseTotal), textAlign: TextAlign.right),
          ),
        if (state.kind.hasPayment)
          row(
            Row(
              children: [
                Checkbox(value: locked, onChanged: state.isCash ? null : (v) => cubit.receivedInFullToggled(v!)),
                Flexible(
                  child: Text(
                    split ? '$paidLabel (${paymentModes[state.paymentMode]})' : paidLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            locked
                ? InputDecorator(
                    decoration: const InputDecoration(filled: true, fillColor: AppColors.background),
                    child: Text(state.fmt(state.firstPartValue), textAlign: TextAlign.right),
                  )
                : TextFormField(
                    initialValue: state.received,
                    onChanged: cubit.receivedChanged,
                    keyboardType: _numeric,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(prefixText: '${state.currencySymbol} '),
                  ),
          ),
        if (state.kind.hasPayment && split) figure('Total $paidLabel', state.receivedValue),
        if (state.kind.hasPayment && state.linkedAmount > 0) figure('Linked payments', state.linkedAmount),
        if (state.kind.hasPayment)
          row(
            const Padding(
              padding: EdgeInsets.only(left: AppSpace.md),
              child: Text('Balance', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(
              state.fmt(state.balance),
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, color: state.balance > 0 ? AppColors.moneyOut : AppColors.moneyIn),
            ),
          ),
      ],
    );
  }
}
