import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'api_client.dart';
import 'change_bus.dart';
import 'offline.dart';

class SyncState extends Equatable {
  const SyncState({
    this.pending = const [],
    this.lastSyncAt,
    this.syncing = false,
    this.online = true,
    this.dailyDue = false,
    this.promptDue = false,
    this.error,
    this.lastResult,
  });

  /// Saves made on this device that the server has not accepted yet (including ones it refused).
  final List<PendingSave> pending;
  final DateTime? lastSyncAt;
  final bool syncing;
  final bool online;

  /// Nothing has been synced yet today.
  final bool dailyDue;

  /// The daily sync is due and the user has not just said "later": show the prompt.
  final bool promptDue;

  /// Why the last sync stopped early, e.g. no connection.
  final String? error;

  /// What the last sync did, e.g. "3 bills sent".
  final String? lastResult;

  int get waiting => pending.where((p) => !p.failed).length;
  List<PendingSave> get failed => [for (final p in pending) if (p.failed) p];

  SyncState copyWith({
    List<PendingSave>? pending,
    DateTime? Function()? lastSyncAt,
    bool? syncing,
    bool? online,
    bool? dailyDue,
    bool? promptDue,
    String? Function()? error,
    String? Function()? lastResult,
  }) => SyncState(
    pending: pending ?? this.pending,
    lastSyncAt: lastSyncAt != null ? lastSyncAt() : this.lastSyncAt,
    syncing: syncing ?? this.syncing,
    online: online ?? this.online,
    dailyDue: dailyDue ?? this.dailyDue,
    promptDue: promptDue ?? this.promptDue,
    error: error != null ? error() : this.error,
    lastResult: lastResult != null ? lastResult() : this.lastResult,
  );

  @override
  List<Object?> get props => [pending, lastSyncAt, syncing, online, dailyDue, promptDue, error, lastResult];
}

/// Keeps a device that may be offline in step with the server: sends the saves it kept, refreshes the data it works from,
/// and insists on this being done at least once a calendar day.
///
/// It never sends anything by itself; the person is asked (a prompt that comes back every [snooze] until it is done) so that
/// a counter that is deliberately offline for the day is not surprised. [refresh] re-reads what the screens need offline
/// (items, accounts, the next bill number, the company settings).
class SyncCubit extends Cubit<SyncState> {
  SyncCubit(
    this._api,
    this._store,
    this._bus, {
    required this._refresh,
    Stream<String?>? firmIds,
    DateTime Function()? clock,
    this.snooze = const Duration(hours: 1),
    Duration tick = const Duration(minutes: 1),
  }) : _clock = clock ?? DateTime.now,
       super(const SyncState()) {
    _online = _api.onlineChanges.listen((v) {
      if (!isClosed) emit(state.copyWith(online: v));
    });
    _firms = firmIds?.listen((_) => load());
    _timer = Timer.periodic(tick, (_) => _evaluate());
  }

  final ApiClient _api;
  final KeyValueStore _store;
  final ChangeBus _bus;
  final Future<void> Function() _refresh;
  final DateTime Function() _clock;
  final Duration snooze;
  late final StreamSubscription<bool> _online;
  StreamSubscription<String?>? _firms;
  late final Timer _timer;
  DateTime? _snoozedUntil;
  String _scope = '';

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';
  String get _lastKey => 'last-sync|$_scope';

  /// Reads what is kept on this device for the current company.
  Future<void> load() async {
    _scope = await _api.scope();
    final text = _store.read(_lastKey);
    final last = text == null ? null : DateTime.tryParse(text);
    if (isClosed) return;
    emit(SyncState(pending: _api.queue?.forScope(_scope) ?? const [], lastSyncAt: last, online: _api.isOnline));
    _evaluate();
  }

  /// A save was just kept on the device.
  void noteQueued() {
    if (!isClosed) emit(state.copyWith(pending: _api.queue?.forScope(_scope) ?? const []));
  }

  void _evaluate() {
    if (isClosed) return;
    final last = state.lastSyncAt;
    final due = last == null || _day(last) != _day(_clock());
    final snoozed = _snoozedUntil != null && _clock().isBefore(_snoozedUntil!);
    final prompt = due && !snoozed;
    if (due != state.dailyDue || prompt != state.promptDue) emit(state.copyWith(dailyDue: due, promptDue: prompt));
  }

  /// "Later": ask again after [snooze].
  void later() {
    _snoozedUntil = _clock().add(snooze);
    emit(state.copyWith(promptDue: false));
  }

  /// Sends the waiting saves in the order they were made, then refreshes the data kept for offline use.
  Future<void> sync() async {
    if (state.syncing) return;
    emit(state.copyWith(syncing: true, error: () => null, lastResult: () => null));
    final queue = _api.queue;
    var sent = 0;
    String? stopped;
    for (final p in [...?queue?.forScope(_scope)]) {
      try {
        await _replay(p);
        await queue!.remove(p.id);
        sent++;
      } on ApiException catch (e) {
        if (e.offline) {
          stopped = e.message;
          break;
        }
        // The server understood and refused it; keep it, with the reason, for the person to look at.
        await queue!.update(p.copyWith(error: e.message, attempts: p.attempts + 1));
      }
    }
    if (stopped == null) {
      try {
        await _refresh();
      } on ApiException catch (e) {
        if (e.offline) stopped = e.message;
      } catch (_) {
        // The data kept for offline use is only a convenience; the sync itself went through.
      }
    }
    if (isClosed) return;
    final pending = queue?.forScope(_scope) ?? const <PendingSave>[];
    if (stopped != null) {
      emit(state.copyWith(syncing: false, pending: pending, error: () => stopped));
      return;
    }
    final now = _clock();
    await _store.write(_lastKey, now.toIso8601String());
    _snoozedUntil = null;
    if (sent > 0) {
      for (final t in [DataTopic.invoices, DataTopic.items, DataTopic.parties, DataTopic.accounts, DataTopic.payments]) {
        _bus.publish(t);
      }
    }
    final refused = pending.where((p) => p.failed).length;
    emit(
      state.copyWith(
        syncing: false,
        pending: pending,
        lastSyncAt: () => now,
        dailyDue: false,
        promptDue: false,
        online: true,
        lastResult: () => [
          sent == 0 ? 'Nothing was waiting to be sent' : '$sent ${sent == 1 ? 'save' : 'saves'} sent',
          if (refused > 0) '$refused refused by the server',
        ].join(' · '),
      ),
    );
  }

  /// A bill number another device used in the meantime is replaced by the next free one, a few times at most.
  Future<void> _replay(PendingSave p) async {
    var save = p;
    for (var attempt = 0; ; attempt++) {
      try {
        await _api.replay(save);
        return;
      } on ApiException catch (e) {
        final body = save.body;
        final taken = !e.offline && body is Map && body['number'] is String && e.message.contains('already used');
        if (!taken || attempt >= 3) rethrow;
        final type = body['type'] as String? ?? 'sale';
        final next = (await _api.get<Map<String, dynamic>>('/invoices/next-number', query: {'type': type}))['number'] as String;
        save = PendingSave(
          id: save.id,
          scope: save.scope,
          method: save.method,
          path: save.path,
          body: {...body.cast<String, dynamic>(), 'number': next},
          label: save.label,
          createdAt: save.createdAt,
        );
      }
    }
  }

  /// Throws away a save the server refused.
  Future<void> discard(String id) async {
    await _api.queue?.remove(id);
    noteQueued();
  }

  @override
  Future<void> close() {
    _timer.cancel();
    _online.cancel();
    _firms?.cancel();
    return super.close();
  }
}
