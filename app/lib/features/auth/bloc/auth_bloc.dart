import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/app_user.dart';
import '../../../data/repositories/auth_repository.dart';

sealed class AuthEvent {
  const AuthEvent();
}

/// App start: restore a saved session.
class AuthStarted extends AuthEvent {
  const AuthStarted();
}

/// Login/registration succeeded elsewhere (form cubits) with this user.
class AuthSignedIn extends AuthEvent {
  const AuthSignedIn(this.user);
  final AppUser user;
}

/// Business name changed in the company profile.
class AuthFirmRenamed extends AuthEvent {
  const AuthFirmRenamed(this.firmName);
  final String firmName;
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState extends Equatable {
  const AuthState._(this.status, [this.user]);
  const AuthState.unknown() : this._(AuthStatus.unknown);
  const AuthState.signedOut() : this._(AuthStatus.signedOut);
  const AuthState.signedIn(AppUser user) : this._(AuthStatus.signedIn, user);

  final AuthStatus status;
  final AppUser? user;

  @override
  List<Object?> get props => [status, user];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repo) : super(const AuthState.unknown()) {
    on<AuthStarted>((_, emit) async {
      final user = await _repo.restore();
      emit(user == null ? const AuthState.signedOut() : AuthState.signedIn(user));
    });
    on<AuthSignedIn>((e, emit) => emit(AuthState.signedIn(e.user)));
    on<AuthFirmRenamed>((e, emit) {
      final user = state.user;
      if (user != null) emit(AuthState.signedIn(user.copyWith(firmName: e.firmName)));
    });
    on<AuthLogoutRequested>((_, emit) async {
      await _repo.logout();
      emit(const AuthState.signedOut());
    });
  }

  final AuthRepository _repo;
}
