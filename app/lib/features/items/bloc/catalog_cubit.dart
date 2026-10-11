import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/change_bus.dart';
import '../../../core/status.dart';
import '../../../data/models/item.dart';
import '../../../data/repositories/items_repository.dart';

class CatalogState extends Equatable {
  const CatalogState({this.status = LoadStatus.initial, this.categories = const [], this.units = const [], this.error});
  final LoadStatus status;
  final List<Category> categories;
  final List<Unit> units;
  final String? error;

  @override
  List<Object?> get props => [status, categories, units, error];
}

/// Categories and units, shared by the items screens and the item form.
class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit(this._repo, ChangeBus bus) : super(const CatalogState()) {
    // Item writes change per-category item counts.
    _sub = bus.on({DataTopic.catalog, DataTopic.items}).listen((_) => load());
  }

  final ItemsRepository _repo;
  late final StreamSubscription<void> _sub;

  Future<void> load() async {
    try {
      final (categories, units) = await (_repo.categories(), _repo.units()).wait;
      emit(CatalogState(status: LoadStatus.success, categories: categories, units: units));
    } catch (e) {
      emit(CatalogState(status: LoadStatus.failure, categories: state.categories, units: state.units, error: ApiException.from(e).message));
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
