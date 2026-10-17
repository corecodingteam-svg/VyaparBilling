import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/keyboard/keyboard.dart';
import '../../../shared/theme.dart';
import '../../../shared/widgets.dart';

/// Settings › Keyboard & Shortcuts: how much the app leans on the keyboard, what Enter does, the barcode box, and every
/// shortcut, which can be changed, turned off or reset. Saved for this login on this device.
class KeyboardSettingsScreen extends StatelessWidget {
  const KeyboardSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<KeyboardPrefsCubit>();
    return BlocBuilder<KeyboardPrefsCubit, KeyboardPrefs>(
      builder: (context, prefs) => FocusFirstField(
        // Built in full (not as a lazy list) so Tab reaches every shortcut, also those scrolled out of view.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSize.page),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSize.dialogXl * 1.4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: AppSpace.sm, children: [
                const Text('Keyboard & Shortcuts', style: AppText.title),
                OutlinedButton.icon(onPressed: () => context.go('/keyboard/playbook'), icon: const Icon(Icons.school_outlined), label: const Text('Keyboard Playbook')),
              ]),
              const SizedBox(height: AppSpace.xs),
              Text('Work without the mouse. These choices are saved for your login on this device.', style: AppText.helper.copyWith(fontSize: AppFont.body)),
              const SizedBox(height: AppSpace.lg),
              _Card(title: 'Keyboard Mode', children: [
                RadioGroup<KeyboardMode>(
                  groupValue: prefs.mode,
                  onChanged: (m) => cubit.setMode(m!),
                  child: Column(children: [
                    for (final m in KeyboardMode.values) RadioListTile<KeyboardMode>(contentPadding: EdgeInsets.zero, value: m, title: Text(m.label), subtitle: Text(m.description)),
                  ]),
                ),
              ]),
              _Card(title: 'Enter Key Behavior', children: [
                RadioGroup<EnterBehavior>(
                  groupValue: prefs.enter,
                  onChanged: (e) => cubit.setEnter(e!),
                  child: Column(children: [
                    for (final e in EnterBehavior.values) RadioListTile<EnterBehavior>(contentPadding: EdgeInsets.zero, value: e, title: Text(e.label), subtitle: Text(e.description)),
                  ]),
                ),
              ]),
              _Card(title: 'Barcode', children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: prefs.barcodeReturnFocus,
                  onChanged: (v) => cubit.setBarcodeReturnFocus(v!),
                  title: const Text('Automatically return focus to item/barcode field'),
                  subtitle: const Text('After a scan the cursor stays in the scan box, ready for the next one. Off: it goes on to the quantity.'),
                ),
              ]),
              for (final section in ShortcutSection.values) _SectionCard(section: section, prefs: prefs),
              const SizedBox(height: AppSpace.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: prefs.custom.isEmpty
                      ? null
                      : () async {
                          if (await _confirm(context, 'Restore default shortcuts?', 'Every shortcut you changed or turned off goes back to how it came.')) {
                            await cubit.resetAll();
                          }
                        },
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore Default Shortcuts'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, this.action, required this.children});
  final String title;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [Expanded(child: Text(title, style: AppText.subtitle)), ?action]),
              const SizedBox(height: AppSpace.sm),
              ...children,
            ]),
          ),
        ),
      );
}

/// What the sections without shortcuts of their own use.
const _sharedNote = {
  ShortcutSection.purchase: 'Purchase bills use the same shortcuts as sale invoices: see Billing and General.',
  ShortcutSection.reports: 'Reports use the General shortcuts, such as Search this screen.',
};

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.prefs});
  final ShortcutSection section;
  final KeyboardPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final commands = AppCommand.values.where((c) => c.section == section).toList();
    final groups = <String, List<AppCommand>>{};
    for (final c in commands) {
      (groups[c.group] ??= []).add(c);
    }
    final changed = commands.any(prefs.custom.containsKey);
    return _Card(
      title: section.label,
      action: commands.isEmpty
          ? null
          : TextButton(
              onPressed: !changed
                  ? null
                  : () async {
                      if (!await _confirm(context, 'Reset ${section.label} shortcuts?', 'The ${section.label} shortcuts go back to how they came.')) return;
                      if (!context.mounted) return;
                      final problem = await context.read<KeyboardPrefsCubit>().resetAll(section);
                      if (problem != null && context.mounted) showError(context, problem);
                    },
              child: const Text('Reset to Default'),
            ),
      children: [
        if (commands.isEmpty) Text(_sharedNote[section] ?? '', style: AppText.helper),
        if (section == ShortcutSection.general) ...[
          const _GroupHeading('Navigation'),
          for (final (keys, what) in navigationKeys)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Row(children: [Expanded(child: Text(what)), KeyChip.text(keys)]),
            ),
          Text('Tab, Enter and the arrow keys move around and cannot be changed.', style: AppText.helper),
        ],
        for (final MapEntry(key: group, value: list) in groups.entries) ...[
          _GroupHeading(group),
          for (final c in list) _ShortcutRow(key: ValueKey('shortcut-${c.id}'), command: c, prefs: prefs),
        ],
      ],
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xs),
        child: Text(text.toUpperCase(), style: AppText.label),
      );
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({super.key, required this.command, required this.prefs});
  final AppCommand command;
  final KeyboardPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final key = prefs.keyOf(command);
    final def = command.defaultKey(web: prefs.web);
    final also = prefs.keysOf(command).skip(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: AppSpace.xs, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSize.dialogMd),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(command.label, style: AppText.bodyStrong),
            Text(command.description, style: AppText.helper),
          ]),
        ),
        Wrap(spacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (key == null) const Text('Off', style: TextStyle(color: AppColors.textMuted)) else KeyChip.combo(key),
          for (final k in also) ...[const Text('or', style: AppText.helper), KeyChip.combo(k)],
          TextButton(onPressed: () => showShortcutEditor(context, command), child: Text(key == null ? 'Set' : 'Change')),
          if (prefs.isCustom(command) || (prefs.custom.containsKey(command) && key == null))
            IconButton(
              tooltip: def == null ? 'Back to no shortcut' : 'Back to the default, ${def.label}',
              icon: const Icon(Icons.undo),
              onPressed: () async {
                final problem = await context.read<KeyboardPrefsCubit>().reset(command);
                if (problem != null && context.mounted) showError(context, problem);
              },
            ),
        ]),
      ]),
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    ) ??
    false;

/// The keys pressed so far in the shortcut editor; null until a key (not just a modifier) is pressed.
class ShortcutCaptureCubit extends Cubit<KeyCombo?> {
  ShortcutCaptureCubit() : super(null);
  void pressed(KeyCombo c) => emit(c);
}

/// Asks for a new shortcut for [command] by having it pressed. A key another command uses, or one the browser or Windows
/// keeps, is refused with the reason; nothing is replaced silently.
Future<void> showShortcutEditor(BuildContext context, AppCommand command) => showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<KeyboardPrefsCubit>(),
        child: BlocProvider(create: (_) => ShortcutCaptureCubit(), child: _ShortcutEditor(command: command)),
      ),
    );

class _ShortcutEditor extends StatelessWidget {
  const _ShortcutEditor({required this.command});
  final AppCommand command;

  /// Takes every key but Tab (to reach the buttons) and Esc (to close), so pressing a shortcut here does not run it.
  KeyEventResult _key(BuildContext context, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    final combo = KeyCombo.fromEvent(e);
    if (combo == null) return KeyEventResult.handled; // a modifier on its own: wait for the key
    if (combo.key == LogicalKeyboardKey.tab && !combo.ctrl && !combo.alt) return KeyEventResult.ignored;
    if (e is KeyDownEvent) context.read<ShortcutCaptureCubit>().pressed(combo);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<KeyboardPrefsCubit>().state;
    final combo = context.watch<ShortcutCaptureCubit>().state;
    final problem = combo == null || combo == prefs.keyOf(command) ? null : prefs.problemWith(command, combo);
    final canSave = combo != null && problem == null && combo != prefs.keyOf(command);
    Future<void> save() async {
      final error = await context.read<KeyboardPrefsCubit>().assign(command, combo!);
      if (!context.mounted) return;
      if (error != null) return showError(context, error);
      Navigator.pop(context);
    }

    return AlertDialog(
      title: Text('Shortcut for "${command.label}"'),
      content: SizedBox(
        width: AppSize.dialogSm,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Press the keys you want to use.'),
          const SizedBox(height: AppSpace.md),
          Focus(
            autofocus: true,
            onKeyEvent: (_, e) => _key(context, e),
            child: Builder(
              builder: (context) => Container(
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: Focus.of(context).hasFocus ? AppColors.primary : AppColors.border, width: Focus.of(context).hasFocus ? AppFocus.width : 1),
                ),
                child: combo == null
                    ? Text(Focus.of(context).hasFocus ? 'Waiting for keys…' : 'Click here or Shift+Tab back, then press the keys', style: const TextStyle(color: AppColors.textMuted))
                    : KeyChip.combo(combo),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          if (problem != null)
            Text(problem, style: const TextStyle(color: AppColors.dangerText))
          else if (combo != null && combo == prefs.keyOf(command))
            Text('That is already the shortcut for "${command.label}".', style: AppText.helper)
          else
            Text(
              prefs.web ? 'Keys the browser keeps for itself (such as Ctrl + T, Ctrl + W and Ctrl + N) cannot be used. Tab moves to the buttons; Esc cancels.' : 'Tab moves to the buttons; Esc cancels.',
              style: AppText.helper,
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (prefs.keyOf(command) != null)
          TextButton(
            onPressed: () {
              context.read<KeyboardPrefsCubit>().turnOff(command);
              Navigator.pop(context);
            },
            child: const Text('Turn Off'),
          ),
        FilledButton(onPressed: canSave ? save : null, child: const Text('Save')),
      ],
    );
  }
}
