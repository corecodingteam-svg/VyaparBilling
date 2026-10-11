import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/status.dart';
import '../../data/models/app_user.dart';
import '../../data/models/extras.dart';
import '../../data/repositories/firm_repository.dart';
import '../../data/repositories/utilities_repository.dart';
import '../../shared/format.dart';

// ---------------------------------------------------------------- verify my data

class VerifyState extends Equatable {
  const VerifyState({this.status = LoadStatus.loading, this.checks = const [], this.fixing = false, this.fixed = 0, this.error});
  final LoadStatus status;
  final List<VerifyCheck> checks;
  final bool fixing;

  /// Bumped after each successful repair, so the screen can say so once.
  final int fixed;
  final String? error;

  bool get allOk => checks.every((c) => c.ok);
  bool get canFix => checks.any((c) => !c.ok && c.fixable);

  @override
  List<Object?> get props => [status, checks, fixing, fixed, error];
}

/// Checks the books for inconsistencies and repairs the ones that can be repaired safely.
class VerifyCubit extends Cubit<VerifyState> {
  VerifyCubit(this._repo) : super(const VerifyState());
  final UtilitiesRepository _repo;

  Future<void> check() async {
    emit(VerifyState(fixed: state.fixed));
    try {
      emit(VerifyState(status: LoadStatus.success, checks: await _repo.verify(), fixed: state.fixed));
    } catch (e) {
      emit(VerifyState(status: LoadStatus.failure, error: ApiException.from(e).message, fixed: state.fixed));
    }
  }

  Future<void> fix() async {
    if (state.fixing) return;
    emit(VerifyState(status: state.status, checks: state.checks, fixing: true, fixed: state.fixed));
    try {
      emit(VerifyState(status: LoadStatus.success, checks: await _repo.fix(), fixed: state.fixed + 1));
    } catch (e) {
      emit(VerifyState(status: LoadStatus.failure, error: ApiException.from(e).message, fixed: state.fixed));
    }
  }
}

// ---------------------------------------------------------------- close financial year

class CloseYearState extends Equatable {
  const CloseYearState({
    this.loadStatus = LoadStatus.loading,
    this.lockDate,
    required this.lockUpTo,
    required this.newYearStart,
    this.firmName = '',
    this.status = SubmitStatus.idle,
    this.message,
    this.created,
    this.error,
  });

  final LoadStatus loadStatus;

  /// The books are currently closed up to this day; null = open.
  final String? lockDate;

  /// The date picked for closing the books.
  final String lockUpTo;

  /// First day of the new company's books.
  final String newYearStart;
  final String firmName;
  final SubmitStatus status;

  /// What just succeeded, shown once.
  final String? message;

  /// The company created by "start a new year".
  final Company? created;
  final String? error;

  CloseYearState copyWith({
    LoadStatus? loadStatus,
    String? Function()? lockDate,
    String? lockUpTo,
    String? newYearStart,
    String? firmName,
    SubmitStatus? status,
    String? message,
    Company? created,
    String? error,
  }) =>
      CloseYearState(
        loadStatus: loadStatus ?? this.loadStatus,
        lockDate: lockDate != null ? lockDate() : this.lockDate,
        lockUpTo: lockUpTo ?? this.lockUpTo,
        newYearStart: newYearStart ?? this.newYearStart,
        firmName: firmName ?? this.firmName,
        status: status ?? this.status,
        message: message,
        created: created ?? this.created,
        error: error,
      );

  @override
  List<Object?> get props => [loadStatus, lockDate, lockUpTo, newYearStart, firmName, status, message, created, error];
}

/// The last day of the financial year (April–March) that ended most recently before [today].
String lastFinancialYearEnd(DateTime today) => isoDate(DateTime(today.month >= 4 ? today.year : today.year - 1, 3, 31));

/// "2026-27" for a financial year starting on [start].
String financialYearLabel(DateTime start) {
  final first = start.month >= 4 ? start.year : start.year - 1;
  return '$first-${((first + 1) % 100).toString().padLeft(2, '0')}';
}

class CloseYearCubit extends Cubit<CloseYearState> {
  CloseYearCubit(this._repo, this._firm, {DateTime? now})
      : super(CloseYearState(
          lockUpTo: lastFinancialYearEnd(now ?? DateTime.now()),
          newYearStart: isoDate(DateTime.parse(lastFinancialYearEnd(now ?? DateTime.now())).add(const Duration(days: 1))),
        ));

  final UtilitiesRepository _repo;
  final FirmRepository _firm;

  Future<void> load() async {
    try {
      final firm = await _firm.get();
      emit(state.copyWith(loadStatus: LoadStatus.success, lockDate: () => firm.booksLockDate, lockUpTo: firm.booksLockDate, firmName: firm.name));
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  void lockUpToChanged(String v) => emit(state.copyWith(lockUpTo: v));
  void newYearStartChanged(String v) => emit(state.copyWith(newYearStart: v));

  Future<void> _run(Future<CloseYearState> Function() action) async {
    if (state.status == SubmitStatus.submitting) return;
    emit(state.copyWith(status: SubmitStatus.submitting));
    try {
      emit(await action());
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> closeBooks() => _run(() async {
        final date = state.lockUpTo;
        await _repo.closeBooks(date);
        return state.copyWith(status: SubmitStatus.success, lockDate: () => date, message: 'Books closed up to ${displayDate(date)}');
      });

  Future<void> reopenBooks() => _run(() async {
        await _repo.closeBooks(null);
        return state.copyWith(status: SubmitStatus.success, lockDate: () => null, message: 'Books re-opened');
      });

  Future<void> startNewYear(String name) => _run(() async {
        final company = await _repo.startNewYear(name: name.trim(), startDate: state.newYearStart);
        return state.copyWith(status: SubmitStatus.success, created: company, message: '"${company.name}" is ready');
      });
}

// ---------------------------------------------------------------- backup

class BackupState extends Equatable {
  const BackupState({this.status = SubmitStatus.idle, this.fileName, this.bytes, this.summary, this.error});
  final SubmitStatus status;

  /// The backup just made, ready to be saved to a file.
  final String? fileName;
  final Uint8List? bytes;

  /// What it contains, e.g. "12 parties, 40 items, 310 invoices".
  final String? summary;
  final String? error;

  @override
  List<Object?> get props => [status, fileName, summary, error];
}

class BackupCubit extends Cubit<BackupState> {
  BackupCubit(this._repo) : super(const BackupState());
  final UtilitiesRepository _repo;

  /// Fetches everything in the company as one JSON file.
  Future<void> create(String firmName) async {
    if (state.status == SubmitStatus.submitting) return;
    emit(const BackupState(status: SubmitStatus.submitting));
    try {
      final backup = await _repo.backup();
      final tables = (backup['tables'] as Map?) ?? const {};
      int count(String t) => (tables[t] as List?)?.length ?? 0;
      final safeName = firmName.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
      emit(BackupState(
        status: SubmitStatus.success,
        fileName: '${safeName.isEmpty ? 'company' : safeName}-backup-${isoDate(DateTime.now())}.json',
        bytes: Uint8List.fromList(utf8.encode(jsonEncode(backup))),
        summary: '${count('parties')} parties, ${count('items')} items, ${count('invoices')} documents, ${count('payments')} payments, '
            '${count('expenses')} expenses, ${count('files')} files',
      ));
    } catch (e) {
      emit(BackupState(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}
