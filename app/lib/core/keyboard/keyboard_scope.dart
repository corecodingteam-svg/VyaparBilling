import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme.dart' show AppButtons;
import 'app_command.dart';
import 'key_combo.dart';
import 'keyboard_prefs.dart';

/// Says what each [AppCommand] does in the area below it: the whole app, a module, a screen, a dialog or a list of rows.
/// Scopes nest, and when a shortcut is pressed the narrowest scope around the focused widget that handles the command
/// runs it, so a payment dialog's Ctrl+Enter wins over the invoice's, which wins over the app's.
///
/// A command mapped to null is known but not available right now (Save while saving): the next scope out gets a chance,
/// and if none takes it the key goes on to the browser or system as if there were no shortcut.
class KeyboardScope extends StatefulWidget {
  const KeyboardScope({super.key, required this.name, this.commands = const {}, this.autofocus = false, required this.child});

  /// Where this is, as the shortcut overlay names it: "Sale invoice", "Payment".
  final String name;
  final Map<AppCommand, VoidCallback?> commands;

  /// Take focus when nothing in the page has it, so shortcuts work before anything is clicked.
  final bool autofocus;
  final Widget child;

  @override
  State<KeyboardScope> createState() => _KeyboardScopeState();
}

class _KeyboardScopeState extends State<KeyboardScope> {
  static final _mounted = <_KeyboardScopeState>{};
  final _node = FocusNode(debugLabel: 'KeyboardScope', skipTraversal: true);

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
  }

  @override
  void dispose() {
    _mounted.remove(this);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _node, autofocus: widget.autofocus, skipTraversal: true, child: widget.child);
}

/// The scopes that apply where focus is now, narrowest first. Focus can sit above every scope of the page (on the page
/// itself before anything is chosen, or after the focused field was removed); the page's outermost scope then applies,
/// so its shortcuts still work but a list's row shortcuts do not.
List<KeyboardScope> activeKeyboardScopes() {
  final primary = FocusManager.instance.primaryFocus;
  if (primary == null) return const [];
  BuildContext? start = primary.context;
  _KeyboardScopeState? below;
  for (final s in _KeyboardScopeState._mounted) {
    if (!s.mounted || !s._node.ancestors.contains(primary)) continue;
    if (below == null || s._node.ancestors.length < below._node.ancestors.length) below = s;
  }
  final chain = <KeyboardScope>[];
  if (below != null) {
    chain.add(below.widget);
    start = below.context;
  }
  var state = start?.findAncestorStateOfType<_KeyboardScopeState>();
  while (state != null) {
    chain.add(state.widget);
    state = state.context.findAncestorStateOfType<_KeyboardScopeState>();
  }
  return chain;
}

/// Runs the shortcut in [event], if [prefs] maps it to a command that a scope around the focus handles. Keys a text input
/// needs (letters, Delete, the arrows…) are left to it while one has focus.
KeyEventResult handleShortcutKey(KeyEvent event, KeyboardPrefs prefs) {
  if (event is KeyUpEvent) return KeyEventResult.ignored;
  final combo = KeyCombo.fromEvent(event);
  if (combo == null) return KeyEventResult.ignored;
  final commands = prefs.commandsFor(combo);
  if (commands.isEmpty) return KeyEventResult.ignored;
  final inText = FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null;
  if (inText && isTextEditingKey(combo)) return KeyEventResult.ignored;
  for (final scope in activeKeyboardScopes()) {
    for (final c in commands) {
      final run = scope.commands[c];
      if (run == null) continue;
      // A held key repeats: it is still ours (so the browser does not act on it), but runs once.
      if (event is KeyDownEvent) run();
      return KeyEventResult.handled;
    }
  }
  // No screen took it. A few commands still mean something everywhere: Search goes to the page's search box, and Save in
  // a dialog presses the dialog's main button.
  final fallback = _fallback(commands);
  if (fallback == null) return KeyEventResult.ignored;
  if (event is KeyDownEvent) fallback();
  return KeyEventResult.handled;
}

VoidCallback? _fallback(List<AppCommand> commands) {
  final focus = FocusManager.instance.primaryFocus;
  final page = (focus is FocusScopeNode ? focus : focus?.nearestScope)?.context;
  if (focus?.context == null || page == null) return null;
  if (commands.contains(AppCommand.find)) {
    final box = _searchBox(page);
    if (box != null && box != focus) return box.requestFocus;
  }
  if (commands.any(const {AppCommand.save, AppCommand.submit, AppCommand.saveAndComplete}.contains) && ModalRoute.of(focus!.context!) is PopupRoute) {
    return _mainButton(page);
  }
  return null;
}

/// The top-left search box (a text input whose keyboard action is Search) on the page.
FocusNode? _searchBox(BuildContext page) {
  final boxes = <FocusNode>[];
  void visit(Element e) {
    final w = e.widget;
    if (w is EditableText && w.textInputAction == TextInputAction.search && w.focusNode.canRequestFocus && !w.readOnly) boxes.add(w.focusNode);
    e.visitChildren(visit);
  }

  page.visitChildElements(visit);
  boxes.sort((a, b) => (a.rect.top - b.rect.top).abs() > 4 ? a.rect.top.compareTo(b.rect.top) : a.rect.left.compareTo(b.rect.left));
  return boxes.firstOrNull;
}

/// What a dialog's main button (its filled one, the last if there are several) does; null when there is none to press.
/// A button that deletes (styled [AppButtons.destructive]) is never pressed this way: that takes a deliberate Enter on it.
VoidCallback? _mainButton(BuildContext dialog) {
  final buttons = <(Rect, VoidCallback)>[];
  void visit(Element e) {
    final w = e.widget;
    final box = e.renderObject;
    if (w is FilledButton && w.onPressed != null && !identical(w.style, AppButtons.destructive) && box is RenderBox && box.hasSize) {
      buttons.add((box.localToGlobal(Offset.zero) & box.size, w.onPressed!));
    }
    e.visitChildren(visit);
  }

  dialog.visitChildElements(visit);
  buttons.sort((a, b) => (a.$1.bottom - b.$1.bottom).abs() > 4 ? a.$1.bottom.compareTo(b.$1.bottom) : a.$1.right.compareTo(b.$1.right));
  return buttons.lastOrNull?.$2;
}

/// Sends shortcut keys to the [KeyboardScope]s. One sits at the top of the app, above the Navigator, so it sees every key
/// that no focused widget used, on every screen, dialog and sheet.
class KeyboardShortcuts extends StatelessWidget {
  const KeyboardShortcuts({super.key, required this.prefs, required this.child});
  final KeyboardPrefs prefs;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) => handleShortcutKey(event, prefs),
        child: child,
      );
}
