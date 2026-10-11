import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'api_client.dart';
import 'status.dart';

class SubmitState<T> extends Equatable {
  const SubmitState({this.status = SubmitStatus.idle, this.result, this.error});
  final SubmitStatus status;
  final T? result;
  final String? error;

  @override
  List<Object?> get props => [status, result, error];
}

/// Runs one async action and exposes its status — for small dialogs with no other state.
class SubmitCubit<T> extends Cubit<SubmitState<T>> {
  SubmitCubit() : super(SubmitState<T>());

  Future<void> run(Future<T> Function() action) async {
    if (state.status == SubmitStatus.submitting) return;
    emit(SubmitState<T>(status: SubmitStatus.submitting));
    try {
      emit(SubmitState<T>(status: SubmitStatus.success, result: await action()));
    } catch (e) {
      emit(SubmitState<T>(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}
