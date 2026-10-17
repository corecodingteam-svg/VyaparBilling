import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether this device's main shortcut modifier is Cmd (a Mac, also in a browser on a Mac) rather than Ctrl.
bool get primaryModifierIsCmd => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

/// A key and its modifiers, as a shortcut is shown, saved and matched. [ctrl] is the main modifier: Ctrl on Windows and
/// Linux, Cmd on a Mac.
class KeyCombo extends Equatable {
  const KeyCombo(this.key, {this.ctrl = false, this.shift = false, this.alt = false});

  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;
  final bool alt;

  static final _modifiers = {
    LogicalKeyboardKey.control, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.alt, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock, LogicalKeyboardKey.numLock, LogicalKeyboardKey.fn, LogicalKeyboardKey.altGraph,
  };

  /// The keypad's Enter is the same shortcut as the main Enter.
  static LogicalKeyboardKey _normal(LogicalKeyboardKey k) => k == LogicalKeyboardKey.numpadEnter ? LogicalKeyboardKey.enter : k;

  /// The combination pressed in [event]; null for a modifier on its own, or when the modifier that is not this device's
  /// main one is held (Cmd on Windows, Ctrl on a Mac), which no shortcut uses.
  static KeyCombo? fromEvent(KeyEvent event, [HardwareKeyboard? keyboard]) {
    final k = keyboard ?? HardwareKeyboard.instance;
    if (_modifiers.contains(event.logicalKey)) return null;
    final cmd = primaryModifierIsCmd;
    if (cmd ? k.isControlPressed : k.isMetaPressed) return null;
    return KeyCombo(_normal(event.logicalKey), ctrl: cmd ? k.isMetaPressed : k.isControlPressed, shift: k.isShiftPressed, alt: k.isAltPressed);
  }

  bool get hasModifier => ctrl || alt;

  static final _names = {
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.insert: 'Insert',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'PgUp',
    LogicalKeyboardKey.pageDown: 'PgDn',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
    LogicalKeyboardKey.slash: '/',
  };

  String get keyName => _names[key] ?? (key.keyLabel.isEmpty ? (key.debugName ?? '?') : key.keyLabel.toUpperCase());

  /// The keys in the order they are held, e.g. `['Ctrl', 'Shift', 'N']`.
  List<String> get parts => [
        if (ctrl) primaryModifierIsCmd ? 'Cmd' : 'Ctrl',
        if (alt) primaryModifierIsCmd ? 'Option' : 'Alt',
        if (shift) 'Shift',
        keyName,
      ];

  /// What people read, e.g. "Ctrl + N".
  String get label => parts.join(' + ');

  /// How it is saved: `ctrl+shift+<key id>`.
  String encode() => [if (ctrl) 'ctrl', if (alt) 'alt', if (shift) 'shift', key.keyId.toString()].join('+');

  static KeyCombo? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    final parts = text.split('+');
    final id = int.tryParse(parts.last);
    if (id == null) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(id) ?? LogicalKeyboardKey(id);
    final mods = parts.sublist(0, parts.length - 1).toSet();
    if (!mods.every(const {'ctrl', 'alt', 'shift'}.contains)) return null;
    return KeyCombo(key, ctrl: mods.contains('ctrl'), alt: mods.contains('alt'), shift: mods.contains('shift'));
  }

  @override
  List<Object?> get props => [key.keyId, ctrl, shift, alt];

  @override
  String toString() => label;
}

/// Shorthands for writing shortcuts.
KeyCombo ctrl(LogicalKeyboardKey key, {bool shift = false}) => KeyCombo(key, ctrl: true, shift: shift);
KeyCombo alt(LogicalKeyboardKey key, {bool shift = false}) => KeyCombo(key, alt: true, shift: shift);
KeyCombo plain(LogicalKeyboardKey key, {bool shift = false}) => KeyCombo(key, shift: shift);

/// Keys a text input needs for itself: typing, moving the cursor and deleting. While a text input has focus these are
/// left to it, so a shortcut on Delete or Home acts only when focus is not in a text input.
bool isTextEditingKey(KeyCombo c) {
  final k = c.key;
  final editing = {
    LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.home, LogicalKeyboardKey.end, LogicalKeyboardKey.pageUp, LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.backspace, LogicalKeyboardKey.delete, LogicalKeyboardKey.space,
  };
  if (editing.contains(k)) return true;
  if (k == LogicalKeyboardKey.enter) return !c.ctrl; // Ctrl+Enter is a shortcut; Enter belongs to the field
  if (c.hasModifier) return false;
  // A character key (letter, digit, punctuation) types itself; function keys, Esc, Insert and Tab do not.
  return k.keyLabel.length == 1 && (k.keyId & LogicalKeyboardKey.planeMask) == LogicalKeyboardKey.unicodePlane;
}
