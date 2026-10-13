import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';
import '../theme.dart';

/// Hands the reload action of a page to the scroll views below it, so pulling down on any of them reloads that page.
class RefreshScope extends InheritedWidget {
  const RefreshScope({super.key, required this.onRefresh, required super.child});
  final Future<void> Function() onRefresh;

  static RefreshScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<RefreshScope>();

  @override
  bool updateShouldNotify(RefreshScope old) => old.onRefresh != onRefresh;
}

/// Pull down to reload. Wraps a vertical scroll view: with [onRefresh] it reloads that; without it, it uses the page's
/// [RefreshScope], and does nothing if there is none. Works with touch, a mouse or a trackpad, and on a list too short to scroll.
class PullToRefresh extends StatelessWidget {
  const PullToRefresh({super.key, this.onRefresh, required this.child});
  final Future<void> Function()? onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final action = onRefresh ?? RefreshScope.maybeOf(context)?.onRefresh;
    if (action == null) return child;
    return ScrollConfiguration(
      behavior: const _PullBehavior(),
      child: RefreshIndicator(color: AppColors.primary, backgroundColor: AppColors.surface, onRefresh: action, child: child),
    );
  }
}

/// A scroll view can always be pulled, and by any pointer (a mouse can drag it too).
class _PullBehavior extends MaterialScrollBehavior {
  const _PullBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus};

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics());
}

/// `context.reloadBloc<PartiesBloc, PartiesEvent, PartiesState>(const PartiesRequested())` reloads a bloc and waits for its answer.
extension BlocReload on BuildContext {
  Future<void> reloadBloc<B extends Bloc<E, S>, E, S>(E reload) {
    final bloc = read<B>();
    return reloadAndWait<S>(bloc, () => bloc.add(reload));
  }
}

/// Asks a bloc to reload and waits until it has answered, so the pull-to-refresh spinner shows for as long as the reload
/// takes. A reload that finds nothing new does not change the bloc's state, so the wait ends after [timeout] at the latest;
/// it also lasts at least [minimum], so the spinner is never a flicker.
Future<void> reloadAndWait<S>(StateStreamable<S> bloc, void Function() reload, {Duration timeout = const Duration(seconds: 3), Duration minimum = const Duration(milliseconds: 500)}) async {
  final answered = bloc.stream.first.timeout(timeout, onTimeout: () => bloc.state);
  reload();
  await Future.wait([answered, Future<void>.delayed(minimum)]);
}
