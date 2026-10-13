import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/firm.dart';
import '../../data/repositories/location_repository.dart';

enum TrackingStatus { off, active, denied }

class TrackingState extends Equatable {
  const TrackingState({this.status = TrackingStatus.off, this.lastSent});
  final TrackingStatus status;
  final DateTime? lastSent;

  @override
  List<Object?> get props => [status, lastSent];
}

/// Records where the signed-in user is while the app is open — a check-in every few minutes, and
/// the spot where each sale or payment is saved — when the business has location tracking on.
/// It only works while the app (or its browser tab) is open; nothing runs in the background.
class TrackingCubit extends Cubit<TrackingState> {
  /// [firm] is the company the session is working in (null when signed out); tracking follows its settings.
  TrackingCubit(this._locations, Stream<Firm?> firm, {Firm? initial, this.interval = const Duration(minutes: 5)}) : super(const TrackingState()) {
    _sub = firm.listen(configure);
    configure(initial);
  }

  final LocationRepository _locations;
  final Duration interval;
  late final StreamSubscription<Firm?> _sub;
  Timer? _timer;
  bool _enabled = false;

  /// Switches tracking on or off to match the company's settings.
  void configure(Firm? firm) {
    final on = firm?.settings.locationTrackingEnabled ?? false;
    if (on == _enabled) return;
    _enabled = on;
    _timer?.cancel();
    if (!_enabled) {
      emit(const TrackingState());
      return;
    }
    _timer = Timer.periodic(interval, (_) => _send('ping'));
    _send('ping');
  }

  /// Notes where a sale or payment was just saved.
  Future<void> recordSaved(String context, String refId) async {
    if (_enabled) await _send(context, refId: refId);
  }

  Future<void> _send(String context, {String? refId}) async {
    final fix = await _locations.currentFix();
    if (isClosed) return;
    if (fix == null) {
      emit(const TrackingState(status: TrackingStatus.denied));
      return;
    }
    try {
      await _locations.record(fix, context: context, refId: refId);
      if (!isClosed) emit(TrackingState(status: TrackingStatus.active, lastSent: DateTime.now()));
    } catch (_) {
      // A missed check-in is not worth interrupting anyone for; the next one tries again.
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    _timer?.cancel();
    return super.close();
  }
}
