import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/change_bus.dart';
import '../../../core/status.dart';
import '../../../data/models/party.dart';
import '../../../data/repositories/parties_repository.dart';

sealed class PartiesEvent {
  const PartiesEvent();
}

class PartiesRequested extends PartiesEvent {
  const PartiesRequested();
}

class PartiesSearchChanged extends PartiesEvent {
  const PartiesSearchChanged(this.query);
  final String query;
}

class PartySelected extends PartiesEvent {
  const PartySelected(this.id);
  final String id;
}

class _PartiesChanged extends PartiesEvent {
  const _PartiesChanged();
}

class PartiesState extends Equatable {
  const PartiesState({
    this.status = LoadStatus.initial,
    this.parties = const [],
    this.search = '',
    this.selectedId,
    this.txnStatus = LoadStatus.initial,
    this.txns = const [],
    this.error,
  });

  final LoadStatus status;
  final List<Party> parties;
  final String search;
  final String? selectedId;
  final LoadStatus txnStatus;
  final List<PartyTxn> txns;
  final String? error;

  Party? get selected => parties.where((p) => p.id == selectedId).firstOrNull;

  List<Party> get visible {
    final term = search.trim().toLowerCase();
    if (term.isEmpty) return parties;
    return parties.where((p) => p.name.toLowerCase().contains(term) || (p.phone ?? '').contains(term)).toList();
  }

  PartiesState copyWith({
    LoadStatus? status,
    List<Party>? parties,
    String? search,
    String? Function()? selectedId,
    LoadStatus? txnStatus,
    List<PartyTxn>? txns,
    String? error,
  }) =>
      PartiesState(
        status: status ?? this.status,
        parties: parties ?? this.parties,
        search: search ?? this.search,
        selectedId: selectedId != null ? selectedId() : this.selectedId,
        txnStatus: txnStatus ?? this.txnStatus,
        txns: txns ?? this.txns,
        error: error,
      );

  @override
  List<Object?> get props => [status, parties, search, selectedId, txnStatus, txns, error];
}

/// Party list, current selection and the selected party's ledger. Reloads when parties, invoices or payments change.
class PartiesBloc extends Bloc<PartiesEvent, PartiesState> {
  /// [openId] is the party to show first (e.g. one picked in quick search).
  PartiesBloc(this._repo, ChangeBus bus, {String? openId}) : super(PartiesState(selectedId: openId)) {
    on<PartiesRequested>((_, emit) => _load(emit));
    on<_PartiesChanged>((_, emit) => _load(emit));
    on<PartiesSearchChanged>((e, emit) => emit(state.copyWith(search: e.query)));
    on<PartySelected>((e, emit) async {
      if (e.id == state.selectedId && state.txnStatus == LoadStatus.success) return;
      emit(state.copyWith(selectedId: () => e.id, txnStatus: LoadStatus.loading, txns: const []));
      await _loadTxns(emit);
    });
    _sub = bus.on({DataTopic.parties, DataTopic.invoices, DataTopic.payments}).listen((_) => add(const _PartiesChanged()));
  }

  final PartiesRepository _repo;
  late final StreamSubscription<void> _sub;

  Future<void> _load(Emitter<PartiesState> emit) async {
    if (state.parties.isEmpty) emit(state.copyWith(status: LoadStatus.loading));
    try {
      final parties = await _repo.list();
      // Keep the selection if it still exists, otherwise select the first party.
      final keep = parties.any((p) => p.id == state.selectedId);
      final selectedId = keep ? state.selectedId : parties.firstOrNull?.id;
      emit(state.copyWith(status: LoadStatus.success, parties: parties, selectedId: () => selectedId));
      await _loadTxns(emit);
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> _loadTxns(Emitter<PartiesState> emit) async {
    final id = state.selectedId;
    if (id == null) return emit(state.copyWith(txnStatus: LoadStatus.success, txns: const []));
    try {
      final txns = await _repo.transactions(id);
      if (state.selectedId == id) emit(state.copyWith(txnStatus: LoadStatus.success, txns: txns));
    } catch (e) {
      emit(state.copyWith(txnStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
