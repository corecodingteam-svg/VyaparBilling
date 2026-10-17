import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billing_app/data/models/extras.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/data/repositories/utilities_repository.dart';
import 'package:billing_app/features/search/quick_search.dart';
import 'package:billing_app/shared/scan_field.dart';
import 'package:billing_app/shared/theme.dart';
import 'package:billing_app/shared/widgets.dart';

import 'support/fakes.dart';
import 'support/invoice_harness.dart';

final rice = Item.fromJson({...itemJson('i1', 'Basmati Rice 5kg'), 'itemCode': '8901234567890'});
final oil = Item.fromJson({...itemJson('i2', 'Mustard Oil 1L'), 'itemCode': 'OIL-1'});

/// Puts the cursor in the scan box, as Tab would.
Future<void> toScanBox(WidgetTester t) async {
  t.widget<TextField>(find.descendant(of: find.byType(ScanField), matching: find.byType(TextField))).focusNode!.requestFocus();
  await t.pumpAndSettle();
}

/// What a scanner does: types the code and presses Enter.
Future<void> scan(WidgetTester t, String code) async {
  await type(t, code);
  await press(t, LogicalKeyboardKey.enter);
}

void main() {
  test('an item is found by its exact code, case and spaces aside', () {
    expect(itemByCode([rice, oil], ' oil-1 '), oil);
    expect(itemByCode([rice, oil], '89012345678'), isNull); // part of a code is not the code
    expect(itemByCode([rice, oil], ''), isNull);
  });

  group('scanning into an invoice', () {
    testWidgets('each scan adds the item; the same item again is one more; the box is ready for the next', (t) async {
      await open(t, items: [rice, oil]);
      await toScanBox(t);
      await scan(t, '8901234567890');
      await scan(t, 'OIL-1');
      await scan(t, '8901234567890');
      final lines = cubit(t).state.lines.where((l) => l.itemId != null).toList();
      expect([for (final l in lines) (l.itemId, l.qty)], [('i1', '2'), ('i2', '1')]);
      expect(focusedLabel(), 'Scan'); // still in the scan box
      final box = t.widget<TextField>(find.descendant(of: find.byType(ScanField), matching: find.byType(TextField)));
      expect(box.controller!.text, isEmpty);
      // The quantity shown in the row follows the scans.
      expect(find.widgetWithText(TextFormField, '2'), findsOneWidget);
    });

    testWidgets('an unknown code adds nothing and stays selected, so the next scan replaces it', (t) async {
      await open(t, items: [rice, oil]);
      await toScanBox(t);
      await scan(t, '0000');
      expect(cubit(t).state.lines.where((l) => l.itemId != null), isEmpty);
      expect(find.text('No item has the code "0000".'), findsOneWidget);
      final box = t.widget<TextField>(find.descendant(of: find.byType(ScanField), matching: find.byType(TextField)));
      expect(box.controller!.selection, const TextSelection(baseOffset: 0, extentOffset: 4));
      expect(focusedLabel(), 'Scan');
    });

    testWidgets('with "return focus to the item box" off, the cursor goes on to the quantity', (t) async {
      await open(t, items: [rice, oil], barcodeReturnFocus: false);
      await toScanBox(t);
      await scan(t, 'OIL-1');
      expect(cell(t), '${cubit(t).state.lines.first.uid}-qty');
    });
  });

  testWidgets('a picker shows the suggestion ↑ ↓ reached, and Enter picks that one', (t) async {
    var picked = '';
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Autocomplete<String>(
          optionsBuilder: (v) => ['Apple', 'Apricot', 'Avocado'].where((o) => o.toLowerCase().startsWith(v.text.toLowerCase())),
          onSelected: (o) => picked = o,
          optionsViewBuilder: (context, onSelected, options) => AutocompleteOptions<String>(width: 300, options: options, onSelected: onSelected, title: (o) => o, trailing: (_) => const SizedBox()),
        ),
      ),
    ));
    await t.enterText(find.byType(TextField), 'a');
    await t.pumpAndSettle();
    bool lit(String o) => t.widget<ListTile>(find.widgetWithText(ListTile, o)).selected;
    expect(lit('Apple'), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect([lit('Apple'), lit('Apricot'), lit('Avocado')], [false, false, true]);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(picked, 'Avocado');
  });

  testWidgets('quick search: ↓ goes into the results, ↑ ↓ move, Enter opens one', (t) async {
    final repo = FakeUtilitiesRepository(hits: const [
      SearchHit(kind: 'party', id: 'a', title: 'Test Customer'),
      SearchHit(kind: 'party', id: 'b', title: 'Test Supplier'),
    ]);
    SearchHit? opened;
    await t.pumpWidget(RepositoryProvider<UtilitiesRepository>.value(
      value: repo,
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => opened = await showDialog<SearchHit>(
                context: context,
                builder: (_) => BlocProvider(create: (_) => SearchCubit(repo, debounce: Duration.zero), child: const QuickSearchDialog()),
              ),
              child: const Text('search'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('search'));
    await t.pumpAndSettle();
    await type(t, 'test');
    await t.pump(const Duration(milliseconds: 10));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(opened?.title, 'Test Supplier');
  });
}
