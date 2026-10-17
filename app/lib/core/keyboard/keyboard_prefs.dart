import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_command.dart';
import 'key_combo.dart';
import 'reserved_keys.dart';

/// How much the app leans towards the keyboard (Settings › Keyboard & Shortcuts › Keyboard Mode). The mouse always works.
enum KeyboardMode {
  standard('Standard', 'Normal behaviour.'),
  keyboardFirst('Keyboard First', 'Shortcut hints on the main buttons, and the first field is ready to type in when a screen opens.'),
  keyboardOnly('Keyboard Only', 'Everything in Keyboard First, plus stronger focus outlines and hints on every button. The mouse still works.');

  const KeyboardMode(this.label, this.description);
  final String label;
  final String description;
}

/// What Enter does in a single-line text input.
enum EnterBehavior {
  contextAware('Confirm / context-aware', 'Moves to the next field, but search boxes, item pickers and multiline boxes keep their own Enter.'),
  nextField('Move to next field', 'Always moves to the next input, even where Enter would submit. Multiline boxes keep their new line.'),
  tab('Follow Tab behaviour', 'Moves exactly like Tab, including onto buttons.'),
  off('Off', 'Enter only does what the field itself does.');

  const EnterBehavior(this.label, this.description);
  final String label;
  final String description;
}

class KeyboardPrefs extends Equatable {
  const KeyboardPrefs({
    this.mode = KeyboardMode.standard,
    this.enter = EnterBehavior.contextAware,
    this.custom = const {},
    this.barcodeReturnFocus = true,
    this.tutorialSeen = false,
    this.web = kIsWeb,
  });

  final KeyboardMode mode;
  final EnterBehavior enter;

  /// Shortcuts the user changed. A command mapped to null has its shortcut turned off.
  final Map<AppCommand, KeyCombo?> custom;

  /// After a scan or an item is added, put the cursor back in the item/barcode box.
  final bool barcodeReturnFocus;

  /// The first-time keyboard tutorial has been offered.
  final bool tutorialSeen;

  /// Browser defaults and reserved keys apply (Flutter web).
  final bool web;

  /// The shortcut [c] has now: the user's own, or the default.
  KeyCombo? keyOf(AppCommand c) => custom.containsKey(c) ? custom[c] : c.defaultKey(web: web);

  bool isCustom(AppCommand c) => custom.containsKey(c) && custom[c] != c.defaultKey(web: web);

  /// Every key that runs [c]: its shortcut plus any fixed extra keys.
  List<KeyCombo> keysOf(AppCommand c) => [?keyOf(c), if (!custom.containsKey(c)) ...c.alsoKeys(web: web)];

  /// The commands [combo] runs, narrowest area first.
  List<AppCommand> commandsFor(KeyCombo combo) => (_byKey[this] ??= _index())[combo] ?? const [];

  static final _byKey = Expando<Map<KeyCombo, List<AppCommand>>>();

  Map<KeyCombo, List<AppCommand>> _index() {
    final m = <KeyCombo, List<AppCommand>>{};
    for (final c in AppCommand.values) {
      for (final k in keysOf(c)) {
        (m[k] ??= []).add(c);
      }
    }
    for (final list in m.values) {
      list.sort((a, b) => b.area.index.compareTo(a.area.index));
    }
    return m;
  }

  /// Why [combo] cannot be [command]'s shortcut, or null when it can. It is never given silently: a key another command
  /// already uses must be freed there first.
  String? problemWith(AppCommand command, KeyCombo combo) {
    final reserved = reservedReason(combo, web: web);
    if (reserved != null) return reserved;
    if (isTextEditingKey(combo) && !const {AppCommand.removeRow, AppCommand.firstRecord, AppCommand.lastRecord}.contains(command)) {
      return '${combo.label} is needed for typing. Add Ctrl or Alt, or use a function key.';
    }
    for (final other in AppCommand.values) {
      if (other == command || !keysOf(other).contains(combo)) continue;
      if (_mayShare(command, other)) continue;
      return 'Shortcut already assigned to "${other.label}". Choose another shortcut.';
    }
    return null;
  }

  /// Pairs of commands that share a key they may not share; empty for a valid set of shortcuts.
  List<(AppCommand, AppCommand)> conflicts() => [
        for (final entry in (_byKey[this] ??= _index()).entries)
          for (var i = 0; i < entry.value.length; i++)
            for (var j = i + 1; j < entry.value.length; j++)
              if (!_mayShare(entry.value[i], entry.value[j])) (entry.value[i], entry.value[j]),
      ];

  /// Two commands may share a key when they are active in different places and the narrower one replaces the global one
  /// there on purpose.
  static bool _mayShare(AppCommand a, AppCommand b) {
    if (a.area == b.area) return false;
    final (narrow, wide) = a.area.index > b.area.index ? (a, b) : (b, a);
    return wide.area == ShortcutArea.global && narrow.overrides == wide;
  }

  KeyboardPrefs copyWith({KeyboardMode? mode, EnterBehavior? enter, Map<AppCommand, KeyCombo?>? custom, bool? barcodeReturnFocus, bool? tutorialSeen}) => KeyboardPrefs(
        mode: mode ?? this.mode,
        enter: enter ?? this.enter,
        custom: custom ?? this.custom,
        barcodeReturnFocus: barcodeReturnFocus ?? this.barcodeReturnFocus,
        tutorialSeen: tutorialSeen ?? this.tutorialSeen,
        web: web,
      );

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'enter': enter.name,
        'barcodeReturnFocus': barcodeReturnFocus,
        'tutorialSeen': tutorialSeen,
        'custom': {for (final e in custom.entries) e.key.id: e.value?.encode()},
      };

  static KeyboardPrefs fromJson(Map<String, Object?> j, {required bool web}) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) => values.where((v) => v.name == name).firstOrNull ?? fallback;
    final custom = <AppCommand, KeyCombo?>{};
    final raw = j['custom'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final c = AppCommand.byId('${e.key}');
        if (c == null) continue; // a command that no longer exists
        if (e.value == null) {
          custom[c] = null;
        } else {
          final k = KeyCombo.decode('${e.value}');
          if (k != null) custom[c] = k;
        }
      }
    }
    return KeyboardPrefs(
      mode: pick(KeyboardMode.values, j['mode'], KeyboardMode.standard),
      enter: pick(EnterBehavior.values, j['enter'], EnterBehavior.contextAware),
      barcodeReturnFocus: j['barcodeReturnFocus'] is bool ? j['barcodeReturnFocus']! as bool : true,
      tutorialSeen: j['tutorialSeen'] == true,
      custom: custom,
      web: web,
    );
  }

  @override
  List<Object?> get props => [mode, enter, custom, barcodeReturnFocus, tutorialSeen, web];
}

/// The keyboard preferences of the signed-in user, remembered on this device; a new user starts from the last choice
/// made here. It also reads the older on/off "Enter Key Navigation" setting the first time.
class KeyboardPrefsCubit extends Cubit<KeyboardPrefs> {
  KeyboardPrefsCubit({Future<SharedPreferences>? prefs, Stream<String?>? userIds, bool web = kIsWeb})
      : _prefs = prefs ?? SharedPreferences.getInstance(),
        _web = web,
        super(KeyboardPrefs(web: web)) {
    _sub = userIds?.listen((id) {
      if (id != _userId) loadFor(id);
    });
  }

  final Future<SharedPreferences> _prefs;
  final bool _web;
  StreamSubscription<String?>? _sub;
  String? _userId;

  static const _lastKey = 'keyboard_prefs_last';
  String _key(String? user) => user == null ? _lastKey : 'keyboard_prefs_$user';

  // The setting this replaces: a bool per user.
  static const _oldLastKey = 'enter_navigation_last';
  String _oldKey(String? user) => user == null ? _oldLastKey : 'enter_navigation_$user';

  Future<void> loadFor(String? userId) async {
    _userId = userId;
    try {
      final p = await _prefs;
      final saved = p.getString(_key(userId)) ?? p.getString(_lastKey);
      if (saved != null) {
        final json = jsonDecode(saved);
        if (json is Map<String, Object?>) return emit(KeyboardPrefs.fromJson(json, web: _web));
      }
      final oldEnter = p.getBool(_oldKey(userId)) ?? p.getBool(_oldLastKey);
      emit(KeyboardPrefs(web: _web, enter: oldEnter == false ? EnterBehavior.off : EnterBehavior.contextAware));
    } catch (_) {
      // Preferences unavailable or unreadable: keep what is showing.
    }
  }

  Future<void> _save(KeyboardPrefs next) async {
    emit(next);
    try {
      final p = await _prefs;
      final text = jsonEncode(next.toJson());
      await p.setString(_key(_userId), text);
      await p.setString(_lastKey, text);
    } catch (_) {
      // Still applies for this session.
    }
  }

  Future<void> setMode(KeyboardMode mode) => _save(state.copyWith(mode: mode));
  Future<void> setEnter(EnterBehavior enter) => _save(state.copyWith(enter: enter));
  Future<void> setBarcodeReturnFocus(bool on) => _save(state.copyWith(barcodeReturnFocus: on));
  Future<void> tutorialOffered() => _save(state.copyWith(tutorialSeen: true));

  /// Gives [command] the shortcut [combo]. Returns why not (and changes nothing) when it cannot have it.
  Future<String?> assign(AppCommand command, KeyCombo combo) async {
    final problem = state.problemWith(command, combo);
    if (problem != null) return problem;
    await _save(state.copyWith(custom: {...state.custom, command: combo}));
    return null;
  }

  /// Turns [command]'s shortcut off; the command still works from its button.
  Future<void> turnOff(AppCommand command) => _save(state.copyWith(custom: {...state.custom, command: null}));

  /// Back to the default shortcut for [command]. Returns why not (and changes nothing) when another command now uses it.
  Future<String?> reset(AppCommand command) => _saveUnlessConflict(state.copyWith(custom: {...state.custom}..remove(command)));

  /// Back to the default shortcuts of a [section], or of every section when it is null. Returns why not (and changes
  /// nothing) when a command of another section now uses one of those defaults.
  Future<String?> resetAll([ShortcutSection? section]) =>
      _saveUnlessConflict(state.copyWith(custom: section == null ? const {} : ({...state.custom}..removeWhere((c, _) => c.section == section))));

  Future<String?> _saveUnlessConflict(KeyboardPrefs next) async {
    final clash = next.conflicts().firstOrNull;
    if (clash != null) {
      final (a, b) = clash;
      return '${next.keyOf(a)?.label ?? 'That key'} is now used by "${state.isCustom(a) ? a.label : b.label}". Change that shortcut first.';
    }
    await _save(next);
    return null;
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
