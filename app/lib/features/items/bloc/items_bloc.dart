import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/change_bus.dart';
import '../../../core/status.dart';
import '../../../data/models/item.dart';
import '../../../data/repositories/items_repository.dart';

sealed class ItemsEvent {
  const ItemsEvent();
}

class ItemsRequested extends ItemsEvent {
  const ItemsRequested();
}

class ItemsSearchChanged extends ItemsEvent {
  const ItemsSearchChanged(this.query);
  final String query;
}

class ItemSelected extends ItemsEvent {
  const ItemSelected(this.id);
  final String id;
}

class _ItemsChanged extends ItemsEvent {
  const _ItemsChanged();
}

class ItemsState extends Equatable {
  const ItemsState({
    this.status = LoadStatus.initial,
    this.items = const [],
    this.search = '',
    this.selectedId,
    this.movementStatus = LoadStatus.initial,
    this.movements = const [],
    this.error,
  });

  final LoadStatus status;
  final List<Item> items;
  final String search;
  final String? selectedId;
  final LoadStatus movementStatus;
  final List<StockMovement> movements;
  final String? error;

  Item? get selected => items.where((i) => i.id == selectedId).firstOrNull;

  List<Item> get visible {
    final term = search.trim().toLowerCase();
    if (term.isEmpty) return items;
    return items.where((i) => i.name.toLowerCase().contains(term) || (i.itemCode ?? '').toLowerCase().contains(term)).toList();
  }

  ItemsState copyWith({
    LoadStatus? status,
    List<Item>? items,
    String? search,
    String? Function()? selectedId,
    LoadStatus? movementStatus,
    List<StockMovement>? movements,
    String? error,
  }) =>
      ItemsState(
        status: status ?? this.status,
        items: items ?? this.items,
        search: search ?? this.search,
        selectedId: selectedId != null ? selectedId() : this.selectedId,
        movementStatus: movementStatus ?? this.movementStatus,
        movements: movements ?? this.movements,
        error: error,
      );

  @override
  List<Object?> get props => [status, items, search, selectedId, movementStatus, movements, error];
}

/// Items of one [type] ('product' / 'service'), the selection and its stock history.
class ItemsBloc extends Bloc<ItemsEvent, ItemsState> {
  /// [openId] is the item to show first (e.g. one picked in quick search), if it is of this [type].
  ItemsBloc(this._repo, ChangeBus bus, this.type, {String? openId}) : super(ItemsState(selectedId: openId)) {
    on<ItemsRequested>((_, emit) => _load(emit));
    on<_ItemsChanged>((_, emit) => _load(emit));
    on<ItemsSearchChanged>((e, emit) => emit(state.copyWith(search: e.query)));
    on<ItemSelected>((e, emit) async {
      emit(state.copyWith(selectedId: () => e.id, movementStatus: LoadStatus.loading, movements: const []));
      await _loadMovements(emit);
    });
    // Invoices change stock quantities and add stock movements.
    _sub = bus.on({DataTopic.items, DataTopic.invoices}).listen((_) => add(const _ItemsChanged()));
  }

  final ItemsRepository _repo;
  final String type;
  late final StreamSubscription<void> _sub;

  Future<void> _load(Emitter<ItemsState> emit) async {
    if (state.items.isEmpty) emit(state.copyWith(status: LoadStatus.loading));
    try {
      final items = await _repo.list(type);
      final keep = items.any((i) => i.id == state.selectedId);
      emit(state.copyWith(status: LoadStatus.success, items: items, selectedId: () => keep ? state.selectedId : items.firstOrNull?.id));
      await _loadMovements(emit);
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> _loadMovements(Emitter<ItemsState> emit) async {
    final item = state.selected;
    if (item == null || !item.isProduct) return emit(state.copyWith(movementStatus: LoadStatus.success, movements: const []));
    try {
      final movements = await _repo.movements(item.id);
      if (state.selectedId == item.id) emit(state.copyWith(movementStatus: LoadStatus.success, movements: movements));
    } catch (e) {
      emit(state.copyWith(movementStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
