import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/status.dart';
import '../../data/models/item.dart';
import '../../data/repositories/items_repository.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../company/firm_cubit.dart';
import 'item_stock_breakdown.dart';
import 'bloc/catalog_cubit.dart';
import 'bloc/items_bloc.dart';
import 'catalog_dialogs.dart';
import 'item_form_dialog.dart';

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key, this.openId, this.openType});

  /// The item to show first, and whether it is a 'product' or a 'service'.
  final String? openId;
  final String? openType;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: openType == 'service' ? 1 : 0,
      child: Column(
        children: [
          const Material(
            color: Colors.white,
            child: TabBar(
              tabs: [
                Tab(text: 'PRODUCTS'),
                Tab(text: 'SERVICES'),
                Tab(text: 'CATEGORY'),
                Tab(text: 'UNITS'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                BlocProvider(
                  create: (ctx) => ItemsBloc(ctx.read(), ctx.read(), 'product', openId: openId)..add(const ItemsRequested()),
                  child: const _ItemsTab(type: 'product'),
                ),
                BlocProvider(
                  create: (ctx) => ItemsBloc(ctx.read(), ctx.read(), 'service', openId: openId)..add(const ItemsRequested()),
                  child: const _ItemsTab(type: 'service'),
                ),
                BlocProvider(create: (ctx) => ItemsBloc(ctx.read(), ctx.read(), 'all')..add(const ItemsRequested()), child: const _CategoryTab()),
                const _UnitsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- products / services

class _ItemsTab extends StatelessWidget {
  const _ItemsTab({required this.type});
  final String type;

  String get _noun => type == 'product' ? 'Item' : 'Service';

  void _open(BuildContext context, Item item) {
    final bloc = context.read<ItemsBloc>()..add(ItemSelected(item.id));
    if (isWide(context)) return;
    final catalog = context.read<CatalogCubit>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: bloc),
            BlocProvider.value(value: catalog),
          ],
          child: BlocBuilder<ItemsBloc, ItemsState>(
            builder: (ctx, s) {
              if (s.status == LoadStatus.success && !s.items.any((x) => x.id == item.id)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (ctx.mounted && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                });
              }
              return Scaffold(
                appBar: AppBar(title: Text(s.selected?.name ?? item.name)),
                body: const _ItemDetail(),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ItemsBloc, ItemsState>(
      builder: (context, state) {
        if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == LoadStatus.failure && state.items.isEmpty) {
          return ErrorRetry(error: state.error!, onRetry: () => context.read<ItemsBloc>().add(const ItemsRequested()));
        }
        if (state.items.isEmpty) {
          return EmptyState(
            icon: type == 'product' ? Icons.inventory_2_outlined : Icons.design_services_outlined,
            title: type == 'product' ? 'No products yet' : 'No services yet',
            message: type == 'product' ? 'Add the products you sell to track prices and stock.' : 'Add the services you offer to bill them quickly.',
            action: FilledButton.icon(
              onPressed: () => showItemForm(context, type: type),
              icon: const Icon(Icons.add),
              label: Text('Add Your First $_noun'),
            ),
          );
        }
        final wide = isWide(context);
        final list = _ItemList(
          state: state,
          highlight: wide,
          isProduct: type == 'product',
          onAdd: () => showItemForm(context, type: type),
          onTap: (i) => _open(context, i),
        );
        return Padding(
          padding: const EdgeInsets.all(12),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 320, child: list),
                    const SizedBox(width: 12),
                    const Expanded(child: _ItemDetail()),
                  ],
                )
              : list,
        );
      },
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({required this.state, required this.highlight, required this.isProduct, required this.onAdd, required this.onTap});

  final ItemsState state;
  final bool highlight;
  final bool isProduct;
  final VoidCallback onAdd;
  final ValueChanged<Item> onTap;

  @override
  Widget build(BuildContext context) {
    final trackStock = settingsOf(context, listen: true).stockMaintenance;
    final shown = state.visible;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => context.read<ItemsBloc>().add(ItemsSearchChanged(v)),
                    decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onAdd,
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          Container(
            color: pageBg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('ITEM', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ),
                Text(isProduct ? 'QUANTITY' : 'PRICE', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('No matching items'))
                : ListView.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) {
                      final item = shown[i];
                      return ListTile(
                        selected: highlight && item.id == state.selectedId,
                        selectedTileColor: brandBlue.withValues(alpha: 0.08),
                        title: Text(item.name, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // With stock maintenance off, products show their price like services do.
                            if (item.lowStock && trackStock)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.warning_amber, size: 18, color: Colors.orange),
                              ),
                            Text(
                              isProduct && trackStock ? qty(item.stockQty) : money(item.salePrice),
                              style: TextStyle(
                                color: trackStock && (item.stockQty < 0 || item.lowStock) ? payRed : receiveGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            _RowMenu(item: item),
                          ],
                        ),
                        onTap: () => onTap(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) async {
        if (v == 'edit') return showItemForm(context, item: item);
        final repo = context.read<ItemsRepository>();
        if (await confirmDelete(context, title: 'Delete item', message: 'Do you really want to delete "${item.name}"?')) {
          try {
            await repo.delete(item.id);
            if (context.mounted) showSuccess(context, 'Item deleted');
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
        }
      },
      itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('View/Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
    );
  }
}

class _ItemDetail extends StatelessWidget {
  const _ItemDetail();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ItemsBloc, ItemsState>(
      builder: (context, state) {
        final item = state.selected;
        if (item == null) return const SizedBox.shrink();
        String taxLabel(bool incl) => incl ? '(incl. tax)' : '(excl. tax)';
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Text(item.name.toUpperCase(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        IconButton(
                          tooltip: 'Edit item',
                          icon: const Icon(Icons.edit_outlined, color: brandBlue, size: 20),
                          onPressed: () => showItemForm(context, item: item),
                        ),
                        if (item.isProduct && settingsOf(context, listen: true).stockMaintenance)
                          FilledButton.icon(
                            onPressed: () => showAdjustStockDialog(context, item),
                            icon: const Icon(Icons.tune, size: 18),
                            label: const Text('ADJUST ITEM'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 40,
                      runSpacing: 12,
                      children: [
                        InfoField('Sale Price', '${money(item.salePrice)} ${taxLabel(item.salePriceIncludesTax)}', valueColor: receiveGreen),
                        InfoField(
                          'Purchase Price',
                          '${money(item.purchasePrice)} ${taxLabel(item.purchasePriceIncludesTax)}',
                          valueColor: receiveGreen,
                        ),
                        if (item.isProduct && settingsOf(context, listen: true).stockMaintenance) ...[
                          InfoField('Stock Quantity', '${qty(item.stockQty)} ${item.unit ?? ''}', valueColor: item.lowStock ? payRed : receiveGreen),
                          InfoField('Stock Value', money(item.stockValue), valueColor: receiveGreen),
                        ],
                        if (item.gstRate != null) InfoField('Tax Rate', 'GST@${numText(item.gstRate)}%'),
                        if (item.categoryName != null) InfoField('Category', item.categoryName!),
                        if (item.itemCode != null) InfoField('Item Code', item.itemCode!),
                        if (item.hsnCode != null) InfoField(item.isProduct ? 'HSN' : 'SAC', item.hsnCode!),
                        if (item.minStock != null) InfoField('Min Stock', qty(item.minStock)),
                        if (item.location != null) InfoField('Location', item.location!),
                        if (item.cessRate != null) InfoField('Cess', '${numText(item.cessRate)}%'),
                        if (item.mrp != null) InfoField('MRP', money(item.mrp)),
                      ],
                    ),
                    ItemStockBreakdown(item: item),
                  ],
                ),
              ),
            ),
            if (item.isProduct) ...[
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('TRANSACTIONS', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    switch (state.movementStatus) {
                      LoadStatus.initial || LoadStatus.loading => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      LoadStatus.failure => ErrorRetry(
                        error: state.error ?? 'Could not load stock history',
                        onRetry: () => context.read<ItemsBloc>().add(ItemSelected(item.id)),
                      ),
                      LoadStatus.success when state.movements.isEmpty => const SizedBox(
                        height: 220,
                        child: EmptyState(icon: Icons.swap_vert, title: 'No stock movements yet'),
                      ),
                      LoadStatus.success => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: const WidgetStatePropertyAll(pageBg),
                          columns: const [
                            DataColumn(label: Text('TYPE')),
                            DataColumn(label: Text('INVOICE')),
                            DataColumn(label: Text('NAME')),
                            DataColumn(label: Text('DATE')),
                            DataColumn(label: Text('QUANTITY'), numeric: true),
                            DataColumn(label: Text('PRICE/UNIT'), numeric: true),
                          ],
                          rows: [
                            for (final m in state.movements)
                              DataRow(
                                cells: [
                                  DataCell(Text(m.label)),
                                  DataCell(Text(m.reference ?? '')),
                                  DataCell(Text(m.details)),
                                  DataCell(Text(displayDate(m.date))),
                                  DataCell(Text(qty(m.quantity), style: TextStyle(color: m.quantity < 0 ? payRed : null))),
                                  DataCell(Text(m.pricePerUnit == null ? '-' : money(m.pricePerUnit))),
                                ],
                              ),
                          ],
                        ),
                      ),
                    },
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- categories

class _CategorySelection extends Cubit<String?> {
  _CategorySelection() : super(null);
  void select(String? id) => emit(id);
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab();

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => _CategorySelection(),
      child: Builder(
        builder: (context) {
          final catalog = context.watch<CatalogCubit>().state;
          final items = context.watch<ItemsBloc>().state.items;
          final cats = catalog.categories;
          final selectedId = context.watch<_CategorySelection>().state;
          final selected = cats.where((c) => c.id == selectedId).firstOrNull ?? cats.firstOrNull;

          Future<void> add() => showCategoryDialog(context);
          if (catalog.status == LoadStatus.initial) return const Center(child: CircularProgressIndicator());
          if (cats.isEmpty) {
            return EmptyState(
              icon: Icons.category_outlined,
              title: 'No categories yet',
              message: 'Group your items into categories to find them faster.',
              action: FilledButton.icon(onPressed: add, icon: const Icon(Icons.add), label: const Text('Add Category')),
            );
          }

          final list = Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(onPressed: add, icon: const Icon(Icons.add), label: const Text('Add Category')),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: cats.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) {
                      final c = cats[i];
                      return ListTile(
                        selected: c.id == selected?.id,
                        selectedTileColor: brandBlue.withValues(alpha: 0.08),
                        title: Text(c.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${c.itemCount}'),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 20),
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  showCategoryDialog(context, category: c);
                                  return;
                                }
                                final repo = context.read<ItemsRepository>();
                                if (await confirmDelete(
                                  context,
                                  title: 'Delete category',
                                  message: 'Delete "${c.name}"? Its items will become uncategorised.',
                                )) {
                                  try {
                                    await repo.deleteCategory(c.id);
                                  } catch (e) {
                                    if (context.mounted) showError(context, e);
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => context.read<_CategorySelection>().select(c.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          );

          final inCategory = items.where((i) => i.categoryId == selected?.id).toList();
          final detail = Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${selected?.name ?? ''} · ${inCategory.length} items',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: inCategory.isEmpty
                      ? const EmptyState(icon: Icons.inventory_2_outlined, title: 'No items in this category')
                      : ListView.separated(
                          itemCount: inCategory.length,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (_, i) {
                            final it = inCategory[i];
                            return ListTile(
                              title: Text(it.name),
                              subtitle: Text(it.isProduct ? 'Product' : 'Service'),
                              trailing: Text(it.isProduct ? '${qty(it.stockQty)} ${it.unit ?? ''}' : money(it.salePrice)),
                              onTap: () => showItemForm(context, item: it),
                            );
                          },
                        ),
                ),
              ],
            ),
          );

          return Padding(
            padding: const EdgeInsets.all(12),
            child: isWide(context)
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 320, child: list),
                      const SizedBox(width: 12),
                      Expanded(child: detail),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: list),
                      const SizedBox(height: 12),
                      Expanded(child: detail),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- units

class _UnitsTab extends StatelessWidget {
  const _UnitsTab();

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>().state;
    if (catalog.status == LoadStatus.initial) return const Center(child: CircularProgressIndicator());
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Units', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  FilledButton.icon(onPressed: () => showUnitDialog(context), icon: const Icon(Icons.add), label: const Text('Add Unit')),
                ],
              ),
            ),
            Container(
              color: pageBg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(
                children: [
                  Expanded(
                    child: Text('FULL NAME', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text('SHORT NAME', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: catalog.units.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, i) {
                  final u = catalog.units[i];
                  return ListTile(
                    title: Text(u.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 120, child: Text(u.shortName)),
                        IconButton(
                          tooltip: 'Delete unit',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            final repo = context.read<ItemsRepository>();
                            if (!await confirmDelete(context, title: 'Delete unit', message: 'Delete "${u.name}"?')) return;
                            try {
                              await repo.deleteUnit(u.id);
                            } catch (e) {
                              if (context.mounted) showError(context, e);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
