import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/status.dart';
import '../../data/models/report.dart';
import '../../data/models/item.dart';
import '../../data/repositories/cash_bank_repository.dart';
import '../../data/repositories/items_repository.dart';
import '../../data/repositories/parties_repository.dart';
import '../../data/repositories/reports_repository.dart';
import '../../shared/period.dart';

/// The list of available reports, for the reports index.
class ReportCatalogCubit extends Cubit<(LoadStatus, List<ReportDef>, String?)> {
  ReportCatalogCubit(this._repo) : super((LoadStatus.loading, const [], null));
  final ReportsRepository _repo;

  Future<void> load() async {
    emit((LoadStatus.loading, state.$2, null));
    try {
      emit((LoadStatus.success, await _repo.catalog(), null));
    } catch (e) {
      emit((LoadStatus.failure, const [], ApiException.from(e).message));
    }
  }
}

class ReportState extends Equatable {
  const ReportState({
    required this.range,
    this.def,
    this.status = LoadStatus.loading,
    this.data,
    this.options = const [],
    this.selectedId,
    this.error,
  });

  final ReportDef? def;
  final PeriodRange range;
  final LoadStatus status;
  final ReportData? data;

  /// Parties or bank accounts to choose from, as (id, name), for reports that need one.
  final List<(String, String)> options;
  final String? selectedId;
  final String? error;

  /// A party/bank report can only run once one is chosen.
  bool get awaitingSelection => def != null && def!.selectionRequired && selectedId == null;

  ReportState copyWith({
    ReportDef? def,
    PeriodRange? range,
    LoadStatus? status,
    ReportData? Function()? data,
    List<(String, String)>? options,
    String? Function()? selectedId,
    String? error,
  }) =>
      ReportState(
        def: def ?? this.def,
        range: range ?? this.range,
        status: status ?? this.status,
        data: data != null ? data() : this.data,
        options: options ?? this.options,
        selectedId: selectedId != null ? selectedId() : this.selectedId,
        error: error,
      );

  @override
  List<Object?> get props => [def, range, status, data, options, selectedId, error];
}

/// Runs one report and re-runs it when its filters change.
class ReportCubit extends Cubit<ReportState> {
  ReportCubit(this._reports, this._parties, this._accounts, this.reportId, {this._items}) : super(ReportState(range: PeriodRange.of(Period.thisMonth)));

  /// Only needed for reports about one item.
  final ItemsRepository? _items;

  final ReportsRepository _reports;
  final PartiesRepository _parties;
  final CashBankRepository _accounts;
  final String reportId;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading));
    try {
      final def = (await _reports.catalog()).firstWhere((r) => r.id == reportId, orElse: () => throw ApiException('Unknown report.'));
      var options = const <(String, String)>[];
      if (def.needsParty || def.optionalParty) options = [for (final p in await _parties.list()) (p.id, p.name)];
      if (def.needsItem) options = [for (final i in await _items?.list('product') ?? const <Item>[]) (i.id, i.name)];
      if (def.needsBank) options = [for (final a in await _accounts.accounts()) (a.id, a.name)];
      // With a single bank account there is nothing to choose.
      final selected = def.needsBank && options.length == 1 ? options.single.$1 : state.selectedId;
      emit(state.copyWith(def: def, options: options, selectedId: () => selected));
      await _run();
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  void rangeChanged(PeriodRange range) {
    emit(state.copyWith(range: range));
    _run();
  }

  void selectionChanged(String? id) {
    emit(state.copyWith(selectedId: () => id));
    _run();
  }

  Future<void> _run() async {
    final def = state.def;
    if (def == null) return;
    if (state.awaitingSelection) {
      emit(state.copyWith(status: LoadStatus.success, data: () => null));
      return;
    }
    emit(state.copyWith(status: LoadStatus.loading));
    final range = state.range;
    final selected = state.selectedId;
    try {
      final data = await _reports.run(
        reportId,
        from: def.needsPeriod ? range.from : null,
        to: def.needsPeriod ? range.to : null,
        partyId: def.needsParty || def.optionalParty ? selected : null,
        bankAccountId: def.needsBank ? selected : null,
        itemId: def.needsItem ? selected : null,
      );
      // Ignore the answer if the filters changed while it was loading.
      if (state.range == range && state.selectedId == selected) emit(state.copyWith(status: LoadStatus.success, data: () => data));
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }
}
