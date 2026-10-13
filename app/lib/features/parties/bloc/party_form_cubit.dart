import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_client.dart';
import '../../../core/status.dart';
import '../../../data/models/accounting.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/party.dart';
import '../../../data/repositories/accounting_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/parties_repository.dart';
import '../../../shared/format.dart';

enum PartyFormResult { none, saved, savedAndNew, deleted }

/// Non-text state of the add/edit party dialog. Text fields live in controllers owned by the widget.
class PartyFormState extends Equatable {
  const PartyFormState({
    required this.gstType,
    required this.stateCode,
    required this.shippingEnabled,
    required this.toReceive,
    required this.asOf,
    required this.customLimit,
    this.groupId,
    this.assignedUserId,
    this.currencyCode,
    this.groups = const [],
    this.salesmen = const [],
    this.currencies = const [],
    this.status = SubmitStatus.idle,
    this.result = PartyFormResult.none,
    this.error,
  });

  factory PartyFormState.from(Party? p) => PartyFormState(
    gstType: p?.gstType ?? 'unregistered',
    stateCode: p?.stateCode,
    shippingEnabled: (p?.shippingAddress ?? '').isNotEmpty,
    toReceive: (p?.openingBalance ?? 0) >= 0,
    asOf: p?.openingBalanceDate ?? isoDate(DateTime.now()),
    customLimit: p?.creditLimit != null,
    groupId: p?.groupId,
    assignedUserId: p?.assignedUserId,
    currencyCode: p?.currencyCode,
  );

  final String gstType;
  final String? stateCode;
  final bool shippingEnabled;
  final bool toReceive;
  final String asOf;
  final bool customLimit;
  final String? groupId;

  /// The salesman this party belongs to.
  final String? assignedUserId;

  /// A foreign party is billed and pays in this currency.
  final String? currencyCode;
  final List<PartyGroup> groups;
  final List<Member> salesmen;
  final List<Currency> currencies;
  final SubmitStatus status;
  final PartyFormResult result;
  final String? error;

  PartyFormState copyWith({
    String? gstType,
    String? Function()? stateCode,
    bool? shippingEnabled,
    bool? toReceive,
    String? asOf,
    bool? customLimit,
    String? Function()? groupId,
    String? Function()? assignedUserId,
    String? Function()? currencyCode,
    List<PartyGroup>? groups,
    List<Member>? salesmen,
    List<Currency>? currencies,
    SubmitStatus? status,
    PartyFormResult? result,
    String? error,
  }) => PartyFormState(
    gstType: gstType ?? this.gstType,
    stateCode: stateCode != null ? stateCode() : this.stateCode,
    shippingEnabled: shippingEnabled ?? this.shippingEnabled,
    toReceive: toReceive ?? this.toReceive,
    asOf: asOf ?? this.asOf,
    customLimit: customLimit ?? this.customLimit,
    groupId: groupId != null ? groupId() : this.groupId,
    assignedUserId: assignedUserId != null ? assignedUserId() : this.assignedUserId,
    currencyCode: currencyCode != null ? currencyCode() : this.currencyCode,
    groups: groups ?? this.groups,
    salesmen: salesmen ?? this.salesmen,
    currencies: currencies ?? this.currencies,
    status: status ?? this.status,
    result: result ?? this.result,
    error: error,
  );

  @override
  List<Object?> get props => [
    gstType,
    stateCode,
    shippingEnabled,
    toReceive,
    asOf,
    customLimit,
    groupId,
    assignedUserId,
    currencyCode,
    groups,
    salesmen,
    currencies,
    status,
    result,
    error,
  ];
}

class PartyFormCubit extends Cubit<PartyFormState> {
  PartyFormCubit(this._repo, this.party, {AuthRepository? auth, AccountingRepository? accounting}) : super(PartyFormState.from(party)) {
    _auth = auth;
    _accounting = accounting;
  }

  late final AuthRepository? _auth;
  late final AccountingRepository? _accounting;

  /// Loads the choices the form offers: party groups, salesmen and currencies. Each is optional —
  /// a salesman cannot list users, and a business may have no groups or currencies.
  Future<void> load() async {
    final (groups, salesmen, currencies) = await (
      _optional(_repo.groups, const <PartyGroup>[]),
      _optional(
        () async => [
          for (final m in await _auth!.members())
            if (m.role == 'salesman') m,
        ],
        const <Member>[],
      ),
      _optional(() async => await _accounting!.currencies(), const <Currency>[]),
    ).wait;
    if (!isClosed) emit(state.copyWith(groups: groups, salesmen: salesmen, currencies: currencies));
  }

  Future<List<T>> _optional<T>(Future<List<T>> Function() load, List<T> fallback) async {
    try {
      return await load();
    } catch (_) {
      return fallback;
    }
  }

  void groupChanged(String? v) => emit(state.copyWith(groupId: () => v));
  void salesmanChanged(String? v) => emit(state.copyWith(assignedUserId: () => v));
  void currencyChanged(String? v) => emit(state.copyWith(currencyCode: () => v));

  final PartiesRepository _repo;
  final Party? party;

  bool get editing => party != null;

  void gstTypeChanged(String v) => emit(state.copyWith(gstType: v));
  void stateChanged(String? v) => emit(state.copyWith(stateCode: () => v));
  void shippingToggled(bool v) => emit(state.copyWith(shippingEnabled: v));
  void balanceDirectionChanged(bool toReceive) => emit(state.copyWith(toReceive: toReceive));
  void asOfChanged(String v) => emit(state.copyWith(asOf: v));
  void creditLimitToggled(bool v) => emit(state.copyWith(customLimit: v));

  /// A valid GSTIN implies a registered party in the GSTIN's state.
  void gstinRecognised(String stateCode) =>
      emit(state.copyWith(stateCode: () => stateCode, gstType: state.gstType == 'unregistered' ? 'regular' : state.gstType));

  /// [fields] holds the text-field values; the cubit adds its own selections.
  Future<void> save(Map<String, dynamic> fields, {required bool andNew}) async {
    if (state.status == SubmitStatus.submitting) return;
    emit(state.copyWith(status: SubmitStatus.submitting, result: PartyFormResult.none));
    final opening = (fields.remove('openingAmount') as num?) ?? 0;
    final limit = fields.remove('creditLimitAmount') as num?;
    try {
      await _repo.save(party?.id, {
        ...fields,
        'gstType': state.gstType,
        'stateCode': state.stateCode,
        'shippingAddress': state.shippingEnabled ? fields['shippingAddress'] : '',
        'openingBalance': state.toReceive ? opening : -opening,
        'openingBalanceDate': state.asOf,
        'creditLimit': state.customLimit ? limit : null,
        'groupId': state.groupId,
        'assignedUserId': state.assignedUserId,
        'currencyCode': state.currencyCode,
      });
      if (andNew) {
        // Fresh form for the next party.
        emit(PartyFormState.from(null).copyWith(status: SubmitStatus.success, result: PartyFormResult.savedAndNew));
      } else {
        emit(state.copyWith(status: SubmitStatus.success, result: PartyFormResult.saved));
      }
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }

  Future<void> delete() async {
    emit(state.copyWith(status: SubmitStatus.submitting, result: PartyFormResult.none));
    try {
      await _repo.delete(party!.id);
      emit(state.copyWith(status: SubmitStatus.success, result: PartyFormResult.deleted));
    } catch (e) {
      emit(state.copyWith(status: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}
