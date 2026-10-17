import 'dart:convert';

import 'package:equatable/equatable.dart';

/// What to do when the device clock has been turned back.
enum ClockTamperPolicy {
  /// Carry on, but say so.
  warn,

  /// Stop while the clock is behind what it was already seen to be.
  block,

  /// Stop until the server has confirmed the date (the default).
  requireOnlineValidation;

  static ClockTamperPolicy parse(String name) => switch (name) {
    'warn' => warn,
    'block' => block,
    _ => requireOnlineValidation,
  };
}

/// The compile-time choice of policy: --dart-define=LICENSE_CLOCK_POLICY=warn|block|requireOnline
const clockTamperPolicy = String.fromEnvironment('LICENSE_CLOCK_POLICY', defaultValue: 'requireOnline');

/// What is kept between starts to tell the real date from the device's. Stored in secure storage.
class ClockState extends Equatable {
  const ClockState({this.lastKnownTrustedTime, this.lastSuccessfulServerSync, this.lastKnownServerTime, this.lastKnownDeviceTime, this.offsetMs = 0, this.tamperDetected = false});

  factory ClockState.fromJson(Map<String, dynamic> j) {
    DateTime? t(String k) => j[k] == null ? null : DateTime.fromMillisecondsSinceEpoch(j[k] as int, isUtc: true);
    return ClockState(
      lastKnownTrustedTime: t('trusted'),
      lastSuccessfulServerSync: t('sync'),
      lastKnownServerTime: t('server'),
      lastKnownDeviceTime: t('device'),
      offsetMs: (j['offset'] as num?)?.toInt() ?? 0,
      tamperDetected: j['tamper'] == true,
    );
  }

  /// The latest moment this device has ever been trusted to have reached: time never goes back below it.
  final DateTime? lastKnownTrustedTime;
  final DateTime? lastSuccessfulServerSync;
  final DateTime? lastKnownServerTime;
  final DateTime? lastKnownDeviceTime;

  /// Server time minus device time when they last met; added to the device clock while offline.
  final int offsetMs;

  /// A clock rollback was seen and the server has not confirmed the date since.
  final bool tamperDetected;

  String toJsonText() => jsonEncode({
    'trusted': lastKnownTrustedTime?.millisecondsSinceEpoch,
    'sync': lastSuccessfulServerSync?.millisecondsSinceEpoch,
    'server': lastKnownServerTime?.millisecondsSinceEpoch,
    'device': lastKnownDeviceTime?.millisecondsSinceEpoch,
    'offset': offsetMs,
    'tamper': tamperDetected,
  });

  static ClockState fromText(String? text) {
    if (text == null) return const ClockState();
    try {
      return ClockState.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return const ClockState(); // unreadable: start again from the certificate's floor
    }
  }

  @override
  List<Object?> get props => [lastKnownTrustedTime, lastSuccessfulServerSync, lastKnownServerTime, lastKnownDeviceTime, offsetMs, tamperDetected];
}

/// What the clock says right now, once the device time has been corrected and checked against what was seen before.
class ClockReading {
  const ClockReading({required this.trusted, required this.rolledBack, required this.state});

  /// The time to judge the licence by: never earlier than anything already seen.
  final DateTime trusted;

  /// The device clock is now behind what was seen before, by more than the tolerance.
  final bool rolledBack;

  /// The state to store.
  final ClockState state;
}

/// A clock for licence decisions that does not simply believe the device.
///
/// Online, the server's time is learned and the gap to the device clock is remembered ([recordServerTime]).
/// Offline, "now" is the device clock plus that gap, and it can never be earlier than the latest time already trusted,
/// or than the server time inside the certificate (so deleting the stored state does not reset it). So turning the
/// clock back never gives more days; it is also noticed ([ClockReading.rolledBack]) and handled by [ClockTamperPolicy].
class TrustedClock {
  const TrustedClock({this.tolerance = const Duration(minutes: 5)});

  /// Small differences (clock correction, a sync that drifted) are not a rollback.
  final Duration tolerance;

  /// [floor] is a time the real clock cannot be earlier than, e.g. the certificate's server timestamp.
  ClockReading read(ClockState state, DateTime deviceNow, {DateTime? floor}) {
    final estimate = deviceNow.toUtc().add(Duration(milliseconds: state.offsetMs));
    final known = [state.lastKnownTrustedTime, floor].whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final rolledBack = known != null && estimate.isBefore(known.subtract(tolerance));
    final trusted = known != null && known.isAfter(estimate) ? known : estimate;
    return ClockReading(
      trusted: trusted,
      rolledBack: rolledBack,
      state: ClockState(
        lastKnownTrustedTime: trusted,
        lastSuccessfulServerSync: state.lastSuccessfulServerSync,
        lastKnownServerTime: state.lastKnownServerTime,
        lastKnownDeviceTime: state.lastKnownDeviceTime,
        offsetMs: state.offsetMs,
        tamperDetected: state.tamperDetected || rolledBack,
      ),
    );
  }

  /// The server has told us the time: the date is confirmed, whatever the device said, and any tamper flag is cleared.
  ClockState recordServerTime(ClockState state, DateTime serverTime, DateTime deviceNow) {
    final server = serverTime.toUtc();
    return ClockState(
      lastKnownTrustedTime: server,
      lastSuccessfulServerSync: server,
      lastKnownServerTime: server,
      lastKnownDeviceTime: deviceNow.toUtc(),
      offsetMs: server.difference(deviceNow.toUtc()).inMilliseconds,
    );
  }
}
