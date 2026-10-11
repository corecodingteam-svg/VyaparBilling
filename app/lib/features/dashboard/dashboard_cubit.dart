import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/change_bus.dart';
import '../../core/status.dart';
import '../../data/models/dashboard_summary.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../shared/period.dart';

class DashboardState extends Equatable {
  const DashboardState({this.status = LoadStatus.initial, this.summary, this.error});
  final LoadStatus status;
  final DashboardSummary? summary;
  final String? error;

  @override
  List<Object?> get props => [status, summary, error];
}

/// Loads the summary and reloads whenever anything it summarises changes.
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repo, ChangeBus bus) : super(const DashboardState()) {
    _sub = bus.on({DataTopic.parties, DataTopic.items, DataTopic.invoices, DataTopic.payments, DataTopic.accounts}).listen((_) => load());
  }

  final DashboardRepository _repo;
  late final StreamSubscription<void> _sub;

  Future<void> load() async {
    if (state.summary == null) emit(const DashboardState(status: LoadStatus.loading));
    try {
      // Chart covers the whole current month.
      final month = PeriodRange.of(Period.thisMonth);
      emit(DashboardState(status: LoadStatus.success, summary: await _repo.summary(from: month.from, to: month.to)));
    } catch (e) {
      emit(DashboardState(status: LoadStatus.failure, summary: state.summary, error: ApiException.from(e).message));
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
