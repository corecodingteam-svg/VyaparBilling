import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/status.dart';
import '../../../data/repositories/items_repository.dart';
import '../../../shared/format.dart';

class AdjustStockState extends Equatable {
  const AdjustStockState({this.type = 'add', required this.date, this.status = SubmitStatus.idle, this.error});
  final String type; // add | reduce
  final String date;
  final SubmitStatus status;
  final String? error;

  AdjustStockState copyWith({String? type, String? date, SubmitStatus? status, String? error}) =>
      AdjustStockState(type: type ?? this.type, date: date ?? this.date, status: status ?? this.status, error: error);

  @override
  List<Object?> get props => [type, date, status, error];
}

class AdjustStockCubit extends Cubit<AdjustStockState> {
  AdjustStockCubit(this._repo, this.itemId) : super(AdjustStockState(date: isoDate(DateTime.now())));

  final ItemsRepository _repo;
  final String itemId;

  void typeChanged(String v) => emit(state.copyWith(type: v));
  void dateChanged(String v) => emit(state.copyWith(date: v));

  Future<void> submit({required num quantity, num? pricePerUnit, String? notes}) async {
    if (state.status == SubmitStatus.submitting) return;
    emit(state.copyWith(status: SubmitStatus.submitting));
    try {
      await _repo.adjust(itemId, {'type': state.type, 'quantity': quantity, 'pricePerUnit': pricePerUnit, 'date': state.date, 'notes': notes});
      emit(state.copyWith(status: SubmitStatus.success));
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}
