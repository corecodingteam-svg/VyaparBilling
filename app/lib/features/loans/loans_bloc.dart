import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../../core/status.dart';
import '../../data/models/cash_bank.dart';
import '../../data/models/loan.dart';
import '../../data/repositories/cash_bank_repository.dart';
import '../../data/repositories/loans_repository.dart';
import '../../shared/format.dart';

sealed class LoansEvent {
  const LoansEvent();
}

class LoansRequested extends LoansEvent {
  const LoansRequested();
}

class LoanSelected extends LoansEvent {
  const LoanSelected(this.id);
  final String id;
}

class LoanDeleted extends LoansEvent {
  const LoanDeleted(this.id);
  final String id;
}

class LoanTxnDeleted extends LoansEvent {
  const LoanTxnDeleted(this.id);
  final String id;
}

class LoansState extends Equatable {
  const LoansState({
    this.status = LoadStatus.initial,
    this.loans = const [],
    this.selectedId,
    this.txnStatus = LoadStatus.initial,
    this.txns = const [],
    this.error,
  });

  final LoadStatus status;
  final List<LoanAccount> loans;
  final String? selectedId;
  final LoadStatus txnStatus;
  final List<LoanTxn> txns;

  /// Set when a load or delete fails; shown once by the screen.
  final String? error;

  LoanAccount? get selected => loans.where((l) => l.id == selectedId).firstOrNull;
  num get totalOutstanding => loans.fold<num>(0, (s, l) => s + l.balance);

  LoansState copyWith({
    LoadStatus? status,
    List<LoanAccount>? loans,
    String? Function()? selectedId,
    LoadStatus? txnStatus,
    List<LoanTxn>? txns,
    String? error,
  }) =>
      LoansState(
        status: status ?? this.status,
        loans: loans ?? this.loans,
        selectedId: selectedId != null ? selectedId() : this.selectedId,
        txnStatus: txnStatus ?? this.txnStatus,
        txns: txns ?? this.txns,
        error: error,
      );

  @override
  List<Object?> get props => [status, loans, selectedId, txnStatus, txns, error];
}

/// Loan accounts with outstanding balances, the selected loan and its transactions.
class LoansBloc extends Bloc<LoansEvent, LoansState> {
  LoansBloc(this._repo, ChangeBus bus) : super(const LoansState()) {
    on<LoansRequested>((_, emit) => _load(emit));
    on<LoanSelected>((e, emit) async {
      emit(state.copyWith(selectedId: () => e.id, txnStatus: LoadStatus.loading, txns: const []));
      await _loadTxns(emit);
    });
    // Deletes go through the repository; the bus then triggers a reload.
    on<LoanDeleted>((e, emit) => _guard(emit, () => _repo.delete(e.id)));
    on<LoanTxnDeleted>((e, emit) => _guard(emit, () => _repo.deleteTransaction(e.id)));
    _sub = bus.on({DataTopic.loans}).listen((_) => add(const LoansRequested()));
  }

  final LoansRepository _repo;
  late final StreamSubscription<void> _sub;

  Future<void> _guard(Emitter<LoansState> emit, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      emit(state.copyWith(error: ApiException.from(e).message));
    }
  }

  Future<void> _load(Emitter<LoansState> emit) async {
    if (state.status == LoadStatus.initial) emit(state.copyWith(status: LoadStatus.loading));
    try {
      final loans = await _repo.list();
      final keep = loans.any((l) => l.id == state.selectedId);
      emit(state.copyWith(status: LoadStatus.success, loans: loans, selectedId: () => keep ? state.selectedId : loans.firstOrNull?.id));
      await _loadTxns(emit);
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> _loadTxns(Emitter<LoansState> emit) async {
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

// ---------------------------------------------------------------- forms

/// Non-text state shared by the loan-account and loan-transaction dialogs: a date, and whether
/// the money moves through cash or a bank account.
class LoanFormState extends Equatable {
  const LoanFormState({
    required this.date,
    this.kind = 'payment',
    this.accounts = const [],
    this.bankAccountId,
    this.status = SubmitStatus.idle,
    this.error,
  });

  final String date;

  /// Transaction dialog only: payment | increase | charge.
  final String kind;
  final List<BankAccount> accounts;

  /// null = cash.
  final String? bankAccountId;
  final SubmitStatus status;
  final String? error;

  LoanFormState copyWith({
    String? date,
    String? kind,
    List<BankAccount>? accounts,
    String? Function()? bankAccountId,
    SubmitStatus? status,
    String? error,
  }) =>
      LoanFormState(
        date: date ?? this.date,
        kind: kind ?? this.kind,
        accounts: accounts ?? this.accounts,
        bankAccountId: bankAccountId != null ? bankAccountId() : this.bankAccountId,
        status: status ?? this.status,
        error: error,
      );

  @override
  List<Object?> get props => [date, kind, accounts, bankAccountId, status, error];
}

class LoanFormCubit extends Cubit<LoanFormState> {
  LoanFormCubit(this._loans, this._accounts, {this.loan, this.txn, String kind = 'payment'})
      : super(LoanFormState(
          date: txn?.date ?? loan?.balanceDate ?? isoDate(DateTime.now()),
          kind: txn?.kind ?? kind,
          bankAccountId: txn != null ? txn.bankAccountId : loan?.bankAccountId,
        ));

  /// For the transaction dialog: the entry being edited, if any.
  final LoanTxn? txn;

  /// For the account dialog: the loan being edited. For the transaction dialog: unused.
  final LoanAccount? loan;
  final LoansRepository _loans;
  final CashBankRepository _accounts;

  Future<void> load() async {
    try {
      final accounts = await _accounts.accounts();
      emit(state.copyWith(accounts: accounts));
    } catch (_) {
      // Without the list the money simply defaults to cash.
    }
  }

  void dateChanged(String v) => emit(state.copyWith(date: v));
  void bankAccountChanged(String? id) => emit(state.copyWith(bankAccountId: () => id));

  Future<void> _submit(Future<void> Function() action) async {
    if (state.status == SubmitStatus.submitting) return;
    emit(state.copyWith(status: SubmitStatus.submitting));
    try {
      await action();
      emit(state.copyWith(status: SubmitStatus.success));
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> saveAccount(Map<String, dynamic> fields) =>
      _submit(() => _loans.save(loan?.id, {...fields, 'balanceDate': state.date, 'bankAccountId': state.bankAccountId}));

  Future<void> saveTransaction(String loanId, {required num principal, num interest = 0, required String description}) {
    final body = {
      'kind': state.kind,
      'principal': principal,
      if (state.kind == 'payment') 'interest': interest,
      'date': state.date,
      'bankAccountId': state.kind == 'charge' ? null : state.bankAccountId,
      'description': description.trim(),
    };
    return _submit(() => txn?.id == null ? _loans.addTransaction(loanId, body) : _loans.updateTransaction(txn!.id!, body));
  }
}
