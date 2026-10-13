import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/status.dart';
import '../../data/models/expense.dart';
import '../../data/models/invoice.dart' show paymentModes;
import '../../data/repositories/expenses_repository.dart';
import '../../shared/data_table_view.dart';
import '../../shared/export.dart';
import '../../shared/format.dart';
import '../../shared/submit_dialog.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'bloc/expenses_bloc.dart';

/// Add (or rename, when [category] is given) an expense category.
Future<ExpenseCategory?> showExpenseCategoryDialog(BuildContext context, {ExpenseCategory? category}) {
  final repo = context.read<ExpensesRepository>();
  final name = TextEditingController(text: category?.name);
  return showSubmitDialog<ExpenseCategory>(
    context,
    title: category == null ? 'Add Expense Category' : 'Edit Expense Category',
    action: () => repo.saveCategory(category?.id, name.text.trim()),
    fields: (submit) => [
      TextFormField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Expense Category'),
        validator: Validators.required('Name'),
        onFieldSubmitted: (_) => submit(),
      ),
    ],
  );
}

/// Expense categories with totals; the selected category's expenses beside (wide) or on a pushed page (phones).
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocProvider(create: (ctx) => ExpensesBloc(ctx.read(), ctx.read())..add(const ExpensesRequested()), child: const _ExpensesView());
}

class _ExpensesView extends StatelessWidget {
  const _ExpensesView();

  void _open(BuildContext context, ExpenseCategory c) {
    final bloc = context.read<ExpensesBloc>()..add(ExpenseCategorySelected(c.id));
    if (isWide(context)) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: bloc,
          child: BlocBuilder<ExpensesBloc, ExpensesState>(
            builder: (ctx, s) => Scaffold(
              appBar: AppBar(title: Text(s.selected?.name ?? c.name)),
              body: const _CategoryDetail(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    return BlocConsumer<ExpensesBloc, ExpensesState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error && b.status == LoadStatus.success,
      listener: (context, state) => showError(context, state.error!),
      builder: (context, state) {
        if (state.status == LoadStatus.initial || state.status == LoadStatus.loading) {
          return const LoadingView();
        }
        if (state.status == LoadStatus.failure && state.categories.isEmpty) {
          return ErrorRetry(error: state.error ?? 'Could not load', onRetry: () => context.read<ExpensesBloc>().add(const ExpensesRequested()));
        }
        final list = _CategoryList(state: state, highlight: wide, onTap: (c) => _open(context, c));
        return Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: AppSize.listPane, child: list),
                    const SizedBox(width: AppSpace.md),
                    const Expanded(child: _CategoryDetail()),
                  ],
                )
              : list,
        );
      },
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.state, required this.highlight, required this.onTap});
  final ExpensesState state;
  final bool highlight;
  final ValueChanged<ExpenseCategory> onTap;

  Future<void> _delete(BuildContext context, ExpenseCategory c) async {
    final bloc = context.read<ExpensesBloc>();
    if (await confirmDelete(context, title: 'Delete category', message: 'Delete the expense category "${c.name}"?')) {
      bloc.add(ExpenseCategoryDeleted(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ExpensesBloc>();
    final shown = state.visible;
    final addPath = state.selectedId == null ? '/expenses/new' : '/expenses/new?categoryId=${state.selectedId}';
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
                    onChanged: (v) => bloc.add(ExpenseCategorySearchChanged(v)),
                    decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search)),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                ExportMenu(table: () => TableExport(
                  title: 'Expense categories',
                  headers: ['Category', 'Total'],
                  rows: [for (final c in shown) [c.name, c.total]],
                )),
                const SizedBox(width: AppSpace.sm),
                FilledButton.icon(
                  onPressed: () => context.push(addPath),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Expense'),
                ),
              ],
            ),
          ),
          Expanded(
            child: PagedListPane<ExpenseCategory>(
              items: shown,
              headings: const ['CATEGORY', 'AMOUNT'],
              sortKeys: [(c) => c.name, (c) => c.total],
              emptyText: 'No matching categories',
              onRefresh: () => context.reloadBloc<ExpensesBloc, ExpensesEvent, ExpensesState>(const ExpensesRequested()),
              itemBuilder: (_, c) {
                      return ListTile(
                        selected: highlight && c.id == state.selectedId,
                        selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                        title: Text(c.name, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(money(c.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                            PopupMenuButton<String>(
                              tooltip: 'More',
                              icon: const Icon(Icons.more_vert, size: AppIconSize.md),
                              onSelected: (v) => v == 'edit' ? showExpenseCategoryDialog(context, category: c) : _delete(context, c),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Rename')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => onTap(c),
                      );
                    },
            ),
          ),
          const Divider(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showExpenseCategoryDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Category'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryDetail extends StatelessWidget {
  const _CategoryDetail();

  Future<void> _delete(BuildContext context, ExpenseSummary e) async {
    final bloc = context.read<ExpensesBloc>();
    if (await confirmDelete(context, title: 'Delete expense', message: 'Delete this ${e.categoryName} expense of ${money(e.total)}?')) {
      bloc.add(ExpenseDeleted(e.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ExpensesBloc, ExpensesState>(
      builder: (context, state) {
        final category = state.selected;
        if (category == null) {
          return const Card(
            child: EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'Add a category to record expenses'),
          );
        }
        return PullToRefresh(onRefresh: () => context.reloadBloc<ExpensesBloc, ExpensesEvent, ExpensesState>(const ExpensesRequested()), child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(category.name.toUpperCase(), style: AppText.subtitle),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Total: '),
                          TextSpan(
                            text: money(category.total),
                            style: const TextStyle(color: AppColors.dangerText, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Card(
              clipBehavior: Clip.antiAlias,
              child: switch (state.expensesStatus) {
                LoadStatus.initial || LoadStatus.loading => const Padding(
                  padding: EdgeInsets.all(AppSpace.huge),
                  child: LoadingView(),
                ),
                LoadStatus.failure => SizedBox(
                  height: AppSize.stateHeight,
                  child: ErrorRetry(
                    error: state.error ?? 'Could not load expenses',
                    onRetry: () => context.read<ExpensesBloc>().add(ExpenseCategorySelected(category.id)),
                  ),
                ),
                LoadStatus.success when state.expenses.isEmpty => SizedBox(
                  height: AppSize.stateHeight,
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No expenses in ${category.name}',
                    action: FilledButton.icon(
                      onPressed: () => context.push('/expenses/new?categoryId=${category.id}'),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Expense'),
                    ),
                  ),
                ),
                LoadStatus.success => PagedDataTable(
                  searchHint: 'Search expenses',
                  initialSortColumn: 0,
                  initialSortAscending: false,
                  columns: const [
                    TableColumnSpec('DATE'),
                    TableColumnSpec('EXP NO.'),
                    TableColumnSpec('PAYMENT TYPE'),
                    TableColumnSpec('AMOUNT', numeric: true),
                    TableColumnSpec('', sortable: false),
                  ],
                  rows: [
                    for (final e in state.expenses)
                      TableRowData(
                        onTap: () => context.push('/expenses/${e.id}/edit'),
                        search: '${displayDate(e.expenseDate)} ${e.number ?? ''} ${paymentModes[e.paymentMode] ?? e.paymentMode}',
                        sort: [e.expenseDate, int.tryParse(e.number ?? '') ?? e.number, paymentModes[e.paymentMode] ?? e.paymentMode, e.total, null],
                        cells: [
                          Text(displayDate(e.expenseDate)),
                          Text(e.number ?? ''),
                          Text(paymentModes[e.paymentMode] ?? e.paymentMode),
                          Text(money(e.total)),
                          PopupMenuButton<String>(
                            tooltip: 'More',
                            icon: const Icon(Icons.more_vert, size: AppIconSize.md),
                            onSelected: (v) => v == 'edit' ? context.push('/expenses/${e.id}/edit') : _delete(context, e),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('View/Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              },
            ),
          ],
        ));
      },
    );
  }
}
