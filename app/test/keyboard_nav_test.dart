import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billing_app/shared/theme.dart';

/// Like the real app: the handler sits above the Navigator, so dialogs and sheets are covered too.
Widget app(Widget body, {bool enabled = true}) => MaterialApp(
      builder: (_, child) => EnterKeyNavigation(enabled: enabled, child: child!),
      home: Scaffold(body: body),
    );

Widget column(List<Widget> children) => Column(children: children);

Finder field(String label) => find.widgetWithText(TextField, label);

/// The label of the focused field (its InputDecoration label).
String? focused() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  final tf = ctx?.findAncestorWidgetOfExactType<TextField>();
  return tf?.decoration?.labelText;
}

Future<void> enter(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
}

TextField tf(String label, {bool enabled = true, bool readOnly = false, int? maxLines = 1, TextInputAction? action, ValueChanged<String>? onSubmitted}) => TextField(
      decoration: InputDecoration(labelText: label),
      enabled: enabled,
      readOnly: readOnly,
      maxLines: maxLines,
      textInputAction: action,
      onSubmitted: onSubmitted,
    );

void main() {
  group('Enter, Tab and Shift+Tab', () {
    testWidgets('Enter moves through the fields in order', (t) async {
      await t.pumpWidget(app(column([tf('First'), tf('Last'), tf('Email'), tf('Phone')])));
      await t.tap(field('First'));
      expect(focused(), 'First');
      for (final next in ['Last', 'Email', 'Phone']) {
        await enter(t);
        expect(focused(), next);
      }
    });

    testWidgets('Tab goes forward and Shift+Tab goes back', (t) async {
      await t.pumpWidget(app(column([tf('A'), tf('B'), tf('C')])));
      await t.tap(field('A'));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(focused(), 'B');
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pump();
      expect(focused(), 'A');
    });

    testWidgets('Tab still works when Enter navigation is off', (t) async {
      await t.pumpWidget(app(column([tf('A'), tf('B')]), enabled: false));
      await t.tap(field('A'));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(focused(), 'B');
    });

    testWidgets('the last field stays focused instead of wrapping to the first', (t) async {
      await t.pumpWidget(app(column([tf('A'), tf('B')])));
      await t.tap(field('B'));
      await enter(t);
      expect(focused(), 'B');
    });
  });

  group('setting', () {
    testWidgets('off: Enter does not move', (t) async {
      await t.pumpWidget(app(column([tf('A'), tf('B')]), enabled: false));
      await t.tap(field('A'));
      await enter(t);
      expect(focused(), 'A');
    });

    testWidgets('turning it on and off at run time takes effect', (t) async {
      final on = ValueNotifier(false);
      await t.pumpWidget(MaterialApp(
        home: ValueListenableBuilder<bool>(valueListenable: on, builder: (_, v, _) => EnterKeyNavigation(enabled: v, child: Scaffold(body: column([tf('A'), tf('B')])))),
      ));
      await t.tap(field('A'));
      await enter(t);
      expect(focused(), 'A');
      on.value = true;
      await t.pump();
      await enter(t);
      expect(focused(), 'B');
    });

    test('defaults to on and is remembered per user across restarts', () async {
      SharedPreferences.setMockInitialValues({});
      final first = KeyboardNavCubit();
      await first.loadFor('u1');
      expect(first.state, isTrue);
      await first.set(false);
      await first.close();

      final restarted = KeyboardNavCubit();
      await restarted.loadFor('u1');
      expect(restarted.state, isFalse);
      await restarted.loadFor('u2'); // a new user starts from the last choice on this device
      expect(restarted.state, isFalse);
      await restarted.set(true);
      await restarted.loadFor('u1');
      expect(restarted.state, isFalse); // u1 keeps their own
      await restarted.close();
    });

    test('follows the signed-in user and stops listening when closed', () async {
      SharedPreferences.setMockInitialValues({'enter_navigation_u1': false});
      final users = StreamController<String?>();
      final cubit = KeyboardNavCubit(userIds: users.stream);
      users.add('u1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cubit.state, isFalse);
      await cubit.close();
      expect(users.hasListener, isFalse);
      await users.close();
    });
  });

  group('fields that keep their own Enter', () {
    testWidgets('multiline keeps the new line', (t) async {
      await t.pumpWidget(app(column([tf('Notes', maxLines: 3), tf('Next')])));
      await t.tap(field('Notes'));
      await enter(t);
      expect(focused(), 'Notes');
    });

    testWidgets('a search field keeps its action', (t) async {
      await t.pumpWidget(app(column([tf('Find', action: TextInputAction.search), tf('Next')])));
      await t.tap(field('Find'));
      await enter(t);
      expect(focused(), 'Find');
    });

    testWidgets('a field with onSubmitted submits and stays', (t) async {
      var submitted = 0;
      await t.pumpWidget(app(column([tf('Password', onSubmitted: (_) => submitted++), tf('Next')])));
      await t.tap(field('Password'));
      await enter(t);
      expect(focused(), 'Password'); // Enter did not move on…
      await t.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, 1); // …the field's own submit ran
    });

    testWidgets('EnterKeyBehavior(next) overrides onSubmitted; submit and ignore leave Enter alone', (t) async {
      await t.pumpWidget(app(column([
        EnterKeyBehavior(action: EnterKeyAction.next, child: tf('Forced', onSubmitted: (_) {})),
        EnterKeyBehavior(action: EnterKeyAction.submit, child: tf('Submit')),
        EnterKeyBehavior(action: EnterKeyAction.ignore, child: tf('Ignored')),
        tf('Last'),
      ])));
      await t.tap(field('Forced'));
      await enter(t);
      expect(focused(), 'Submit');
      await enter(t);
      expect(focused(), 'Submit');
      await t.tap(field('Ignored'));
      await enter(t);
      expect(focused(), 'Ignored');
    });

    testWidgets('a button still activates with Enter', (t) async {
      var pressed = 0;
      await t.pumpWidget(app(column([tf('A'), ElevatedButton(onPressed: () => pressed++, child: const Text('Save'))])));
      await t.tap(field('A'));
      await enter(t); // Enter only lands on inputs, so it stays here
      expect(focused(), 'A');
      await t.sendKeyEvent(LogicalKeyboardKey.tab); // Tab reaches the button
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(pressed, 1);
    });

    testWidgets('autocomplete fields keep Enter', (t) async {
      await t.pumpWidget(app(column([
        Autocomplete<String>(
          optionsBuilder: (v) => ['apple', 'apricot'].where((o) => o.startsWith(v.text)),
          fieldViewBuilder: (context, controller, node, onSubmit) => TextField(controller: controller, focusNode: node, onSubmitted: (_) => onSubmit(), decoration: const InputDecoration(labelText: 'Fruit')),
        ),
        tf('Next'),
      ])));
      await t.tap(field('Fruit'));
      await t.enterText(field('Fruit'), 'ap');
      await t.pumpAndSettle();
      expect(find.text('apple'), findsOneWidget); // the suggestions are showing
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      // The field's own submit (which picks a suggestion) owns Enter, so focus must not jump to the next field.
      expect(focused(), 'Fruit');
    });
  });

  group('which fields Enter lands on', () {
    testWidgets('skips disabled, read-only and hidden fields', (t) async {
      await t.pumpWidget(app(column([
        tf('A'),
        tf('Disabled', enabled: false),
        tf('Read only', readOnly: true),
        Offstage(child: tf('Hidden')),
        Visibility(visible: false, child: tf('Gone')),
        tf('B'),
      ])));
      await t.tap(field('A'));
      await enter(t);
      expect(focused(), 'B');
    });

    testWidgets('dropdown form fields are part of the order', (t) async {
      await t.pumpWidget(app(column([
        tf('A'),
        DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: 'Type'), items: const [DropdownMenuItem(value: 'x', child: Text('x'))], onChanged: (_) {}),
        tf('B'),
      ])));
      await t.tap(field('A'));
      await enter(t);
      final onDropdown = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<DropdownButtonFormField<String>>();
      expect(onDropdown, isNotNull);
    });

    testWidgets('dynamic forms: a field added later joins the order', (t) async {
      late StateSetter set;
      var extra = false;
      await t.pumpWidget(app(StatefulBuilder(builder: (context, setState) {
        set = setState;
        return column([tf('A'), if (extra) tf('Added'), tf('B')]);
      })));
      await t.tap(field('A'));
      await enter(t);
      expect(focused(), 'B');
      set(() => extra = true);
      await t.pump();
      await t.tap(field('A'));
      await enter(t);
      expect(focused(), 'Added');
    });

    testWidgets('works inside a dialog and a bottom sheet', (t) async {
      await t.pumpWidget(app(Builder(builder: (context) => Column(children: [
            TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => AlertDialog(content: column([tf('D1'), tf('D2')]))), child: const Text('dialog')),
            TextButton(onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => column([tf('S1'), tf('S2')])), child: const Text('sheet')),
          ]))));
      await t.tap(find.text('dialog'));
      await t.pumpAndSettle();
      await t.tap(field('D1'));
      await enter(t);
      expect(focused(), 'D2');
      Navigator.of(t.element(field('D2'))).pop();
      await t.pumpAndSettle();
      await t.tap(find.text('sheet'));
      await t.pumpAndSettle();
      await t.tap(field('S1'));
      await enter(t);
      expect(focused(), 'S2');
    });
  });

  group('architecture', () {
    testWidgets('one handler: Enter moves exactly one field, also after navigating away and back', (t) async {
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(
        navigatorKey: nav,
        builder: (_, child) => EnterKeyNavigation(enabled: true, child: child!),
        home: Scaffold(body: column([tf('A'), tf('B'), tf('C')])),
      ));
      for (var i = 0; i < 3; i++) {
        nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: column([tf('X'), tf('Y'), tf('Z')]))));
        await t.pumpAndSettle();
        await t.tap(field('X'));
        await enter(t);
        expect(focused(), 'Y');
        nav.currentState!.pop();
        await t.pumpAndSettle();
      }
      await t.tap(field('A'));
      await enter(t);
      expect(focused(), 'B');
    });

    testWidgets('removing the widget leaves nothing behind', (t) async {
      await t.pumpWidget(app(column([tf('A'), tf('B')])));
      await t.tap(field('A'));
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(t.takeException(), isNull);
    });
  });
}
