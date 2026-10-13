import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/change_bus.dart';
import '../../../core/status.dart';
import '../../../data/models/payment.dart';
import '../../../data/repositories/payments_repository.dart';
import '../../../shared/period.dart';

sealed class PaymentsEvent {
  const PaymentsEvent();
}

class PaymentsRequested extends PaymentsEvent {
  const PaymentsRequested();
}

class PaymentsPeriodChanged extends PaymentsEvent {
  const PaymentsPeriodChanged(this.range);
  final PeriodRange range;
}

class PaymentsSearchChanged extends PaymentsEvent {
  const PaymentsSearchChanged(this.query);
  final String query;
}

class PaymentDeleted extends PaymentsEvent {
  const PaymentDeleted(this.id);
  final String id;
}

class PaymentsState extends Equatable {
  const PaymentsState({required this.range, this.status = LoadStatus.initial, this.payments = const [], this.search = '', this.error});

  final PeriodRange range;
  final LoadStatus status;
  final List<Payment> payments;
  final String search;
  final String? error;

  List<Payment> get visible {
    final term = search.trim().toLowerCase();
    if (term.isEmpty) return payments;
    return payments.where((p) => p.partyName.toLowerCase().contains(term) || p.number.toLowerCase().contains(term)).toList();
  }

  num get total => payments.fold<num>(0, (s, p) => s + p.amount);

  PaymentsState copyWith({PeriodRange? range, LoadStatus? status, List<Payment>? payments, String? search, String? error}) => PaymentsState(
    range: range ?? this.range,
    status: status ?? this.status,
    payments: payments ?? this.payments,
    search: search ?? this.search,
    error: error,
  );

  @override
  List<Object?> get props => [range, status, payments, search, error];
}

/// Payments of one [type] ('in' / 'out') for the selected period.
class PaymentsBloc extends Bloc<PaymentsEvent, PaymentsState> {
  PaymentsBloc(this._repo, ChangeBus bus, this.type) : super(PaymentsState(range: PeriodRange.of(Period.thisMonth))) {
    on<PaymentsRequested>((_, emit) => _load(emit));
    on<PaymentsPeriodChanged>((e, emit) {
      emit(state.copyWith(range: e.range, status: LoadStatus.loading));
      return _load(emit);
    });
    on<PaymentsSearchChanged>((e, emit) => emit(state.copyWith(search: e.query)));
    on<PaymentDeleted>((e, emit) async {
      try {
        await _repo.delete(e.id); // the bus then triggers a reload
      } catch (err) {
        emit(state.copyWith(error: ApiException.from(err).message));
      }
    });
    _sub = bus.on({DataTopic.payments}).listen((_) => add(const PaymentsRequested()));
  }

  final PaymentsRepository _repo;
  final String type;
  late final StreamSubscription<void> _sub;

  Future<void> _load(Emitter<PaymentsState> emit) async {
    if (state.status == LoadStatus.initial) emit(state.copyWith(status: LoadStatus.loading));
    final range = state.range;
    try {
      final payments = await _repo.list(type, from: range.from, to: range.to);
      if (state.range == range) emit(state.copyWith(status: LoadStatus.success, payments: payments));
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
