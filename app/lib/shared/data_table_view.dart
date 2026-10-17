import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/keyboard/row_navigation.dart';
import 'theme.dart';
import 'widgets.dart';

/// One row of a [PagedDataTable]: what to show, and what sorting and searching should look at.
class TableRowData {
  const TableRowData({required this.cells, this.sort = const [], this.search = '', this.onTap, this.selected = false, this.color, this.pinned = false});

  /// One widget per column.
  final List<Widget> cells;

  /// One comparable value per column (`num`, `String`, `DateTime`, or null), used when that column is sorted.
  final List<Object?> sort;

  /// Text the search box looks in.
  final String search;
  final VoidCallback? onTap;
  final bool selected;
  final Color? color;

  /// A totals or heading row: it ignores sorting and searching and stays at the bottom of the last page.
  final bool pinned;
}

class TableColumnSpec {
  const TableColumnSpec(this.label, {this.numeric = false, this.sortable = true});
  final String label;
  final bool numeric;
  final bool sortable;
}

class TableViewState extends Equatable {
  const TableViewState({this.query = '', this.sortColumn, this.ascending = true, this.page = 0, this.pageSize = 25});
  final String query;
  final int? sortColumn;
  final bool ascending;
  final int page;
  final int pageSize;

  TableViewState copyWith({String? query, Object? sortColumn = _keep, bool? ascending, int? page, int? pageSize}) => TableViewState(
        query: query ?? this.query,
        sortColumn: identical(sortColumn, _keep) ? this.sortColumn : sortColumn as int?,
        ascending: ascending ?? this.ascending,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
      );
  static const _keep = Object();

  @override
  List<Object?> get props => [query, sortColumn, ascending, page, pageSize];
}

/// Search text, sort order and page of one table. Each [PagedDataTable] has its own.
class TableViewCubit extends Cubit<TableViewState> {
  TableViewCubit({int? sortColumn, bool ascending = true, int pageSize = 25}) : super(TableViewState(sortColumn: sortColumn, ascending: ascending, pageSize: pageSize));

  void search(String q) => emit(state.copyWith(query: q, page: 0));
  void sort(int column) => emit(state.sortColumn == column ? state.copyWith(ascending: !state.ascending, page: 0) : state.copyWith(sortColumn: column, ascending: true, page: 0));
  void sortBy(int column) => emit(state.copyWith(sortColumn: column, ascending: true, page: 0));
  void flipDirection() => emit(state.copyWith(ascending: !state.ascending, page: 0));
  void goTo(int page) => emit(state.copyWith(page: page < 0 ? 0 : page));
  void pageSize(int size) => emit(state.copyWith(pageSize: size, page: 0));
}

int _compare(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // empty values go last whichever way it sorts
  if (b == null) return -1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is DateTime && b is DateTime) return a.compareTo(b);
  return a.toString().toLowerCase().compareTo(b.toString().toLowerCase());
}

/// The rows of [all] that match [state]'s search, in its sort order (pinned rows excluded).
List<TableRowData> visibleRows(List<TableRowData> all, TableViewState state) {
  final words = state.query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  var rows = [
    for (final r in all)
      if (!r.pinned && words.every(r.search.toLowerCase().contains)) r,
  ];
  final col = state.sortColumn;
  if (col != null) {
    // Nulls stay last in both directions.
    rows.sort((a, b) {
      final x = col < a.sort.length ? a.sort[col] : null, y = col < b.sort.length ? b.sort[col] : null;
      if (x == null || y == null) return _compare(x, y);
      final c = _compare(x, y);
      return state.ascending ? c : -c;
    });
  }
  return rows;
}

/// A table with a search box, click-to-sort column headings and pages. Reuse it for every list of rows
/// (hand it [TableRowData]s) so every table behaves the same.
class PagedDataTable extends StatelessWidget {
  const PagedDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.searchable = true,
    this.searchHint = 'Search this list',
    this.initialSortColumn,
    this.initialSortAscending = true,
    this.empty,
    this.columnSpacing = 28,
    this.plain = false,
  });

  final List<TableColumnSpec> columns;
  final List<TableRowData> rows;

  /// Off where the page already has its own search box.
  final bool searchable;
  final String searchHint;
  final int? initialSortColumn;
  final bool initialSortAscending;

  /// Shown instead of the table when there are no rows at all.
  final Widget? empty;
  final double columnSpacing;

  /// A statement whose row order is its meaning (balance sheet, profit & loss): no search, sorting or pages.
  final bool plain;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => TableViewCubit(sortColumn: initialSortColumn, ascending: initialSortAscending),
        child: BlocBuilder<TableViewCubit, TableViewState>(builder: (context, state) {
          if (rows.isEmpty && empty != null) return empty!;
          final cubit = context.read<TableViewCubit>();
          final matching = plain ? [for (final r in rows) if (!r.pinned) r] : visibleRows(rows, state);
          final pinned = [for (final r in rows) if (r.pinned) r];
          final pageSize = plain ? (matching.length + rows.length + 1) : state.pageSize;
          final pages = (matching.length / pageSize).ceil().clamp(1, 1 << 30);
          final page = state.page.clamp(0, pages - 1);
          final start = page * pageSize;
          final shown = matching.skip(start).take(pageSize).toList();
          final lastPage = page == pages - 1;
          return RowNavigation(
            onNextPage: page < pages - 1 ? () => cubit.goTo(page + 1) : null,
            onPreviousPage: page > 0 ? () => cubit.goTo(page - 1) : null,
            onFirstPage: page > 0 ? () => cubit.goTo(0) : null,
            onLastPage: page < pages - 1 ? () => cubit.goTo(pages - 1) : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (searchable && !plain)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: AppSize.fieldLg,
                    child: TextField(
                      textInputAction: TextInputAction.search,
                      onChanged: cubit.search,
                      decoration: InputDecoration(hintText: searchHint, prefixIcon: const Icon(Icons.search)),
                    ),
                  ),
                ),
              ),
            if (matching.isEmpty)
              SizedBox(height: AppSize.stateHeight, child: EmptyState(icon: Icons.search_off, title: 'Nothing matches "${state.query}"', message: 'Try fewer words or clear the search.'))
            else
              FullWidthTable(
                child: DataTable(
                  showCheckboxColumn: false,
                  columnSpacing: columnSpacing,
                  sortColumnIndex: plain ? null : state.sortColumn,
                  sortAscending: state.ascending,
                  headingRowColor: WidgetStatePropertyAll(AppColors.background),
                  columns: [
                    for (var i = 0; i < columns.length; i++)
                      DataColumn(label: Text(columns[i].label), numeric: columns[i].numeric, onSort: columns[i].sortable && !plain ? (_, _) => cubit.sort(i) : null),
                  ],
                  rows: [
                    for (final r in [...shown, if (lastPage) ...pinned])
                      DataRow(
                        selected: r.selected,
                        color: r.color == null ? null : WidgetStatePropertyAll(r.color),
                        onSelectChanged: r.onTap == null ? null : (_) => r.onTap!(),
                        cells: [for (final c in r.cells) DataCell(c)],
                      ),
                  ],
                ),
              ),
            if (!plain && (matching.length > 10 || state.pageSize != 25))
              TablePager(total: matching.length, page: page, pages: pages, pageSize: state.pageSize, filtered: matching.length != rows.where((r) => !r.pinned).length),
          ]));
        }),
      );
}

const pageSizes = [10, 25, 50, 100];

class TablePager extends StatelessWidget {
  const TablePager({super.key, required this.total, required this.page, required this.pages, required this.pageSize, required this.filtered, this.compact = false});
  final bool compact;
  final int total;
  final int page;
  final int pages;
  final int pageSize;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TableViewCubit>();
    final from = total == 0 ? 0 : page * pageSize + 1;
    final to = ((page + 1) * pageSize).clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xs),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: compact
          ? Row(children: [
              Expanded(child: Text('$from–$to of $total', style: AppText.small)),
              IconButton(tooltip: 'Previous page', onPressed: page == 0 ? null : () => cubit.goTo(page - 1), icon: const Icon(Icons.chevron_left)),
              IconButton(tooltip: 'Next page', onPressed: page >= pages - 1 ? null : () => cubit.goTo(page + 1), icon: const Icon(Icons.chevron_right)),
            ])
          : Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.md, children: [
        Text('Rows per page', style: AppText.helper),
        DropdownButton<int>(
          value: pageSize,
          underline: const SizedBox.shrink(),
          items: [for (final s in pageSizes) DropdownMenuItem(value: s, child: Text('$s'))],
          onChanged: (s) => cubit.pageSize(s ?? 25),
        ),
        Text('$from–$to of $total${filtered ? ' (filtered)' : ''}', style: AppText.small),
        IconButton(tooltip: 'First page', onPressed: page == 0 ? null : () => cubit.goTo(0), icon: const Icon(Icons.first_page)),
        IconButton(tooltip: 'Previous page', onPressed: page == 0 ? null : () => cubit.goTo(page - 1), icon: const Icon(Icons.chevron_left)),
        Text('Page ${page + 1} of $pages', style: AppText.small),
        IconButton(tooltip: 'Next page', onPressed: page >= pages - 1 ? null : () => cubit.goTo(page + 1), icon: const Icon(Icons.chevron_right)),
        IconButton(tooltip: 'Last page', onPressed: page >= pages - 1 ? null : () => cubit.goTo(pages - 1), icon: const Icon(Icons.last_page)),
      ]),
    );
  }
}

/// The list pane beside a detail view (parties, items, banks…): heading labels that sort when clicked, then the rows a page at a
/// time with a small pager. [headings] are the column labels (the first is left, the rest right-aligned); [sortKeys] gives each
/// row's value for each heading.
class PagedListPane<T> extends StatelessWidget {
  const PagedListPane({super.key, required this.items, required this.headings, required this.sortKeys, required this.itemBuilder, required this.emptyText, this.onRefresh, this.pageSize = 25});

  final List<T> items;
  final List<String> headings;
  final List<Object? Function(T)> sortKeys;
  final Widget Function(BuildContext, T) itemBuilder;
  final String emptyText;
  final Future<void> Function()? onRefresh;
  final int pageSize;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => TableViewCubit(pageSize: pageSize),
        child: BlocBuilder<TableViewCubit, TableViewState>(builder: (context, state) {
          final cubit = context.read<TableViewCubit>();
          final data = [for (final i in items) TableRowData(cells: const [], sort: [for (final k in sortKeys) k(i)])];
          // Sort the items themselves, using the same ordering as the tables.
          final order = List<int>.generate(items.length, (i) => i);
          final col = state.sortColumn;
          if (col != null) {
            order.sort((a, b) {
              final x = data[a].sort[col], y = data[b].sort[col];
              if (x == null || y == null) return _compare(x, y);
              final c = _compare(x, y);
              return state.ascending ? c : -c;
            });
          }
          final pages = (items.length / state.pageSize).ceil().clamp(1, 1 << 30);
          final page = state.page.clamp(0, pages - 1);
          final shown = [for (final i in order.skip(page * state.pageSize).take(state.pageSize)) items[i]];
          Widget heading(int i) {
            final active = state.sortColumn == i;
            return InkWell(
              onTap: () => cubit.sort(i),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(headings[i], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.small)),
                if (active) Icon(state.ascending ? Icons.arrow_upward : Icons.arrow_downward, size: AppIconSize.xs),
              ]),
            );
          }

          Widget list = shown.isEmpty
              ? Center(child: Text(emptyText))
              : ListView.separated(itemCount: shown.length, separatorBuilder: (_, _) => const Divider(), itemBuilder: (context, i) => itemBuilder(context, shown[i]));
          if (onRefresh != null && shown.isNotEmpty) list = PullToRefresh(onRefresh: onRefresh, child: list);
          return RowNavigation(
            onNextPage: page < pages - 1 ? () => cubit.goTo(page + 1) : null,
            onPreviousPage: page > 0 ? () => cubit.goTo(page - 1) : null,
            onFirstPage: page > 0 ? () => cubit.goTo(0) : null,
            onLastPage: page < pages - 1 ? () => cubit.goTo(pages - 1) : null,
            child: Column(children: [
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
              child: Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: heading(0))), for (var i = 1; i < headings.length; i++) heading(i)]),
            ),
            Expanded(child: list),
            if (items.length > state.pageSize) TablePager(total: items.length, page: page, pages: pages, pageSize: state.pageSize, filtered: false, compact: true),
          ]));
        }),
      );
}
