import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/status.dart';
import '../../data/models/item.dart';
import '../../data/repositories/items_repository.dart';
import '../../shared/format.dart';
import '../../shared/submit_dialog.dart';
import '../../shared/widgets.dart';
import 'bloc/adjust_stock_cubit.dart';

// The small dialogs below don't dispose their controllers: the dialog's exit animation can still
// reference them after the future completes, and an unlistened controller is simply garbage-collected.

/// Add (or rename, when [category] is given) a category.
Future<Category?> showCategoryDialog(BuildContext context, {Category? category}) {
  final repo = context.read<ItemsRepository>();
  final name = TextEditingController(text: category?.name);
  return showSubmitDialog<Category>(
    context,
    title: category == null ? 'Add Category' : 'Edit Category',
    action: () => repo.saveCategory(category?.id, name.text.trim()),
    fields: (submit) => [
      TextFormField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Category Name'),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
        onFieldSubmitted: (_) => submit(),
      ),
    ],
  );
}

Future<Unit?> showUnitDialog(BuildContext context) {
  final repo = context.read<ItemsRepository>();
  final name = TextEditingController();
  final short = TextEditingController();
  return showSubmitDialog<Unit>(
    context,
    title: 'Add Unit',
    action: () => repo.createUnit(name.text.trim(), short.text.trim().toUpperCase()),
    fields: (submit) => [
      TextFormField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Unit Name', hintText: 'e.g. Kilograms'),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: short,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Short Name', hintText: 'e.g. KG'),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a short name' : null,
        onFieldSubmitted: (_) => submit(),
      ),
    ],
  );
}

Future<void> showAdjustStockDialog(BuildContext context, Item item) {
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) => AdjustStockCubit(context.read(), item.id),
      child: _AdjustStockDialog(item: item),
    ),
  );
}

class _AdjustStockDialog extends StatefulWidget {
  const _AdjustStockDialog({required this.item});
  final Item item;

  @override
  State<_AdjustStockDialog> createState() => _AdjustStockDialogState();
}

/// Stateful only to own the text controllers; all other state lives in [AdjustStockCubit].
class _AdjustStockDialogState extends State<_AdjustStockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qty = TextEditingController();
  late final _price = TextEditingController(text: numText(widget.item.purchasePrice));
  final _notes = TextEditingController();

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AdjustStockCubit>().submit(quantity: parseNum(_qty.text)!, pricePerUnit: parseNum(_price.text), notes: _notes.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.item.unit ?? '';
    final cubit = context.read<AdjustStockCubit>();
    return BlocConsumer<AdjustStockCubit, AdjustStockState>(
      listener: (context, s) {
        if (s.status == SubmitStatus.success) {
          showSuccess(context, 'Stock adjusted');
          Navigator.pop(context);
        }
        if (s.status == SubmitStatus.failure) showError(context, s.error!);
      },
      builder: (context, s) => AlertDialog(
        title: const Text('Stock Adjustment'),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${widget.item.name} · current stock ${qty(widget.item.stockQty)} $unit'),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'add', label: Text('Add Stock'), icon: Icon(Icons.add)),
                    ButtonSegment(value: 'reduce', label: Text('Reduce Stock'), icon: Icon(Icons.remove)),
                  ],
                  selected: {s.type},
                  onSelectionChanged: (v) => cubit.typeChanged(v.first),
                ),
                const SizedBox(height: 16),
                DateField(label: 'Adjustment Date', value: s.date, onChanged: cubit.dateChanged),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _qty,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Total Qty *', suffixText: unit),
                  validator: (v) => (parseNum(v ?? '') ?? 0) <= 0 ? 'Enter a quantity greater than 0' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'At Price', prefixText: '₹ ', suffixText: unit.isEmpty ? null : '/ $unit'),
                  validator: (v) => (v ?? '').trim().isNotEmpty && parseNum(v!) == null ? 'Enter a valid price' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Details')),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: s.status == SubmitStatus.submitting ? null : _submit, child: const Text('Save')),
        ],
      ),
    );
  }
}
