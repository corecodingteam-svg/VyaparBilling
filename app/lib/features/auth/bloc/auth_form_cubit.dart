import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/status.dart';
import '../../../data/repositories/auth_repository.dart';
import 'auth_bloc.dart';

class AuthFormState extends Equatable {
  const AuthFormState({this.status = SubmitStatus.idle, this.error, this.obscurePassword = true, this.stateCode});

  final SubmitStatus status;
  final String? error;
  final bool obscurePassword;
  final String? stateCode; // registration only

  AuthFormState copyWith({SubmitStatus? status, String? error, bool clearError = false, bool? obscurePassword, String? stateCode}) =>
      AuthFormState(
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        obscurePassword: obscurePassword ?? this.obscurePassword,
        stateCode: stateCode ?? this.stateCode,
      );

  @override
  List<Object?> get props => [status, error, obscurePassword, stateCode];
}

/// Drives the login and registration forms; on success hands the user to [AuthBloc].
class AuthFormCubit extends Cubit<AuthFormState> {
  AuthFormCubit(this._repo, this._auth) : super(const AuthFormState());

  final AuthRepository _repo;
  final AuthBloc _auth;

  void togglePasswordVisibility() => emit(state.copyWith(obscurePassword: !state.obscurePassword));

  void stateCodeChanged(String? code) => emit(state.copyWith(stateCode: code));

  Future<void> login({required String email, required String password}) =>
      _submit(() => _repo.login(email: email, password: password));

  Future<void> register({required String firmName, required String fullName, required String email, required String password}) =>
      _submit(() => _repo.register(
            firmName: firmName,
            stateCode: state.stateCode!,
            fullName: fullName,
            email: email,
            password: password,
          ));

  Future<void> _submit(Future<dynamic> Function() action) async {
    if (state.status == SubmitStatus.submitting) return;
    emit(state.copyWith(status: SubmitStatus.submitting, clearError: true));
    try {
      final user = await action();
      emit(state.copyWith(status: SubmitStatus.success));
      _auth.add(AuthSignedIn(user));
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}
