import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billing_app/core/keyboard/keyboard.dart';
import 'package:billing_app/features/settings/keyboard/keyboard_settings_screen.dart';
import 'package:billing_app/shared/theme.dart';

late KeyboardPrefsCubit prefs;
var ranSave = 0;

Future<void> open(WidgetTester t, {bool web = false}) async {
  t.view.physicalSize = const Size(1200, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  prefs = KeyboardPrefsCubit(web: web);
  await prefs.loadFor('u1');
  ranSave = 0;
  await t.pumpWidget(BlocProvider.value(
    value: prefs,
    child: BlocBuilder<KeyboardPrefsCubit, KeyboardPrefs>(
      builder: (context, keys) => MaterialApp(
        theme: buildTheme(),
        builder: (_, child) => KeyboardShortcuts(prefs: keys, child: child!),
        // A screen around the settings that would save on Ctrl+S, to show the editor keeps keys to itself.
        home: Scaffold(body: KeyboardScope(name: 'Around', commands: {AppCommand.save: () => ranSave++}, child: const KeyboardSettingsScreen())),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

Finder row(AppCommand c) => find.byKey(ValueKey('shortcut-${c.id}'));

Future<void> change(WidgetTester t, AppCommand c) async {
  await t.ensureVisible(row(c));
  await t.tap(find.descendant(of: row(c), matching: find.textContaining(RegExp(r'^(Change|Set)$'))));
  await t.pumpAndSettle();
}

Future<void> press(WidgetTester t, LogicalKeyboardKey key, {bool ctrl = false}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(key);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
}

bool saveEnabled(WidgetTester t) => t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed != null;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('mode, Enter behaviour and the barcode option are kept after a restart', (t) async {
    await open(t);
    await t.tap(find.text('Keyboard Only'));
    await t.tap(find.text('Move to next field'));
    await t.tap(find.text('Automatically return focus to item/barcode field'));
    await t.pumpAndSettle();
    final restarted = KeyboardPrefsCubit(web: false);
    await restarted.loadFor('u1');
    expect([restarted.state.mode, restarted.state.enter, restarted.state.barcodeReturnFocus], [KeyboardMode.keyboardOnly, EnterBehavior.nextField, false]);
  });

  testWidgets('change a shortcut by pressing it; it is kept after a restart', (t) async {
    await open(t);
    await change(t, AppCommand.print);
    expect(find.text('Waiting for keys…'), findsOneWidget);
    await press(t, LogicalKeyboardKey.f9);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('F9')), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(prefs.state.keyOf(AppCommand.print), plain(LogicalKeyboardKey.f9));
    expect(find.descendant(of: row(AppCommand.print), matching: find.text('F9')), findsOneWidget);
    final restarted = KeyboardPrefsCubit(web: false);
    await restarted.loadFor('u1');
    expect(restarted.state.keyOf(AppCommand.print), plain(LogicalKeyboardKey.f9));
  });

  testWidgets('a key another command has is refused, naming that command; pressing it runs nothing', (t) async {
    await open(t);
    await change(t, AppCommand.print);
    await press(t, LogicalKeyboardKey.f4);
    expect(find.text('Shortcut already assigned to "Lookup". Choose another shortcut.'), findsOneWidget);
    expect(saveEnabled(t), isFalse);
    await press(t, LogicalKeyboardKey.keyS, ctrl: true); // Save's own key: shown, refused, and not run
    expect(find.text('Shortcut already assigned to "Save". Choose another shortcut.'), findsOneWidget);
    expect(ranSave, 0);
    await press(t, LogicalKeyboardKey.escape); // Esc closes without changing anything
    expect(find.byType(AlertDialog), findsNothing);
    expect(prefs.state.custom, isEmpty);
  });

  testWidgets('in a browser, the browser\'s own keys are refused', (t) async {
    await open(t, web: true);
    await change(t, AppCommand.print);
    await press(t, LogicalKeyboardKey.keyT, ctrl: true);
    expect(find.textContaining('The browser uses Ctrl + T'), findsOneWidget);
    expect(saveEnabled(t), isFalse);
  });

  testWidgets('turn a shortcut off, then reset the section and restore all, each after confirming', (t) async {
    await open(t);
    await change(t, AppCommand.addRow);
    await t.tap(find.text('Turn Off'));
    await t.pumpAndSettle();
    expect(prefs.state.keyOf(AppCommand.addRow), isNull);
    expect(find.descendant(of: row(AppCommand.addRow), matching: find.text('Off')), findsOneWidget);

    final billing = find.ancestor(of: find.text('Billing'), matching: find.byType(Card));
    await t.ensureVisible(billing);
    await t.tap(find.descendant(of: billing, matching: find.text('Reset to Default')));
    await t.pumpAndSettle();
    expect(find.text('Reset Billing shortcuts?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Reset'));
    await t.pumpAndSettle();
    expect(prefs.state.keyOf(AppCommand.addRow), plain(LogicalKeyboardKey.insert));

    await prefs.turnOff(AppCommand.save);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Restore Default Shortcuts'));
    await t.tap(find.text('Restore Default Shortcuts'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Cancel')); // not without saying so
    await t.pumpAndSettle();
    expect(prefs.state.custom, isNotEmpty);
    await t.tap(find.text('Restore Default Shortcuts'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Reset'));
    await t.pumpAndSettle();
    expect(prefs.state.custom, isEmpty);
  });
}
