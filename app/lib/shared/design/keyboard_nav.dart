import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the Enter key does in a text input. Set it for a whole area with [EnterKeyBehavior].
enum EnterKeyAction {
  /// Decide from the field: leave multiline fields, fields with their own `onSubmitted` and search/send/go fields
  /// alone, and move to the next field in every other single-line field.
  automatic,

  /// Always move to the next field, even if the field has an `onSubmitted`.
  next,

  /// Leave Enter to the field's own `onSubmitted` (the form's submit action).
  submit,

  /// Leave Enter to the field (a new line).
  newline,

  /// Do nothing special; the field behaves as if Enter navigation did not exist.
  ignore,
}

/// Overrides [EnterKeyAction] for every input below it: `EnterKeyBehavior(action: EnterKeyAction.submit, child: …)`.
class EnterKeyBehavior extends InheritedWidget {
  const EnterKeyBehavior({super.key, required this.action, required super.child});
  final EnterKeyAction action;

  static EnterKeyAction of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<EnterKeyBehavior>()?.action ?? EnterKeyAction.automatic;

  @override
  bool updateShouldNotify(EnterKeyBehavior old) => old.action != action;
}

/// Handles the Enter key for the whole app: in a single-line text input it moves focus to the next input, like Tab.
/// Tab and Shift+Tab are Flutter's own focus traversal and are left untouched.
///
/// It is one `Focus` at the top of the tree. Key events travel from the focused widget up to it, so it sees Enter
/// for every field on every screen, dialog and sheet without any per-field code.
class EnterKeyNavigation extends StatelessWidget {
  const EnterKeyNavigation({super.key, required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) => enabled ? handleEnterKey(event) : KeyEventResult.ignored,
        child: child,
      );
}

bool _isEnter(KeyEvent e) => e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter;

/// Whether the app gave the field its own submit action. A Material `TextField` always hands `EditableText` an
/// internal `onSubmitted`, so the `TextField` (or `TextFormField`'s, which becomes one) is the one to ask.
bool _hasOwnSubmit(EditableTextState state) {
  final textField = state.context.findAncestorWidgetOfExactType<TextField>();
  return textField != null ? textField.onSubmitted != null : state.widget.onSubmitted != null;
}

/// Whether [state]'s field leaves Enter alone, given the chosen [action].
bool enterBelongsToField(EditableTextState state, EnterKeyAction action) {
  switch (action) {
    case EnterKeyAction.next:
      return state.widget.maxLines != 1; // a multiline field still needs its Enter for new lines
    case EnterKeyAction.submit:
    case EnterKeyAction.newline:
    case EnterKeyAction.ignore:
      return true;
    case EnterKeyAction.automatic:
      final w = state.widget;
      if (w.maxLines != 1) return true;
      if (_hasOwnSubmit(state)) return true;
      return const {TextInputAction.search, TextInputAction.send, TextInputAction.go, TextInputAction.newline}.contains(w.textInputAction);
  }
}

/// A field Enter may land on: an editable text input that is not read-only, or another form control (dropdown, checkbox …).
bool _eligible(FocusNode node) {
  final context = node.context;
  if (context == null || !node.canRequestFocus) return false;
  final editable = context.findAncestorStateOfType<EditableTextState>();
  if (editable != null) return !editable.widget.readOnly;
  return context.findAncestorStateOfType<FormFieldState<dynamic>>() != null;
}

/// Moves focus from the focused text input to the next eligible one. Returns [KeyEventResult.handled] if it did.
KeyEventResult handleEnterKey(KeyEvent event) {
  if (!_isEnter(event) || event is! KeyDownEvent) return KeyEventResult.ignored;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isShiftPressed || keyboard.isControlPressed || keyboard.isAltPressed || keyboard.isMetaPressed) return KeyEventResult.ignored;

  final start = FocusManager.instance.primaryFocus;
  final context = start?.context;
  if (start == null || context == null) return KeyEventResult.ignored;
  final field = context.findAncestorStateOfType<EditableTextState>();
  if (field == null) return KeyEventResult.ignored; // buttons, checkboxes… keep Enter as "activate"

  final composing = field.widget.controller.value.composing;
  if (composing.isValid && !composing.isCollapsed) return KeyEventResult.ignored; // Enter confirms an IME suggestion
  if (enterBelongsToField(field, EnterKeyBehavior.of(context))) return KeyEventResult.ignored;

  final startRect = start.rect;
  // Tab order can pass over buttons and read-only fields; keep going until an input is reached.
  for (var i = 0; i < 50; i++) {
    final moved = start.nextFocus();
    FocusManager.instance.applyFocusChangesIfNeeded(); // focus changes are otherwise applied a microtask later
    final now = FocusManager.instance.primaryFocus;
    if (!moved) break;
    if (now == null || now == start) break;
    final wrapped = now.rect.top < startRect.top - 1 || ((now.rect.top - startRect.top).abs() <= 1 && now.rect.left < startRect.left - 1);
    if (wrapped) {
      // Past the last field: stay on it instead of jumping back to the top of the form.
      start.requestFocus();
      return KeyEventResult.handled;
    }
    if (_eligible(now)) return KeyEventResult.handled;
  }
  start.requestFocus();
  return KeyEventResult.handled;
}

/// Whether Enter moves to the next field (Settings › Keyboard). Remembered per user on this device; on by default.
class KeyboardNavCubit extends Cubit<bool> {
  KeyboardNavCubit({Future<SharedPreferences>? prefs, Stream<String?>? userIds})
      : _prefs = prefs ?? SharedPreferences.getInstance(),
        super(true) {
    _sub = userIds?.listen((id) {
      if (id != _userId) loadFor(id);
    });
  }

  final Future<SharedPreferences> _prefs;
  StreamSubscription<String?>? _sub;
  String? _userId;

  static const _lastKey = 'enter_navigation_last';
  String _key(String? user) => user == null ? _lastKey : 'enter_navigation_$user';

  Future<void> loadFor(String? userId) async {
    _userId = userId;
    try {
      final p = await _prefs;
      emit(p.getBool(_key(userId)) ?? p.getBool(_lastKey) ?? true);
    } catch (_) {
      // Preferences unavailable: keep the current value.
    }
  }

  Future<void> set(bool enabled) async {
    emit(enabled);
    try {
      final p = await _prefs;
      await p.setBool(_key(_userId), enabled);
      await p.setBool(_lastKey, enabled);
    } catch (_) {
      // Still applies for this session.
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
