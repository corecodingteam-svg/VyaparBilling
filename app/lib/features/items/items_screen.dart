import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/keyboard/keyboard.dart';
import '../../core/status.dart';
import '../../data/models/item.dart';
import '../../data/repositories/items_repository.dart';
import '../../shared/data_table_view.dart';
import '../../shared/export.dart';
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
            color: AppColors.onPrimary,
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
          return const LoadingView();
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
        final selected = state.selected;
        void add() => showItemForm(context, type: type);
        void edit() => showItemForm(context, item: selected!);
        final adjust = selected != null && selected.isProduct && settingsOf(context).stockMaintenance;
        final keys = <AppCommand, VoidCallback?>{
          AppCommand.newRecord: add,
          AppCommand.addRow: add,
          AppCommand.refresh: () => context.read<ItemsBloc>().add(const ItemsRequested()),
          if (selected != null) ...{
            AppCommand.editSelected: edit,
            AppCommand.edit: edit,
            AppCommand.delete: () => deleteItem(context, selected),
            if (adjust) AppCommand.adjustStock: () => showAdjustStockDialog(context, selected),
          },
        };
        final list = _ItemList(
          state: state,
          highlight: wide,
          isProduct: type == 'product',
          onAdd: () => showItemForm(context, type: type),
          onTap: (i) => _open(context, i),
        );
        return KeyboardScope(name: type == 'product' ? 'Items' : 'Services', commands: keys, child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: AppSize.listPane, child: list),
                    const SizedBox(width: AppSpace.md),
                    const Expanded(child: _ItemDetail()),
                  ],
                )
              : list,
        ));
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
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(
              children: [
                Expanded(
                  child: TextField(textInputAction: TextInputAction.search, 
                    onChanged: (v) => context.read<ItemsBloc>().add(ItemsSearchChanged(v)),
                    decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search)),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                ExportMenu(table: () => TableExport(
                  title: isProduct ? 'Products' : 'Services',
                  headers: isProduct
                      ? ['Name', 'Code', 'HSN', 'Unit', 'Sale price', 'Purchase price', 'GST %', 'Stock qty', 'Stock value']
                      : ['Name', 'Code', 'SAC', 'Unit', 'Sale price', 'GST %'],
                  rows: [
                    for (final i in shown)
                      isProduct
                          ? [i.name, i.itemCode, i.hsnCode, i.unit, i.salePrice, i.purchasePrice, i.gstRate, i.stockQty, i.stockValue]
                          : [i.name, i.itemCode, i.hsnCode, i.unit, i.salePrice, i.gstRate],
                  ],
                )),
                const SizedBox(width: AppSpace.sm),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          Expanded(
            child: KeyboardScope(
              name: 'Item list',
              commands: {if (state.selected != null) AppCommand.removeRow: () => deleteItem(context, state.selected!)},
              child: PagedListPane<Item>(
              items: shown,
              headings: const ['ITEM', 'QUANTITY / PRICE'],
              sortKeys: [(i) => i.name, (i) => isProduct && trackStock ? i.stockQty : i.salePrice],
              emptyText: 'No matching items',
              onRefresh: () => context.reloadBloc<ItemsBloc, ItemsEvent, ItemsState>(const ItemsRequested()),
              itemBuilder: (_, item) {
                      return ListTile(
                        selected: highlight && item.id == state.selectedId,
                        selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                        title: Text(item.name, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // With stock maintenance off, products show their price like services do.
                            if (item.lowStock && trackStock)
                              const Padding(
                                padding: EdgeInsets.only(right: AppSpace.sm),
                                child: Icon(Icons.warning_amber, size: AppIconSize.sm, color: AppColors.warning),
                              ),
                            Text(
                              isProduct && trackStock ? qty(item.stockQty) : money(item.salePrice),
                              style: TextStyle(
                                color: trackStock && (item.stockQty < 0 || item.lowStock) ? AppColors.moneyOut : AppColors.moneyIn,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            _RowMenu(item: item),
                          ],
                        ),
                        onTap: () => onTap(item),
                        // Beside the details, moving through the list with the keyboard shows each item's details.
                        onFocusChange: highlight ? (f) => f ? context.read<ItemsBloc>().add(ItemSelected(item.id)) : null : null,
                      );
                    },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Deletes [item] once the user confirms.
Future<void> deleteItem(BuildContext context, Item item) async {
  final repo = context.read<ItemsRepository>();
  if (!await confirmDelete(context, title: 'Delete item', message: 'Do you really want to delete "${item.name}"?')) return;
  try {
    await repo.delete(item.id);
    if (context.mounted) showSuccess(context, 'Item deleted');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert, size: AppIconSize.md),
      onSelected: (v) async => v == 'edit' ? showItemForm(context, item: item) : deleteItem(context, item),
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
        return PullToRefresh(onRefresh: () => context.reloadBloc<ItemsBloc, ItemsEvent, ItemsState>(const ItemsRequested()), child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Text(item.name.toUpperCase(), style: AppText.subtitle),
                        IconButton(
                          tooltip: 'Edit item',
                          icon: Icon(Icons.edit_outlined, color: AppColors.primary, size: AppIconSize.md),
                          onPressed: () => showItemForm(context, item: item),
                        ),
                        if (item.isProduct && settingsOf(context, listen: true).stockMaintenance)
                          FilledButton.icon(
                            onPressed: () => showAdjustStockDialog(context, item),
                            icon: const Icon(Icons.tune, size: AppIconSize.sm),
                            label: const Text('ADJUST ITEM'),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Wrap(
                      spacing: 40,
                      runSpacing: 12,
                      children: [
                        InfoField('Sale Price', '${money(item.salePrice)} ${taxLabel(item.salePriceIncludesTax)}', valueColor: AppColors.moneyIn),
                        InfoField(
                          'Purchase Price',
                          '${money(item.purchasePrice)} ${taxLabel(item.purchasePriceIncludesTax)}',
                          valueColor: AppColors.successText,
                        ),
                        if (item.isProduct && settingsOf(context, listen: true).stockMaintenance) ...[
                          InfoField('Stock Quantity', '${qty(item.stockQty)} ${item.unit ?? ''}', valueColor: item.lowStock ? AppColors.moneyOut : AppColors.moneyIn),
                          InfoField('Stock Value', money(item.stockValue), valueColor: AppColors.moneyIn),
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
              const SizedBox(height: AppSpace.md),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(AppSpace.lg),
                      child: Text('TRANSACTIONS', style: TextStyle(fontSize: AppFont.bodyLarge, fontWeight: FontWeight.w600)),
                    ),
                    switch (state.movementStatus) {
                      LoadStatus.initial || LoadStatus.loading => const Padding(
                        padding: EdgeInsets.all(AppSpace.xxl),
                        child: LoadingView(),
                      ),
                      LoadStatus.failure => ErrorRetry(
                        error: state.error ?? 'Could not load stock history',
                        onRetry: () => context.read<ItemsBloc>().add(ItemSelected(item.id)),
                      ),
                      LoadStatus.success when state.movements.isEmpty => const SizedBox(
                        height: AppSize.stateHeight,
                        child: EmptyState(icon: Icons.swap_vert, title: 'No stock movements yet'),
                      ),
                      LoadStatus.success => PagedDataTable(
                        searchHint: 'Search transactions',
                        initialSortColumn: 3,
                        initialSortAscending: false,
                        columns: const [
                          TableColumnSpec('TYPE'),
                          TableColumnSpec('INVOICE'),
                          TableColumnSpec('NAME'),
                          TableColumnSpec('DATE'),
                          TableColumnSpec('QUANTITY', numeric: true),
                          TableColumnSpec('PRICE/UNIT', numeric: true),
                        ],
                        rows: [
                          for (final m in state.movements)
                            TableRowData(
                              search: '${m.label} ${m.reference ?? ''} ${m.details} ${displayDate(m.date)}',
                              sort: [m.label, int.tryParse(m.reference ?? '') ?? m.reference, m.details, m.date, m.quantity, m.pricePerUnit],
                              cells: [
                                Text(m.label),
                                Text(m.reference ?? ''),
                                Text(m.details),
                                Text(displayDate(m.date)),
                                Text(qty(m.quantity), style: TextStyle(color: m.quantity < 0 ? AppColors.moneyOut : null)),
                                Text(m.pricePerUnit == null ? '-' : money(m.pricePerUnit)),
                              ],
                            ),
                        ],
                      ),
                    },
                  ],
                ),
              ),
            ],
          ],
        ));
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
          if (catalog.status == LoadStatus.initial) return const LoadingView();
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
                  padding: const EdgeInsets.all(AppSpace.md),
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
                        selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                        title: Text(c.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${c.itemCount}'),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: AppIconSize.md),
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
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Text(
                    '${selected?.name ?? ''} · ${inCategory.length} items',
                    style: AppText.subtitle,
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
            padding: const EdgeInsets.all(AppSpace.md),
            child: isWide(context)
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: AppSize.listPane, child: list),
                      const SizedBox(width: AppSpace.md),
                      Expanded(child: detail),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: list),
                      const SizedBox(height: AppSpace.md),
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
    if (catalog.status == LoadStatus.initial) return const LoadingView();
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Units', style: AppText.subtitle),
                  ),
                  FilledButton.icon(onPressed: () => showUnitDialog(context), icon: const Icon(Icons.add), label: const Text('Add Unit')),
                ],
              ),
            ),
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
              child: const Row(
                children: [
                  Expanded(
                    child: Text('FULL NAME', style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.small)),
                  ),
                  SizedBox(
                    width: AppSize.fieldXs,
                    child: Text('SHORT NAME', style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.small)),
                  ),
                  SizedBox(width: AppSpace.huge),
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
                        SizedBox(width: AppSize.fieldXs, child: Text(u.shortName)),
                        IconButton(
                          tooltip: 'Delete unit',
                          icon: const Icon(Icons.delete_outline, size: AppIconSize.md),
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
