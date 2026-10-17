import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/keyboard/keyboard.dart';
import '../../../shared/theme.dart';

enum PracticeStatus { waiting, correct, wrong }

/// Where a practice box is: waiting, got it right, or got [pressed] instead.
class PracticeCubit extends Cubit<(PracticeStatus, KeyCombo?)> {
  PracticeCubit() : super((PracticeStatus.waiting, null));
  void pressed(KeyCombo c, {required bool right}) => emit((right ? PracticeStatus.correct : PracticeStatus.wrong, c));
}

/// "Try it": press [keys] to learn them. A key pressed in the box is only checked against [keys], never acted on, so
/// nothing is saved, printed or deleted while practising. Esc, and Tab unless Tab is the key being learnt, still leave
/// the box, so it never holds the cursor.
class PracticeKey extends StatefulWidget {
  const PracticeKey({super.key, required this.keys, required this.toDo, required this.does, this.onCorrect, this.autofocus = false});

  final KeyCombo keys;

  /// What the keys are for, as in "Press F4 to ...": "open Product Search".
  final String toDo;

  /// The same, as in "F4 ...": "opens Product Search".
  final String does;
  final VoidCallback? onCorrect;
  final bool autofocus;

  @override
  State<PracticeKey> createState() => _PracticeKeyState();
}

/// Stateful only to own the box's focus, which [PracticeKey.autofocus] takes when it appears (even from a button that
/// has it, as in the tutorial).
class _PracticeKeyState extends State<PracticeKey> {
  final _focus = FocusNode(debugLabel: 'Practice');

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) afterNextFrame(() => mounted ? _focus.requestFocus() : null);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider(create: (_) => PracticeCubit(), child: _PracticeBox(widget, _focus));
}

class _PracticeBox extends StatelessWidget {
  const _PracticeBox(this.p, this.focus);
  final PracticeKey p;
  final FocusNode focus;

  KeyEventResult _key(BuildContext context, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final combo = KeyCombo.fromEvent(e);
    if (combo == null) return KeyEventResult.handled; // a modifier on its own: wait for the key
    final right = combo == p.keys;
    final learningTab = p.keys.key == LogicalKeyboardKey.tab;
    final done = context.read<PracticeCubit>().state.$1 == PracticeStatus.correct;
    if (combo.key == LogicalKeyboardKey.escape && !right) return KeyEventResult.ignored;
    if (combo.key == LogicalKeyboardKey.tab && !combo.ctrl && (!learningTab || done)) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      context.read<PracticeCubit>().pressed(combo, right: right);
      if (right && !done) p.onCorrect?.call();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final (status, pressed) = context.watch<PracticeCubit>().state;
    return Focus(
      focusNode: focus,
      onKeyEvent: (_, e) => _key(context, e),
      child: Builder(builder: (context) {
        final focused = Focus.of(context).hasFocus;
        final (color, line) = switch (status) {
          PracticeStatus.correct => (AppColors.moneyIn, '✓ Correct! ${p.keys.label} ${p.does}.'),
          PracticeStatus.wrong => (AppColors.dangerText, 'That was ${pressed!.label}. Press ${p.keys.label} to ${p.toDo}.'),
          PracticeStatus.waiting => (AppColors.textMuted, focused ? 'Waiting for key…' : 'Select this box (or Tab to it), then press the key.'),
        };
        return GestureDetector(
          onTap: () => Focus.of(context).requestFocus(),
          child: Semantics(
            label: 'Practice: press ${p.keys.label} to ${p.toDo}',
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: focused ? AppColors.primary : AppColors.border, width: focused ? AppFocus.width : 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('TRY IT', style: AppText.label),
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Text('Press'),
                  KeyChip.combo(p.keys),
                  Text('to ${p.toDo}.'),
                ]),
                const SizedBox(height: AppSpace.sm),
                Text(line, style: TextStyle(color: color, fontWeight: status == PracticeStatus.waiting ? FontWeight.w400 : FontWeight.w600)),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

/// Which tutorial step is showing (0 is the welcome), and which were practised.
class TutorialCubit extends Cubit<(int, Set<int>)> {
  TutorialCubit() : super((0, const {}));
  void go(int step) => emit((step, state.$2));
  void practised(int step) => emit((state.$1, {...state.$2, step}));
}

/// The first-time tutorial: five keys to start with, each practised safely. Offered once, when Keyboard First or
/// Keyboard Only is first chosen, and from the Playbook at any time.
Future<void> showKeyboardTutorial(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<KeyboardPrefsCubit>(),
        child: BlocProvider(create: (_) => TutorialCubit(), child: const _Tutorial()),
      ),
    );

class _Tutorial extends StatelessWidget {
  const _Tutorial();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<KeyboardPrefsCubit>().state;
    final (step, done) = context.watch<TutorialCubit>().state;
    final cubit = context.read<TutorialCubit>();
    final steps = <(String, KeyCombo, String, String)>[
      ('Use Tab to move forward.', plain(LogicalKeyboardKey.tab), 'go to the next field', 'goes to the next field'),
      ('Use Shift + Tab to move backward.', plain(LogicalKeyboardKey.tab, shift: true), 'go back a field', 'goes back a field'),
      ('Use Enter to confirm.', plain(LogicalKeyboardKey.enter), 'confirm, or go to the next field', 'confirms, or goes to the next field'),
      if (prefs.keyOf(AppCommand.lookup) case final k?) ('Press ${k.label} to search.', k, 'search for an item', 'searches for an item'),
      if (prefs.keyOf(AppCommand.submit) case final k?) ('Press ${k.label} to save.', k, 'save', 'saves'),
    ];
    final last = steps.length + 1;
    Widget body;
    if (step == 0) {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < steps.length; i++) ...[
          Text('STEP ${i + 1}', style: AppText.label),
          Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: Text(steps[i].$1)),
        ],
        Text('You can practise each one here; nothing is saved while you do.', style: AppText.helper),
      ]);
    } else if (step < last) {
      final (text, keys, toDo, does) = steps[step - 1];
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('STEP $step OF ${steps.length}', style: AppText.label),
        const SizedBox(height: AppSpace.xs),
        Text(text, style: AppText.subtitle),
        const SizedBox(height: AppSpace.md),
        PracticeKey(key: ValueKey(step), keys: keys, toDo: toDo, does: does, autofocus: true, onCorrect: () => cubit.practised(step)),
      ]);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('You are ready.', style: AppText.subtitle),
        const SizedBox(height: AppSpace.sm),
        Text('You practised ${done.length} of ${steps.length} keys. Press ${prefs.keyOf(AppCommand.shortcutHelp)?.label ?? '?'} on any screen to see its shortcuts, or open the Keyboard Playbook to learn more.'),
      ]);
    }
    return AlertDialog(
      title: const Text('Welcome to Keyboard Mode'),
      content: SizedBox(width: AppSize.dialogSm, child: body),
      actions: [
        if (step > 0 && step < last) TextButton(onPressed: () => cubit.go(step - 1), child: const Text('Back')),
        if (step < last) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(
          autofocus: step == 0 || step == last,
          onPressed: step == last ? () => Navigator.pop(context) : () => cubit.go(step + 1),
          child: Text(step == 0 ? 'Start Practice' : step == last ? 'Done' : done.contains(step) ? 'Next' : 'Skip'),
        ),
      ],
    );
  }
}
