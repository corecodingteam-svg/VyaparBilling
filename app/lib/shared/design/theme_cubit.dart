import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

/// Accent colours offered in Settings › Theme.
const themeAccentChoices = <(String, Color)>[
  ('Violet', Color(0xFF7C3AED)),
  ('Blue', Color(0xFF2563EB)),
  ('Teal', Color(0xFF0F766E)),
  ('Green', Color(0xFF16A34A)),
  ('Orange', Color(0xFFEA580C)),
  ('Red', Color(0xFFDC2626)),
  ('Pink', Color(0xFFDB2777)),
  ('Slate', Color(0xFF475569)),
];

/// Parses `#RRGGBB` (the `#` is optional); null when it is not a colour.
Color? parseAccent(String text) {
  final t = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(t)) return null;
  return Color(0xFF000000 | int.parse(t, radix: 16));
}

String accentHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The signed-in user's chosen accent colour. It is remembered per user on this device, and the last
/// choice is also used on the sign-in page. Applying it sets [AppColors.applyAccent] so every token
/// that derives from the brand colour follows.
class ThemeCubit extends Cubit<Color> {
  ThemeCubit({Future<SharedPreferences>? prefs, Stream<String?>? userIds})
      : _prefs = prefs ?? SharedPreferences.getInstance(),
        super(AppColors.defaultAccent) {
    _sub = userIds?.listen(_userChanged);
  }

  final Future<SharedPreferences> _prefs;
  StreamSubscription<String?>? _sub;
  String? _userId;

  static const _lastKey = 'theme_accent_last';
  String _key(String? user) => user == null ? _lastKey : 'theme_accent_$user';

  Future<void> loadFor(String? userId) async {
    _userId = userId;
    try {
      final p = await _prefs;
      final saved = p.getString(_key(userId)) ?? p.getString(_lastKey);
      final color = saved == null ? null : parseAccent(saved);
      _apply(color ?? AppColors.defaultAccent);
    } catch (_) {
      // Preferences unavailable: keep the current colour.
    }
  }

  void _userChanged(String? id) {
    if (id != _userId) loadFor(id);
  }

  void _apply(Color c) {
    AppColors.applyAccent(c);
    emit(c);
  }

  Future<void> choose(Color c) async {
    _apply(c);
    try {
      final p = await _prefs;
      await p.setString(_key(_userId), accentHex(c));
      await p.setString(_lastKey, accentHex(c));
    } catch (_) {
      // The colour still applies for this session.
    }
  }

  Future<void> reset() => choose(AppColors.defaultAccent);

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
