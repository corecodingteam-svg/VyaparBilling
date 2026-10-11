import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/change_bus.dart';
import '../../../core/status.dart';
import '../../../data/models/cash_bank.dart';
import '../../../data/repositories/cash_bank_repository.dart';

class MoneyListState extends Equatable {
  const MoneyListState({this.status = LoadStatus.initial, this.balance = 0, this.txns = const [], this.accounts = const [], this.error});

  final LoadStatus status;

  /// Cash list only: cash in hand.
  final num balance;
  final List<MoneyTxn> txns;

  /// Cheque list only: accounts a cheque can be deposited into.
  final List<BankAccount> accounts;

  /// Set when a load or action fails; shown once by the screen.
  final String? error;

  MoneyListState copyWith({LoadStatus? status, num? balance, List<MoneyTxn>? txns, List<BankAccount>? accounts, String? error}) => MoneyListState(
        status: status ?? this.status,
        balance: balance ?? this.balance,
        txns: txns ?? this.txns,
        accounts: accounts ?? this.accounts,
        error: error,
      );

  @override
  List<Object?> get props => [status, balance, txns, accounts, error];
}

/// A flat list of money movements that reloads when any account changes.
abstract class _MoneyListCubit extends Cubit<MoneyListState> {
  _MoneyListCubit(this.repo, ChangeBus bus) : super(const MoneyListState()) {
    _sub = bus.on({DataTopic.accounts}).listen((_) => load());
  }

  final CashBankRepository repo;
  late final StreamSubscription<void> _sub;

  Future<MoneyListState> fetch();

  Future<void> load() async {
    if (state.status == LoadStatus.initial) emit(state.copyWith(status: LoadStatus.loading));
    try {
      final next = await fetch();
      if (!isClosed) emit(next);
    } catch (e) {
      if (!isClosed) emit(state.copyWith(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  /// Runs a write; the repository's bus event then reloads the list.
  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      emit(state.copyWith(error: ApiException.from(e).message));
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}

/// Cash in hand: balance and every cash movement.
class CashCubit extends _MoneyListCubit {
  CashCubit(super.repo, super.bus);

  @override
  Future<MoneyListState> fetch() async {
    final (balance, txns) = await repo.cash();
    return MoneyListState(status: LoadStatus.success, balance: balance, txns: txns);
  }

  Future<void> deleteAdjustment(String id) => run(() => repo.deleteAdjustment(id));
}

/// Cheque payments and whether each has been deposited.
class ChequesCubit extends _MoneyListCubit {
  ChequesCubit(super.repo, super.bus);

  @override
  Future<MoneyListState> fetch() async {
    final (txns, accounts) = await (repo.cheques(), repo.accounts()).wait;
    return MoneyListState(status: LoadStatus.success, txns: txns, accounts: accounts);
  }

  Future<void> reopen(MoneyTxn cheque) => run(() => repo.reopenCheque(cheque));
}
