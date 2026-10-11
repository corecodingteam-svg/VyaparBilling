import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/status.dart';
import '../../data/models/firm.dart';
import '../../data/repositories/firm_repository.dart';
import '../auth/bloc/auth_bloc.dart';

class CompanyState extends Equatable {
  const CompanyState({
    this.loadStatus = LoadStatus.initial,
    this.submitStatus = SubmitStatus.idle,
    this.firm,
    this.businessType,
    this.businessCategory,
    this.stateCode,
    this.booksStartDate,
    this.logoFileId,
    this.signatureFileId,
    this.error,
  });

  final LoadStatus loadStatus;
  final SubmitStatus submitStatus;
  final Firm? firm;
  // Non-text selections; text fields live in controllers.
  final String? businessType;
  final String? businessCategory;
  final String? stateCode;
  final String? booksStartDate;

  /// Uploaded images printed on documents.
  final String? logoFileId;
  final String? signatureFileId;
  final String? error;

  CompanyState copyWith({
    LoadStatus? loadStatus,
    SubmitStatus? submitStatus,
    Firm? firm,
    String? Function()? businessType,
    String? Function()? businessCategory,
    String? Function()? stateCode,
    String? booksStartDate,
    String? Function()? logoFileId,
    String? Function()? signatureFileId,
    String? error,
  }) =>
      CompanyState(
        loadStatus: loadStatus ?? this.loadStatus,
        submitStatus: submitStatus ?? this.submitStatus,
        firm: firm ?? this.firm,
        businessType: businessType != null ? businessType() : this.businessType,
        businessCategory: businessCategory != null ? businessCategory() : this.businessCategory,
        stateCode: stateCode != null ? stateCode() : this.stateCode,
        booksStartDate: booksStartDate ?? this.booksStartDate,
        logoFileId: logoFileId != null ? logoFileId() : this.logoFileId,
        signatureFileId: signatureFileId != null ? signatureFileId() : this.signatureFileId,
        error: error,
      );

  @override
  List<Object?> get props =>
      [loadStatus, submitStatus, firm, businessType, businessCategory, stateCode, booksStartDate, logoFileId, signatureFileId, error];
}

class CompanyCubit extends Cubit<CompanyState> {
  CompanyCubit(this._repo, this._auth) : super(const CompanyState());

  final FirmRepository _repo;
  final AuthBloc _auth;

  Future<void> load() async {
    emit(state.copyWith(loadStatus: LoadStatus.loading));
    try {
      _apply(await _repo.get(), LoadStatus.success, SubmitStatus.idle);
    } catch (e) {
      emit(state.copyWith(loadStatus: LoadStatus.failure, error: ApiException.from(e).message));
    }
  }

  void _apply(Firm f, LoadStatus load, SubmitStatus submit) => emit(CompanyState(
        loadStatus: load,
        submitStatus: submit,
        firm: f,
        businessType: f.businessType,
        businessCategory: f.businessCategory,
        stateCode: f.stateCode,
        booksStartDate: f.booksStartDate,
        logoFileId: f.logoFileId,
        signatureFileId: f.signatureFileId,
      ));

  void businessTypeChanged(String? v) => emit(state.copyWith(businessType: () => v));
  void businessCategoryChanged(String? v) => emit(state.copyWith(businessCategory: () => v));
  void stateChanged(String? v) => emit(state.copyWith(stateCode: () => v));
  void booksStartDateChanged(String v) => emit(state.copyWith(booksStartDate: v));
  void logoChanged(String? fileId) => emit(state.copyWith(logoFileId: () => fileId));
  void signatureChanged(String? fileId) => emit(state.copyWith(signatureFileId: () => fileId));

  /// Restores the last saved values (Cancel).
  void reset() {
    if (state.firm != null) _apply(state.firm!, LoadStatus.success, SubmitStatus.idle);
  }

  Future<void> save(Map<String, dynamic> textFields) async {
    emit(state.copyWith(submitStatus: SubmitStatus.submitting));
    try {
      final firm = await _repo.update({
        ...textFields,
        'businessType': state.businessType ?? '',
        'businessCategory': state.businessCategory ?? '',
        'stateCode': state.stateCode ?? '',
        'booksStartDate': state.booksStartDate,
        'logoFileId': state.logoFileId,
        'signatureFileId': state.signatureFileId,
      });
      _apply(firm, LoadStatus.success, SubmitStatus.success);
      _auth.add(AuthFirmRenamed(firm.name));
    } catch (e) {
      emit(state.copyWith(submitStatus: SubmitStatus.failure, error: ApiException.from(e).message));
    }
  }
}
