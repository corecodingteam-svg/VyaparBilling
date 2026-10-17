import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billing_app/core/keyboard/keyboard.dart';
import 'package:billing_app/shared/theme.dart';

TextField tf(String label) => TextField(decoration: InputDecoration(labelText: label));
Finder field(String label) => find.widgetWithText(TextField, label);

String? focused() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>()?.decoration?.labelText;

Future<void> key(WidgetTester t, LogicalKeyboardKey k, {bool shift = false}) async {
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(k);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.pumpAndSettle();
}

Future<KeyboardPrefsCubit> prefsWith(KeyboardMode mode) async {
  SharedPreferences.setMockInitialValues({'keyboard_prefs_last': '{"mode":"${mode.name}"}'});
  final cubit = KeyboardPrefsCubit(web: false);
  await cubit.loadFor(null);
  return cubit;
}

/// Like the real app: Enter navigation above the Navigator, and the keyboard preferences provided.
Widget app(Widget body, {KeyboardPrefsCubit? prefs, GlobalKey<NavigatorState>? nav}) {
  final material = MaterialApp(
    navigatorKey: nav,
    theme: buildTheme(),
    builder: (_, child) => EnterKeyNavigation(enabled: true, child: child!),
    home: Scaffold(body: body),
  );
  return prefs == null ? material : BlocProvider.value(value: prefs, child: material);
}

void main() {
  group('sections', () {
    // Customer on the left, invoice details on the right, as on the invoice form.
    final sideBySide = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: FocusSection(child: Column(children: [tf('Customer'), tf('Phone'), tf('Address')]))),
      Expanded(child: FocusSection(child: Column(children: [tf('Invoice no'), tf('Date')]))),
    ]);

    testWidgets('Tab finishes a section before the one beside it', (t) async {
      await t.pumpWidget(app(sideBySide));
      await t.tap(field('Customer'));
      final seen = <String?>[];
      for (var i = 0; i < 4; i++) {
        await key(t, LogicalKeyboardKey.tab);
        seen.add(focused());
      }
      expect(seen, ['Phone', 'Address', 'Invoice no', 'Date']);
      await key(t, LogicalKeyboardKey.tab, shift: true);
      expect(focused(), 'Invoice no');
    });

    testWidgets('Enter follows the same order, from the last field of one section to the next section higher up', (t) async {
      await t.pumpWidget(app(sideBySide));
      await t.tap(field('Address'));
      await key(t, LogicalKeyboardKey.enter);
      expect(focused(), 'Invoice no');
      await key(t, LogicalKeyboardKey.enter);
      expect(focused(), 'Date');
      await key(t, LogicalKeyboardKey.enter); // the last field: stays rather than going back to the top
      expect(focused(), 'Date');
    });

    testWidgets('ordered sections are visited by their order, not their place on screen', (t) async {
      await t.pumpWidget(app(OrderedFocus(
        child: Column(children: [
          FocusSection(order: 3, child: TextButton(onPressed: () {}, child: const Text('Top bar'))),
          FocusSection(order: 1, child: Column(children: [tf('Item'), tf('Qty')])),
          FocusSection(order: 2, child: TextButton(onPressed: () {}, child: const Text('Save'))),
        ]),
      )));
      await t.tap(field('Item'));
      await key(t, LogicalKeyboardKey.tab);
      expect(focused(), 'Qty');
      await key(t, LogicalKeyboardKey.tab);
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextButton>()?.child, isA<Text>().having((x) => x.data, 'text', 'Save'));
      await key(t, LogicalKeyboardKey.tab);
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextButton>()?.child, isA<Text>().having((x) => x.data, 'text', 'Top bar'));
      // Enter from the last input stays there: the buttons after it are not inputs, and past them the order starts again.
      await t.tap(field('Qty'));
      await key(t, LogicalKeyboardKey.enter);
      expect(focused(), 'Qty');
    });
  });

  group('focus when a screen opens', () {
    final form = Column(children: [TextButton(onPressed: () {}, child: const Text('Back')), tf('Customer'), tf('Phone')]);

    testWidgets('Keyboard First: the first input is ready to type in', (t) async {
      final prefs = await prefsWith(KeyboardMode.keyboardFirst);
      await t.pumpWidget(app(FocusFirstField(child: form), prefs: prefs));
      await t.pump();
      expect(focused(), 'Customer');
    });

    testWidgets('Standard: nothing is focused for you (a phone keeps its keyboard closed)', (t) async {
      final prefs = await prefsWith(KeyboardMode.standard);
      await t.pumpWidget(app(FocusFirstField(child: form), prefs: prefs));
      await t.pump();
      expect(focused(), isNull);
    });

    testWidgets('a new page in the same area is focused again', (t) async {
      final prefs = await prefsWith(KeyboardMode.keyboardOnly);
      final page = ValueNotifier('a');
      await t.pumpWidget(app(
        ValueListenableBuilder<String>(
          valueListenable: page,
          builder: (_, p, _) => FocusFirstField(page: p, child: Column(key: ValueKey(p), children: [tf('$p first'), tf('$p second')])),
        ),
        prefs: prefs,
      ));
      await t.pump();
      expect(focused(), 'a first');
      await t.tap(field('a second'));
      page.value = 'b';
      await t.pump();
      await t.pump();
      expect(focused(), 'b first');
    });
  });

  group('focus comes back', () {
    testWidgets('closing a dialog returns focus to the control that opened it', (t) async {
      await t.pumpWidget(app(Builder(
        builder: (context) => Column(children: [
          tf('Before'),
          TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => AlertDialog(content: tf('In dialog'))), child: const Text('Open')),
        ]),
      )));
      await t.tap(field('Before'));
      await key(t, LogicalKeyboardKey.tab); // onto the button
      await key(t, LogicalKeyboardKey.enter); // opens the dialog
      expect(find.byType(AlertDialog), findsOneWidget);
      await key(t, LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing);
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextButton>(), isNotNull);
    });

    testWidgets('going back to a screen returns focus to where it was', (t) async {
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(app(Column(children: [tf('A'), tf('B')]), nav: nav));
      await t.tap(field('B'));
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: tf('Other'))));
      await t.pumpAndSettle();
      await t.tap(field('Other'));
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(focused(), 'B');
    });
  });

  group('no keyboard traps', () {
    testWidgets('Tab moves on out of every section and comes round again', (t) async {
      await t.pumpWidget(app(Column(children: [
        FocusSection(child: Column(children: [tf('A1'), tf('A2')])),
        FocusSection(child: Row(children: [Expanded(child: tf('B1')), Expanded(child: tf('B2'))])),
      ])));
      await t.tap(field('A1'));
      final seen = <String?>[];
      for (var i = 0; i < 4; i++) {
        await key(t, LogicalKeyboardKey.tab);
        seen.add(focused());
      }
      expect(seen, ['A2', 'B1', 'B2', 'A1']);
    });

    testWidgets('a dialog keeps Tab inside it, and Esc always leaves', (t) async {
      await t.pumpWidget(app(Builder(
        builder: (context) => Column(children: [
          tf('Behind'),
          TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [tf('D1'), tf('D2')]))), child: const Text('Open')),
        ]),
      )));
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.tap(field('D1'));
      for (var i = 0; i < 5; i++) {
        await key(t, LogicalKeyboardKey.tab);
        expect(focused(), anyOf('D1', 'D2'));
      }
      await key(t, LogicalKeyboardKey.escape);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('focus outline', () {
    test('a ring outside every kind of button, thicker in Keyboard Only mode', () {
      const focusedState = {WidgetState.focused};
      for (final strong in [false, true]) {
        final theme = buildTheme(strongFocus: strong);
        final width = strong ? 3.0 : 2.0;
        for (final style in [theme.filledButtonTheme.style, theme.outlinedButtonTheme.style, theme.textButtonTheme.style, theme.elevatedButtonTheme.style, theme.iconButtonTheme.style, theme.segmentedButtonTheme.style]) {
          final ring = style!.side!.resolve(focusedState)!;
          expect(ring.width, width);
          expect(ring.strokeAlign, BorderSide.strokeAlignOutside);
          expect(ring.color, AppColors.text);
        }
        expect((theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder).borderSide.width, width);
        expect(theme.checkboxTheme.side, isA<WidgetStateBorderSide>());
        expect(WidgetStateProperty.resolveAs(theme.checkboxTheme.side, focusedState)?.width, width);
        expect(theme.switchTheme.trackOutlineWidth!.resolve(focusedState), width);
      }
      // Not focused: an outlined button keeps its normal border, a filled one has none.
      final theme = buildTheme();
      expect(theme.outlinedButtonTheme.style!.side!.resolve({})!.color, AppColors.border);
      expect(theme.filledButtonTheme.style!.side!.resolve({}), isNull);
      buildTheme(); // leave the normal outline for other tests
    });
  });
}
