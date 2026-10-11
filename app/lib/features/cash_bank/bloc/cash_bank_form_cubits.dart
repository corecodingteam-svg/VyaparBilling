import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/status.dart';
import '../../../data/models/cash_bank.dart';
import '../../../data/repositories/cash_bank_repository.dart';
import '../../../shared/format.dart';

// ---------------------------------------------------------------- bank account form

class BankAccountFormState extends Equatable {
  const BankAccountFormState({required this.openingDate, required this.showMore, this.status = SubmitStatus.idle, this.error});
  final String openingDate;

  /// Whether the optional account number / IFSC / UPI fields are shown.
  final bool showMore;
  final SubmitStatus status;
  final String? error;

  BankAccountFormState copyWith({String? openingDate, bool? showMore, SubmitStatus? status, String? error}) => BankAccountFormState(
        openingDate: openingDate ?? this.openingDate,
        showMore: showMore ?? this.showMore,
        status: status ?? this.status,
        error: error,
      );

  @override
  List<Object?> get props => [openingDate, showMore, status, error];
}

class BankAccountFormCubit extends Cubit<BankAccountFormState> {
  BankAccountFormCubit(this._repo, this.account)
      : super(BankAccountFormState(
          openingDate: account?.openingDate ?? isoDate(DateTime.now()),
          showMore: account?.hasDetails ?? false,
        ));

  final CashBankRepository _repo;
  final BankAccount? account;

  bool get editing => account != null;

  void openingDateChanged(String v) => emit(state.copyWith(openingDate: v));
  void showMoreFields() => emit(state.copyWith(showMore: true));

  Future<void> save(Map<String, dynamic> fields) async {
    if (state.status == SubmitStatus.submitting) return;
    emit(state.copyWith(status: SubmitStatus.submitting));
    try {
      await _repo.saveAccount(account?.id, {...fields, 'openingDate': state.openingDate});
      emit(state.copyWith(status: SubmitStatus.success));
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}

// ---------------------------------------------------------------- adjustments & transfers

class AdjustmentFormState extends Equatable {
  const AdjustmentFormState({
    required this.kind,
    required this.date,
    this.accounts = const [],
    this.bankAccountId,
    this.toBankAccountId,
    this.initialAmount = '',
    this.initialDescription = '',
    this.loadStatus = LoadStatus.loading,
    this.status = SubmitStatus.idle,
    this.error,
  });

  final String kind;
  final String date;
  final List<BankAccount> accounts;
  final String? bankAccountId;
  final String? toBankAccountId;

  /// Editing: the stored amount and description, put into the text inputs once loaded.
  final String initialAmount;
  final String initialDescription;
  final LoadStatus loadStatus;
  final SubmitStatus status;
  final String? error;

  bool get needsBank => kind != 'cash_add' && kind != 'cash_reduce';
  bool get isTransfer => kind == 'bank_to_bank';

  AdjustmentFormState copyWith({
    String? kind,
    String? date,
    List<BankAccount>? accounts,
    String? Function()? bankAccountId,
    String? Function()? toBankAccountId,
    String? initialAmount,
    String? initialDescription,
    LoadStatus? loadStatus,
    SubmitStatus? status,
    String? error,
  }) =>
      AdjustmentFormState(
        kind: kind ?? this.kind,
        date: date ?? this.date,
        accounts: accounts ?? this.accounts,
        bankAccountId: bankAccountId != null ? bankAccountId() : this.bankAccountId,
        toBankAccountId: toBankAccountId != null ? toBankAccountId() : this.toBankAccountId,
        initialAmount: initialAmount ?? this.initialAmount,
        initialDescription: initialDescription ?? this.initialDescription,
        loadStatus: loadStatus ?? this.loadStatus,
        status: status ?? this.status,
        error: error,
      );

  @override
  List<Object?> get props => [kind, date, accounts, bankAccountId, toBankAccountId, initialAmount, initialDescription, loadStatus, status, error];
}

/// Cash adjustments, bank adjustments and transfers between cash and banks.
class AdjustmentFormCubit extends Cubit<AdjustmentFormState> {
  AdjustmentFormCubit(this._repo, {required this.kinds, String? bankAccountId, this.editId})
      : super(AdjustmentFormState(kind: kinds.first, date: isoDate(DateTime.now()), bankAccountId: bankAccountId));

  final CashBankRepository _repo;

  /// The kinds offered by this dialog (cash screen: add/reduce; bank screen: transfers and bank adjustments).
  final List<String> kinds;

  /// The adjustment being changed; null when adding one.
  final String? editId;

  bool get editing => editId != null;

  Future<void> load() async {
    try {
      // Await first: the user's choices made while loading (e.g. the kind picked from the menu) must survive.
      final accounts = await _repo.accounts();
      if (editing) {
        final a = await _repo.adjustment(editId!);
        emit(state.copyWith(
          loadStatus: LoadStatus.success,
          accounts: accounts,
          kind: a['kind'] as String,
          date: a['date'] as String,
          bankAccountId: () => a['bankAccountId'] as String?,
          toBankAccountId: () => a['toBankAccountId'] as String?,
          initialAmount: numText(a['amount'] as num?),
          initialDescription: (a['description'] as String?) ?? '',
        ));
        return;
      }
      emit(state.copyWith(loadStatus: LoadStatus.success, accounts: accounts));
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  void kindChanged(String v) => emit(state.copyWith(kind: v));
  void dateChanged(String v) => emit(state.copyWith(date: v));
  void bankAccountChanged(String? v) => emit(state.copyWith(bankAccountId: () => v));
  void toBankAccountChanged(String? v) => emit(state.copyWith(toBankAccountId: () => v));

  Future<void> submit({required num amount, required String description}) async {
    if (state.status == SubmitStatus.submitting) return;
    final s = state;
    String? problem;
    if (s.needsBank && s.bankAccountId == null) problem = 'Select a bank account.';
    if (s.isTransfer && s.toBankAccountId == null) problem = 'Select the account to transfer to.';
    if (s.isTransfer && s.toBankAccountId != null && s.toBankAccountId == s.bankAccountId) problem = 'Choose two different accounts.';
    if (problem != null) {
      emit(s.copyWith(status: SubmitStatus.failure, error: problem));
      return;
    }
    emit(s.copyWith(status: SubmitStatus.submitting));
    try {
      final body = {
        'kind': s.kind,
        'bankAccountId': s.needsBank ? s.bankAccountId : null,
        'toBankAccountId': s.isTransfer ? s.toBankAccountId : null,
        'amount': amount,
        'date': s.date,
        'description': description.trim(),
      };
      editing ? await _repo.updateAdjustment(editId!, body) : await _repo.createAdjustment(body);
      emit(state.copyWith(status: SubmitStatus.success));
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}
