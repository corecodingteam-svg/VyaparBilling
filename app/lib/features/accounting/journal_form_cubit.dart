import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/status.dart';
import '../../data/models/accounting.dart';
import '../../data/models/cash_bank.dart';
import '../../data/repositories/accounting_repository.dart';
import '../../data/repositories/cash_bank_repository.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';

num _r2(num v) => (v * 100).round() / 100;

/// One editable journal line. [account] is 'cash', a bank account ('bank:' + its id) or a ledger account ('ledger:' + its id).
class JournalLineDraft extends Equatable {
  const JournalLineDraft({required this.uid, this.account, this.debit = '', this.credit = '', this.rev = 0});
  final int uid;
  final String? account;
  final String debit;
  final String credit;

  /// Bumped when one side is cleared because the other was typed, so its input shows the change.
  final int rev;

  bool get isBlank => account == null && debit.trim().isEmpty && credit.trim().isEmpty;

  JournalLineDraft copyWith({String? Function()? account, String? debit, String? credit, int? rev}) => JournalLineDraft(
        uid: uid,
        account: account != null ? account() : this.account,
        debit: debit ?? this.debit,
        credit: credit ?? this.credit,
        rev: rev ?? this.rev,
      );

  @override
  List<Object?> get props => [uid, account, debit, credit, rev];
}

class JournalFormState extends Equatable {
  const JournalFormState({
    this.loadStatus = LoadStatus.loading,
    this.ledgerAccounts = const [],
    this.bankAccounts = const [],
    this.number = '',
    required this.date,
    this.description = '',
    this.lines = const [],
    this.formRev = 0,
    this.status = SubmitStatus.idle,
    this.error,
    this.issue,
  });

  final LoadStatus loadStatus;
  final List<LedgerAccount> ledgerAccounts;
  final List<BankAccount> bankAccounts;
  final String number;
  final String date;
  final String description;
  final List<JournalLineDraft> lines;

  /// Bumped once the entry has loaded so the text inputs show it.
  final int formRev;
  final SubmitStatus status;
  final String? error;

  /// Which part of the form [error] is about, so the screen can outline it.
  final FormIssue? issue;

  num get debitTotal => _r2(lines.fold<num>(0, (s, l) => s + (parseNum(l.debit) ?? 0)));
  num get creditTotal => _r2(lines.fold<num>(0, (s, l) => s + (parseNum(l.credit) ?? 0)));
  num get difference => _r2(debitTotal - creditTotal);

  /// Every account a line can be posted to, as (key, label).
  List<(String, String)> get accountOptions => [
        ('cash', 'Cash in hand'),
        for (final b in bankAccounts) ('bank:${b.id}', 'Bank: ${b.name}'),
        for (final a in ledgerAccounts) ('ledger:${a.id}', '${a.name}  (${ledgerTypes[a.type] ?? a.type})'),
      ];

  JournalFormState copyWith({
    LoadStatus? loadStatus,
    List<LedgerAccount>? ledgerAccounts,
    List<BankAccount>? bankAccounts,
    String? number,
    String? date,
    String? description,
    List<JournalLineDraft>? lines,
    int? formRev,
    SubmitStatus? status,
    String? error,
    FormIssue? issue,
  }) =>
      JournalFormState(
        loadStatus: loadStatus ?? this.loadStatus,
        ledgerAccounts: ledgerAccounts ?? this.ledgerAccounts,
        bankAccounts: bankAccounts ?? this.bankAccounts,
        number: number ?? this.number,
        date: date ?? this.date,
        description: description ?? this.description,
        lines: lines ?? this.lines,
        formRev: formRev ?? this.formRev,
        status: status ?? this.status,
        error: error,
        issue: issue,
      );

  @override
  List<Object?> get props => [loadStatus, ledgerAccounts, bankAccounts, number, date, description, lines, formRev, status, error, issue];
}

/// State and rules of the journal entry dialog: at least two lines, each on one account and one
/// side, with debits equal to credits.
class JournalFormCubit extends Cubit<JournalFormState> {
  JournalFormCubit(this._repo, this._accounts, {this.entryId}) : super(JournalFormState(date: isoDate(DateTime.now())));

  final AccountingRepository _repo;
  final CashBankRepository _accounts;
  final String? entryId;
  int _nextUid = 0;

  bool get editing => entryId != null;

  JournalLineDraft _blank() => JournalLineDraft(uid: _nextUid++);

  Future<void> load() async {
    try {
      final (ledger, banks) = await (_repo.ledgerAccounts(), _accounts.accounts()).wait;
      if (editing) {
        final e = await _repo.journal(entryId!);
        emit(state.copyWith(
          loadStatus: LoadStatus.success,
          ledgerAccounts: ledger,
          bankAccounts: banks,
          number: e.number,
          date: e.date,
          description: e.description ?? '',
          lines: [
            for (final l in e.lines)
              JournalLineDraft(
                uid: _nextUid++,
                account: l.ledgerAccountId != null ? 'ledger:${l.ledgerAccountId}' : (l.moneyAccount == 'bank' ? 'bank:${l.bankAccountId}' : 'cash'),
                debit: l.debit == 0 ? '' : numText(l.debit),
                credit: l.credit == 0 ? '' : numText(l.credit),
              ),
          ],
          formRev: state.formRev + 1,
        ));
      } else {
        final number = await _repo.nextJournalNumber();
        emit(state.copyWith(
          loadStatus: LoadStatus.success,
          ledgerAccounts: ledger,
          bankAccounts: banks,
          number: number,
          lines: [_blank(), _blank()],
          formRev: state.formRev + 1,
        ));
      }
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  void numberChanged(String v) => emit(state.copyWith(number: v));
  void dateChanged(String v) => emit(state.copyWith(date: v));
  void descriptionChanged(String v) => emit(state.copyWith(description: v));

  void _update(int uid, JournalLineDraft Function(JournalLineDraft) change) =>
      emit(state.copyWith(lines: [for (final l in state.lines) l.uid == uid ? change(l) : l]));

  void addLine() => emit(state.copyWith(lines: [...state.lines, _blank()]));
  void removeLine(int uid) {
    final rest = state.lines.where((l) => l.uid != uid).toList();
    emit(state.copyWith(lines: rest.length < 2 ? [...rest, _blank()] : rest));
  }

  void accountChanged(int uid, String? account) => _update(uid, (l) => l.copyWith(account: () => account));

  /// A line is either a debit or a credit: typing one side clears the other.
  void debitChanged(int uid, String v) =>
      _update(uid, (l) => l.credit.isEmpty || v.trim().isEmpty ? l.copyWith(debit: v) : l.copyWith(debit: v, credit: '', rev: l.rev + 1));
  void creditChanged(int uid, String v) =>
      _update(uid, (l) => l.debit.isEmpty || v.trim().isEmpty ? l.copyWith(credit: v) : l.copyWith(credit: v, debit: '', rev: l.rev + 1));

  /// Returns a message for the first problem, or null when the entry can be saved.
  /// The first problem and which part of the form it is about, or null when the form can be saved.
  FormIssue? firstIssue() {
    final s = state;
    if (s.number.trim().isEmpty) return FormIssue('number', 'Enter the journal number.');
    final filled = s.lines.where((l) => !l.isBlank).toList();
    if (filled.length < 2) return FormIssue('lines', 'A journal entry needs at least two lines.');
    for (final l in filled) {
      final row = s.lines.indexOf(l) + 1;
      if (l.account == null) return FormIssue('line:${l.uid}', 'Line $row: select an account.');
      final debit = parseNum(l.debit) ?? 0;
      final credit = parseNum(l.credit) ?? 0;
      if ((l.debit.trim().isNotEmpty && parseNum(l.debit) == null) || (l.credit.trim().isNotEmpty && parseNum(l.credit) == null)) {
        return FormIssue('line:${l.uid}', 'Line $row: enter a valid amount.');
      }
      if ((debit > 0) == (credit > 0)) return FormIssue('line:${l.uid}', 'Line $row: enter either a debit or a credit amount.');
    }
    if (s.difference != 0) return FormIssue('totals', 'Debits (${money(s.debitTotal)}) and credits (${money(s.creditTotal)}) must be equal.');
    return null;
  }

  /// The message for the first problem, or null when the form can be saved.
  String? validate() => firstIssue()?.message;


  Future<void> save() async {
    if (state.status == SubmitStatus.submitting) return;
    final issue = firstIssue();
    final problem = issue?.message;
    if (issue != null) {
      emit(state.copyWith(status: SubmitStatus.failure, error: problem, issue: issue));
      return;
    }
    emit(state.copyWith(status: SubmitStatus.submitting));
    final s = state;
    try {
      await _repo.saveJournal(entryId, {
        'number': s.number.trim(),
        'date': s.date,
        'description': s.description.trim(),
        'lines': [
          for (final l in s.lines.where((l) => !l.isBlank))
            {
              if (l.account!.startsWith('ledger:')) 'ledgerAccountId': l.account!.substring(7),
              if (l.account == 'cash') 'moneyAccount': 'cash',
              if (l.account!.startsWith('bank:')) ...{'moneyAccount': 'bank', 'bankAccountId': l.account!.substring(5)},
              if ((parseNum(l.debit) ?? 0) > 0) 'debit': parseNum(l.debit) else 'credit': parseNum(l.credit),
            },
        ],
      });
      emit(state.copyWith(status: SubmitStatus.success));
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}
