import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billing_app/core/keyboard/keyboard.dart';

import 'support/invoice_harness.dart';

void main() {
  testWidgets('a whole invoice from the keyboard: customer, items, payment, save', (t) async {
    await open(t);
    // Keyboard First: the customer box is ready to type in.
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>()?.decoration?.labelText, contains('Customer'));
    await type(t, 'Test');
    await press(t, LogicalKeyboardKey.enter); // picks the highlighted customer and moves on
    expect(cubit(t).state.partyId, 'a');
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>()?.decoration?.labelText, isNot(contains('Customer')));

    await press(t, LogicalKeyboardKey.f4); // product search: the first row's item box
    final row1 = cubit(t).state.lines.first.uid;
    expect(inItemBox(t, row1), isTrue);
    await type(t, 'Sam');
    await press(t, LogicalKeyboardKey.enter); // picks the item and goes to its quantity
    expect(cubit(t).state.lines.first.itemId, 'i1');
    expect(cell(t), '$row1-qty');

    await type(t, '3');
    // Enter: quantity → price (passing over the unit) → discount % → discount amount → tax.
    for (final next in ['price', 'pct', 'disc', 'gst']) {
      await press(t, LogicalKeyboardKey.enter);
      expect(cell(t), '$row1-$next');
    }
    // Choosing the tax (Enter opens the list, Enter picks) goes on to the next row's item.
    await press(t, LogicalKeyboardKey.enter);
    await press(t, LogicalKeyboardKey.enter);
    final row2 = cubit(t).state.lines[1].uid;
    expect(inItemBox(t, row2), isTrue);
    await type(t, 'Sample');
    await press(t, LogicalKeyboardKey.enter);
    expect(cubit(t).state.lines[1].itemId, 'i1');
    expect(cubit(t).state.lines.first.qty, '3');

    await press(t, LogicalKeyboardKey.f8); // payment
    expect(focusedLabel(), 'Received');
    await type(t, '100');
    expect(cubit(t).state.received, '100');

    await press(t, LogicalKeyboardKey.f10); // save
    expect(invoices.saved, hasLength(1));
    expect(invoices.saved.single['lines'], hasLength(2));
    expect(find.textContaining('PREVIEW'), findsOneWidget); // then the printable invoice
  });

  group('item rows', () {
    Future<int> oneItem(WidgetTester t) async {
      await open(t);
      await press(t, LogicalKeyboardKey.f4);
      await type(t, 'Sam');
      await press(t, LogicalKeyboardKey.enter);
      return cubit(t).state.lines.first.uid;
    }

    testWidgets('Insert adds a row and puts the cursor in its item box', (t) async {
      await oneItem(t);
      expect(cubit(t).state.lines, hasLength(2)); // picking an item already opened row 2
      await press(t, LogicalKeyboardKey.insert);
      expect(cubit(t).state.lines, hasLength(3));
      expect(inItemBox(t, cubit(t).state.lines.last.uid), isTrue);
    });

    testWidgets('Ctrl+D copies the row the cursor is in, and the copy gets the cursor', (t) async {
      final row1 = await oneItem(t);
      await press(t, LogicalKeyboardKey.keyD, ctrl: true);
      final lines = cubit(t).state.lines;
      expect(lines, hasLength(3));
      expect([lines[1].itemId, lines[1].qty], ['i1', '1']);
      expect(lines[1].uid, isNot(row1));
      expect(inItemBox(t, lines[1].uid), isTrue);
    });

    testWidgets('Delete in a text box deletes text; on the row (not in a text box) it removes the row', (t) async {
      final row1 = await oneItem(t);
      await press(t, LogicalKeyboardKey.delete);
      expect(cubit(t).state.lines, hasLength(2)); // still there: the cursor was in the quantity
      // Tab on to the row's tax list (not a text box) and press Delete.
      while (cell(t) != '$row1-gst') {
        await press(t, LogicalKeyboardKey.tab);
      }
      await press(t, LogicalKeyboardKey.delete);
      expect(cubit(t).state.lines.map((l) => l.uid), isNot(contains(row1)));
      expect(inItemBox(t, cubit(t).state.lines.first.uid), isTrue);
    });
  });

  group('saving, printing and leaving', () {
    testWidgets('Ctrl+Enter saves and shows the printable invoice, even with the preview setting off', (t) async {
      await open(t, settings: {'showInvoicePreview': false});
      await type(t, 'Test'); // a credit sale needs its customer
      await press(t, LogicalKeyboardKey.enter);
      await press(t, LogicalKeyboardKey.f4);
      await type(t, 'Sam');
      await press(t, LogicalKeyboardKey.enter);
      await press(t, LogicalKeyboardKey.enter, ctrl: true);
      expect(invoices.saved, hasLength(1));
      expect(find.textContaining('PREVIEW'), findsOneWidget);
    });

    testWidgets('F10 with the preview setting off saves and closes', (t) async {
      await open(t, settings: {'showInvoicePreview': false});
      await type(t, 'Test'); // a credit sale needs its customer
      await press(t, LogicalKeyboardKey.enter);
      await press(t, LogicalKeyboardKey.f4);
      await type(t, 'Sam');
      await press(t, LogicalKeyboardKey.enter);
      await press(t, LogicalKeyboardKey.f10);
      expect(invoices.saved, hasLength(1));
      expect(find.text('LIST'), findsOneWidget);
    });

    testWidgets('Ctrl+P prints a saved invoice as it is, without saving it again', (t) async {
      await open(t, path: '/sale-invoices/v1/edit');
      await press(t, LogicalKeyboardKey.keyP, ctrl: true);
      expect(invoices.saved, isEmpty);
      expect(find.text('PREVIEW v1'), findsOneWidget);
    });

    testWidgets('Esc on an untouched form closes it', (t) async {
      await open(t);
      await press(t, LogicalKeyboardKey.escape);
      expect(find.text('LIST'), findsOneWidget);
    });

    testWidgets('Esc after entering something asks first; Keep Editing is the default', (t) async {
      await open(t);
      await type(t, 'Somebody');
      await press(t, LogicalKeyboardKey.escape);
      expect(find.text('Discard changes?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter); // Keep Editing
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('LIST'), findsNothing);

      await press(t, LogicalKeyboardKey.escape);
      await press(t, LogicalKeyboardKey.escape); // Esc closes the question too, keeping the form
      expect(find.text('LIST'), findsNothing);

      await press(t, LogicalKeyboardKey.escape);
      await press(t, LogicalKeyboardKey.tab, shift: true); // onto Discard
      await press(t, LogicalKeyboardKey.enter);
      expect(find.text('LIST'), findsOneWidget);
      expect(invoices.saved, isEmpty);
    });

    testWidgets('Ctrl+N: nothing to do on a blank new invoice; after changes it asks, then starts a new one', (t) async {
      await open(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(await t.sendKeyEvent(LogicalKeyboardKey.keyN), isFalse);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await type(t, 'Somebody');
      await press(t, LogicalKeyboardKey.keyN, ctrl: true);
      expect(find.text('Discard changes?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.tab, shift: true);
      await press(t, LogicalKeyboardKey.enter);
      expect(cubit(t).state.partyName, isEmpty);
    });
  });

  group('pickers', () {
    testWidgets('Enter navigation off: Enter only picks', (t) async {
      await open(t, enter: EnterBehavior.off);
      await type(t, 'Test');
      await press(t, LogicalKeyboardKey.enter);
      expect(cubit(t).state.partyId, 'a');
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>()?.decoration?.labelText, contains('Customer'));
    });

    testWidgets('typed text that matches nothing is kept, and Enter still moves on', (t) async {
      await open(t);
      await press(t, LogicalKeyboardKey.f4);
      await type(t, 'Hand-made gift');
      await press(t, LogicalKeyboardKey.enter);
      expect(cubit(t).state.lines.first.name, 'Hand-made gift');
      expect(cell(t), '${cubit(t).state.lines.first.uid}-qty');
    });
  });
}
