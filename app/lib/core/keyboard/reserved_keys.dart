import 'package:flutter/services.dart';

import 'key_combo.dart';

/// Why [c] cannot be a shortcut here, or null when it can. [web] adds the keys a browser keeps for itself: some it never
/// passes to a page at all (Ctrl+N, Ctrl+T, Ctrl+W), the rest would stop the browser doing what people expect of it.
String? reservedReason(KeyCombo c, {required bool web}) {
  final k = c.key;
  bool key(LogicalKeyboardKey other) => k == other;
  final only = !c.ctrl && !c.alt && !c.shift;
  final ctrlOnly = c.ctrl && !c.alt && !c.shift;
  final ctrlShift = c.ctrl && c.shift && !c.alt;
  final altOnly = c.alt && !c.ctrl && !c.shift;

  // Windows, and the app's own movement between fields.
  if (altOnly && key(LogicalKeyboardKey.f4)) return 'Windows uses Alt + F4 to close the app.';
  if (altOnly && (key(LogicalKeyboardKey.tab) || key(LogicalKeyboardKey.escape) || key(LogicalKeyboardKey.space))) return 'Windows uses ${c.label} to switch or manage windows.';
  if (c.ctrl && c.alt && key(LogicalKeyboardKey.delete)) return 'Ctrl + Alt + Delete belongs to Windows.';
  if (c.ctrl && key(LogicalKeyboardKey.escape)) return 'Windows uses ${c.label} for the Start menu or Task Manager.';
  if (key(LogicalKeyboardKey.printScreen)) return 'Print Screen belongs to Windows.';
  if (key(LogicalKeyboardKey.tab) && !c.ctrl && !c.alt) return 'Tab and Shift + Tab move between fields.';
  if (only && key(LogicalKeyboardKey.enter)) return 'Enter confirms or moves to the next field.';
  if (!web) return null;

  // The browser.
  final reason = switch (true) {
    _ when ctrlOnly && key(LogicalKeyboardKey.keyN) => 'opens a new window',
    _ when ctrlOnly && key(LogicalKeyboardKey.keyT) => 'opens a new tab',
    _ when ctrlOnly && key(LogicalKeyboardKey.keyW) => 'closes the tab',
    _ when ctrlShift && (key(LogicalKeyboardKey.keyN) || key(LogicalKeyboardKey.keyT) || key(LogicalKeyboardKey.keyW)) => 'opens or closes windows and tabs',
    _ when c.ctrl && key(LogicalKeyboardKey.tab) => 'switches tabs',
    _ when (ctrlOnly && (key(LogicalKeyboardKey.pageUp) || key(LogicalKeyboardKey.pageDown))) => 'switches tabs',
    _ when ctrlOnly && (key(LogicalKeyboardKey.keyL)) => 'goes to the address bar',
    _ when altOnly && key(LogicalKeyboardKey.keyD) => 'goes to the address bar',
    _ when only && key(LogicalKeyboardKey.f6) => 'goes to the address bar',
    _ when altOnly && (key(LogicalKeyboardKey.arrowLeft) || key(LogicalKeyboardKey.arrowRight) || key(LogicalKeyboardKey.home)) => 'goes back, forward or home',
    _ when (only || ctrlOnly || c.shift && !c.alt) && key(LogicalKeyboardKey.f5) => 'reloads the page, losing unsaved work',
    _ when (ctrlOnly || ctrlShift) && key(LogicalKeyboardKey.keyR) => 'reloads the page, losing unsaved work',
    _ when ctrlOnly && (key(LogicalKeyboardKey.keyH) || key(LogicalKeyboardKey.keyJ)) => 'opens history or downloads',
    _ when ctrlShift && (key(LogicalKeyboardKey.keyI) || key(LogicalKeyboardKey.keyJ) || key(LogicalKeyboardKey.keyC) || key(LogicalKeyboardKey.delete)) => 'opens developer tools or clears browsing data',
    _ when only && (key(LogicalKeyboardKey.f11) || key(LogicalKeyboardKey.f12)) => 'goes full screen or opens developer tools',
    _ when ctrlOnly && (key(LogicalKeyboardKey.equal) || key(LogicalKeyboardKey.minus) || key(LogicalKeyboardKey.digit0) || key(LogicalKeyboardKey.add) || key(LogicalKeyboardKey.numpadAdd) || key(LogicalKeyboardKey.numpadSubtract)) => 'zooms the page',
    _ when ctrlOnly && _digits.contains(k) => 'switches to a tab',
    _ when altOnly && (key(LogicalKeyboardKey.keyF) || key(LogicalKeyboardKey.keyE)) => 'opens the browser menu',
    _ => null,
  };
  return reason == null ? null : 'The browser uses ${c.label}: it $reason.';
}

final _digits = {
  LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
};
