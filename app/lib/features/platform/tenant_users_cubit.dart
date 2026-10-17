import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/status.dart';
import '../../data/models/platform.dart';
import '../../data/repositories/platform_repository.dart';

class TenantUsersState extends Equatable {
  const TenantUsersState({this.status = LoadStatus.loading, this.users = const [], this.busy = false, this.error, this.newPassword});
  final LoadStatus status;
  final List<TenantUser> users;
  final bool busy;
  final String? error;

  /// After a reset: who, and the password to hand over (shown once).
  final ({String email, String password})? newPassword;

  @override
  List<Object?> get props => [status, users, busy, error, newPassword];
}

/// The master admin's view of one business's logins: reset a password, disable or enable, make someone the owner.
class TenantUsersCubit extends Cubit<TenantUsersState> {
  TenantUsersCubit(this._repo, this.tenantId) : super(const TenantUsersState());
  final PlatformRepository _repo;
  final String tenantId;

  Future<void> load() async {
    try {
      final users = await _repo.users(tenantId);
      if (!isClosed) emit(TenantUsersState(status: LoadStatus.success, users: users));
    } catch (e) {
      if (!isClosed) emit(TenantUsersState(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> _run(Future<List<TenantUser>> Function() action) async {
    emit(TenantUsersState(status: state.status, users: state.users, busy: true));
    try {
      final users = await action();
      if (!isClosed) emit(TenantUsersState(status: LoadStatus.success, users: users));
    } catch (e) {
      if (!isClosed) emit(TenantUsersState(status: state.status, users: state.users, error: ApiException.from(e).message));
    }
  }

  Future<void> setDisabled(TenantUser u, bool disabled) => _run(() => _repo.setDisabled(tenantId, u.id, disabled));
  Future<void> makeOwner(TenantUser u) => _run(() => _repo.setOwner(tenantId, u.id));

  Future<void> resetPassword(TenantUser u) async {
    emit(TenantUsersState(status: state.status, users: state.users, busy: true));
    try {
      final password = await _repo.resetPassword(tenantId, u.id);
      if (!isClosed) emit(TenantUsersState(status: state.status, users: state.users, newPassword: (email: u.email, password: password)));
    } catch (e) {
      if (!isClosed) emit(TenantUsersState(status: state.status, users: state.users, error: ApiException.from(e).message));
    }
  }
}

class AuditState extends Equatable {
  const AuditState({this.status = LoadStatus.loading, this.entries = const [], this.error});
  final LoadStatus status;
  final List<AuditEntry> entries;
  final String? error;
  @override
  List<Object?> get props => [status, entries, error];
}

/// The master admin's audit log, of every business or of one.
class AuditCubit extends Cubit<AuditState> {
  AuditCubit(this._repo, {this.firmId}) : super(const AuditState());
  final PlatformRepository _repo;
  final String? firmId;

  Future<void> load() async {
    try {
      final entries = await _repo.audit(firmId: firmId);
      if (!isClosed) emit(AuditState(status: LoadStatus.success, entries: entries));
    } catch (e) {
      if (!isClosed) emit(AuditState(status: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }
}
