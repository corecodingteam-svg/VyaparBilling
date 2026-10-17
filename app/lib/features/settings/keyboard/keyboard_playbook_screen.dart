import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/keyboard/keyboard.dart';
import '../../../shared/theme.dart';
import 'practice.dart';

/// One thing to learn in a topic: what to do, the keys, and whether it can be tried here.
class _Step {
  const _Step(this.text, {this.keys, this.command, this.toDo, this.does});

  final String text;

  /// Fixed keys ("Tab"); or a [command], whose current shortcut is shown (and practised, with [toDo] and [does]).
  final String? keys;
  final AppCommand? command;
  final String? toDo, does;
}

class _Topic {
  const _Topic(this.id, this.title, this.blurb, this.icon, this.steps);
  final String id, title, blurb;
  final IconData icon;
  final List<_Step> steps;
}

const _topics = [
  _Topic('navigation', 'Navigation', 'Move around the app', Icons.open_with, [
    _Step('Go to the next field, button or row.', keys: 'Tab'),
    _Step('Go back to the previous one.', keys: 'Shift + Tab'),
    _Step('Confirm, or go on to the next field. In a picker it picks the highlighted suggestion; in a box of several lines it starts a new line.', keys: 'Enter'),
    _Step('Cancel, or close the dialog or form. A form with unsaved changes asks first.', command: AppCommand.cancel),
    _Step('Search parties, items and documents from any screen.', command: AppCommand.quickSearch, toDo: 'open quick search', does: 'opens quick search'),
    _Step('See the shortcuts of the screen you are on.', command: AppCommand.shortcutHelp, toDo: 'show the shortcuts', does: 'shows the shortcuts'),
  ]),
  _Topic('billing', 'Billing', 'Create invoices', Icons.receipt_long_outlined, [
    _Step('Start a new invoice. The customer box is first.', command: AppCommand.newRecord, toDo: 'start a new invoice', does: 'starts a new invoice'),
    _Step('Type the customer and press Enter to pick them.', keys: 'Enter'),
    _Step('Search for an item in the row you are on.', command: AppCommand.lookup, toDo: 'open Product Search', does: 'opens Product Search'),
    _Step('Enter goes item → quantity → price → discount → tax → the next row\'s item.', keys: 'Enter'),
    _Step('Add an item row.', command: AppCommand.addRow, toDo: 'add a row', does: 'adds a row'),
    _Step('Copy the row you are on.', command: AppCommand.duplicateRow, toDo: 'copy the row', does: 'copies the row'),
    _Step('Remove the row you are on (when the cursor is not in a text box).', command: AppCommand.removeRow),
    _Step('Go to the payment received.', command: AppCommand.payment, toDo: 'go to the payment', does: 'goes to the payment'),
    _Step('Save the invoice.', command: AppCommand.submit, toDo: 'save the invoice', does: 'saves the invoice'),
    _Step('Save and show it for printing.', command: AppCommand.saveAndComplete, toDo: 'save and print', does: 'saves and shows it for printing'),
    _Step('Print it.', command: AppCommand.print, toDo: 'print', does: 'prints'),
  ]),
  _Topic('inventory', 'Inventory', 'Manage stock', Icons.inventory_2_outlined, [
    _Step('On Items, add a new item.', command: AppCommand.newRecord, toDo: 'add an item', does: 'adds an item'),
    _Step('Edit the selected item. Beside the details, ↑ and ↓ through the list show each item.', command: AppCommand.editSelected, toDo: 'edit the item', does: 'edits the item'),
    _Step('Add or reduce its stock.', command: AppCommand.adjustStock, toDo: 'adjust stock', does: 'adjusts stock'),
    _Step('Delete it (you are asked first).', command: AppCommand.delete),
    _Step('Stock comes in with purchase bills and goes out with sale invoices: see Billing.'),
  ]),
  _Topic('search', 'Search', 'Find anything fast', Icons.search, [
    _Step('Search everything: parties, items, invoices, payments.', command: AppCommand.quickSearch, toDo: 'open quick search', does: 'opens quick search'),
    _Step('In quick search, ↓ goes into the results; ↑ ↓ move and Enter opens one.', keys: '↓'),
    _Step('Go to the search box of the screen you are on.', command: AppCommand.find, toDo: 'search this screen', does: 'searches this screen'),
    _Step('In a picker, ↑ ↓ highlight a suggestion and Enter picks it; Esc closes the list.', keys: '↑ ↓'),
  ]),
  _Topic('tables', 'Tables', 'Navigate data fast', Icons.table_rows_outlined, [
    _Step('Previous / next row.', keys: '↑ ↓'),
    _Step('Open the row.', keys: 'Enter'),
    _Step('First / last row of the page.', keys: 'Home / End'),
    _Step('Previous / next page.', keys: 'PgUp / PgDn'),
    _Step('The very first record.', command: AppCommand.firstRecord, toDo: 'go to the first record', does: 'goes to the first record'),
    _Step('The very last record.', command: AppCommand.lastRecord, toDo: 'go to the last record', does: 'goes to the last record'),
    _Step('Edit the selected row.', command: AppCommand.editSelected, toDo: 'edit the selected row', does: 'edits the selected row'),
  ]),
  _Topic('barcode', 'Barcode', 'Fast billing', Icons.qr_code_scanner, [
    _Step('Put the cursor in the scan box above the invoice items (or the POS search box), and scan. A scanner types the code and presses Enter for you.'),
    _Step('Each scan adds the item; scanning it again adds one more. The box empties itself for the next scan.'),
    _Step('A code that is not found stays selected, so the next scan replaces it.'),
    _Step('The cursor stays in the scan box after each scan. Turn that off in Keyboard & Shortcuts to go to the quantity instead.'),
  ]),
];

/// Settings › Keyboard Playbook: a guide for people learning to work from the keyboard, with keys to try safely.
class KeyboardPlaybookScreen extends StatelessWidget {
  const KeyboardPlaybookScreen({super.key, this.topic});

  /// The topic being learnt, from `?topic=`; the topic cards when null.
  final String? topic;

  @override
  Widget build(BuildContext context) {
    final open = _topics.where((t) => t.id == topic).firstOrNull;
    return BlocProvider(
      create: (_) => ReferenceFilterCubit(),
      child: FocusFirstField(
        page: topic,
        // Built in full so Tab reaches everything, also what is scrolled out of view.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSize.page),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSize.dialogXl * 1.4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: AppSpace.sm, children: [
                const Text('Keyboard Playbook', style: AppText.title),
                Wrap(spacing: AppSpace.sm, children: [
                  OutlinedButton.icon(onPressed: () => showKeyboardTutorial(context), icon: const Icon(Icons.play_arrow), label: const Text('Start the Tutorial')),
                  OutlinedButton.icon(onPressed: () => context.go('/keyboard'), icon: const Icon(Icons.tune), label: const Text('Change Shortcuts')),
                ]),
              ]),
              const SizedBox(height: AppSpace.xs),
              Text('Work faster without reaching for the mouse.', style: AppText.helper.copyWith(fontSize: AppFont.bodyLarge)),
              const SizedBox(height: AppSpace.lg),
              if (open == null) const _TopicCards() else _Lesson(topic: open),
              const SizedBox(height: AppSpace.xl),
              const _Reference(),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TopicCards extends StatelessWidget {
  const _TopicCards();

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpace.md, runSpacing: AppSpace.md, children: [
        for (final t in _topics)
          SizedBox(
            width: 240,
            child: Card(
              child: InkWell(
                borderRadius: AppRadius.lgAll,
                onTap: () => context.go('/keyboard/playbook?topic=${t.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(t.icon, color: AppColors.primary),
                    const SizedBox(height: AppSpace.sm),
                    Text(t.title, style: AppText.subtitle),
                    Text(t.blurb, style: AppText.helper),
                    const SizedBox(height: AppSpace.sm),
                    Text('Learn →', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
      ]);
}

class _Lesson extends StatelessWidget {
  const _Lesson({required this.topic});
  final _Topic topic;

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<KeyboardPrefsCubit>().state;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => context.go('/keyboard/playbook'), icon: const Icon(Icons.arrow_back), label: const Text('All topics')),
          ),
          Row(children: [Icon(topic.icon, color: AppColors.primary), const SizedBox(width: AppSpace.sm), Text(topic.title, style: AppText.title)]),
          const SizedBox(height: AppSpace.md),
          for (final s in topic.steps) ...[
            _StepRow(step: s, prefs: prefs),
            const Divider(),
          ],
        ]),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.prefs});
  final _Step step;
  final KeyboardPrefs prefs;

  @override
  Widget build(BuildContext context) {
    final combo = step.command == null ? null : prefs.keyOf(step.command!);
    final keys = step.keys != null
        ? KeyChip.text(step.keys!)
        : step.command == null
            ? null
            : combo == null
                ? const Text('Shortcut turned off', style: AppText.helper)
                : KeyChip.combo(combo);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: AppSpace.xs, children: [
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: AppSize.dialogMd), child: Text(step.text)),
          ?keys,
        ]),
        if (combo != null && step.toDo != null) ...[
          const SizedBox(height: AppSpace.sm),
          PracticeKey(keys: combo, toDo: step.toDo!, does: step.does!),
        ],
      ]),
    );
  }
}

/// The reference list's search text and category (a [ShortcutSection], or null for all; navigation keys are General).
class ReferenceFilterCubit extends Cubit<(String, ShortcutSection?)> {
  ReferenceFilterCubit() : super(('', null));
  void search(String q) => emit((q, state.$2));
  void category(ShortcutSection? s) => emit((state.$1, s));
}

class _Reference extends StatelessWidget {
  const _Reference();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<KeyboardPrefsCubit>().state;
    final (query, section) = context.watch<ReferenceFilterCubit>().state;
    final filter = context.read<ReferenceFilterCubit>();
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    bool matches(String text) => words.every(text.toLowerCase().contains);
    final rows = <(String, String, Widget)>[
      if (section == null || section == ShortcutSection.general)
        for (final (keys, what) in navigationKeys)
          if (matches('$what $keys navigation general')) (what, 'General · Navigation', KeyChip.text(keys, dense: true)),
      for (final c in AppCommand.values)
        if ((section == null || c.section == section) && matches('${c.label} ${c.description} ${c.section.label} ${c.group} ${prefs.keysOf(c).map((k) => k.label).join(' ')}'))
          (
            c.label,
            '${c.section.label} · ${c.group}',
            prefs.keysOf(c).isEmpty
                ? const Text('Off', style: AppText.helper)
                : Wrap(spacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (final (i, k) in prefs.keysOf(c).indexed) ...[if (i > 0) const Text('or', style: AppText.helper), KeyChip.combo(k, dense: true)],
                  ]),
          ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Keyboard Shortcuts', style: AppText.title),
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.md, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: AppSize.fieldLg,
              child: TextField(
                textInputAction: TextInputAction.search,
                onChanged: filter.search,
                decoration: const InputDecoration(hintText: 'Search shortcuts…', prefixIcon: Icon(Icons.search)),
              ),
            ),
            SizedBox(
              width: AppSize.fieldMd,
              child: DropdownButtonFormField<ShortcutSection?>(
                initialValue: section,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  for (final s in ShortcutSection.values) DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: filter.category,
              ),
            ),
          ]),
          const SizedBox(height: AppSpace.md),
          if (rows.isEmpty)
            Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text('No shortcut matches "$query".', style: AppText.helper))
          else
            for (final (action, where, keys) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs + 2),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(action, style: AppText.bodyStrong), Text(where, style: AppText.helper)])),
                  keys,
                ]),
              ),
        ]),
      ),
    );
  }
}
