import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/change_bus.dart';
import '../../core/list_cubit.dart';
import '../../data/models/item.dart';
import '../../data/repositories/items_repository.dart';
import '../../shared/format.dart';
import '../../shared/page.dart';
import '../../shared/submit_dialog.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';

Future<void> _showGodownDialog(BuildContext context, {Godown? godown}) {
  final repo = context.read<ItemsRepository>();
  final name = TextEditingController(text: godown?.name);
  final address = TextEditingController(text: godown?.address);
  return showSubmitDialog<List<Godown>>(
    context,
    title: godown == null ? 'Add Godown' : 'Edit Godown',
    action: () => repo.saveGodown(godown?.id, name: name.text.trim(), address: address.text.trim()),
    fields: (submit) => [
      TextFormField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Godown Name *', hintText: 'e.g. Warehouse, Shop Floor'),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: address,
        decoration: const InputDecoration(labelText: 'Address'),
        onFieldSubmitted: (_) => submit(),
      ),
    ],
  );
}

/// What one store holds.
Future<void> _showStoreStock(BuildContext context, Godown g) async {
  final repo = context.read<ItemsRepository>();
  List<GodownStock> stock;
  try {
    stock = await repo.godownStock(g.id);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(g.name),
      content: SizedBox(
        width: 420,
        height: 380,
        child: stock.isEmpty
            ? const Center(child: Text('Nothing in stock here.'))
            : ListView(
                children: [
                  for (final s in stock)
                    ListTile(
                      dense: true,
                      title: Text(s.name),
                      subtitle: Text(money(s.value)),
                      trailing: Text('${qty(s.quantity)} ${s.unit ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ),
  );
}

/// Moves stock from one store to another (null = main store).
Future<void> showTransferDialog(BuildContext context, List<Godown> godowns) async {
  final repo = context.read<ItemsRepository>();
  List<Item> items;
  try {
    items = await repo.list('product');
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  if (!context.mounted) return;
  final quantity = TextEditingController();
  final batch = TextEditingController();
  // The dropdowns' own FormField state holds the choices; these just carry them to the action.
  String? itemId;
  String? from;
  String? to = godowns.length > 1 ? godowns[1].id : null;
  var date = isoDate(DateTime.now());
  await showSubmitDialog<void>(
    context,
    title: 'Transfer Stock',
    action: () => repo.transferStock({
      'itemId': itemId,
      'fromGodownId': from,
      'toGodownId': to,
      'quantity': parseNum(quantity.text),
      'date': date,
      if (batch.text.trim().isNotEmpty) 'batchNo': batch.text.trim(),
    }),
    fields: (submit) => [
      DropdownButtonFormField<String?>(
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Item *'),
        items: [
          for (final i in items)
            DropdownMenuItem(
              value: i.id,
              child: Text(i.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => itemId = v,
        validator: (v) => v == null ? 'Select an item' : null,
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String?>(
        initialValue: from,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'From'),
        items: [for (final g in godowns) DropdownMenuItem(value: g.id, child: Text(g.name))],
        onChanged: (v) => from = v,
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String?>(
        initialValue: to,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'To'),
        items: [for (final g in godowns) DropdownMenuItem(value: g.id, child: Text(g.name))],
        onChanged: (v) => to = v,
        validator: (v) => v == from ? 'Choose two different stores' : null,
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantity *'),
              validator: (v) => (parseNum(v ?? '') ?? 0) <= 0 ? 'Enter a quantity' : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: batch,
              decoration: const InputDecoration(labelText: 'Batch (optional)'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      DateField(label: 'Date', value: date, onChanged: (v) => date = v),
    ],
  );
}

/// The main store and every godown, with what each holds; transfer stock between them.
class GodownsScreen extends StatelessWidget {
  const GodownsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => ListCubit<Godown>(ctx.read<ItemsRepository>().godowns, bus: ctx.read<ChangeBus>(), topics: const {DataTopic.items})..load(),
    child: ListCubitView<Godown>(
      builder: (context, state) {
        final cubit = context.read<ListCubit<Godown>>();
        final repo = context.read<ItemsRepository>();
        return TitledPage(
          title: 'Godowns',
          subtitle: 'Stores that hold your stock. Pick the store on a sale or purchase; stock without one is in the main store.',
          actions: [
            OutlinedButton.icon(
              onPressed: state.items.length < 2 ? null : () => showTransferDialog(context, state.items),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Transfer Stock'),
            ),
            FilledButton.icon(onPressed: () => _showGodownDialog(context), icon: const Icon(Icons.add), label: const Text('Add Godown')),
          ],
          children: [
            RowsCard(
              empty: const EmptyState(icon: Icons.warehouse_outlined, title: 'No godowns'),
              rows: [
                for (final g in state.items)
                  ListTile(
                    onTap: () => _showStoreStock(context, g),
                    leading: CircleAvatar(
                      backgroundColor: brandBlue.withValues(alpha: 0.1),
                      child: Icon(g.isMain ? Icons.storefront_outlined : Icons.warehouse_outlined, color: brandBlue, size: 20),
                    ),
                    title: Text(g.name),
                    subtitle: Text(
                      '${g.itemCount} ${g.itemCount == 1 ? 'item' : 'items'} · ${money(g.stockValue)}${(g.address ?? '').isEmpty ? '' : ' · ${g.address}'}',
                    ),
                    trailing: g.isMain
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _showGodownDialog(context, godown: g),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () async {
                                  if (await confirmDelete(context, title: 'Delete godown', message: 'Delete "${g.name}"? It must be empty.')) {
                                    cubit.run(() => repo.deleteGodown(g.id!));
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
