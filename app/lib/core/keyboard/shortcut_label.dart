import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../shared/theme.dart';
import 'app_command.dart';
import 'keyboard_prefs.dart';

/// A button's text with its shortcut beside it ("Save   F10"), shown as the keyboard mode asks: Keyboard First on a
/// screen's [main] buttons, Keyboard Only on every button that has one, Standard not at all unless [always]. The key is
/// the user's own if they changed it, and nothing is shown for a shortcut they turned off.
class ShortcutLabel extends StatelessWidget {
  const ShortcutLabel(this.text, this.command, {super.key, this.main = false, this.always = false});

  final String text;
  final AppCommand command;
  final bool main;
  final bool always;

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<KeyboardPrefsCubit?>()?.state;
    final key = prefs?.keyOf(command);
    final mode = prefs?.mode ?? KeyboardMode.standard;
    final show = always || mode == KeyboardMode.keyboardOnly || (mode == KeyboardMode.keyboardFirst && main);
    if (!show || key == null) return Text(text);
    return Semantics(
      label: '$text, shortcut ${key.label}',
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(text),
          const SizedBox(width: AppSpace.md),
          Opacity(opacity: 0.72, child: Text(key.parts.join(' '), style: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w500))),
        ]),
      ),
    );
  }
}
