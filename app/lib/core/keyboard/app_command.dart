import 'package:flutter/services.dart';

import 'key_combo.dart';

/// Where a command is listed in Settings › Keyboard & Shortcuts and in the Keyboard Playbook.
enum ShortcutSection {
  general('General'),
  billing('Billing'),
  inventory('Inventory'),
  purchase('Purchase'),
  reports('Reports');

  const ShortcutSection(this.label);
  final String label;
}

/// Where a command's shortcut is active. A key may mean one thing in [global] and another in a narrower area only when the
/// narrower command says it [AppCommand.overrides] the global one (Ctrl+D duplicates a row in a list of rows, and deletes
/// the record elsewhere); any other shared key is a conflict.
enum ShortcutArea {
  /// Every screen and dialog.
  global,

  /// A list of rows being edited, such as an invoice's items.
  rows,
}

/// Something the keyboard can do. Screens and dialogs say what each command does there with a `KeyboardScope`; a command
/// nobody handles on the current screen does nothing, and its key is left to the browser or the system.
enum AppCommand {
  // General › Application
  newRecord('New', 'Start a new record on this screen: an invoice, a party, an item…', ShortcutSection.general, 'Application'),
  save('Save', 'Save what is open (an invoice is kept as it is, without closing).', ShortcutSection.general, 'Application'),
  saveAndComplete('Save & complete', 'Save and finish, for example save the invoice and show it for printing.', ShortcutSection.general, 'Application'),
  submit('Save / submit', 'Save the form, like its main button.', ShortcutSection.general, 'Application'),
  print('Print', 'Print or share what is open.', ShortcutSection.general, 'Application'),
  payment('Payment', 'Go to the payment of what is open, or record a payment.', ShortcutSection.general, 'Application'),
  refresh('Refresh', 'Load the screen again from the server.', ShortcutSection.general, 'Application'),

  // General › Search
  find('Search this screen', "Go to this screen's search box.", ShortcutSection.general, 'Search'),
  lookup('Lookup', 'Open the lookup for the field you are on: items, parties, invoices…', ShortcutSection.general, 'Search'),
  quickSearch('Quick search', 'Search parties, items and documents anywhere in the app.', ShortcutSection.general, 'Search'),

  // General › Records
  edit('Edit', 'Edit the record that is open.', ShortcutSection.general, 'Records'),
  editSelected('Edit selected', 'Edit the selected row or record.', ShortcutSection.general, 'Records'),
  delete('Delete', 'Delete or void the record, where you are allowed to.', ShortcutSection.general, 'Records'),
  firstRecord('First record', 'Go to the first record.', ShortcutSection.general, 'Records'),
  lastRecord('Last record', 'Go to the last record.', ShortcutSection.general, 'Records'),

  // General › Windows/Dialogs
  cancel('Cancel / close', 'Cancel what you are doing, or close the dialog or form.', ShortcutSection.general, 'Windows/Dialogs'),
  shortcutHelp('Show shortcuts', 'Show the shortcuts for this screen.', ShortcutSection.general, 'Windows/Dialogs'),

  // Billing › Items
  addRow('Add item row', 'Add a new row to the items.', ShortcutSection.billing, 'Items', area: ShortcutArea.rows),
  removeRow('Remove item row', 'Remove the row you are on.', ShortcutSection.billing, 'Items', area: ShortcutArea.rows),
  duplicateRow('Duplicate item row', 'Copy the row you are on into a new row below it.', ShortcutSection.billing, 'Items', area: ShortcutArea.rows, overrides: AppCommand.delete);

  const AppCommand(this.label, this.description, this.section, this.group, {this.area = ShortcutArea.global, this.overrides});

  final String label;
  final String description;
  final ShortcutSection section;

  /// The heading it is listed under inside its [section], e.g. "Application".
  final String group;
  final ShortcutArea area;

  /// The global command whose key this one may reuse inside its [area].
  final AppCommand? overrides;

  /// Saved preferences refer to a command by this, so renaming the enum value would forget a custom shortcut.
  String get id => name;

  static AppCommand? byId(String id) => values.where((c) => c.id == id).firstOrNull;

  /// The shortcut a command has until the user changes it; null when it has none by default. In a browser a few differ,
  /// because the browser keeps Ctrl+N (new window) and F5/Ctrl+R (reload) for itself.
  KeyCombo? defaultKey({required bool web}) => switch (this) {
        newRecord => web ? alt(LogicalKeyboardKey.keyN) : ctrl(LogicalKeyboardKey.keyN),
        save => ctrl(LogicalKeyboardKey.keyS),
        saveAndComplete => ctrl(LogicalKeyboardKey.enter),
        submit => plain(LogicalKeyboardKey.f10),
        print => ctrl(LogicalKeyboardKey.keyP),
        payment => plain(LogicalKeyboardKey.f8),
        refresh => web ? null : plain(LogicalKeyboardKey.f5),
        find => ctrl(LogicalKeyboardKey.keyF),
        lookup => plain(LogicalKeyboardKey.f4),
        quickSearch => ctrl(LogicalKeyboardKey.keyK),
        edit => ctrl(LogicalKeyboardKey.keyE),
        editSelected => plain(LogicalKeyboardKey.f2),
        delete => ctrl(LogicalKeyboardKey.keyD),
        firstRecord => ctrl(LogicalKeyboardKey.home),
        lastRecord => ctrl(LogicalKeyboardKey.end),
        cancel => plain(LogicalKeyboardKey.escape),
        shortcutHelp => ctrl(LogicalKeyboardKey.slash),
        addRow => plain(LogicalKeyboardKey.insert),
        removeRow => plain(LogicalKeyboardKey.delete),
        duplicateRow => ctrl(LogicalKeyboardKey.keyD),
      };

  /// Other keys that also do it, which are not changed in Settings (F5 refreshes beside Ctrl+R on Windows).
  List<KeyCombo> alsoKeys({required bool web}) => switch (this) {
        refresh => web ? const [] : [ctrl(LogicalKeyboardKey.keyR)],
        _ => const [],
      };
}

/// Keys that move around rather than run a command. They are Flutter's own focus and text handling, listed in the
/// Playbook and the shortcut overlay but not changeable.
const navigationKeys = <(String keys, String what)>[
  ('Tab', 'Next field'),
  ('Shift + Tab', 'Previous field'),
  ('Enter', 'Confirm, or go to the next field'),
  ('Esc', 'Cancel or close'),
  ('↑ ↓', 'Previous / next item'),
  ('← →', 'Previous / next cell or section'),
  ('Home / End', 'First / last item'),
];
