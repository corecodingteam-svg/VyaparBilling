import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/change_bus.dart';
import '../../core/list_cubit.dart';
import '../../data/models/expense.dart';
import '../../data/models/item.dart' show gstRateOptions;
import '../../data/repositories/expenses_repository.dart';
import '../../shared/export.dart';
import '../../shared/format.dart';
import '../../shared/page.dart';
import '../../shared/submit_dialog.dart';
import '../../shared/widgets.dart';
import '../company/firm_cubit.dart';
import '../../shared/theme.dart';

/// Add or edit a reusable expense item.
Future<void> showExpenseItemDialog(BuildContext context, {ExpenseItemDef? item}) {
  final repo = context.read<ExpensesRepository>();
  final gstEnabled = settingsOf(context).gstEnabled;
  final name = TextEditingController(text: item?.name);
  final price = TextEditingController(text: item == null || item.price == 0 ? '' : numText(item.price));
  final hsn = TextEditingController(text: item?.hsnCode);
  // The dropdown's own FormField state holds the choice; this just carries it to the action.
  num? gstRate = item?.gstRate;
  return showSubmitDialog<List<ExpenseItemDef>>(
    context,
    title: item == null ? 'Add Expense Item' : 'Edit Expense Item',
    action: () =>
        repo.saveItemDef(item?.id, {'name': name.text.trim(), 'price': parseNum(price.text) ?? 0, 'hsnCode': hsn.text.trim(), 'gstRate': gstRate}),
    fields: (submit) => [
      TextFormField(
        controller: name,
        autofocus: item == null,
        decoration: const InputDecoration(labelText: 'Item Name *', hintText: 'e.g. Petrol, Tea, Courier'),
        validator: Validators.required('Name'),
      ),
      const SizedBox(height: AppSpace.md),
      TextFormField(
        controller: price,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Usual Price',
          prefixText: '₹ ',
          helperText: 'Filled in when you pick this item; can be changed each time',
        ),
        validator: Validators.number('Price', nonNegative: true),
        onFieldSubmitted: (_) => submit(),
      ),
      if (gstEnabled || item?.gstRate != null) ...[
        const SizedBox(height: AppSpace.md),
        TextFormField(
          controller: hsn,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'HSN / SAC'),
          validator: Validators.hsn(),
        ),
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<num?>(
          initialValue: gstRateOptions.contains(gstRate) ? gstRate : null,
          decoration: const InputDecoration(labelText: 'GST Rate'),
          items: [
            const DropdownMenuItem(value: null, child: Text('None')),
            for (final r in gstRateOptions) DropdownMenuItem(value: r, child: Text('GST@${numText(r)}%')),
          ],
          onChanged: (v) => gstRate = v,
        ),
      ],
    ],
  );
}

/// Reusable expense items with what has been spent on each.
class ExpenseItemsScreen extends StatelessWidget {
  const ExpenseItemsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) =>
        ListCubit<ExpenseItemDef>(ctx.read<ExpensesRepository>().itemDefs, bus: ctx.read<ChangeBus>(), topics: const {DataTopic.expenses})..load(),
    child: ListCubitView<ExpenseItemDef>(
      builder: (context, state) {
        final cubit = context.read<ListCubit<ExpenseItemDef>>();
        final repo = context.read<ExpensesRepository>();
        return TitledPage(
          title: 'Expense Items',
          subtitle: 'Things you spend on again and again. Pick them while entering an expense to fill in the price and GST.',
          actions: [ExportMenu(table: () => TableExport(title: 'Expense Items', headers: ['Item', 'Price', 'HSN/SAC', 'GST %', 'Spent so far'], rows: [for (final d in state.items) [d.name, d.price, d.hsnCode, d.gstRate, d.total]])),
            
            FilledButton.icon(onPressed: () => showExpenseItemDialog(context), icon: const Icon(Icons.add), label: const Text('Add Expense Item')),
          ],
          children: [
            RowsCard(
              texts: [for (final d in state.items) '${d.name} ${d.hsnCode ?? ''}'],
              sorts: {'Name': [for (final d in state.items) d.name], 'Price': [for (final d in state.items) d.price], 'Spent so far': [for (final d in state.items) d.total]},
              empty: const EmptyState(
                icon: Icons.local_gas_station_outlined,
                title: 'No expense items yet',
                message: 'Add the things you pay for regularly.',
              ),
              rows: [
                for (final d in state.items)
                  ListTile(
                    title: Text(d.name),
                    subtitle: Text(
                      [
                        if (d.price > 0) 'Usual price ${money(d.price)}',
                        if (d.gstRate != null) 'GST ${numText(d.gstRate)}%',
                        if ((d.hsnCode ?? '').isNotEmpty) 'HSN/SAC ${d.hsnCode}',
                      ].join(' · '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(money(d.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                            const Text('spent so far', style: AppText.caption),
                          ],
                        ),
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_outlined, size: AppIconSize.sm),
                          onPressed: () => showExpenseItemDialog(context, item: d),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline, size: AppIconSize.md),
                          onPressed: () async {
                            if (await confirmDelete(
                              context,
                              title: 'Delete expense item',
                              message: 'Delete "${d.name}"? Expenses already entered keep it.',
                            )) {
                              cubit.run(() => repo.deleteItemDef(d.id));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
