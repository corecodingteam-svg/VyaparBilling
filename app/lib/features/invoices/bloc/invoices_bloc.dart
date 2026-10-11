import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/change_bus.dart';
import '../../../core/status.dart';
import '../../../data/models/invoice.dart';
import '../../../data/repositories/invoices_repository.dart';
import '../../../shared/period.dart';

sealed class InvoicesEvent {
  const InvoicesEvent();
}

class InvoicesRequested extends InvoicesEvent {
  const InvoicesRequested();
}

class InvoicesPeriodChanged extends InvoicesEvent {
  const InvoicesPeriodChanged(this.range);
  final PeriodRange range;
}

class InvoicesSearchChanged extends InvoicesEvent {
  const InvoicesSearchChanged(this.query);
  final String query;
}

class InvoiceDeleted extends InvoicesEvent {
  const InvoiceDeleted(this.id);
  final String id;
}

class InvoicesState extends Equatable {
  const InvoicesState({
    required this.range,
    this.status = LoadStatus.initial,
    this.invoices = const [],
    this.search = '',
    this.error,
  });

  final PeriodRange range;
  final LoadStatus status;
  final List<InvoiceSummary> invoices;
  final String search;

  /// Set when a load or delete fails; shown once by the screen.
  final String? error;

  List<InvoiceSummary> get visible {
    final term = search.trim().toLowerCase();
    if (term.isEmpty) return invoices;
    return invoices.where((i) => i.partyName.toLowerCase().contains(term) || i.number.toLowerCase().contains(term)).toList();
  }

  num get total => invoices.fold<num>(0, (s, i) => s + i.total);
  // Paid with the document plus payments linked to it later.
  num get received => invoices.fold<num>(0, (s, i) => s + i.paid);
  num get balance => invoices.fold<num>(0, (s, i) => s + i.balance);

  /// Estimates not yet converted to a sale.
  num get openTotal => invoices.where((i) => i.isOpen).fold<num>(0, (s, i) => s + i.total);

  InvoicesState copyWith({PeriodRange? range, LoadStatus? status, List<InvoiceSummary>? invoices, String? search, String? error}) =>
      InvoicesState(
        range: range ?? this.range,
        status: status ?? this.status,
        invoices: invoices ?? this.invoices,
        search: search ?? this.search,
        error: error,
      );

  @override
  List<Object?> get props => [range, status, invoices, search, error];
}

/// Invoices of one [type] ('sale' / 'purchase') for the selected period.
class InvoicesBloc extends Bloc<InvoicesEvent, InvoicesState> {
  InvoicesBloc(this._repo, ChangeBus bus, this.type) : super(InvoicesState(range: PeriodRange.of(Period.thisMonth))) {
    on<InvoicesRequested>((_, emit) => _load(emit));
    on<InvoicesPeriodChanged>((e, emit) {
      emit(state.copyWith(range: e.range, status: LoadStatus.loading));
      return _load(emit);
    });
    on<InvoicesSearchChanged>((e, emit) => emit(state.copyWith(search: e.query)));
    on<InvoiceDeleted>((e, emit) async {
      try {
        await _repo.delete(e.id); // the bus then triggers a reload
      } catch (err) {
        emit(state.copyWith(error: ApiException.from(err).message));
      }
    });
    _sub = bus.on({DataTopic.invoices}).listen((_) => add(const InvoicesRequested()));
  }

  final InvoicesRepository _repo;
  final String type;
  late final StreamSubscription<void> _sub;

  Future<void> _load(Emitter<InvoicesState> emit) async {
    if (state.status == LoadStatus.initial) emit(state.copyWith(status: LoadStatus.loading));
    final range = state.range;
    try {
      final invoices = await _repo.list(type, from: range.from, to: range.to);
      if (state.range == range) emit(state.copyWith(status: LoadStatus.success, invoices: invoices));
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
