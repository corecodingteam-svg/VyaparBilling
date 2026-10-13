import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'passcode_store.dart';

class AppLockState extends Equatable {
  const AppLockState({this.ready = false, this.hasPin = false, this.locked = false, this.failures = 0, this.waitUntil, this.message, this.rev = 0});

  /// The saved PIN has been read; until then the app shows nothing rather than flashing unlocked.
  final bool ready;
  final bool hasPin;
  final bool locked;

  /// Wrong attempts since the last success.
  final int failures;

  /// After too many wrong attempts, no attempt is accepted before this moment.
  final DateTime? waitUntil;

  /// What to tell the user about the last attempt.
  final String? message;
  final int rev;

  @override
  List<Object?> get props => [ready, hasPin, locked, failures, waitUntil, message, rev];
}

/// The app lock: asks for the PIN on start, after the app has been away for a while, and on demand.
class LockCubit extends Cubit<AppLockState> {
  LockCubit(this._store, {DateTime Function()? clock, this.awayBeforeLock = const Duration(minutes: 1), this.freeAttempts = 5})
    : _now = clock ?? DateTime.now,
      super(const AppLockState());

  final PasscodeStore _store;
  final DateTime Function() _now;

  /// How long the app can be in the background before it locks again.
  final Duration awayBeforeLock;

  /// Wrong attempts allowed before each further one has to wait.
  final int freeAttempts;
  DateTime? _wentAway;

  static const minLength = 4;
  static const maxLength = 6;

  Future<void> load() async {
    final has = await _store.hasPin();
    if (!isClosed) emit(AppLockState(ready: true, hasPin: has, locked: has));
  }

  /// The app went to the background (a tab hidden, the phone locked).
  void away() => _wentAway ??= _now();

  /// The app is back; it locks if it was away long enough.
  void back() {
    final left = _wentAway;
    _wentAway = null;
    if (left != null && state.hasPin && !state.locked && _now().difference(left) >= awayBeforeLock) {
      emit(AppLockState(ready: true, hasPin: true, locked: true, rev: state.rev + 1));
    }
  }

  void lockNow() {
    if (state.hasPin) emit(AppLockState(ready: true, hasPin: true, locked: true, rev: state.rev + 1));
  }

  /// Tries [pin]. Wrong attempts add up; after [freeAttempts] each further one waits, longer each time.
  Future<void> unlock(String pin) async {
    final wait = state.waitUntil;
    if (wait != null && _now().isBefore(wait)) {
      emit(
        AppLockState(
          ready: true,
          hasPin: true,
          locked: true,
          failures: state.failures,
          waitUntil: wait,
          message: 'Too many wrong attempts. Try again in ${wait.difference(_now()).inSeconds + 1} seconds.',
          rev: state.rev + 1,
        ),
      );
      return;
    }
    if (await _store.check(pin)) {
      emit(AppLockState(ready: true, hasPin: true, rev: state.rev + 1));
      return;
    }
    final failures = state.failures + 1;
    final over = failures - freeAttempts;
    emit(
      AppLockState(
        ready: true,
        hasPin: true,
        locked: true,
        failures: failures,
        waitUntil: over >= 0 ? _now().add(Duration(seconds: 30 * (over + 1))) : null,
        message: over >= 0
            ? 'Wrong PIN. Wait ${30 * (over + 1)} seconds before trying again.'
            : 'Wrong PIN. ${freeAttempts - failures} attempts left before a wait.',
        rev: state.rev + 1,
      ),
    );
  }

  /// Sets or changes the PIN; changing one needs the current one. Returns an error message, or null when done.
  Future<String?> setPin(String pin, {String? current}) async {
    if (!RegExp('^[0-9]{$minLength,$maxLength}\$').hasMatch(pin)) return 'Use $minLength to $maxLength digits.';
    if (state.hasPin && !await _store.check(current ?? '')) return 'The current PIN is wrong.';
    await _store.setPin(pin);
    emit(AppLockState(ready: true, hasPin: true, rev: state.rev + 1));
    return null;
  }

  /// Removes the lock; needs the current PIN. Returns an error message, or null when done.
  Future<String?> removePin(String current) async {
    if (!await _store.check(current)) return 'The PIN is wrong.';
    await _store.clear();
    emit(AppLockState(ready: true, rev: state.rev + 1));
    return null;
  }

  /// Forgotten PIN: signing in again with the password proves it is the owner, so the lock is cleared.
  /// The caller signs the user out.
  Future<void> forgot() async {
    await _store.clear();
    emit(AppLockState(ready: true, rev: state.rev + 1));
  }
}
