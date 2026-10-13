import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/status.dart';
import '../../data/models/tax_statement.dart';
import '../../data/repositories/tax_statements_repository.dart';

class TaxStatementsState extends Equatable {
  const TaxStatementsState({
    required this.form,
    required this.taxYear,
    required this.quarter,
    this.status = LoadStatus.loading,
    this.statement,
    this.challans = const [],
    this.deductor = const Deductor(),
    this.tdsSections = const {},
    this.tcsCodes = const {},
    this.busy = false,
    this.message,
    this.error,
    this.rev = 0,
  });

  /// '140' (TDS, formerly 26Q) or '143' (TCS, formerly 27EQ).
  final String form;
  final String taxYear;
  final String quarter;
  final LoadStatus status;
  final TaxStatement? statement;
  final List<TaxChallan> challans;
  final Deductor deductor;
  final Map<String, String> tdsSections;
  final Map<String, String> tcsCodes;
  final bool busy;

  /// What just happened, shown once; [rev] changes with each.
  final String? message;
  final String? error;
  final int rev;

  String get kind => form == '140' ? 'tds' : 'tcs';

  TaxStatementsState copyWith({
    String? form,
    String? taxYear,
    String? quarter,
    LoadStatus? status,
    TaxStatement? statement,
    List<TaxChallan>? challans,
    Deductor? deductor,
    Map<String, String>? tdsSections,
    Map<String, String>? tcsCodes,
    bool? busy,
    String? message,
    String? error,
    bool bump = false,
  }) => TaxStatementsState(
    form: form ?? this.form,
    taxYear: taxYear ?? this.taxYear,
    quarter: quarter ?? this.quarter,
    status: status ?? this.status,
    statement: statement ?? this.statement,
    challans: challans ?? this.challans,
    deductor: deductor ?? this.deductor,
    tdsSections: tdsSections ?? this.tdsSections,
    tcsCodes: tcsCodes ?? this.tcsCodes,
    busy: busy ?? this.busy,
    message: message,
    error: error,
    rev: bump ? rev + 1 : rev,
  );

  @override
  List<Object?> get props => [form, taxYear, quarter, status, statement, challans, deductor, tdsSections, tcsCodes, busy, message, error, rev];
}

/// The quarterly TDS / TCS statement screen: pick the form and quarter, record challans, and download the file.
class TaxStatementsCubit extends Cubit<TaxStatementsState> {
  TaxStatementsCubit(this._repo, {DateTime? now})
    : super(() {
        // The statement usually due next is for the quarter that has just ended.
        final d = (now ?? DateTime.now()).subtract(const Duration(days: 92));
        return TaxStatementsState(form: '140', taxYear: taxYearOf(d), quarter: quarterOfDate(d));
      }());

  final TaxStatementsRepository _repo;

  Future<void> load() async {
    try {
      final ((tds, tcs), deductor) = await (_repo.codes(), _repo.deductor()).wait;
      emit(state.copyWith(tdsSections: tds, tcsCodes: tcs, deductor: deductor));
      await _refresh();
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> _refresh() async {
    final (statement, challans) = await (_repo.statement(state.form, state.taxYear, state.quarter), _repo.challans(state.kind, state.taxYear, state.quarter)).wait;
    if (!isClosed) emit(state.copyWith(status: LoadStatus.success, statement: statement, challans: challans));
  }

  Future<void> _act(Future<void> Function() action, {String? done}) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      await action();
      await _refresh();
      emit(state.copyWith(busy: false, message: done, bump: done != null));
    } catch (e) {
      emit(state.copyWith(busy: false, error: ApiException.from(e).message, bump: true));
    }
  }

  Future<void> periodChanged({String? form, String? taxYear, String? quarter}) {
    emit(state.copyWith(form: form, taxYear: taxYear, quarter: quarter, status: LoadStatus.loading));
    return _act(() async {});
  }

  Future<void> addChallan({required String bsrCode, required String challanNo, required String depositDate, required num tax, num interest = 0, num fee = 0, num other = 0}) => _act(
    () => _repo.addChallan(
      kind: state.kind,
      taxYear: state.taxYear,
      quarter: state.quarter,
      bsrCode: bsrCode,
      challanNo: challanNo,
      depositDate: depositDate,
      tax: tax,
      interest: interest,
      fee: fee,
      other: other,
    ),
    done: 'Challan added',
  );

  Future<void> removeChallan(String id) => _act(() => _repo.removeChallan(id), done: 'Challan removed');

  Future<void> saveDeductor(Deductor d) => _act(() async {
    await _repo.saveDeductor(d);
    emit(state.copyWith(deductor: d));
  }, done: 'Saved');

  /// Downloads go through [save]; failures are reported like any other.
  Future<void> download(Future<void> Function() save, String done) => _act(save, done: done);
}
