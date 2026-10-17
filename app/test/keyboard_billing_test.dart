import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/core/keyboard/keyboard.dart';
import 'package:billing_app/data/models/invoice.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/data/models/party.dart';
import 'package:billing_app/data/repositories/accounting_repository.dart';
import 'package:billing_app/data/repositories/cash_bank_repository.dart';
import 'package:billing_app/data/repositories/files_repository.dart';
import 'package:billing_app/data/repositories/firm_repository.dart';
import 'package:billing_app/data/repositories/invoices_repository.dart';
import 'package:billing_app/data/repositories/items_repository.dart';
import 'package:billing_app/data/repositories/parties_repository.dart';
import 'package:billing_app/features/invoices/bloc/invoice_form_cubit.dart';
import 'package:billing_app/features/invoices/invoice_form_screen.dart';
import 'package:billing_app/features/team/tracking_cubit.dart';
import 'package:billing_app/shared/theme.dart';

import 'support/fakes.dart';

late FakeInvoicesRepository invoices;

/// The invoice form as the app shows it, on a desktop-sized window, opened from the invoice list.
Future<void> open(WidgetTester t, {String path = '/sale-invoices/new', EnterBehavior enter = EnterBehavior.contextAware, Map<String, dynamic> settings = const {}}) async {
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({'keyboard_prefs_last': '{"mode":"keyboardFirst","enter":"${enter.name}"}'});
  final prefs = KeyboardPrefsCubit(web: false);
  await prefs.loadFor(null);
  final bus = ChangeBus();
  invoices = FakeInvoicesRepository(bus);
  final router = GoRouter(initialLocation: '/sale-invoices', routes: [
    GoRoute(path: '/sale-invoices', builder: (_, _) => const Scaffold(body: Text('LIST')), routes: [
      GoRoute(path: 'new', builder: (_, _) => const InvoiceFormScreen(kind: InvoiceKind.sale)),
      GoRoute(path: ':id/edit', builder: (_, s) => InvoiceFormScreen(kind: InvoiceKind.sale, invoiceId: s.pathParameters['id'])),
      GoRoute(path: ':id/preview', builder: (_, s) => Scaffold(body: Text('PREVIEW ${s.pathParameters['id']}'))),
    ]),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(MultiRepositoryProvider(
    providers: [
      RepositoryProvider.value(value: bus),
      RepositoryProvider<InvoicesRepository>.value(value: invoices),
      RepositoryProvider<PartiesRepository>.value(value: FakePartiesRepository([Party.fromJson(partyJson('a', 'Test Customer', 500, phone: '9000000001'))], bus)),
      RepositoryProvider<ItemsRepository>.value(value: FakeItemsRepository([Item.fromJson(itemJson('i1', 'Sample Item', gstRate: 18))], bus)),
      RepositoryProvider<CashBankRepository>.value(value: FakeCashBankRepository()),
      RepositoryProvider<FirmRepository>.value(value: FakeFirmRepository(settings: settings)),
      RepositoryProvider<AccountingRepository>.value(value: FakeAccountingRepository(bus: bus)),
      RepositoryProvider<FilesRepository>.value(value: FakeFilesRepository()),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider.value(value: prefs),
        BlocProvider(create: (_) => TrackingCubit(FakeLocationRepository(), const Stream.empty())),
      ],
      child: BlocBuilder<KeyboardPrefsCubit, KeyboardPrefs>(
        builder: (context, keys) => MaterialApp.router(
          routerConfig: router,
          theme: buildTheme(),
          builder: (_, child) => KeyboardShortcuts(
            prefs: keys,
            child: EnterKeyNavigation(enabled: keys.enter != EnterBehavior.off, action: keys.enter == EnterBehavior.nextField ? EnterKeyAction.next : EnterKeyAction.automatic, child: child!),
          ),
        ),
      ),
    ),
  ));
  router.push(path);
  await t.pumpAndSettle();
}

InvoiceFormCubit cubit(WidgetTester t) => t.element(find.byType(OrderedFocus).first).read<InvoiceFormCubit>();

/// Presses [key] with the modifiers held, and lets everything it starts finish. As on a real keyboard, an Enter no
/// widget used reaches the focused text box as "submit".
Future<void> press(WidgetTester t, LogicalKeyboardKey key, {bool ctrl = false, bool shift = false}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  final used = await t.sendKeyEvent(key);
  final inText = FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null;
  if (key == LogicalKeyboardKey.enter && !ctrl && !shift && !used && inText) await t.testTextInput.receiveAction(TextInputAction.done);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
}

/// Types into whatever input has focus, as a keyboard would.
Future<void> type(WidgetTester t, String text) async {
  t.testTextInput.enterText(text);
  await t.pumpAndSettle();
}

/// Which part of which row the cursor is in, from the field's key: "qty", "price", "pct", "disc", "gst", "unit".
String? cell(WidgetTester t) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  String? found;
  ctx.visitAncestorElements((e) {
    final k = e.widget.key;
    if (k is ValueKey<String> && RegExp(r'^\d+-(qty|price|pct|disc|gst|unit)').hasMatch(k.value)) {
      found = k.value.split('-').sublist(0, 2).join('-');
      return false;
    }
    return true;
  });
  return found;
}

bool inItemBox(WidgetTester t, int uid) => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>()?.decoration?.hintText == 'Item name' && rowOfFocus(t) == uid;

int? rowOfFocus(WidgetTester t) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  int? uid;
  ctx?.visitAncestorElements((e) {
    final k = e.widget.key;
    if (k is ValueKey<String> && k.value.startsWith('line-')) {
      uid = int.parse(k.value.substring(5));
      return false;
    }
    return true;
  });
  return uid;
}

String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

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
