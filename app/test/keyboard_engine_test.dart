import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billing_app/core/keyboard/keyboard.dart';

const desktop = KeyboardPrefs(web: false);
const web = KeyboardPrefs(web: true);

/// Like the real app: the shortcut handler sits above the Navigator, so dialogs are covered too.
Widget app(Widget home, {KeyboardPrefs prefs = desktop}) => MaterialApp(
      builder: (_, child) => KeyboardShortcuts(prefs: prefs, child: child!),
      home: Scaffold(body: home),
    );

/// Presses [combo] and says whether the app used it (when it did not, a browser or the system gets it).
Future<bool> press(WidgetTester t, KeyCombo combo) async {
  final mods = [
    if (combo.ctrl) primaryModifierIsCmd ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
    if (combo.alt) LogicalKeyboardKey.altLeft,
    if (combo.shift) LogicalKeyboardKey.shiftLeft,
  ];
  for (final m in mods) {
    await t.sendKeyDownEvent(m);
  }
  final handled = await t.sendKeyEvent(combo.key);
  for (final m in mods.reversed) {
    await t.sendKeyUpEvent(m);
  }
  await t.pump();
  return handled;
}

void main() {
  group('shortcuts', () {
    test('labels, saving and reading back', () {
      final c = ctrl(LogicalKeyboardKey.keyN, shift: true);
      expect(c.label, 'Ctrl + Shift + N');
      expect(KeyCombo.decode(c.encode()), c);
      expect(plain(LogicalKeyboardKey.f4).label, 'F4');
      expect(plain(LogicalKeyboardKey.escape).label, 'Esc');
      expect(KeyCombo.decode('nonsense'), isNull);
      expect(KeyCombo.decode('super+${LogicalKeyboardKey.keyA.keyId}'), isNull);
    });

    test('the default shortcuts never clash, on Windows or in a browser', () {
      expect(desktop.conflicts(), isEmpty);
      expect(web.conflicts(), isEmpty);
    });

    test('a browser keeps Ctrl+N and reload for itself, so the defaults differ there', () {
      expect(desktop.keyOf(AppCommand.newRecord), ctrl(LogicalKeyboardKey.keyN));
      expect(web.keyOf(AppCommand.newRecord), alt(LogicalKeyboardKey.keyN));
      expect(desktop.keysOf(AppCommand.refresh), [plain(LogicalKeyboardKey.f5), ctrl(LogicalKeyboardKey.keyR)]);
      expect(web.keysOf(AppCommand.refresh), isEmpty);
      for (final c in AppCommand.values) {
        for (final k in web.keysOf(c)) {
          expect(reservedReason(k, web: true), isNull, reason: '${c.label} defaults to a browser key ${k.label}');
        }
      }
    });

    test('reserved keys: the browser\'s only in a browser, Windows\' everywhere', () {
      for (final k in [ctrl(LogicalKeyboardKey.keyT), ctrl(LogicalKeyboardKey.keyW), ctrl(LogicalKeyboardKey.keyL), ctrl(LogicalKeyboardKey.keyN), ctrl(LogicalKeyboardKey.keyT, shift: true), ctrl(LogicalKeyboardKey.tab), alt(LogicalKeyboardKey.arrowLeft), alt(LogicalKeyboardKey.arrowRight), plain(LogicalKeyboardKey.f5)]) {
        expect(reservedReason(k, web: true), isNotNull, reason: k.label);
      }
      expect(reservedReason(ctrl(LogicalKeyboardKey.keyT), web: false), isNull);
      expect(reservedReason(alt(LogicalKeyboardKey.f4), web: false), contains('Alt + F4'));
      expect(reservedReason(plain(LogicalKeyboardKey.tab), web: false), isNotNull);
    });

    test('a key already in use is refused with the command that has it, never taken over', () {
      expect(desktop.problemWith(AppCommand.print, plain(LogicalKeyboardKey.f4)), 'Shortcut already assigned to "Lookup". Choose another shortcut.');
      expect(desktop.problemWith(AppCommand.print, plain(LogicalKeyboardKey.keyQ)), contains('needed for typing'));
      expect(web.problemWith(AppCommand.print, ctrl(LogicalKeyboardKey.keyT)), contains('browser'));
      expect(desktop.problemWith(AppCommand.print, plain(LogicalKeyboardKey.f9)), isNull);
      // A row command may reuse the key of the global command it replaces in a list of rows, but no other.
      expect(desktop.problemWith(AppCommand.duplicateRow, ctrl(LogicalKeyboardKey.keyD)), isNull);
      expect(desktop.problemWith(AppCommand.addRow, ctrl(LogicalKeyboardKey.keyD)), contains('already assigned'));
    });
  });

  group('preferences', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a changed shortcut is still changed after a restart, per user', () async {
      final first = KeyboardPrefsCubit(web: false);
      await first.loadFor('u1');
      expect(await first.assign(AppCommand.print, plain(LogicalKeyboardKey.f9)), isNull);
      await first.setMode(KeyboardMode.keyboardFirst);
      await first.setBarcodeReturnFocus(false);
      await first.close();

      final restarted = KeyboardPrefsCubit(web: false);
      await restarted.loadFor('u1');
      expect(restarted.state.keyOf(AppCommand.print), plain(LogicalKeyboardKey.f9));
      expect(restarted.state.mode, KeyboardMode.keyboardFirst);
      expect(restarted.state.barcodeReturnFocus, isFalse);
      expect(restarted.state.commandsFor(plain(LogicalKeyboardKey.f9)), [AppCommand.print]);
      expect(restarted.state.commandsFor(ctrl(LogicalKeyboardKey.keyP)), isEmpty);

      await restarted.loadFor('u2'); // a new user starts from the last choice on this device
      expect(restarted.state.keyOf(AppCommand.print), plain(LogicalKeyboardKey.f9));
      await restarted.reset(AppCommand.print);
      await restarted.loadFor('u1');
      expect(restarted.state.keyOf(AppCommand.print), plain(LogicalKeyboardKey.f9)); // u1 keeps their own
      await restarted.close();
    });

    test('a refused shortcut changes nothing', () async {
      final cubit = KeyboardPrefsCubit(web: false);
      await cubit.loadFor('u1');
      final before = cubit.state;
      expect(await cubit.assign(AppCommand.print, plain(LogicalKeyboardKey.f4)), contains('"Lookup"'));
      expect(cubit.state, before);
      await cubit.close();
    });

    test('turning a shortcut off, and resetting one, a section or all', () async {
      final cubit = KeyboardPrefsCubit(web: false);
      await cubit.loadFor('u1');
      await cubit.turnOff(AppCommand.save);
      expect(cubit.state.keyOf(AppCommand.save), isNull);
      expect(await cubit.assign(AppCommand.print, ctrl(LogicalKeyboardKey.keyS)), isNull); // Ctrl+S is free now
      // Save's default is taken, so resetting Save alone is refused rather than leaving two commands on Ctrl+S.
      expect(await cubit.reset(AppCommand.save), contains('Ctrl + S'));
      expect(cubit.state.keyOf(AppCommand.save), isNull);
      expect(await cubit.assign(AppCommand.addRow, plain(LogicalKeyboardKey.f9)), isNull);
      expect(await cubit.resetAll(ShortcutSection.billing), isNull);
      expect(cubit.state.keyOf(AppCommand.addRow), plain(LogicalKeyboardKey.insert));
      expect(cubit.state.keyOf(AppCommand.print), ctrl(LogicalKeyboardKey.keyS)); // another section is untouched
      expect(await cubit.resetAll(), isNull);
      expect(cubit.state.custom, isEmpty);
      await cubit.close();
    });

    test('the older Enter on/off setting carries over', () async {
      SharedPreferences.setMockInitialValues({'enter_navigation_u1': false});
      final cubit = KeyboardPrefsCubit(web: false);
      await cubit.loadFor('u1');
      expect(cubit.state.enter, EnterBehavior.off);
      await cubit.loadFor('u2');
      expect(cubit.state.enter, EnterBehavior.contextAware);
      await cubit.close();
    });

    test('follows the signed-in user and stops listening when closed', () async {
      SharedPreferences.setMockInitialValues({'keyboard_prefs_u1': '{"enter":"nextField"}'});
      final users = StreamController<String?>();
      final cubit = KeyboardPrefsCubit(userIds: users.stream, web: false);
      await cubit.loadFor(null);
      expect(cubit.state.enter, EnterBehavior.contextAware);
      users.add('u1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cubit.state.enter, EnterBehavior.nextField);
      await cubit.close();
      expect(users.hasListener, isFalse);
      await users.close();
    });
  });

  group('which screen a shortcut goes to', () {
    testWidgets('each default shortcut runs its command', (t) async {
      final ran = <AppCommand>[];
      const tried = [
        AppCommand.newRecord, AppCommand.save, AppCommand.print, AppCommand.find, AppCommand.cancel, AppCommand.editSelected,
        AppCommand.lookup, AppCommand.refresh, AppCommand.payment, AppCommand.submit, AppCommand.saveAndComplete, AppCommand.edit, AppCommand.delete,
      ];
      await t.pumpWidget(app(KeyboardScope(
        name: 'Screen',
        autofocus: true,
        commands: {for (final c in tried) c: () => ran.add(c)},
        child: const SizedBox(),
      )));
      for (final c in tried) {
        expect(await press(t, desktop.keyOf(c)!), isTrue, reason: c.label);
      }
      expect(ran, tried);
      expect(await press(t, ctrl(LogicalKeyboardKey.keyR)), isTrue); // Refresh's second key
      expect(ran.last, AppCommand.refresh);
    });

    testWidgets('the narrowest scope wins: dialog over screen over module over app', (t) async {
      final ran = <String>[];
      VoidCallback? screenSubmit = () => ran.add('screen');
      late StateSetter set;
      await t.pumpWidget(app(KeyboardScope(
        name: 'App',
        commands: {AppCommand.submit: () => ran.add('app'), AppCommand.print: () => ran.add('app print')},
        child: KeyboardScope(
          name: 'Billing',
          commands: {AppCommand.submit: () => ran.add('module')},
          child: StatefulBuilder(builder: (context, setState) {
            set = setState;
            return KeyboardScope(
              name: 'Invoice',
              commands: {AppCommand.submit: screenSubmit},
              child: Column(children: [
                const TextField(decoration: InputDecoration(labelText: 'Qty')),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => KeyboardScope(
                      name: 'Payment',
                      commands: {AppCommand.submit: () => ran.add('dialog')},
                      child: const AlertDialog(content: TextField(decoration: InputDecoration(labelText: 'Amount'))),
                    ),
                  ),
                  child: const Text('pay'),
                ),
              ]),
            );
          }),
        ),
      )));
      await t.tap(find.widgetWithText(TextField, 'Qty'));
      final f10 = plain(LogicalKeyboardKey.f10);
      await press(t, f10);
      expect(ran, ['screen']);
      expect(activeKeyboardScopes().map((s) => s.name), ['Invoice', 'Billing', 'App']);

      await press(t, ctrl(LogicalKeyboardKey.keyP)); // only the app handles Print
      expect(ran.last, 'app print');

      set(() => screenSubmit = null); // not available right now: the module's runs instead
      await t.pump();
      await press(t, f10);
      expect(ran.last, 'module');

      await t.tap(find.text('pay'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextField, 'Amount'));
      await press(t, f10);
      expect(ran.last, 'dialog');
      expect(activeKeyboardScopes().first.name, 'Payment');
    });

    testWidgets('a dialog is closed off from the screen behind it, and Esc still closes it', (t) async {
      final ran = <String>[];
      await t.pumpWidget(app(KeyboardScope(
        name: 'Screen',
        commands: {AppCommand.submit: () => ran.add('screen')},
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(context: context, builder: (_) => const AlertDialog(content: TextField())),
            child: const Text('open'),
          ),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byType(TextField));
      await press(t, plain(LogicalKeyboardKey.f10));
      expect(ran, isEmpty);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('shortcuts work before anything on the page is focused', (t) async {
      var saved = 0;
      await t.pumpWidget(app(KeyboardScope(name: 'Screen', commands: {AppCommand.save: () => saved++}, child: const TextField())));
      expect(await press(t, ctrl(LogicalKeyboardKey.keyS)), isTrue);
      expect(saved, 1);
    });

    testWidgets('keys a browser or the system needs are left to them', (t) async {
      await t.pumpWidget(app(
        KeyboardScope(name: 'Screen', autofocus: true, commands: {AppCommand.save: () {}}, child: const SizedBox()),
        prefs: web,
      ));
      for (final k in [ctrl(LogicalKeyboardKey.keyT), ctrl(LogicalKeyboardKey.keyW), ctrl(LogicalKeyboardKey.keyL), ctrl(LogicalKeyboardKey.keyN), ctrl(LogicalKeyboardKey.tab), alt(LogicalKeyboardKey.arrowLeft), plain(LogicalKeyboardKey.f5), ctrl(LogicalKeyboardKey.keyR)]) {
        expect(await press(t, k), isFalse, reason: k.label);
      }
      // A shortcut this screen has no use for goes to the browser too (Ctrl+F is the browser's find here).
      expect(await press(t, ctrl(LogicalKeyboardKey.keyF)), isFalse);
      expect(await press(t, ctrl(LogicalKeyboardKey.keyS)), isTrue);
    });

    testWidgets('in a text input, typing keys type; shortcuts with Ctrl still run', (t) async {
      final ran = <AppCommand>[];
      await t.pumpWidget(app(KeyboardScope(
        name: 'Rows',
        commands: {AppCommand.removeRow: () => ran.add(AppCommand.removeRow), AppCommand.save: () => ran.add(AppCommand.save), AppCommand.addRow: () => ran.add(AppCommand.addRow)},
        child: const TextField(),
      )));
      await t.tap(find.byType(TextField));
      await press(t, plain(LogicalKeyboardKey.delete)); // deletes a character, not the row
      await press(t, ctrl(LogicalKeyboardKey.keyS));
      await press(t, plain(LogicalKeyboardKey.insert));
      expect(ran, [AppCommand.save, AppCommand.addRow]);
    });

    testWidgets('a row command replaces the global one inside its rows only', (t) async {
      final ran = <String>[];
      await t.pumpWidget(app(KeyboardScope(
        name: 'Invoice',
        commands: {AppCommand.delete: () => ran.add('delete invoice')},
        child: Column(children: [
          const TextField(decoration: InputDecoration(labelText: 'Customer')),
          KeyboardScope(name: 'Items', commands: {AppCommand.duplicateRow: () => ran.add('duplicate row')}, child: const TextField(decoration: InputDecoration(labelText: 'Qty'))),
        ]),
      )));
      final ctrlD = ctrl(LogicalKeyboardKey.keyD);
      await t.tap(find.widgetWithText(TextField, 'Qty'));
      await press(t, ctrlD);
      await t.tap(find.widgetWithText(TextField, 'Customer'));
      await press(t, ctrlD);
      expect(ran, ['duplicate row', 'delete invoice']);
    });

    testWidgets('the keypad Enter is Enter, and a held key runs once', (t) async {
      var ran = 0;
      await t.pumpWidget(app(KeyboardScope(name: 'Screen', autofocus: true, commands: {AppCommand.saveAndComplete: () => ran++, AppCommand.submit: () => ran++}, child: const SizedBox())));
      await press(t, ctrl(LogicalKeyboardKey.numpadEnter));
      expect(ran, 1);
      await t.sendKeyDownEvent(LogicalKeyboardKey.f10);
      expect(await t.sendKeyRepeatEvent(LogicalKeyboardKey.f10), isTrue);
      await t.sendKeyUpEvent(LogicalKeyboardKey.f10);
      expect(ran, 2);
    });

    testWidgets('a custom shortcut replaces the default', (t) async {
      var printed = 0;
      final prefs = desktop.copyWith(custom: {AppCommand.print: plain(LogicalKeyboardKey.f9)});
      await t.pumpWidget(app(KeyboardScope(name: 'Screen', autofocus: true, commands: {AppCommand.print: () => printed++}, child: const SizedBox()), prefs: prefs));
      expect(await press(t, ctrl(LogicalKeyboardKey.keyP)), isFalse);
      await press(t, plain(LogicalKeyboardKey.f9));
      expect(printed, 1);
    });

    testWidgets('Windows: Ctrl shortcuts and function keys', (t) async {
      var saved = 0, looked = 0;
      await t.pumpWidget(app(KeyboardScope(name: 'Screen', autofocus: true, commands: {AppCommand.save: () => saved++, AppCommand.lookup: () => looked++}, child: const SizedBox())));
      await press(t, ctrl(LogicalKeyboardKey.keyS));
      await press(t, plain(LogicalKeyboardKey.f4));
      expect((saved, looked), (1, 1));
      expect(ctrl(LogicalKeyboardKey.keyS).label, 'Ctrl + S');
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('a Mac uses Cmd where Windows uses Ctrl', (t) async {
      var saved = 0;
      await t.pumpWidget(app(KeyboardScope(name: 'Screen', autofocus: true, commands: {AppCommand.save: () => saved++}, child: const SizedBox())));
      await press(t, ctrl(LogicalKeyboardKey.keyS)); // sends Cmd here
      expect(saved, 1);
      expect(ctrl(LogicalKeyboardKey.keyS).label, 'Cmd + S');
      expect(defaultTargetPlatform, TargetPlatform.macOS);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}
