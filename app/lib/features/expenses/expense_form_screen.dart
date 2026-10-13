import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/gst_states.dart';
import '../../core/status.dart';
import '../../data/models/cash_bank.dart';
import '../../data/models/expense.dart';
import '../../data/models/invoice.dart' show paymentModes;
import '../../data/models/item.dart' show gstRateOptions;
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../files/attachments.dart';
import '../payments/split_parts_editor.dart';
import 'bloc/expense_form_cubit.dart';
import 'expenses_screen.dart' show showExpenseCategoryDialog;

const _numeric = TextInputType.numberWithOptions(decimal: true);
const _addNew = '__new__';

/// Full-screen create/edit form for an expense.
class ExpenseFormScreen extends StatelessWidget {
  const ExpenseFormScreen({super.key, this.expenseId, this.categoryId});
  final String? expenseId;

  /// Category to preselect for a new expense.
  final String? categoryId;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (ctx) => ExpenseFormCubit(ctx.read(), ctx.read(), ctx.read(), expenseId: expenseId, categoryId: categoryId, firm: ctx.read())..load(),
      ),
      BlocProvider(
        create: (ctx) => AttachmentsCubit(ctx.read(), ownerType: 'expense', ownerId: expenseId)..load(),
      ),
    ],
    child: const _ExpenseFormView(),
  );
}

class _ExpenseFormView extends StatelessWidget {
  const _ExpenseFormView();

  void _close(BuildContext context) => context.canPop() ? context.pop() : context.go('/expenses');

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ExpenseFormCubit, ExpenseFormState>(
      listenWhen: (a, b) => a.submitStatus != b.submitStatus && (b.submitStatus == SubmitStatus.success || b.submitStatus == SubmitStatus.failure),
      listener: (context, s) async {
        if (s.submitStatus == SubmitStatus.failure) {
          showError(context, s.error!);
          return;
        }
        showSuccess(context, 'Expense saved');
        // Files added before the expense existed are attached to it now.
        await context.read<AttachmentsCubit>().commit(s.savedId!);
        if (context.mounted && s.result == ExpenseFormResult.saved) _close(context);
      },
      builder: (context, state) {
        final cubit = context.read<ExpenseFormCubit>();
        final busy = state.submitStatus == SubmitStatus.submitting;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            shape: const Border(bottom: BorderSide(color: Color(0xFFE3E8EF))),
            leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => _close(context)),
            titleSpacing: 0,
            title: const Text('Expense', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          body: switch (state.loadStatus) {
            LoadStatus.failure => ErrorRetry(error: state.error ?? 'Could not load', onRetry: cubit.load),
            LoadStatus.success => _Body(state: state),
            _ => const Center(child: CircularProgressIndicator()),
          },
          bottomNavigationBar: state.loadStatus != LoadStatus.success
              ? null
              : Material(
                  color: Colors.white,
                  elevation: 8,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!cubit.editing) ...[
                            OutlinedButton(onPressed: busy ? null : () => cubit.save(andNew: true), child: const Text('Save & New')),
                            const SizedBox(width: 12),
                          ],
                          FilledButton(
                            onPressed: busy ? null : () => cubit.save(andNew: false),
                            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                            child: busy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(cubit.editing ? 'Update' : 'Save'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});
  final ExpenseFormState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ExpenseFormCubit>();
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final category = DropdownButtonFormField<String?>(
      key: ValueKey('cat-${state.categoryId}-${state.categories.length}'),
      initialValue: state.categories.any((c) => c.id == state.categoryId) ? state.categoryId : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Expense Category *'),
      items: [
        for (final c in state.categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
        const DropdownMenuItem(
          value: _addNew,
          child: Text('+ Add new category', style: TextStyle(color: brandBlue)),
        ),
      ],
      onChanged: (v) async {
        if (v != _addNew) return cubit.categoryChanged(v);
        final created = await showExpenseCategoryDialog(context);
        cubit.categoryChanged(created?.id ?? state.categoryId);
      },
    );
    final details = Column(
      children: [
        TextFormField(
          initialValue: state.number,
          onChanged: cubit.numberChanged,
          decoration: const InputDecoration(labelText: 'Expense No'),
        ),
        const SizedBox(height: 12),
        DateField(label: 'Date', value: state.date, onChanged: cubit.dateChanged),
      ],
    );
    final payment = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            key: ValueKey('mode-${state.paymentMode}'),
            initialValue: state.paymentMode,
            decoration: const InputDecoration(labelText: 'Payment Type'),
            items: [for (final e in paymentModes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => cubit.paymentModeChanged(v!),
          ),
        ),
        if (modeUsesBank(state.paymentMode))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SizedBox(
              width: 300,
              child: BankAccountField(
                accounts: [for (final a in state.bankAccounts) (a.id, a.name)],
                value: state.bankAccountId,
                onChanged: cubit.bankAccountChanged,
              ),
            ),
          ),
        SplitPartsEditor(
          parts: state.extraParts,
          firstMode: state.paymentMode,
          bankAccounts: state.bankAccounts,
          symbol: '₹',
          onAdd: cubit.addPart,
          onRemove: cubit.removePart,
          onMode: cubit.partModeChanged,
          onBank: cubit.partBankAccountChanged,
          onAmount: cubit.partAmountChanged,
        ),
        if (state.gstEnabled) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('gstin-${state.formRev}'),
                    initialValue: state.supplierGstin,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: cubit.supplierGstinChanged,
                    decoration: const InputDecoration(labelText: 'Supplier GSTIN (optional)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('state-${state.supplierState}'),
                    initialValue: state.supplierState,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Supplier state', helperText: 'Another state = IGST'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Same as mine')),
                      for (final e in gstStates.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: cubit.supplierStateChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: TextFormField(
            initialValue: state.description,
            onChanged: cubit.descriptionChanged,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
          ),
        ),
        const SizedBox(height: 12),
        const AttachmentsField(label: 'Attach the bill'),
      ],
    );
    Widget figure(String label, num value) => Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 12),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(money(value)),
        ],
      ),
    );
    final totals = Column(
      children: [
        if (state.taxTotal > 0) ...[figure('Before Tax', state.taxableTotal), figure('GST', state.taxTotal)],
        Row(
          children: [
            Checkbox(value: state.roundOff, onChanged: (v) => cubit.roundOffToggled(v!)),
            const Expanded(child: Text('Round Off')),
            Text(state.roundOff ? numText(state.roundOffValue) : '-'),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            SizedBox(
              width: 170,
              child: InputDecorator(
                decoration: const InputDecoration(filled: true, fillColor: pageBg),
                child: Text(
                  money(state.total),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return ListView(
      // A new formRev (loaded / reset after Save & New) rebuilds every input with fresh values.
      key: ValueKey('form-${state.formRev}'),
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: SizedBox(width: 300, child: category),
                        ),
                      ),
                      const SizedBox(width: 48),
                      Expanded(flex: 2, child: details),
                    ],
                  )
                : Column(children: [category, const SizedBox(height: 12), details]),
          ),
        ),
        const SizedBox(height: 12),
        _Lines(state: state, wide: wide),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: payment),
                      const SizedBox(width: 48),
                      Expanded(flex: 2, child: totals),
                    ],
                  )
                : Column(children: [totals, const SizedBox(height: 20), payment]),
          ),
        ),
      ],
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.state, required this.wide});
  final ExpenseFormState state;
  final bool wide;

  static const _cell = InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12));

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ExpenseFormCubit>();
    const head = TextStyle(fontWeight: FontWeight.w600, fontSize: 12);

    Widget row(int index, ExpenseLineDraft l) {
      final uid = l.uid;
      // Saved expense items are suggested while typing; any other text is fine too.
      final name = Autocomplete<ExpenseItemDef>(
        key: ValueKey('$uid-name-${l.rev}'),
        initialValue: TextEditingValue(text: l.name),
        displayStringForOption: (d) => d.name,
        optionsBuilder: (v) {
          final term = v.text.trim().toLowerCase();
          return state.itemDefs.where((d) => term.isEmpty || d.name.toLowerCase().contains(term));
        },
        onSelected: (d) => cubit.itemDefSelected(uid, d),
        fieldViewBuilder: (context, controller, focusNode, _) => TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (v) => cubit.lineNameChanged(uid, v),
          decoration: _cell.copyWith(hintText: 'Item name', labelText: wide ? null : 'Item'),
        ),
        optionsViewBuilder: (context, onSelected, options) => AutocompleteOptions<ExpenseItemDef>(
          width: 380,
          options: options,
          onSelected: onSelected,
          title: (d) => d.name,
          subtitle: (d) => d.gstRate == null ? 'Expense item' : 'GST ${numText(d.gstRate)}%',
          trailing: (d) => Text(d.price == 0 ? '' : money(d.price)),
        ),
      );
      final taxField = DropdownButtonFormField<num?>(
        key: ValueKey('$uid-gst-${l.rev}-${l.gstRate}'),
        initialValue: gstRateOptions.contains(l.gstRate) ? l.gstRate : null,
        isExpanded: true,
        decoration: _cell.copyWith(labelText: wide ? null : 'GST %'),
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
      Widget number(String key, String value, ValueChanged<String> onChanged, String label) => TextFormField(
        key: ValueKey('$uid-$key'),
        initialValue: value,
        onChanged: onChanged,
        keyboardType: _numeric,
        textAlign: TextAlign.right,
        decoration: _cell.copyWith(labelText: wide ? null : label),
      );
      final qtyField = number('qty-${l.rev}', l.qty, (v) => cubit.lineQtyChanged(uid, v), 'Qty');
      final price = number('price-${l.rev}', l.price, (v) => cubit.linePriceChanged(uid, v), 'Price/Unit');
      final amount = Text(
        money(state.amountOf(l)),
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w600),
      );
      final delete = IconButton(tooltip: 'Remove row', icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => cubit.removeLine(uid));

      if (wide) {
        return Container(
          key: ValueKey('line-$uid'),
          color: index.isOdd ? const Color(0xFFFAFBFD) : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text('${index + 1}', style: const TextStyle(color: Colors.black54)),
              ),
              Expanded(
                flex: 8,
                child: Padding(padding: const EdgeInsets.only(right: 6), child: name),
              ),
              Expanded(
                flex: 2,
                child: Padding(padding: const EdgeInsets.only(right: 6), child: qtyField),
              ),
              Expanded(
                flex: 3,
                child: Padding(padding: const EdgeInsets.only(right: 6), child: price),
              ),
              if (state.gstEnabled)
                Expanded(
                  flex: 3,
                  child: Padding(padding: const EdgeInsets.only(right: 6), child: taxField),
                ),
              Expanded(flex: 3, child: amount),
              SizedBox(width: 44, child: delete),
            ],
          ),
        );
      }
      return Padding(
        key: ValueKey('line-$uid'),
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        child: Column(
          children: [
            Row(
              children: [
                Text('${index + 1}.', style: const TextStyle(color: Colors.black54)),
                const SizedBox(width: 8),
                Expanded(child: name),
                delete,
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(child: qtyField),
                  const SizedBox(width: 8),
                  Expanded(child: price),
                  if (state.gstEnabled) const SizedBox(width: 8),
                  if (state.gstEnabled) Expanded(child: taxField),
                  const SizedBox(width: 8),
                  Expanded(child: amount),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
          ],
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.gstEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  const Text('Prices are entered', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<bool>(
                      value: state.pricesIncludeTax,
                      isDense: true,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: brandBlue),
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
              color: pageBg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const SizedBox(width: 32, child: Text('#', style: head)),
                  const Expanded(flex: 8, child: Text('ITEM', style: head)),
                  const Expanded(flex: 2, child: Text('QTY', style: head)),
                  const Expanded(flex: 3, child: Text('PRICE/UNIT', style: head)),
                  if (state.gstEnabled) const Expanded(flex: 3, child: Text('GST %', style: head)),
                  const Expanded(
                    flex: 3,
                    child: Text('AMOUNT', style: head, textAlign: TextAlign.right),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
          for (var i = 0; i < state.lines.length; i++) row(i, state.lines[i]),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(12),
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
                      TextSpan(text: 'Qty ${qty(state.totalQty)}   '),
                      TextSpan(
                        text: money(state.subtotal),
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
