import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/status.dart';
import '../../data/models/firm.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/firm_repository.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.loadStatus = LoadStatus.loading,
    this.saved,
    this.draft = const FirmSettings(),
    this.rev = 0,
    this.status = SubmitStatus.idle,
    this.error,
  });

  final LoadStatus loadStatus;

  /// What is stored on the server.
  final FirmSettings? saved;

  /// What the screen currently shows.
  final FirmSettings draft;

  /// Bumped when the draft is replaced wholesale (loaded, saved, discarded) so text inputs show it.
  final int rev;
  final SubmitStatus status;
  final String? error;

  bool get dirty => saved != null && draft != saved;

  SettingsState copyWith({LoadStatus? loadStatus, FirmSettings? saved, FirmSettings? draft, int? rev, SubmitStatus? status, String? error}) => SettingsState(
        loadStatus: loadStatus ?? this.loadStatus,
        saved: saved ?? this.saved,
        draft: draft ?? this.draft,
        rev: rev ?? this.rev,
        status: status ?? this.status,
        error: error,
      );

  @override
  List<Object?> get props => [loadStatus, saved, draft, rev, status, error];
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._firm) : super(const SettingsState());
  final FirmRepository _firm;

  Future<void> load() async {
    try {
      final settings = (await _firm.get()).settings;
      emit(SettingsState(loadStatus: LoadStatus.success, saved: settings, draft: settings, rev: state.rev + 1));
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  void change(FirmSettings Function(FirmSettings) update) => emit(state.copyWith(draft: update(state.draft), status: SubmitStatus.idle));

  void discard() => emit(state.copyWith(draft: state.saved, rev: state.rev + 1, status: SubmitStatus.idle));

  Future<void> save() async {
    if (!state.dirty || state.status == SubmitStatus.submitting) return;
    emit(state.copyWith(status: SubmitStatus.submitting));
    try {
      final settings = (await _firm.update({'settings': state.draft.toJson()})).settings;
      emit(SettingsState(loadStatus: LoadStatus.success, saved: settings, draft: settings, rev: state.rev + 1, status: SubmitStatus.success));
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}

/// Change-password form: only its submission status is state; the fields live in controllers.
class ChangePasswordCubit extends Cubit<(SubmitStatus, String?)> {
  ChangePasswordCubit(this._auth) : super((SubmitStatus.idle, null));
  final AuthRepository _auth;

  Future<void> submit({required String current, required String next}) async {
    emit((SubmitStatus.submitting, null));
    try {
      await _auth.changePassword(current: current, next: next);
      emit((SubmitStatus.success, null));
    } catch (e) {
      emit((SubmitStatus.failure, ApiException.from(e).message));
    }
  }
}
