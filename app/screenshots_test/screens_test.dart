// Renders key screens to PNGs for visual review (not part of the normal test run):
//   FONT_DIR=<flutter>/bin/cache/artifacts/material_fonts flutter test screenshots_test --update-goldens
import 'dart:io';

import 'package:billing_app/core/api_client.dart';
import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/data/models/extras.dart';
import 'package:billing_app/data/models/firm.dart';
import 'package:billing_app/data/models/invoice.dart';
import 'package:billing_app/data/models/payment.dart';
import 'package:billing_app/data/repositories/accounting_repository.dart';
import 'package:billing_app/data/repositories/expenses_repository.dart';
import 'package:billing_app/data/repositories/files_repository.dart';
import 'package:billing_app/data/repositories/utilities_repository.dart';
import 'package:billing_app/features/company/firm_cubit.dart';
import 'package:billing_app/features/accounting/accounting_screens.dart';
import 'package:billing_app/features/expenses/expense_items_screen.dart';
import 'package:billing_app/features/payments/payment_form_dialog.dart';
import 'package:billing_app/features/reminders/reminders_screens.dart';
import 'package:billing_app/features/team/team_screens.dart';
import 'package:billing_app/features/tools/tools_screens.dart';
import 'package:billing_app/data/models/team_location.dart';
import 'package:billing_app/data/repositories/location_repository.dart';
import 'package:billing_app/features/parties/party_groups_screen.dart';
import 'package:billing_app/features/stock/godowns_screen.dart';
import 'package:billing_app/features/team/team_locations_screen.dart';
import 'package:billing_app/features/team/tracking_cubit.dart';
import 'package:billing_app/features/lock/lock_cubit.dart';
import 'package:billing_app/features/lock/lock_screen.dart';
import 'package:billing_app/features/printing/thermal/escpos.dart';
import 'package:billing_app/data/repositories/firm_repository.dart';
import 'package:billing_app/data/repositories/loans_repository.dart';
import 'package:billing_app/data/repositories/integrations_repository.dart';
import 'package:billing_app/features/integrations/integrations_screens.dart';
import 'package:billing_app/data/repositories/reports_repository.dart';
import 'package:billing_app/data/repositories/invoices_repository.dart';
import 'package:billing_app/features/expenses/expense_form_screen.dart';
import 'package:billing_app/features/expenses/expenses_screen.dart';
import 'package:billing_app/data/repositories/payments_repository.dart';
import 'package:billing_app/features/invoices/invoice_form_screen.dart';
import 'package:billing_app/features/invoices/invoices_screen.dart';
import 'package:billing_app/features/payments/payments_screen.dart';
import 'package:billing_app/features/printing/pdf_documents.dart';
import 'package:billing_app/data/models/app_user.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/data/models/party.dart';
import 'package:billing_app/data/repositories/auth_repository.dart';
import 'package:billing_app/data/repositories/cash_bank_repository.dart';
import 'package:billing_app/features/cash_bank/cash_bank_screens.dart';
import 'package:billing_app/data/repositories/dashboard_repository.dart';
import 'package:billing_app/data/repositories/items_repository.dart';
import 'package:billing_app/data/repositories/parties_repository.dart';
import 'package:billing_app/features/auth/bloc/auth_bloc.dart';
import 'package:billing_app/features/auth/login_screen.dart';
import 'package:billing_app/features/dashboard/dashboard_screen.dart';
import 'package:billing_app/features/items/bloc/catalog_cubit.dart';
import 'package:billing_app/features/items/items_screen.dart';
import 'package:billing_app/features/loans/loans_screen.dart';
import 'package:billing_app/features/pos/pos_screen.dart';
import 'package:billing_app/features/reports/reports_screen.dart';
import 'package:billing_app/features/settings/settings_screen.dart';
import 'package:billing_app/features/utilities/import_spec.dart';
import 'package:billing_app/features/utilities/utilities_cubits.dart';
import 'package:billing_app/features/utilities/utilities_screens.dart';
import 'package:billing_app/features/parties/parties_screen.dart';
import 'package:billing_app/shared/theme.dart';
import 'package:billing_app/shell/app_shell.dart';
import 'package:billing_app/shell/nav_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fakes.dart';

Future<void> _loadFonts() async {
  final dir = Platform.environment['FONT_DIR']!;
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

const _user = AppUser(id: 'u', email: 'demo@example.com', fullName: 'Demo Owner', firmId: 'f', firmName: 'Demo Traders');

Widget _app(String location, Widget child, {bool shell = true, Map<String, dynamic> settings = const {'invoicePrefix': 'INV-'}, AppUser user = _user}) {
  final bus = ChangeBus();
  final parties = FakePartiesRepository([
    Party.fromJson(partyJson('a', 'Test Customer', 500, phone: '9000000001')),
    Party.fromJson(partyJson('b', 'Test Supplier', -250, phone: '9000000002')),
    Party.fromJson(partyJson('c', 'Sharma General Store', 90)),
  ], bus);
  final items = FakeItemsRepository([
    Item.fromJson(itemJson('i1', 'Sample Item', stock: 50, gstRate: 18)),
    Item.fromJson(itemJson('i2', 'Basmati Rice 5kg', stock: 4, minStock: 10)),
    Item.fromJson(itemJson('s1', 'Home Delivery', type: 'service')),
  ], bus);
  final integrations = FakeIntegrationsRepository()
    ..providers = [
      integrationJson('whatsapp', connected: true, stored: '••••1234'),
      integrationJson('sms'),
      integrationJson('einvoice', connected: true, stored: '••••9876'),
      integrationJson('razorpay'),
      integrationJson('google_profile', connected: true, location: 'Acme Traders'),
    ]
    ..einvoiceState = einvoiceInfoJson(problems: ['The customer needs a 6-digit pincode.'], ewayProblems: ['Enter the distance in km.']);
  final AuthRepository authRepo = FakeAuthRepository();
  final firm = FakeFirmRepository(settings: settings);
  final locations = FakeLocationRepository()
    ..members = [
      TeamMemberLocation.fromJson({
        'userId': 'u3', 'fullName': 'Sam Salesman', 'role': 'salesman', 'latitude': 19.07, 'longitude': 72.87, 'accuracy': 10,
        'recordedAt': DateTime.now().subtract(const Duration(minutes: 12)).toUtc().toIso8601String(), 'context': 'sale', 'pointsToday': 9, 'salesToday': 4, 'paymentsToday': 2,
      }),
      TeamMemberLocation.fromJson({'userId': 'u2', 'fullName': 'Asha Accountant', 'role': 'accountant', 'pointsToday': 0, 'salesToday': 0, 'paymentsToday': 0}),
    ];
  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<ChangeBus>.value(value: bus),
      RepositoryProvider<ApiClient>.value(value: ApiClient(TokenStore())),
      RepositoryProvider<AuthRepository>.value(value: authRepo),
      RepositoryProvider<InvoicesRepository>.value(value: FakeInvoicesRepository(bus)),
      RepositoryProvider<PaymentsRepository>.value(value: FakePaymentsRepository(bus)),
      RepositoryProvider<ExpensesRepository>.value(value: FakeExpensesRepository(bus)),
      RepositoryProvider<CashBankRepository>.value(value: FakeCashBankRepository(bus: bus)),
      RepositoryProvider<FirmRepository>.value(value: firm),
      RepositoryProvider<FilesRepository>.value(value: FakeFilesRepository()),
      RepositoryProvider<AccountingRepository>.value(value: FakeAccountingRepository(currencyList: const [('USD', r'$', 83.5)], bus: bus)),
      RepositoryProvider<LocationRepository>.value(value: locations),
      RepositoryProvider<UtilitiesRepository>.value(
        value: FakeUtilitiesRepository(hits: const [
          SearchHit(kind: 'party', id: 'a', title: 'Test Customer', subtitle: '9000000001'),
          SearchHit(kind: 'party', id: 'b', title: 'Test Supplier', subtitle: '9000000002'),
          SearchHit(kind: 'item', id: 'i9', title: 'Tea Premium 250g', subtitle: 'Item · ₹ 180.00 · Stock 24'),
          SearchHit(kind: 'invoice', id: 'v1', type: 'sale', title: 'Sale INV-1 Test Customer', subtitle: 'Test Customer · 10/10/2026 · ₹ 1,000.00'),
        ]),
      ),
      RepositoryProvider<LoansRepository>.value(value: FakeLoansRepository()),
      RepositoryProvider<IntegrationsRepository>.value(value: integrations),
      RepositoryProvider<ReportsRepository>.value(value: FakeReportsRepository()),
      RepositoryProvider<PartiesRepository>.value(value: parties),
      RepositoryProvider<ItemsRepository>.value(value: items),
      RepositoryProvider<DashboardRepository>.value(value: FakeDashboardRepository()),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AuthBloc(authRepo)..add(AuthSignedIn(user))),
        BlocProvider(lazy: false, create: (ctx) => FirmCubit(firm, bus, ctx.read<AuthBloc>())..load()),
        BlocProvider(create: (_) => TrackingCubit(locations, const Stream.empty())),
        BlocProvider(create: (_) => LockCubit(FakePasscodeStore())..load()),
        BlocProvider(create: (_) => NavCubit(location)),
        BlocProvider(create: (ctx) => CatalogCubit(items, bus)..load()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme().copyWith(textTheme: buildTheme().textTheme.apply(fontFamily: 'Roboto')),
        home: shell ? AppShell(location: location, child: child) : child,
      ),
    ),
  );
}

Future<void> _shot(WidgetTester tester, Size size, Widget app, String name, {Future<void> Function()? then}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  if (then != null) {
    await then();
    await tester.pumpAndSettle();
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  setUpAll(_loadFonts);
  const desktop = Size(1440, 900);
  const phone = Size(400, 860);

  testWidgets('login', (t) async {
    final repo = AuthRepository(ApiClient(TokenStore()));
    await _shot(
      t,
      desktop,
      RepositoryProvider.value(
        value: repo,
        child: BlocProvider(
          create: (_) => AuthBloc(repo),
          child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: const LoginScreen()),
        ),
      ),
      'login_desktop',
    );
  });

  testWidgets('dashboard', (t) => _shot(t, desktop, _app('/', const DashboardScreen()), 'dashboard_desktop'));
  testWidgets('parties', (t) => _shot(t, desktop, _app('/parties', const PartiesScreen()), 'parties_desktop'));
  testWidgets('parties phone', (t) => _shot(t, phone, _app('/parties', const PartiesScreen()), 'parties_phone'));
  testWidgets('add party', (t) => _shot(t, desktop, _app('/parties', const PartiesScreen()), 'party_form_desktop',
      then: () => t.tap(find.text('Add Party'))));
  testWidgets('party credit tab', (t) => _shot(t, desktop, _app('/parties', const PartiesScreen()), 'party_form_credit',
      then: () async {
        await t.tap(find.text('Add Party'));
        await t.pumpAndSettle();
        await t.tap(find.text('Credit & Balance'));
      }));
  testWidgets('sale invoices', (t) => _shot(t, desktop, _app('/sale-invoices', const InvoicesScreen(kind: InvoiceKind.sale)), 'invoices_desktop'));
  testWidgets('sale invoices phone', (t) => _shot(t, phone, _app('/sale-invoices', const InvoicesScreen(kind: InvoiceKind.sale)), 'invoices_phone'));
  testWidgets('invoice form edit', (t) => _shot(
      t, desktop, _app('/', const InvoiceFormScreen(kind: InvoiceKind.sale, invoiceId: 'v1'), shell: false), 'invoice_form_desktop'));
  testWidgets('invoice form item picker', (t) => _shot(
      t, desktop, _app('/', const InvoiceFormScreen(kind: InvoiceKind.sale), shell: false), 'invoice_form_picker',
      then: () => t.tap(find.widgetWithText(TextField, 'Item name').first)));
  testWidgets('invoice form phone', (t) => _shot(
      t, phone, _app('/', const InvoiceFormScreen(kind: InvoiceKind.sale, invoiceId: 'v1'), shell: false), 'invoice_form_phone'));
  testWidgets('purchase form', (t) => _shot(
      t, desktop, _app('/', const InvoiceFormScreen(kind: InvoiceKind.purchase), shell: false), 'purchase_form_desktop'));
  testWidgets('purchase bills', (t) => _shot(
      t, desktop, _app('/purchase-bills', const InvoicesScreen(kind: InvoiceKind.purchase)), 'purchases_desktop'));
  testWidgets('estimates', (t) => _shot(t, desktop, _app('/estimates', const InvoicesScreen(kind: InvoiceKind.estimate)), 'estimates_desktop'));
  testWidgets('estimate form', (t) => _shot(
      t, desktop, _app('/', const InvoiceFormScreen(kind: InvoiceKind.estimate, invoiceId: 'e1'), shell: false), 'estimate_form_desktop'));
  testWidgets('expenses', (t) => _shot(t, desktop, _app('/expenses', const ExpensesScreen()), 'expenses_desktop'));
  testWidgets('expenses phone', (t) => _shot(t, phone, _app('/expenses', const ExpensesScreen()), 'expenses_phone'));
  testWidgets('expense form', (t) => _shot(
      t, desktop, _app('/', const ExpenseFormScreen(expenseId: 'ex2'), shell: false), 'expense_form_desktop'));
  testWidgets('bank accounts', (t) => _shot(t, desktop, _app('/bank-accounts', const BankAccountsScreen()), 'bank_accounts_desktop'));
  testWidgets('bank transfer dialog', (t) => _shot(t, desktop, _app('/bank-accounts', const BankAccountsScreen()), 'bank_transfer_dialog',
      then: () async {
        await t.tap(find.text('Deposit / Withdraw'));
        await t.pumpAndSettle();
        await t.tap(find.text('Bank to Bank Transfer').last);
      }));
  testWidgets('add bank dialog', (t) => _shot(t, desktop, _app('/bank-accounts', const BankAccountsScreen()), 'bank_account_form',
      then: () => t.tap(find.byTooltip('Edit account'))));
  testWidgets('cash in hand', (t) => _shot(t, desktop, _app('/cash-in-hand', const CashInHandScreen()), 'cash_desktop'));
  testWidgets('cash in hand phone', (t) => _shot(t, phone, _app('/cash-in-hand', const CashInHandScreen()), 'cash_phone'));
  testWidgets('cheques', (t) => _shot(t, desktop, _app('/cheques', const ChequesScreen()), 'cheques_desktop'));
  testWidgets('gst invoice form', (t) => _shot(
      t, desktop, _app('/', const InvoiceFormScreen(kind: InvoiceKind.sale, invoiceId: 'g1'), shell: false), 'invoice_form_gst'));
  testWidgets('sale orders', (t) => _shot(t, desktop, _app('/sale-orders', const InvoicesScreen(kind: InvoiceKind.saleOrder)), 'sale_orders_desktop'));
  testWidgets('pos', (t) => _shot(t, desktop, _app('/pos', const PosScreen()), 'pos_desktop', then: () async {
        await t.tap(find.text('Sample Item'));
        await t.tap(find.text('Sample Item').first);
        await t.tap(find.text('Home Delivery'));
      }));
  testWidgets('pos phone', (t) => _shot(t, phone, _app('/pos', const PosScreen()), 'pos_phone', then: () => t.tap(find.text('Sample Item'))));
  testWidgets('loans', (t) => _shot(t, desktop, _app('/loan-accounts', const LoanAccountsScreen()), 'loans_desktop'));
  testWidgets('loan payment', (t) => _shot(t, desktop, _app('/loan-accounts', const LoanAccountsScreen()), 'loan_payment_dialog',
      then: () => t.tap(find.text('Make Payment'))));
  testWidgets('reports index', (t) => _shot(t, desktop, _app('/reports', const ReportsScreen()), 'reports_index'));
  testWidgets('report view', (t) => _shot(t, desktop, _app('/reports/gstr1', const ReportViewScreen(reportId: 'gstr1')), 'report_view_desktop'));
  testWidgets('report view phone', (t) => _shot(t, phone, _app('/reports/gstr1', const ReportViewScreen(reportId: 'gstr1')), 'report_view_phone'));
  testWidgets('settings', (t) => _shot(t, desktop, _app('/settings', const SettingsScreen()), 'settings_desktop'));
  testWidgets('import items', (t) => _shot(t, desktop, _app('/import-items', ImportScreen(spec: itemImportSpec)), 'import_items_desktop',
      then: () async {
        // Feed a file straight to the cubit (the picker itself is a native dialog).
        final cubit = BlocProvider.of<ImportCubit>(t.element(find.text('Choose CSV file')));
        cubit.fileChosen('Item Name,Sale Price,GST Rate,HSN\nBasmati Rice 5kg,650,5,1006\nDelivery,50,18,\n,10,,\nBad Tax,10,7,\n');
      }));
  testWidgets('bulk update', (t) => _shot(t, desktop, _app('/bulk-update-items', const BulkUpdateItemsScreen()), 'bulk_update_desktop'));
  testWidgets('barcode', (t) => _shot(t, desktop, _app('/barcode', const BarcodeGeneratorScreen()), 'barcode_desktop'));
  testWidgets('payment in', (t) => _shot(t, desktop, _app('/payment-in', const PaymentsScreen(kind: PaymentKind.paymentIn)), 'payments_desktop'));
  testWidgets('payment in dialog', (t) => _shot(
      t, desktop, _app('/payment-in', const PaymentsScreen(kind: PaymentKind.paymentIn)), 'payment_form_desktop',
      then: () => t.tap(find.widgetWithText(FilledButton, 'Add Payment-In'))));

  // ---- second feature batch
  const accounting = {'invoicePrefix': 'INV-', 'accountingEnabled': true, 'serviceRemindersEnabled': true, 'dueDatesEnabled': true};
  testWidgets('journals', (t) => _shot(t, desktop, _app('/journals', const JournalsScreen(), settings: accounting), 'journals_desktop'));
  testWidgets('journal form', (t) => _shot(t, desktop, _app('/journals', const JournalsScreen(), settings: accounting), 'journal_form',
      then: () => t.tap(find.widgetWithText(FilledButton, 'Add Journal Entry'))));
  testWidgets('ledger accounts', (t) => _shot(t, desktop, _app('/ledger-accounts', const LedgerAccountsScreen(), settings: accounting), 'ledger_accounts'));
  testWidgets('currencies', (t) => _shot(t, desktop, _app('/currencies', const CurrenciesScreen()), 'currencies'));
  testWidgets('expense items', (t) => _shot(t, desktop, _app('/expense-items', const ExpenseItemsScreen()), 'expense_items'));
  testWidgets('expense item dialog', (t) => _shot(t, desktop, _app('/expense-items', const ExpenseItemsScreen()), 'expense_item_dialog',
      then: () => t.tap(find.widgetWithText(FilledButton, 'Add Expense Item'))));
  testWidgets('payment reminders', (t) => _shot(t, desktop, _app('/payment-reminders', const PaymentRemindersScreen()), 'payment_reminders'));
  testWidgets('payment reminders phone', (t) => _shot(t, phone, _app('/payment-reminders', const PaymentRemindersScreen()), 'payment_reminders_phone'));
  testWidgets('setup', (t) => _shot(t, desktop, _app('/setup', const SetupScreen()), 'setup'));
  testWidgets('verify', (t) => _shot(t, desktop, _app('/verify-data', const VerifyDataScreen()), 'verify'));
  testWidgets('close year', (t) => _shot(t, desktop, _app('/close-year', const CloseYearScreen()), 'close_year'));
  testWidgets('backup', (t) => _shot(t, desktop, _app('/backup', const BackupScreen()), 'backup'));
  testWidgets('companies', (t) => _shot(t, desktop, _app('/companies', const CompaniesScreen()), 'companies'));
  testWidgets('users', (t) => _shot(t, desktop, _app('/users', const UsersScreen()), 'users'));
  testWidgets('add user', (t) => _shot(t, desktop, _app('/users', const UsersScreen()), 'user_dialog',
      then: () => t.tap(find.widgetWithText(FilledButton, 'Add User'))));
  testWidgets('quick search', (t) => _shot(t, desktop, _app('/', const DashboardScreen()), 'quick_search', then: () async {
        await t.tap(find.textContaining('Search'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).last, 'te');
        await t.pump(const Duration(milliseconds: 400));
      }));
  testWidgets('salesman home', (t) => _shot(
      t, desktop, _app('/', const DashboardScreen(), user: const AppUser(id: 'u3', email: 's@example.com', fullName: 'Sam Salesman', firmId: 'f', firmName: 'Demo Traders', role: 'salesman')),
      'salesman_home'));
  testWidgets('settings lower', (t) => _shot(t, const Size(1440, 2600), _app('/settings', const SettingsScreen(), settings: accounting), 'settings_full'));
  testWidgets('invoice form split payment', (t) => _shot(
      t, const Size(1440, 1100), _app('/', const InvoiceFormScreen(kind: InvoiceKind.sale, invoiceId: 'v1'), shell: false, settings: accounting), 'invoice_form_split',
      then: () async {
        await t.scrollUntilVisible(find.textContaining('split payment'), 200, scrollable: find.byType(Scrollable).first);
        await t.tap(find.textContaining('split payment'));
      }));
  testWidgets('payment linked to invoices', (t) => _shot(
      t,
      desktop,
      _app('/payment-in', Builder(builder: (ctx) => Center(child: FilledButton(onPressed: () => showPaymentForm(ctx, PaymentKind.paymentIn, partyId: 'a'), child: const Text('open'))))),
      'payment_form_links',
      then: () async {
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        await t.enterText(find.widgetWithText(TextFormField, 'Received *'), '800');
        await t.pump();
        await t.tap(find.text('Auto link'));
      }));
  testWidgets('item form with image and service reminder', (t) => _shot(t, desktop, _app('/items', const ItemsScreen(openType: 'service'), settings: accounting), 'item_form_service',
      then: () => t.tap(find.widgetWithText(FilledButton, 'Add').last)));

  // ---- third batch
  const everything = {
    'invoicePrefix': 'INV-', 'godownsEnabled': true, 'batchTrackingEnabled': true, 'serialTrackingEnabled': true, 'mrpEnabled': true, 'cessEnabled': true,
    'billDiscountEnabled': true, 'additionalChargesEnabled': true, 'tcsEnabled': true, 'tdsEnabled': true, 'loyaltyEnabled': true, 'partyGroupsEnabled': true,
    'locationTrackingEnabled': true, 'autoBackup': 'daily', 'dueDatesEnabled': true,
  };
  testWidgets('invoice form with every option', (t) => _shot(
      t, const Size(1440, 1500), _app('/', const InvoiceFormScreen(kind: InvoiceKind.sale, invoiceId: 'v1'), shell: false, settings: everything), 'invoice_form_everything',
      then: () async {
        await t.tap(find.textContaining('Add charge'));
        await t.pumpAndSettle();
        await t.enterText(find.widgetWithText(TextFormField, 'Serial no. / IMEI').first, 'IM1, IM2, IM3');
      }));
  testWidgets('invoice form foreign currency', (t) => _shot(
      t, desktop, _app('/', const InvoiceFormScreen(kind: InvoiceKind.sale, invoiceId: 'v1'), shell: false, settings: everything), 'invoice_form_currency',
      then: () async {
        await t.tap(find.byKey(const ValueKey('cur-null')));
        await t.pumpAndSettle();
        await t.tap(find.text(r'$ USD').last);
      }));
  testWidgets('payment form split and currency', (t) => _shot(
      t, desktop, _app('/payment-in', Builder(builder: (ctx) => Center(child: FilledButton(onPressed: () => showPaymentForm(ctx, PaymentKind.paymentIn, partyId: 'a'), child: const Text('open'))))),
      'payment_form_split',
      then: () async {
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        await t.tap(find.textContaining('split'));
      }));
  testWidgets('godowns', (t) => _shot(t, desktop, _app('/godowns', const GodownsScreen(), settings: everything), 'godowns'));
  testWidgets('transfer stock', (t) => _shot(t, desktop, _app('/godowns', const GodownsScreen(), settings: everything), 'transfer_stock', then: () => t.tap(find.text('Transfer Stock'))));
  testWidgets('party groups', (t) => _shot(t, desktop, _app('/party-groups', const PartyGroupsScreen(), settings: everything), 'party_groups'));
  testWidgets('team locations', (t) => _shot(t, desktop, _app('/team-locations', const TeamLocationsScreen(), settings: everything), 'team_locations'));
  testWidgets('integrations', (t) => _shot(t, const Size(1200, 1300), _app('/integrations', const IntegrationsScreen()), 'integrations'));
  testWidgets('integration keys', (t) => _shot(t, desktop, _app('/integrations', const IntegrationsScreen()), 'integration_keys', then: () => t.tap(find.text('Edit keys').first)));
  testWidgets('messages', (t) => _shot(t, const Size(1200, 1000), _app('/messages', const MessagesScreen()), 'messages'));
  testWidgets('google profile', (t) => _shot(t, const Size(1200, 1500), _app('/google-profile', const GoogleProfileScreen()), 'google_profile'));
  testWidgets('invoice menu', (t) => _shot(t, desktop, _app('/sale', const InvoicesScreen(kind: InvoiceKind.sale), settings: const {'einvoiceEnabled': true}), 'invoice_menu', then: () async {
        await t.tap(find.byIcon(Icons.more_vert).first);
      }));
  testWidgets('einvoice dialog', (t) => _shot(t, const Size(1700, 1100), _app('/sale', const InvoicesScreen(kind: InvoiceKind.sale), settings: const {'einvoiceEnabled': true}), 'einvoice_dialog', then: () async {
        await t.tap(find.byIcon(Icons.more_vert).first);
        await t.pumpAndSettle();
        await t.tap(find.text('E-invoice / e-way bill'));
      }));
  testWidgets('backups', (t) => _shot(t, const Size(1440, 1100), _app('/backup', const BackupScreen(), settings: everything), 'backups'));
  testWidgets('item detail with stores', (t) => _shot(t, desktop, _app('/items', const ItemsScreen(), settings: everything), 'item_detail_stores'));
  testWidgets('party form more', (t) => _shot(t, desktop, _app('/parties', const PartiesScreen(), settings: everything), 'party_form_more', then: () async {
        await t.tap(find.text('Add Party'));
        await t.pumpAndSettle();
        await t.tap(find.text('Credit & Balance'));
      }));
  testWidgets('settings with every option', (t) => _shot(t, const Size(1440, 4200), _app('/settings', const SettingsScreen(), settings: everything), 'settings_everything'));

  testWidgets('lock screen', (t) async {
    final store = FakePasscodeStore('1234');
    await _shot(
      t,
      const Size(900, 700),
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme().copyWith(textTheme: buildTheme().textTheme.apply(fontFamily: 'Roboto')),
        home: BlocProvider(create: (_) => LockCubit(store)..load(), child: AppLock(onForgot: () {}, child: const SizedBox())),
      ),
      'lock_screen',
      then: () async {
        await t.enterText(find.byType(TextField), '0000');
        await t.tap(find.text('Unlock'));
      },
    );
  });
  testWidgets('set PIN dialog', (t) => _shot(
      t, const Size(1440, 6000), _app('/settings', const SettingsScreen(), settings: const {'invoicePrefix': 'INV-'}), 'set_pin_dialog',
      then: () => t.tap(find.text('Set PIN'))));

  testWidgets('invoice pdf themes', (t) async {
    final firm = Firm.fromJson(firmJson(settings: {'invoiceTerms': 'Goods once sold will not be taken back.', 'themeColor': '#0F766E'}));
    final invoice = Invoice.fromJson({
      ...gstInvoiceJson(), 'shippingAddress': 'Godown 4, Okhla Phase 2\nNew Delhi 110020', 'dueDate': '2026-10-25', 'linkedAmount': 100, 'balance': 900,
      'paymentLabel': 'Cash + UPI',
      'payments': [{'mode': 'cash', 'bankAccountId': null, 'amount': 200}, {'mode': 'upi', 'bankAccountId': 'b1', 'amount': 190}],
    });
    await t.runAsync(() async {
      for (final theme in invoiceThemes.keys) {
        File('screenshots_test/goldens/invoice_$theme.pdf').writeAsBytesSync(await buildInvoicePdf(invoice, firm, options: PrintOptions.of(firm, theme: theme)));
      }
      final bytes = buildReceiptBytes(invoice, firm, paperWidthMm: 58);
      File('screenshots_test/goldens/receipt_58.escpos').writeAsBytesSync(bytes);
      File('screenshots_test/goldens/receipt_80.pdf').writeAsBytesSync(await buildThermalReceiptPdf(invoice, firm, widthMm: 80));
      File('screenshots_test/goldens/receipt_58.pdf').writeAsBytesSync(await buildThermalReceiptPdf(invoice, firm, widthMm: 58));
    });
  });

  testWidgets('invoice pdf', (t) async {
    final firm = Firm.fromJson({
      'id': 'f', 'name': 'Demo Traders', 'phone': '9650269758', 'gstin': '07AAACR5055K1Z5', 'email': 'demo@example.com',
      'booksStartDate': '2026-04-01', 'businessType': 'Retail', 'businessCategory': null, 'stateCode': '07', 'pincode': '110001',
      'address': '1 Main Road, New Delhi',
    });
    final invoice = Invoice.fromJson(gstInvoiceJson());
    // rootBundle + PDF layout need real async, which testWidgets fakes by default.
    final bytes = await t.runAsync(() => buildInvoicePdf(invoice, firm));
    File('screenshots_test/goldens/invoice.pdf').writeAsBytesSync(bytes!);
    expect(bytes.length, greaterThan(1000));
  });

  testWidgets('items', (t) => _shot(t, desktop, _app('/items', const ItemsScreen()), 'items_desktop'));
  testWidgets('add item', (t) => _shot(t, desktop, _app('/items', const ItemsScreen()), 'item_form_desktop',
      then: () => t.tap(find.widgetWithText(FilledButton, 'Add'))));
  testWidgets('add item stock', (t) => _shot(t, desktop, _app('/items', const ItemsScreen()), 'item_form_stock',
      then: () async {
        await t.tap(find.widgetWithText(FilledButton, 'Add'));
        await t.pumpAndSettle();
        await t.tap(find.text('Stock'));
      }));
  testWidgets('item form phone', (t) => _shot(t, phone, _app('/items', const ItemsScreen()), 'item_form_phone',
      then: () async {
        await t.tap(find.text('Sample Item'));
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('Edit item'));
      }));
}
