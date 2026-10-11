import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/list_cubit.dart';
import '../core/status.dart';
import 'widgets.dart';

/// A scrolling page with a title row (and optional actions on its right).
class TitledPage extends StatelessWidget {
  const TitledPage({super.key, required this.title, this.subtitle, this.actions = const [], required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 12),
        ...children,
      ]);
}

/// Body of a screen backed by a [ListCubit]: spinner, error with retry, or [builder] with the rows.
/// Failed actions are shown as a snackbar.
class ListCubitView<T> extends StatelessWidget {
  const ListCubitView({super.key, required this.builder});
  final Widget Function(BuildContext context, ListState<T> state) builder;

  @override
  Widget build(BuildContext context) => BlocConsumer<ListCubit<T>, ListState<T>>(
        listenWhen: (a, b) => a.errorRev != b.errorRev,
        listener: (context, s) => showError(context, s.error ?? 'Something went wrong.'),
        builder: (context, s) => switch (s.status) {
          LoadStatus.failure => ErrorRetry(error: s.error ?? 'Could not load', onRetry: context.read<ListCubit<T>>().load),
          LoadStatus.success => builder(context, s),
          _ => const Center(child: CircularProgressIndicator()),
        },
      );
}

/// A card holding a plain list of rows separated by dividers, or [empty] when there are none.
class RowsCard extends StatelessWidget {
  const RowsCard({super.key, required this.rows, required this.empty});
  final List<Widget> rows;
  final Widget empty;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: rows.isEmpty
            ? SizedBox(height: 260, child: empty)
            : Column(children: [
                for (var i = 0; i < rows.length; i++) ...[if (i > 0) const Divider(), rows[i]],
              ]),
      );
}
