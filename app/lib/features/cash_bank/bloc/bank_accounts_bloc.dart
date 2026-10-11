import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/change_bus.dart';
import '../../../core/status.dart';
import '../../../data/models/cash_bank.dart';
import '../../../data/repositories/cash_bank_repository.dart';

sealed class BankAccountsEvent {
  const BankAccountsEvent();
}

class BankAccountsRequested extends BankAccountsEvent {
  const BankAccountsRequested();
}

class BankAccountSelected extends BankAccountsEvent {
  const BankAccountSelected(this.id);
  final String id;
}

class BankAccountsSearchChanged extends BankAccountsEvent {
  const BankAccountsSearchChanged(this.query);
  final String query;
}

class BankAccountDeleted extends BankAccountsEvent {
  const BankAccountDeleted(this.id);
  final String id;
}

class BankAdjustmentDeleted extends BankAccountsEvent {
  const BankAdjustmentDeleted(this.id);
  final String id;
}

class BankAccountsState extends Equatable {
  const BankAccountsState({
    this.status = LoadStatus.initial,
    this.accounts = const [],
    this.search = '',
    this.selectedId,
    this.txnStatus = LoadStatus.initial,
    this.txns = const [],
    this.error,
  });

  final LoadStatus status;
  final List<BankAccount> accounts;
  final String search;
  final String? selectedId;
  final LoadStatus txnStatus;
  final List<MoneyTxn> txns;

  /// Set when a load or delete fails; shown once by the screen.
  final String? error;

  BankAccount? get selected => accounts.where((a) => a.id == selectedId).firstOrNull;

  List<BankAccount> get visible {
    final term = search.trim().toLowerCase();
    return term.isEmpty ? accounts : accounts.where((a) => a.name.toLowerCase().contains(term)).toList();
  }

  BankAccountsState copyWith({
    LoadStatus? status,
    List<BankAccount>? accounts,
    String? search,
    String? Function()? selectedId,
    LoadStatus? txnStatus,
    List<MoneyTxn>? txns,
    String? error,
  }) =>
      BankAccountsState(
        status: status ?? this.status,
        accounts: accounts ?? this.accounts,
        search: search ?? this.search,
        selectedId: selectedId != null ? selectedId() : this.selectedId,
        txnStatus: txnStatus ?? this.txnStatus,
        txns: txns ?? this.txns,
        error: error,
      );

  @override
  List<Object?> get props => [status, accounts, search, selectedId, txnStatus, txns, error];
}

/// Bank accounts with balances, the selected account and its transactions.
class BankAccountsBloc extends Bloc<BankAccountsEvent, BankAccountsState> {
  BankAccountsBloc(this._repo, ChangeBus bus) : super(const BankAccountsState()) {
    on<BankAccountsRequested>((_, emit) => _load(emit));
    on<BankAccountsSearchChanged>((e, emit) => emit(state.copyWith(search: e.query)));
    on<BankAccountSelected>((e, emit) async {
      emit(state.copyWith(selectedId: () => e.id, txnStatus: LoadStatus.loading, txns: const []));
      await _loadTxns(emit);
    });
    // Deletes go through the repository; the bus then triggers a reload.
    on<BankAccountDeleted>((e, emit) => _guard(emit, () => _repo.deleteAccount(e.id)));
    on<BankAdjustmentDeleted>((e, emit) => _guard(emit, () => _repo.deleteAdjustment(e.id)));
    _sub = bus.on({DataTopic.accounts}).listen((_) => add(const BankAccountsRequested()));
  }

  final CashBankRepository _repo;
  late final StreamSubscription<void> _sub;

  Future<void> _guard(Emitter<BankAccountsState> emit, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      emit(state.copyWith(error: ApiException.from(e).message));
    }
  }

  Future<void> _load(Emitter<BankAccountsState> emit) async {
    if (state.status == LoadStatus.initial) emit(state.copyWith(status: LoadStatus.loading));
    try {
      final accounts = await _repo.accounts();
      final keep = accounts.any((a) => a.id == state.selectedId);
      emit(state.copyWith(status: LoadStatus.success, accounts: accounts, selectedId: () => keep ? state.selectedId : accounts.firstOrNull?.id));
      await _loadTxns(emit);
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> _loadTxns(Emitter<BankAccountsState> emit) async {
    final id = state.selectedId;
    if (id == null) return emit(state.copyWith(txnStatus: LoadStatus.success, txns: const []));
    try {
      final txns = await _repo.accountTransactions(id);
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
