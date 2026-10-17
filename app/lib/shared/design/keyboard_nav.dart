import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the Enter key does in a text input. Set it for a whole area with [EnterKeyBehavior].
enum EnterKeyAction {
  /// Decide from the field: leave multiline fields, fields with their own `onSubmitted` and search/send/go fields
  /// alone, and move to the next field in every other single-line field.
  automatic,

  /// Always move to the next field, even if the field has an `onSubmitted`.
  next,

  /// Move exactly like Tab: to the next thing that takes focus, buttons included, even if the field has an `onSubmitted`.
  tab,

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
///
/// [action] is what Enter does everywhere below unless an [EnterKeyBehavior] says otherwise for an area.
class EnterKeyNavigation extends StatelessWidget {
  const EnterKeyNavigation({super.key, required this.enabled, this.action = EnterKeyAction.automatic, required this.child});
  final bool enabled;
  final EnterKeyAction action;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) => enabled ? handleEnterKey(event) : KeyEventResult.ignored,
        child: EnterKeyBehavior(action: enabled ? action : EnterKeyAction.ignore, child: child),
      );
}

/// A control Enter passes over when moving to the next field; Tab still stops on it. For a choice that usually stays as
/// it is, such as an invoice row's unit between its quantity and price.
class SkipOnEnter extends StatelessWidget {
  const SkipOnEnter({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Runs [f] once the next frame has been drawn, and makes sure there is one: a key press alone does not draw a frame,
/// so a focus change waiting for one would otherwise wait for the next mouse move.
void afterNextFrame(VoidCallback f) {
  WidgetsBinding.instance.addPostFrameCallback((_) => f());
  WidgetsBinding.instance.ensureVisualUpdate();
}

bool _inAutocomplete(BuildContext context) {
  var found = false;
  context.visitAncestorElements((e) {
    found = e.widget is RawAutocomplete;
    return !found;
  });
  return found;
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
  // An item or party picker's Enter chooses the highlighted suggestion, whatever Enter does elsewhere.
  if (action != EnterKeyAction.ignore && _inAutocomplete(state.context)) return true;
  switch (action) {
    case EnterKeyAction.next:
    case EnterKeyAction.tab:
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
  if (context.findAncestorWidgetOfExactType<SkipOnEnter>() != null) return false;
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
  final action = EnterKeyBehavior.of(context);
  if (enterBelongsToField(field, action)) return KeyEventResult.ignored;
  if (action == EnterKeyAction.tab) {
    start.nextFocus();
    return KeyEventResult.handled;
  }

  focusNextField(start);
  return KeyEventResult.handled;
}

/// Moves focus from [start] to the next input in Tab order, passing over buttons and read-only fields. Past the last
/// input focus stays on [start] rather than going back to the top. Returns whether it moved.
bool focusNextField(FocusNode start) {
  // Where Tab order starts again after the last field: reaching it means there is no next field. Asked of the same policy
  // Tab uses, so sections (FocusTraversalGroups) side by side are followed as Tab follows them.
  final policy = FocusTraversalGroup.maybeOfNode(start) ?? ReadingOrderTraversalPolicy();
  final first = policy.findFirstFocus(start, ignoreCurrentFocus: true);
  // Tab order can pass over buttons and read-only fields; keep going until an input is reached.
  for (var i = 0; i < 50; i++) {
    final moved = start.nextFocus();
    FocusManager.instance.applyFocusChangesIfNeeded(); // focus changes are otherwise applied a microtask later
    final now = FocusManager.instance.primaryFocus;
    if (!moved) break;
    if (now == null || now == start) break;
    if (now == first) {
      // Past the last field: stay on it instead of jumping back to the top of the form.
      start.requestFocus();
      return false;
    }
    if (_eligible(now)) return true;
  }
  start.requestFocus();
  return false;
}

/// Put around an [Autocomplete] (an item or party picker) whose field's `onSubmitted` calls [PickOnEnter.submit]. Enter
/// then picks the highlighted suggestion and goes on to the next input, as Enter does in other inputs, even when picking
/// rebuilds the field. With Enter navigation off it only picks.
class PickOnEnter extends StatefulWidget {
  const PickOnEnter({super.key, required this.child});
  final Widget child;

  /// For the picker's text field: `onSubmitted: (_) => PickOnEnter.submit(context, onFieldSubmitted)`.
  static void submit(BuildContext context, VoidCallback onFieldSubmitted) {
    final state = context.findAncestorStateOfType<_PickOnEnterState>();
    onFieldSubmitted();
    state?._moveOnSoon();
  }

  @override
  State<PickOnEnter> createState() => _PickOnEnterState();
}

class _PickOnEnterState extends State<PickOnEnter> {
  final _node = FocusNode(debugLabel: 'PickOnEnter', skipTraversal: true, canRequestFocus: false);

  void _moveOnSoon() {
    final moveOn = EnterKeyBehavior.of(context) != EnterKeyAction.ignore;
    final hadFocus = _node.hasFocus;
    // After the pick has been drawn: it may have replaced the field, and the fields after it.
    afterNextFrame(() {
      if (!mounted) return;
      if (hadFocus && !_node.hasFocus && FocusManager.instance.primaryFocus is FocusScopeNode) {
        // Picking rebuilt the field and its focus was dropped: put the cursor in the new one.
        final field = _node.traversalDescendants.where(_eligible).firstOrNull;
        if (field == null) return;
        field.requestFocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
      }
      final here = FocusManager.instance.primaryFocus;
      if (moveOn && here != null && _node.hasFocus) focusNextField(here);
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _node, child: widget.child);
}
