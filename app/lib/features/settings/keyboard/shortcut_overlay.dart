import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/keyboard/keyboard.dart';
import '../../../shared/theme.dart';

var _showing = false;

/// The quick shortcut list (Ctrl+/ or ?): what works on this screen first, then moving around, then everything else.
/// [scopes] are where focus was when it was asked for, narrowest first.
Future<void> showShortcutOverlay(BuildContext context, List<KeyboardScope> scopes) async {
  if (_showing) return;
  _showing = true;
  try {
    await showDialog<void>(context: context, builder: (_) => _Overlay(scopes: scopes, prefs: context.read<KeyboardPrefsCubit>().state));
  } finally {
    _showing = false;
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.scopes, required this.prefs});
  final List<KeyboardScope> scopes;
  final KeyboardPrefs prefs;

  Widget _line(String what, Widget keys) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [SizedBox(width: 150, child: keys), const SizedBox(width: AppSpace.md), Expanded(child: Text(what))]),
      );

  Widget _command(AppCommand c) {
    final keys = prefs.keysOf(c);
    return _line(c.label, keys.isEmpty ? const Text('Off', style: AppText.helper) : KeyChip.combo(keys.first, dense: true));
  }

  @override
  Widget build(BuildContext context) {
    final here = <AppCommand>{
      for (final s in scopes)
        for (final e in s.commands.entries)
          if (e.value != null && e.key != AppCommand.shortcutHelp) e.key,
    };
    final where = [for (final s in scopes.reversed) if (s.name != 'App' && s.name != 'List') s.name].join(' › ');
    final rest = AppCommand.values.where((c) => !here.contains(c) && prefs.keysOf(c).isNotEmpty).toList();
    final router = GoRouter.maybeOf(context);
    return AlertDialog(
      title: const Text('Keyboard Shortcuts'),
      content: SizedBox(
        width: AppSize.dialogMd,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (here.isNotEmpty) ...[
              Text(where.isEmpty ? 'ON THIS SCREEN' : 'ON THIS SCREEN · ${where.toUpperCase()}', style: AppText.label),
              for (final c in here) _command(c),
              const SizedBox(height: AppSpace.md),
            ],
            const Text('NAVIGATION', style: AppText.label),
            for (final (keys, what) in navigationKeys) _line(what, KeyChip.text(keys, dense: true)),
            const SizedBox(height: AppSpace.md),
            Text(here.isEmpty ? 'SHORTCUTS' : 'ELSEWHERE', style: AppText.label),
            for (final c in rest) _command(c),
          ]),
        ),
      ),
      actions: [
        if (router != null) ...[
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              router.go('/keyboard');
            },
            child: const Text('Change Shortcuts'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              router.go('/keyboard/playbook');
            },
            child: const Text('View all shortcuts'),
          ),
        ],
        FilledButton(autofocus: true, onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
