import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'api_client.dart';
import 'change_bus.dart';
import 'status.dart';

class ListState<T> extends Equatable {
  const ListState({this.status = LoadStatus.loading, this.items = const [], this.busy = false, this.error, this.errorRev = 0});

  final LoadStatus status;
  final List<T> items;

  /// An action (save, delete, ...) is running.
  final bool busy;

  /// The last failure: of the load when [status] is failure, otherwise of an action.
  final String? error;

  /// Bumped with every failed action so the screen shows each one once, even the same message twice.
  final int errorRev;

  @override
  List<Object?> get props => [status, items, busy, error, errorRev];
}

/// A list loaded from the server, with actions that change it. Enough for simple master screens
/// (currencies, users, expense items, ...) that need no state beyond their rows.
class ListCubit<T> extends Cubit<ListState<T>> {
  /// With [bus] and [topics] the list reloads whenever one of those kinds of data changes.
  ListCubit(this._loader, {ChangeBus? bus, Set<DataTopic> topics = const {}}) : super(ListState<T>()) {
    if (bus != null && topics.isNotEmpty) _sub = bus.on(topics).listen((_) => load());
  }

  final Future<List<T>> Function() _loader;
  StreamSubscription<void>? _sub;

  Future<void> load() async {
    try {
      final items = await _loader();
      if (!isClosed) emit(ListState<T>(status: LoadStatus.success, items: items, errorRev: state.errorRev));
    } catch (e) {
      if (isClosed) return;
      // Keep showing what we have if a refresh fails; only a first load shows the error page.
      emit(state.status == LoadStatus.success
          ? ListState<T>(status: LoadStatus.success, items: state.items, error: ApiException.from(e).message, errorRev: state.errorRev + 1)
          : ListState<T>(status: LoadStatus.failure, error: ApiException.from(e).message, errorRev: state.errorRev));
    }
  }

  /// Runs [action] and reloads the list. Returns whether it succeeded; a failure is reported through the state.
  Future<bool> run(Future<void> Function() action) async {
    if (state.busy) return false;
    emit(ListState<T>(status: state.status, items: state.items, busy: true, errorRev: state.errorRev));
    try {
      await action();
      await load();
      return true;
    } catch (e) {
      if (!isClosed) {
        emit(ListState<T>(status: state.status, items: state.items, error: ApiException.from(e).message, errorRev: state.errorRev + 1));
      }
      return false;
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
