import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../data/models/extras.dart';
import '../../data/models/invoice.dart';
import '../../data/repositories/utilities_repository.dart';
import '../../shared/theme.dart';

class SearchState extends Equatable {
  const SearchState({this.query = '', this.loading = false, this.hits = const [], this.error});
  final String query;
  final bool loading;
  final List<SearchHit> hits;
  final String? error;

  @override
  List<Object?> get props => [query, loading, hits, error];
}

/// Searches parties, items and documents as the user types, a moment after they pause.
class SearchCubit extends Cubit<SearchState> {
  SearchCubit(this._repo, {this.debounce = const Duration(milliseconds: 250)}) : super(const SearchState());

  final UtilitiesRepository _repo;
  final Duration debounce;
  Timer? _timer;

  void queryChanged(String text) {
    _timer?.cancel();
    final query = text.trim();
    if (query.length < 2) return emit(SearchState(query: query));
    emit(SearchState(query: query, loading: true, hits: state.hits));
    _timer = Timer(debounce, () => _search(query));
  }

  Future<void> _search(String query) async {
    try {
      final hits = await _repo.search(query);
      // An answer for text the user has since changed is dropped.
      if (!isClosed && state.query == query) emit(SearchState(query: query, hits: hits));
    } catch (e) {
      if (!isClosed && state.query == query) emit(SearchState(query: query, error: ApiException.from(e).message));
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}

/// Where a search result leads.
String searchHitPath(SearchHit hit) => switch (hit.kind) {
      'party' => '/parties?open=${hit.id}',
      'item' => '/items?open=${hit.id}&type=${hit.type ?? 'product'}',
      _ => '${InvoiceKind.of(hit.type ?? 'sale').basePath}/${hit.id}/edit',
    };

/// Opens quick search (also on Ctrl/Cmd+K). Picking a result goes to it.
Future<void> showQuickSearch(BuildContext context) async {
  final router = GoRouter.maybeOf(context);
  final hit = await showDialog<SearchHit>(
    context: context,
    builder: (_) => BlocProvider(create: (_) => SearchCubit(context.read()), child: const _QuickSearchDialog()),
  );
  if (hit == null) return;
  final path = searchHitPath(hit);
  hit.kind == 'invoice' ? router?.push(path) : router?.go(path);
}

const _icons = {'party': Icons.person_outline, 'item': Icons.inventory_2_outlined, 'invoice': Icons.receipt_long_outlined};

class _QuickSearchDialog extends StatelessWidget {
  const _QuickSearchDialog();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchCubit>();
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 70, 16, 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
        child: BlocBuilder<SearchCubit, SearchState>(
          builder: (context, s) => Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                onChanged: cubit.queryChanged,
                // Enter opens the first result.
                onSubmitted: (_) => s.hits.isEmpty ? null : Navigator.of(context).pop(s.hits.first),
                decoration: InputDecoration(
                  hintText: 'Search parties, items, invoice numbers…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: s.loading ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                ),
              ),
            ),
            const Divider(),
            if (s.error != null)
              Padding(padding: const EdgeInsets.all(20), child: Text(s.error!, style: const TextStyle(color: payRed)))
            else if (s.query.length < 2)
              const Padding(padding: EdgeInsets.all(20), child: Text('Type at least 2 letters or digits.', style: TextStyle(color: Colors.black54)))
            else if (s.hits.isEmpty && !s.loading)
              Padding(padding: const EdgeInsets.all(20), child: Text('Nothing found for "${s.query}".', style: const TextStyle(color: Colors.black54)))
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final h in s.hits)
                    ListTile(
                      dense: true,
                      leading: Icon(_icons[h.kind], color: brandBlue),
                      title: Text(h.title, overflow: TextOverflow.ellipsis),
                      subtitle: Text(h.subtitle, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).pop(h),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Makes Ctrl+K / Cmd+K open quick search anywhere below it.
class QuickSearchShortcut extends StatelessWidget {
  const QuickSearchShortcut({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => showQuickSearch(context),
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => showQuickSearch(context),
        },
        child: Focus(autofocus: true, child: child),
      );
}
