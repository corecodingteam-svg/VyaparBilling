import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/status.dart';
import '../../data/models/platform.dart';
import '../../data/repositories/platform_repository.dart';

class PlatformState extends Equatable {
  const PlatformState({this.status = LoadStatus.loading, this.tenants = const [], this.catalog, this.search = '', this.busy = false, this.error, this.errorRev = 0});
  final LoadStatus status;
  final List<Tenant> tenants;
  final PlatformCatalog? catalog;
  final String search;
  final bool busy;
  final String? error;

  /// Bumped with every failed action so each failure is shown once.
  final int errorRev;

  PlatformState copyWith({LoadStatus? status, List<Tenant>? tenants, PlatformCatalog? catalog, String? search, bool? busy, String? Function()? error, int? errorRev}) => PlatformState(
    status: status ?? this.status,
    tenants: tenants ?? this.tenants,
    catalog: catalog ?? this.catalog,
    search: search ?? this.search,
    busy: busy ?? this.busy,
    error: error != null ? error() : this.error,
    errorRev: errorRev ?? this.errorRev,
  );

  @override
  List<Object?> get props => [status, tenants, catalog, search, busy, error, errorRev];
}

/// The provider's list of businesses, with creating one and changing its plan, switches, licence and suspension.
class PlatformCubit extends Cubit<PlatformState> {
  PlatformCubit(this._repo) : super(const PlatformState());
  final PlatformRepository _repo;

  Future<void> load() async {
    try {
      final (catalog, tenants) = await (_repo.catalog(), _repo.tenants(q: state.search)).wait;
      if (!isClosed) emit(state.copyWith(status: LoadStatus.success, catalog: catalog, tenants: tenants, error: () => null));
    } catch (e) {
      if (isClosed) return;
      final message = ApiException.from(e).message;
      emit(state.status == LoadStatus.success ? state.copyWith(error: () => message, errorRev: state.errorRev + 1) : state.copyWith(status: LoadStatus.failure, error: () => message));
    }
  }

  Future<void> searchChanged(String v) async {
    emit(state.copyWith(search: v));
    try {
      final tenants = await _repo.tenants(q: v);
      if (!isClosed && state.search == v) emit(state.copyWith(tenants: tenants));
    } catch (_) {
      // The list stays as it was; the next keystroke or refresh tries again.
    }
  }

  /// Runs a change, then reloads. Returns the message of a failure, or null on success.
  Future<String?> _run(Future<void> Function() action) async {
    emit(state.copyWith(busy: true));
    try {
      await action();
      final tenants = await _repo.tenants(q: state.search);
      if (!isClosed) emit(state.copyWith(busy: false, tenants: tenants));
      return null;
    } catch (e) {
      final message = ApiException.from(e).message;
      if (!isClosed) emit(state.copyWith(busy: false));
      return message;
    }
  }

  Future<String?> create(Map<String, dynamic> body) => _run(() => _repo.create(body));
  Future<String?> update(String id, Map<String, dynamic> body) => _run(() => _repo.update(id, body));
  /// [status]: active | suspended | revoked.
  Future<String?> setStatus(Tenant t, String status, {String? reason}) => update(t.id, {'status': status, if (status != 'active') 'statusReason': reason});
  Future<String?> removeDevice(Tenant t, LicenseDevice d) => _run(() => _repo.removeDevice(t.id, d.id));
}

/// The draft of one business in the add/edit dialog.
class TenantDraft extends Equatable {
  const TenantDraft({required this.plan, required this.features, this.licenceExpiresOn, this.maxDevices = 5});
  final String plan;
  final Map<String, bool> features;
  final String? licenceExpiresOn;
  final int maxDevices;

  TenantDraft copyWith({String? plan, Map<String, bool>? features, String? Function()? licenceExpiresOn, int? maxDevices}) => TenantDraft(
    plan: plan ?? this.plan,
    features: features ?? this.features,
    licenceExpiresOn: licenceExpiresOn != null ? licenceExpiresOn() : this.licenceExpiresOn,
    maxDevices: maxDevices ?? this.maxDevices,
  );

  @override
  List<Object?> get props => [plan, features, licenceExpiresOn, maxDevices];
}

class TenantDraftCubit extends Cubit<TenantDraft> {
  TenantDraftCubit(super.initial, this._catalog);
  final PlatformCatalog _catalog;

  /// A plan sets every switch to what that plan includes.
  void planChanged(String id) {
    final plan = _catalog.plans.firstWhere((p) => p.id == id);
    emit(state.copyWith(plan: id, features: {...plan.features}));
  }

  void featureChanged(String id, bool on) => emit(state.copyWith(features: {...state.features, id: on}));
  void licenceChanged(String? iso) => emit(state.copyWith(licenceExpiresOn: () => iso));
  void maxDevicesChanged(int v) => emit(state.copyWith(maxDevices: v.clamp(1, 1000)));
}
