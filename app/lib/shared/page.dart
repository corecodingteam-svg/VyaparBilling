import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/list_cubit.dart';
import '../core/status.dart';
import 'data_table_view.dart';
import 'theme.dart';
import 'widgets.dart';

/// A scrolling page with a title row (and optional actions on its right).
class TitledPage extends StatelessWidget {
  const TitledPage({super.key, required this.title, this.subtitle, this.actions = const [], required this.children, this.onRefresh});
  final String title;
  /// Reloads the page when it is pulled down; defaults to the page's [RefreshScope].
  final Future<void> Function()? onRefresh;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => PullToRefresh(onRefresh: onRefresh, child: ListView(padding: const EdgeInsets.all(AppSize.page), children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: AppSpace.sm, children: [
          Text(title, style: AppText.title),
          if (actions.isNotEmpty) Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: actions),
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(subtitle!, style: AppText.helper.copyWith(fontSize: AppFont.body)),
        ],
        const SizedBox(height: AppSpace.md),
        ...children,
      ]));
}

/// Body of a screen backed by a [ListCubit]: spinner, error with retry, or [builder] with the rows.
/// Failed actions are shown as a snackbar.
class ListCubitView<T> extends StatelessWidget {
  const ListCubitView({super.key, required this.builder});
  final Widget Function(BuildContext context, ListState<T> state) builder;

  @override
  Widget build(BuildContext context) => BlocConsumer<ListCubit<T>, ListState<T>>(
        listenWhen: (a, b) => a.errorRev != b.errorRev,
        listener: (context, s) => showError(context, s.error ?? 'That did not work. Please try again.'),
        builder: (context, s) => StateSwitcher(
          child: switch (s.status) {
            LoadStatus.failure => KeyedSubtree(key: const ValueKey('failure'), child: ErrorRetry(error: s.error ?? 'Could not load', onRetry: context.read<ListCubit<T>>().load)),
            LoadStatus.success => KeyedSubtree(key: const ValueKey('content'), child: RefreshScope(onRefresh: context.read<ListCubit<T>>().load, child: Builder(builder: (context) => builder(context, s)))),
            _ => const KeyedSubtree(key: ValueKey('loading'), child: LoadingView()),
          },
        ),
      );
}

/// A card holding a list of rows separated by dividers, or [empty] when there are none. Every list is paged (10, 25, 50 or
/// 100 a page). Give [texts] (the words each row can be found by) to add a search box, and [sorts] (a value per row, for each
/// way of ordering) to add a "Sort by" menu.
class RowsCard extends StatelessWidget {
  const RowsCard({super.key, required this.rows, required this.empty, this.texts, this.sorts, this.searchHint = 'Search this list'})
     ;
  final List<Widget> rows;
  final Widget empty;
  final List<String>? texts;
  final Map<String, List<Object?>>? sorts;
  final String searchHint;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Card(clipBehavior: Clip.antiAlias, child: SizedBox(height: AppSize.stateHeight, child: empty));
    final sortNames = sorts?.keys.toList() ?? const <String>[];
    final data = [
      for (var i = 0; i < rows.length; i++)
        TableRowData(cells: [rows[i]], search: texts == null || i >= texts!.length ? '' : texts![i], sort: [for (final n in sortNames) i < sorts![n]!.length ? sorts![n]![i] : null]),
    ];
    return BlocProvider(
      create: (_) => TableViewCubit(sortColumn: sortNames.isEmpty ? null : 0, pageSize: 25),
      child: BlocBuilder<TableViewCubit, TableViewState>(builder: (context, state) {
        final cubit = context.read<TableViewCubit>();
        final matching = visibleRows(data, state);
        final pages = (matching.length / state.pageSize).ceil().clamp(1, 1 << 30);
        final page = state.page.clamp(0, pages - 1);
        final shown = matching.skip(page * state.pageSize).take(state.pageSize).toList();
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (texts != null || sortNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Wrap(spacing: AppSpace.md, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (texts != null)
                    SizedBox(
                      width: AppSize.fieldLg,
                      child: TextField(textInputAction: TextInputAction.search, onChanged: cubit.search, decoration: InputDecoration(hintText: searchHint, prefixIcon: const Icon(Icons.search))),
                    ),
                  if (sortNames.isNotEmpty) ...[
                    Text('Sort by', style: AppText.helper),
                    DropdownButton<int>(
                      value: state.sortColumn ?? 0,
                      underline: const SizedBox.shrink(),
                      items: [for (var i = 0; i < sortNames.length; i++) DropdownMenuItem(value: i, child: Text(sortNames[i]))],
                      onChanged: (i) => cubit.sortBy(i ?? 0),
                    ),
                    IconButton(
                      tooltip: state.ascending ? 'Ascending' : 'Descending',
                      icon: Icon(state.ascending ? Icons.arrow_upward : Icons.arrow_downward, size: AppIconSize.md),
                      onPressed: cubit.flipDirection,
                    ),
                  ],
                ]),
              ),
            if (matching.isEmpty)
              SizedBox(height: AppSize.stateHeight, child: EmptyState(icon: Icons.search_off, title: 'Nothing matches "${state.query}"', message: 'Try fewer words or clear the search.'))
            else
              for (var i = 0; i < shown.length; i++) ...[if (i > 0 || texts != null || sortNames.isNotEmpty) const Divider(), FadeSlideIn(index: i, child: shown[i].cells.first)],
            if (matching.length > 10 || state.pageSize != 25)
              TablePager(total: matching.length, page: page, pages: pages, pageSize: state.pageSize, filtered: state.query.isNotEmpty),
          ]),
        );
      }),
    );
  }
}
