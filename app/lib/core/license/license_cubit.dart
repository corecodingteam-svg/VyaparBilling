import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/license_repository.dart';
import '../api_client.dart';
import 'license_certificate.dart';
import 'license_checker.dart';
import 'license_vault.dart';
import 'trusted_clock.dart';

class LicenseState extends Equatable {
  const LicenseState({this.status = LicenseStatus.checking, this.certificate, this.message = '', this.warning, this.busy = false, this.notice});
  final LicenseStatus status;
  final LicenseCertificate? certificate;

  /// Why the app is locked.
  final String message;

  /// The app runs, but this is worth saying.
  final String? warning;

  /// Contacting the server.
  final bool busy;

  /// The result of the last "check again" (e.g. no connection).
  final String? notice;

  bool get allowed => status == LicenseStatus.valid;

  @override
  List<Object?> get props => [status, certificate, message, warning, busy, notice];
}

/// Decides, on every start and every minute, whether this device may run, **without a connection**: it verifies the signed
/// certificate kept on the device and judges it against a clock that cannot be wound back (see [TrustedClock]).
/// The server is only needed to activate, to renew, and to confirm the date after a clock rollback; those happen quietly in
/// the background whenever there is a connection, or when the person taps "Check again".
class LicenseCubit extends Cubit<LicenseState> {
  LicenseCubit(
    this._repo,
    this._vault, {
    LicenseVerifier? verifier,
    DateTime Function()? now,
    this.policy = ClockTamperPolicy.requireOnlineValidation,
    Duration tick = const Duration(minutes: 1),
    this.onlineEvery = const Duration(hours: 6),
    Stream<bool>? onlineChanges,
  }) : _verifier = verifier ?? LicenseVerifier(),
       _now = now ?? (() => DateTime.now().toUtc()),
       super(const LicenseState()) {
    _timer = Timer.periodic(tick, (_) => _onTick());
    _online = onlineChanges?.listen((up) {
      if (up && state.status != LicenseStatus.valid) validateOnline(silent: true);
    });
  }

  final LicenseRepository _repo;
  final LicenseVault _vault;
  final LicenseVerifier _verifier;
  final DateTime Function() _now;
  final ClockTamperPolicy policy;
  final Duration onlineEvery;
  late final Timer _timer;
  StreamSubscription<bool>? _online;
  String? _customerId;
  DateTime? _lastOnlineTry;
  bool _validating = false;
  final _clock = const TrustedClock();

  /// Begins (or, after switching business, restarts) for [customerId]; null = signed out.
  Future<void> start(String? customerId) async {
    _customerId = customerId;
    _lastOnlineTry = null;
    if (customerId == null) {
      emit(const LicenseState());
      return;
    }
    emit(const LicenseState());
    await evaluate();
    unawaited(validateOnline(silent: true));
  }

  Future<void> _onTick() async {
    if (_customerId == null || isClosed) return;
    await evaluate();
    final last = _lastOnlineTry;
    if (state.status == LicenseStatus.valid && (last == null || _now().difference(last) >= onlineEvery)) unawaited(validateOnline(silent: true));
  }

  /// The offline check. Needs no connection.
  Future<void> evaluate() async {
    final customer = _customerId;
    if (customer == null) return;
    final installation = await _vault.installationId();
    final token = await _vault.certificate(customer);
    final verified = token == null ? null : await _verifier.verify(token);
    final decision = checkLicense(
      certificate: verified,
      installationId: installation,
      customerId: customer,
      clockState: await _vault.clock(),
      deviceNow: _now(),
      highestVersionSeen: await _vault.highestVersion(customer),
      serverVerdict: await _vault.verdict(customer),
      policy: policy,
      clock: _clock,
      signatureOk: token == null || verified != null,
    );
    if (decision.clock != null) await _vault.saveClock(decision.clock!);
    if (isClosed) return;
    emit(LicenseState(status: decision.status, certificate: decision.certificate, message: decision.message, warning: decision.warning, busy: state.busy, notice: state.notice));
  }

  /// Gets a fresh certificate (or the first one) from the server, learns the real time from it, and re-checks.
  /// [silent]: do not report a missing connection.
  Future<void> validateOnline({bool silent = false}) async {
    final customer = _customerId;
    if (customer == null || _validating) return;
    _validating = true;
    _lastOnlineTry = _now();
    if (!silent && !isClosed) emit(LicenseState(status: state.status, certificate: state.certificate, message: state.message, warning: state.warning, busy: true));
    try {
      final installation = await _vault.installationId();
      final hasCert = await _vault.certificate(customer) != null;
      LicenseGrant grant;
      try {
        grant = hasCert ? await _repo.refresh(installation) : await _repo.activate(installation);
      } on ApiException catch (e) {
        // This device is not on the licence (it was removed, or is new): ask to be added.
        if (e.code == 'NOT_ACTIVATED') {
          grant = await _repo.activate(installation);
        } else {
          rethrow;
        }
      }
      final cert = await _verifier.verify(grant.certificate);
      if (cert == null || cert.installationId != installation || cert.customerId != customer) {
        if (!isClosed) emit(const LicenseState(status: LicenseStatus.invalid, message: 'The license sent by the server could not be verified.'));
        return;
      }
      await _vault.saveCertificate(customer, grant.certificate);
      await _vault.saveHighestVersion(customer, cert.version > await _vault.highestVersion(customer) ? cert.version : await _vault.highestVersion(customer));
      await _vault.clearVerdict(customer);
      // The server's clock is the truth: remember the gap to this device's clock, and clear any rollback flag.
      await _vault.saveClock(_clock.recordServerTime(await _vault.clock(), grant.serverTime, _now()));
      await evaluate();
    } on ApiException catch (e) {
      await _handleServerAnswer(customer, e, silent);
    } catch (_) {
      // Anything unexpected: the offline decision stands.
    } finally {
      _validating = false;
      if (!isClosed && state.busy) emit(LicenseState(status: state.status, certificate: state.certificate, message: state.message, warning: state.warning, notice: state.notice));
    }
  }

  Future<void> _handleServerAnswer(String customer, ApiException e, bool silent) async {
    switch (e.code) {
      case 'LICENSE_SUSPENDED':
        await _vault.saveVerdict(customer, (status: LicenseStatus.suspended, message: e.message));
        await evaluate();
      case 'LICENSE_REVOKED':
        await _vault.saveVerdict(customer, (status: LicenseStatus.revoked, message: e.message));
        await evaluate();
      case 'DEVICE_LIMIT':
        if (!isClosed) emit(LicenseState(status: LicenseStatus.deviceLimit, message: e.message));
      default:
        // No connection, or a server problem: the offline decision stands. Only an explicit "check again" says so.
        if (!silent && !isClosed) emit(LicenseState(status: state.status, certificate: state.certificate, message: state.message, warning: state.warning, notice: e.offline ? 'No internet connection. Connect and try again.' : e.message));
    }
  }

  @override
  Future<void> close() {
    _timer.cancel();
    _online?.cancel();
    return super.close();
  }
}
