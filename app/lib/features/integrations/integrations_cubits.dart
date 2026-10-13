import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_client.dart';
import '../../core/status.dart';
import '../../data/models/integrations.dart';
import '../../data/repositories/integrations_repository.dart';

// ---------------------------------------------------------------- e-invoice and e-way bill

class EinvoiceState extends Equatable {
  const EinvoiceState({this.status = LoadStatus.loading, this.info, this.busy = false, this.message, this.error, this.rev = 0});

  final LoadStatus status;
  final EinvoiceInfo? info;
  final bool busy;

  /// What just happened, shown once; [rev] changes with every message or error so each shows once.
  final String? message;
  final String? error;
  final int rev;

  @override
  List<Object?> get props => [status, info, busy, message, error, rev];
}

/// One document's e-invoice and e-way bill: what is missing, what the portal has, and the actions.
class EinvoiceCubit extends Cubit<EinvoiceState> {
  EinvoiceCubit(this._repo, this.invoiceId) : super(const EinvoiceState());
  final IntegrationsRepository _repo;
  final String invoiceId;

  Future<void> load() async {
    try {
      emit(EinvoiceState(status: LoadStatus.success, info: await _repo.einvoice(invoiceId), rev: state.rev));
    } catch (e) {
      emit(EinvoiceState(status: LoadStatus.failure, error: ApiException.from(e).message, rev: state.rev));
    }
  }

  /// Runs [action]; its result replaces the document's e-invoice state. [done] is the message shown afterwards.
  Future<void> _act(Future<EinvoiceInfo> Function() action, String done) async {
    if (state.busy) return;
    emit(EinvoiceState(status: LoadStatus.success, info: state.info, busy: true, rev: state.rev));
    try {
      emit(EinvoiceState(status: LoadStatus.success, info: await action(), message: done, rev: state.rev + 1));
    } catch (e) {
      emit(EinvoiceState(status: LoadStatus.success, info: state.info, error: ApiException.from(e).message, rev: state.rev + 1));
    }
  }

  Future<void> saveTransport(Transport t) => _act(() => _repo.saveTransport(invoiceId, t), 'Transport details saved');
  Future<void> generate() => _act(() => _repo.generateEinvoice(invoiceId), 'E-invoice generated');
  Future<void> recordIrn(String irn, String ackNo, String ackDate) => _act(() => _repo.recordIrn(invoiceId, irn: irn, ackNo: ackNo, ackDate: ackDate), 'IRN saved');
  Future<void> cancel(String reason, String remark, {required bool onPortal}) =>
      _act(() => _repo.cancelEinvoice(invoiceId, reason: reason, remark: remark, onPortal: onPortal), 'E-invoice cancelled');
  Future<void> generateEway() => _act(() => _repo.generateEway(invoiceId), 'E-way bill generated');
  Future<void> recordEway(String no) => _act(() => _repo.recordEway(invoiceId, no), 'E-way bill number saved');

  /// A download or other call that changes nothing here; failures are reported the same way.
  Future<void> attempt(Future<void> Function() action, {String? done}) async {
    if (state.busy) return;
    emit(EinvoiceState(status: LoadStatus.success, info: state.info, busy: true, rev: state.rev));
    try {
      await action();
      emit(EinvoiceState(status: LoadStatus.success, info: state.info, message: done, rev: state.rev + (done == null ? 0 : 1)));
    } catch (e) {
      emit(EinvoiceState(status: LoadStatus.success, info: state.info, error: ApiException.from(e).message, rev: state.rev + 1));
    }
  }
}

// ---------------------------------------------------------------- payment link

class PaymentLinkState extends Equatable {
  const PaymentLinkState({this.status = LoadStatus.loading, this.link, this.busy = false, this.error, this.rev = 0});
  final LoadStatus status;
  final PaymentLink? link;
  final bool busy;
  final String? error;
  final int rev;

  @override
  List<Object?> get props => [status, link, busy, error, rev];
}

/// The pay-online link of one invoice: made on opening, and checked on request.
class PaymentLinkCubit extends Cubit<PaymentLinkState> {
  PaymentLinkCubit(this._repo, this.invoiceId) : super(const PaymentLinkState());
  final IntegrationsRepository _repo;
  final String invoiceId;

  Future<void> load() async {
    try {
      emit(PaymentLinkState(status: LoadStatus.success, link: await _repo.createPaymentLink(invoiceId), rev: state.rev));
    } catch (e) {
      emit(PaymentLinkState(status: LoadStatus.failure, error: ApiException.from(e).message, rev: state.rev));
    }
  }

  Future<void> check() async {
    final link = state.link;
    if (link == null || state.busy) return;
    emit(PaymentLinkState(status: LoadStatus.success, link: link, busy: true, rev: state.rev));
    try {
      emit(PaymentLinkState(status: LoadStatus.success, link: await _repo.refreshPaymentLink(link.id), rev: state.rev));
    } catch (e) {
      emit(PaymentLinkState(status: LoadStatus.success, link: link, error: ApiException.from(e).message, rev: state.rev + 1));
    }
  }
}

// ---------------------------------------------------------------- Google Business Profile

enum GoogleStage { loading, notConnected, pickLocation, ready, failure }

class GoogleProfileState extends Equatable {
  const GoogleProfileState({
    this.stage = GoogleStage.loading,
    this.email,
    this.locations = const [],
    this.profile,
    this.reviews,
    this.busy = false,
    this.message,
    this.error,
    this.rev = 0,
  });

  final GoogleStage stage;
  final String? email;
  final List<GoogleLocation> locations;
  final GoogleProfileInfo? profile;
  final GoogleReviews? reviews;
  final bool busy;
  final String? message;
  final String? error;
  final int rev;

  GoogleProfileState copyWith({
    GoogleStage? stage,
    List<GoogleLocation>? locations,
    GoogleProfileInfo? profile,
    GoogleReviews? reviews,
    bool? busy,
    String? message,
    String? error,
    bool bump = false,
  }) => GoogleProfileState(
    stage: stage ?? this.stage,
    email: email,
    locations: locations ?? this.locations,
    profile: profile ?? this.profile,
    reviews: reviews ?? this.reviews,
    busy: busy ?? this.busy,
    message: message,
    error: error,
    rev: bump ? rev + 1 : rev,
  );

  @override
  List<Object?> get props => [stage, email, locations, profile, reviews, busy, message, error, rev];
}

class GoogleProfileCubit extends Cubit<GoogleProfileState> {
  GoogleProfileCubit(this._repo) : super(const GoogleProfileState());
  final IntegrationsRepository _repo;

  Future<void> load() async {
    try {
      final google = (await _repo.integrations()).firstWhere((i) => i.provider == 'google_profile');
      if (!google.connected) return emit(GoogleProfileState(stage: GoogleStage.notConnected, rev: state.rev));
      final connected = GoogleProfileState(email: google.email, rev: state.rev);
      if (google.location == null) {
        emit(GoogleProfileState(stage: GoogleStage.pickLocation, email: google.email, locations: await _repo.googleLocations(), rev: state.rev));
      } else {
        final (profile, reviews) = await (_repo.googleProfile(), _repo.googleReviews()).wait;
        emit(GoogleProfileState(stage: GoogleStage.ready, email: google.email, profile: profile, reviews: reviews, rev: connected.rev));
      }
    } catch (e) {
      emit(GoogleProfileState(stage: GoogleStage.failure, error: ApiException.from(e).message, rev: state.rev));
    }
  }

  Future<String> authUrl() => _repo.googleAuthUrl();

  Future<void> _act(Future<void> Function() action, {String? done, bool reload = false}) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      await action();
      if (reload) {
        await load();
        return;
      }
      emit(state.copyWith(busy: false, message: done, bump: true));
    } catch (e) {
      emit(state.copyWith(busy: false, error: ApiException.from(e).message, bump: true));
    }
  }

  Future<void> choose(GoogleLocation l) => _act(() => _repo.chooseGoogleLocation(l), reload: true);

  Future<void> saveProfile(String description, String website) => _act(() async {
    final profile = await _repo.saveGoogleProfile(description: description, website: website);
    emit(state.copyWith(profile: profile));
  }, done: 'Profile updated');

  Future<void> post(String summary, String url) => _act(() => _repo.googlePost(summary, url: url), done: 'Posted to your Google listing');

  Future<void> reply(String reviewId, String comment) => _act(() async {
    await _repo.replyToReview(reviewId, comment);
    emit(state.copyWith(reviews: await _repo.googleReviews()));
  }, done: 'Reply posted');

  Future<void> disconnect() => _act(() => _repo.disconnect('google_profile'), reload: true);
}
