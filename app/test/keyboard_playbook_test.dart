import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billing_app/core/keyboard/keyboard.dart';
import 'package:billing_app/features/settings/keyboard/keyboard_playbook_screen.dart';
import 'package:billing_app/features/settings/keyboard/keyboard_settings_screen.dart';
import 'package:billing_app/features/settings/keyboard/shortcut_overlay.dart';
import 'package:billing_app/shared/theme.dart';

late KeyboardPrefsCubit prefs;
final ran = <AppCommand>[];
final nav = GlobalKey<NavigatorState>();

/// [body] in an app like the real one: shortcuts above the navigator, the shortcut list on Ctrl+/ and ?, and a screen
/// around [body] that records the commands it runs.
Future<void> open(WidgetTester t, Widget body, {String saved = '{}'}) async {
  t.view.physicalSize = const Size(1200, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({'keyboard_prefs_last': saved});
  prefs = KeyboardPrefsCubit(web: false);
  await prefs.loadFor(null);
  ran.clear();
  await t.pumpWidget(BlocProvider.value(
    value: prefs,
    child: BlocBuilder<KeyboardPrefsCubit, KeyboardPrefs>(
      builder: (context, keys) => MaterialApp(
        navigatorKey: nav,
        theme: buildTheme(),
        builder: (_, child) => KeyboardShortcuts(
          prefs: keys,
          child: KeyboardScope(name: 'App', commands: {AppCommand.shortcutHelp: () => showShortcutOverlay(nav.currentContext!, activeKeyboardScopes())}, child: child!),
        ),
        home: Scaffold(
          body: KeyboardScope(
            name: 'Screen',
            commands: {for (final c in [AppCommand.save, AppCommand.lookup, AppCommand.submit, AppCommand.print]) c: () => ran.add(c)},
            child: body,
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> press(WidgetTester t, LogicalKeyboardKey key, {bool ctrl = false, bool shift = false}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(key);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
}

Finder practice(String toDo) => find.ancestor(of: find.text('to $toDo.'), matching: find.byType(Focus)).first;

void main() {
  testWidgets('the Playbook home: title, subtitle and the six topics', (t) async {
    await open(t, const KeyboardPlaybookScreen());
    expect(find.text('Keyboard Playbook'), findsOneWidget);
    expect(find.text('Work faster without reaching for the mouse.'), findsOneWidget);
    for (final topic in ['Navigation', 'Billing', 'Inventory', 'Search', 'Tables', 'Barcode']) {
      expect(find.widgetWithText(Card, topic), findsWidgets);
    }
    expect(find.text('Learn →'), findsNWidgets(6));
  });

  testWidgets('Try it: the key is checked, never acted on, and Tab still leaves the box', (t) async {
    await open(t, const KeyboardPlaybookScreen(topic: 'billing'));
    await t.ensureVisible(practice('open Product Search'));
    await t.tap(practice('open Product Search'));
    await t.pumpAndSettle();
    expect(find.text('Waiting for key…'), findsOneWidget);
    await press(t, LogicalKeyboardKey.keyS, ctrl: true);
    expect(find.text('That was Ctrl + S. Press F4 to open Product Search.'), findsOneWidget);
    await press(t, LogicalKeyboardKey.f4);
    expect(find.text('✓ Correct! F4 opens Product Search.'), findsOneWidget);
    expect(ran, isEmpty); // neither Save nor Lookup ran while practising
    final box = Focus.of(t.element(find.text('✓ Correct! F4 opens Product Search.')));
    expect(box.hasFocus, isTrue);
    await press(t, LogicalKeyboardKey.tab);
    expect(box.hasFocus, isFalse); // the cursor moved on (to the next box to try)
  });

  testWidgets('the reference: search by action or key, filter by category; your own keys are shown', (t) async {
    await open(t, const KeyboardPlaybookScreen(), saved: '{"custom":{"print":"${plain(LogicalKeyboardKey.f9).encode()}"}}');
    final search = find.widgetWithText(TextField, 'Search shortcuts…');
    await t.ensureVisible(search);
    await t.enterText(search, 'print');
    await t.pumpAndSettle();
    final printRow = find.ancestor(of: find.text('Print'), matching: find.byType(Row)).first;
    expect(find.descendant(of: printRow, matching: find.text('F9')), findsOneWidget);
    expect(find.text('Payment'), findsNothing);

    await t.enterText(search, 'f4');
    await t.pumpAndSettle();
    expect(find.text('Lookup'), findsOneWidget);

    await t.enterText(search, '');
    await t.tap(find.byType(DropdownButtonFormField<ShortcutSection?>));
    await t.pumpAndSettle();
    await t.tap(find.text('Inventory').last);
    await t.pumpAndSettle();
    expect(find.text('Adjust stock'), findsWidgets);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('the tutorial: Start Practice, each key tried safely, then Done', (t) async {
    await open(t, const KeyboardPlaybookScreen());
    await t.tap(find.text('Start the Tutorial'));
    await t.pumpAndSettle();
    expect(find.text('Welcome to Keyboard Mode'), findsOneWidget);
    await t.tap(find.text('Start Practice'));
    await t.pumpAndSettle();
    for (final (key, shift) in [(LogicalKeyboardKey.tab, false), (LogicalKeyboardKey.tab, true), (LogicalKeyboardKey.enter, false), (LogicalKeyboardKey.f4, false), (LogicalKeyboardKey.f10, false)]) {
      await press(t, key, shift: shift);
      expect(find.textContaining('✓ Correct!'), findsOneWidget);
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
    }
    expect(find.textContaining('You practised 5 of 5 keys.'), findsOneWidget);
    expect(ran, isEmpty);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Welcome to Keyboard Mode'), findsNothing);
  });

  testWidgets('choosing a keyboard mode the first time offers the tutorial, once', (t) async {
    await open(t, const KeyboardSettingsScreen());
    await t.tap(find.text('Keyboard First'));
    await t.pumpAndSettle();
    expect(find.text('Welcome to Keyboard Mode'), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    await t.tap(find.text('Keyboard Only'));
    await t.pumpAndSettle();
    expect(find.text('Welcome to Keyboard Mode'), findsNothing);
    expect(prefs.state.tutorialSeen, isTrue);
  });

  group('the shortcut list (Ctrl+/ or ?)', () {
    testWidgets('shows this screen\'s shortcuts first', (t) async {
      await open(t, const SizedBox());
      await press(t, LogicalKeyboardKey.slash, ctrl: true);
      expect(find.text('Keyboard Shortcuts'), findsOneWidget);
      expect(find.text('ON THIS SCREEN · SCREEN'), findsOneWidget);
      final screen = t.getTopLeft(find.text('ON THIS SCREEN · SCREEN')).dy, navigation = t.getTopLeft(find.text('NAVIGATION')).dy;
      expect(t.getTopLeft(find.text('Lookup')).dy, inInclusiveRange(screen, navigation));
      expect(t.getTopLeft(find.text('Adjust stock')).dy, greaterThan(navigation)); // not on this screen: further down
      await press(t, LogicalKeyboardKey.escape);
      expect(find.text('Keyboard Shortcuts'), findsNothing);
    });

    testWidgets('? opens it, except in a text box, where it types', (t) async {
      await open(t, const TextField());
      await press(t, LogicalKeyboardKey.slash, shift: true);
      expect(find.text('Keyboard Shortcuts'), findsOneWidget);
      await press(t, LogicalKeyboardKey.escape);
      await t.tap(find.byType(TextField));
      await t.pump();
      await press(t, LogicalKeyboardKey.slash, shift: true);
      expect(find.text('Keyboard Shortcuts'), findsNothing);
    });
  });

  group('shortcut hints on buttons', () {
    Widget buttons() => const Column(children: [ShortcutLabel('Save', AppCommand.submit, main: true), ShortcutLabel('Add Row', AppCommand.addRow)]);

    testWidgets('Standard: none', (t) async {
      await open(t, buttons());
      expect(find.text('F10'), findsNothing);
      expect(find.text('Insert'), findsNothing);
    });

    testWidgets('Keyboard First: on the main buttons', (t) async {
      await open(t, buttons(), saved: '{"mode":"keyboardFirst"}');
      expect(find.text('F10'), findsOneWidget);
      expect(find.text('Insert'), findsNothing);
    });

    testWidgets('Keyboard Only: on every button with a shortcut, and not for one turned off', (t) async {
      await open(t, buttons(), saved: '{"mode":"keyboardOnly","custom":{"addRow":null}}');
      expect(find.text('F10'), findsOneWidget);
      expect(find.text('Insert'), findsNothing);
    });
  });
}
