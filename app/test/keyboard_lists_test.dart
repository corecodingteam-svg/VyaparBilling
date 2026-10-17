import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billing_app/core/keyboard/keyboard.dart';
import 'package:billing_app/shared/data_table_view.dart';
import 'package:billing_app/shared/theme.dart';
import 'package:billing_app/shared/widgets.dart';

Widget app(Widget body) => MaterialApp(
      theme: buildTheme(),
      builder: (_, child) => KeyboardShortcuts(prefs: const KeyboardPrefs(web: false), child: EnterKeyNavigation(enabled: true, child: child!)),
      home: Scaffold(body: body),
    );

Future<bool> press(WidgetTester t, LogicalKeyboardKey key, {bool ctrl = false}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  final used = await t.sendKeyEvent(key);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
  return used;
}

/// The first text inside the focused widget: which row has focus.
String? focusedText() {
  String? found;
  void visit(Element e) {
    if (found != null) return;
    final w = e.widget;
    if (w is Text) {
      found = w.data;
      return;
    }
    e.visitChildren(visit);
  }

  final ctx = FocusManager.instance.primaryFocus?.context as Element?;
  ctx?.visitChildren(visit);
  return found;
}

void focusRow(WidgetTester t, String text) {
  Focus.of(t.element(find.text(text))).requestFocus();
}

void main() {
  group('tables', () {
    late List<String> opened;
    Widget table() => SingleChildScrollView(
          child: PagedDataTable(
            columns: const [TableColumnSpec('Name'), TableColumnSpec('Qty', numeric: true)],
            rows: [
              for (var i = 0; i < 30; i++)
                TableRowData(cells: [Text('Row $i'), Text('$i')], sort: ['Row ${i.toString().padLeft(2, '0')}', i], search: 'Row $i', onTap: () => opened.add('Row $i')),
            ],
          ),
        );

    setUp(() => opened = []);

    testWidgets('Home and End go to the first and last row of the page; the arrows move a row', (t) async {
      t.view.physicalSize = const Size(1200, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(table()));
      focusRow(t, 'Row 3');
      await t.pump();
      await press(t, LogicalKeyboardKey.home);
      expect(focusedText(), 'Row 0'); // not a column heading
      await press(t, LogicalKeyboardKey.end);
      expect(focusedText(), 'Row 24');
      await press(t, LogicalKeyboardKey.arrowUp);
      expect(focusedText(), 'Row 23');
      await press(t, LogicalKeyboardKey.enter);
      expect(opened, ['Row 23']);
    });

    testWidgets('Page Down / Page Up turn the page; Ctrl+End / Ctrl+Home go to the very last / first row', (t) async {
      t.view.physicalSize = const Size(1200, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(table()));
      focusRow(t, 'Row 5');
      await t.pump();
      await press(t, LogicalKeyboardKey.pageDown);
      expect(focusedText(), 'Row 25');
      await press(t, LogicalKeyboardKey.pageUp);
      expect(focusedText(), 'Row 0');
      await press(t, LogicalKeyboardKey.end, ctrl: true);
      expect(focusedText(), 'Row 29');
      await press(t, LogicalKeyboardKey.home, ctrl: true);
      expect(focusedText(), 'Row 0');
    });

    testWidgets('in the search box Home and End stay with the text; Ctrl+F gets there from anywhere', (t) async {
      t.view.physicalSize = const Size(1200, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(table()));
      focusRow(t, 'Row 7');
      await t.pump();
      expect(await press(t, LogicalKeyboardKey.keyF, ctrl: true), isTrue); // no screen handles it: the page's search box
      final search = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>();
      expect(search?.decoration?.hintText, 'Search this list');
      await press(t, LogicalKeyboardKey.home);
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>(), same(search));
    });
  });

  testWidgets('a list pane: End scrolls to the last row of the page and focuses it', (t) async {
    t.view.physicalSize = const Size(600, 500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final names = [for (var i = 0; i < 20; i++) 'Item $i'];
    await t.pumpWidget(app(PagedListPane<String>(
      items: names,
      headings: const ['ITEM'],
      sortKeys: [(n) => n],
      emptyText: 'none',
      itemBuilder: (_, n) => ListTile(title: Text(n), onTap: () {}, trailing: IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert))),
    )));
    focusRow(t, 'Item 0');
    await t.pump();
    await press(t, LogicalKeyboardKey.end);
    expect(focusedText(), 'Item 19'); // built only after scrolling
    await press(t, LogicalKeyboardKey.home);
    expect(focusedText(), 'Item 0');
  });

  group('dialogs', () {
    Widget opener(Widget Function(BuildContext) dialog) => Builder(
          builder: (context) => TextButton(onPressed: () => showDialog<void>(context: context, builder: dialog), child: const Text('open')),
        );

    testWidgets('F10, Ctrl+S or Ctrl+Enter press a dialog\'s main button', (t) async {
      var saved = 0;
      await t.pumpWidget(app(opener((ctx) => AlertDialog(
            content: const TextField(autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: () => saved++, child: const Text('Save')),
            ],
          ))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await press(t, LogicalKeyboardKey.f10);
      await press(t, LogicalKeyboardKey.keyS, ctrl: true);
      await press(t, LogicalKeyboardKey.enter, ctrl: true);
      expect(saved, 3);
    });

    testWidgets('a Delete button is never pressed by a shortcut', (t) async {
      await t.pumpWidget(app(Builder(builder: (context) => TextButton(onPressed: () => confirmDelete(context, title: 'Delete item', message: 'Sure?'), child: const Text('open')))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await press(t, LogicalKeyboardKey.f10);
      await press(t, LogicalKeyboardKey.keyS, ctrl: true);
      expect(find.text('Delete item'), findsOneWidget); // still asking
    });
  });
}
