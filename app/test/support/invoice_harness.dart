/// The invoice form in a test app, and keyboard helpers for driving it.
library;

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

import 'fakes.dart';

late FakeInvoicesRepository invoices;

/// The invoice form as the app shows it, on a desktop-sized window, opened from the invoice list.
Future<void> open(
  WidgetTester t, {
  String path = '/sale-invoices/new',
  EnterBehavior enter = EnterBehavior.contextAware,
  Map<String, dynamic> settings = const {},
  List<Item>? items,
  bool barcodeReturnFocus = true,
}) async {
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({'keyboard_prefs_last': '{"mode":"keyboardFirst","enter":"${enter.name}","barcodeReturnFocus":$barcodeReturnFocus}'});
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
      RepositoryProvider<ItemsRepository>.value(value: FakeItemsRepository(items ?? [Item.fromJson(itemJson('i1', 'Sample Item', gstRate: 18))], bus)),
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
