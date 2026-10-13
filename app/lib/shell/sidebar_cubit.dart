import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the wide-screen sidebar is collapsed to an icon rail. Remembered on this device.
class SidebarCubit extends Cubit<bool> {
  SidebarCubit({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance,
        super(false);

  final Future<SharedPreferences> Function() _prefs;
  static const _key = 'sidebar_collapsed';

  Future<void> load() async {
    try {
      emit((await _prefs()).getBool(_key) ?? false);
    } catch (_) {
      // Keep the default.
    }
  }

  Future<void> toggle() async {
    emit(!state);
    try {
      await (await _prefs()).setBool(_key, state);
    } catch (_) {
      // Still applies for this session.
    }
  }
}
