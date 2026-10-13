import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/api_client.dart';
import 'core/change_bus.dart';
import 'data/models/invoice.dart';
import 'data/models/payment.dart';
import 'data/repositories/accounting_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/cash_bank_repository.dart';
import 'data/repositories/dashboard_repository.dart';
import 'data/repositories/expenses_repository.dart';
import 'data/repositories/files_repository.dart';
import 'data/repositories/firm_repository.dart';
import 'data/repositories/invoices_repository.dart';
import 'data/repositories/items_repository.dart';
import 'data/repositories/loans_repository.dart';
import 'data/repositories/location_repository.dart';
import 'data/repositories/parties_repository.dart';
import 'data/repositories/payments_repository.dart';
import 'data/repositories/reports_repository.dart';
import 'data/repositories/integrations_repository.dart';
import 'data/repositories/utilities_repository.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/cash_bank/cash_bank_screens.dart';
import 'features/company/company_screen.dart';
import 'features/company/firm_cubit.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/expenses/expense_form_screen.dart';
import 'features/accounting/accounting_screens.dart';
import 'features/expenses/expense_items_screen.dart';
import 'features/expenses/expenses_screen.dart';
import 'features/integrations/integrations_screens.dart';
import 'features/reminders/reminders_screens.dart';
import 'features/team/team_locations_screen.dart';
import 'features/team/team_screens.dart';
import 'features/team/tracking_cubit.dart';
import 'features/tools/tools_screens.dart';
import 'features/invoices/invoice_form_screen.dart';
import 'features/lock/lock_cubit.dart';
import 'features/lock/lock_screen.dart';
import 'features/lock/passcode_store.dart';
import 'features/invoices/invoices_screen.dart';
import 'features/items/bloc/catalog_cubit.dart';
import 'features/items/items_screen.dart';
import 'features/loans/loans_screen.dart';
import 'features/parties/parties_screen.dart';
import 'features/parties/party_groups_screen.dart';
import 'features/stock/godowns_screen.dart';
import 'features/payments/payments_screen.dart';
import 'features/pos/pos_screen.dart';
import 'data/models/firm.dart';
import 'features/printing/invoice_print.dart';
import 'features/printing/pdf_documents.dart';
import 'features/reports/reports_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/utilities/import_spec.dart';
import 'features/utilities/utilities_screens.dart';
import 'features/printing/pdf_preview_screen.dart';
import 'shared/theme.dart';
import 'shell/app_shell.dart';
import 'shell/nav_cubit.dart';

void main() {
  final api = ApiClient(TokenStore());
  final bus = ChangeBus();
  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: bus),
        RepositoryProvider.value(value: api),
        RepositoryProvider(create: (_) => AuthRepository(api)),
        RepositoryProvider(create: (_) => FirmRepository(api, bus)),
        RepositoryProvider(create: (_) => PartiesRepository(api, bus)),
        RepositoryProvider(create: (_) => ItemsRepository(api, bus)),
        RepositoryProvider(create: (_) => InvoicesRepository(api, bus)),
        RepositoryProvider(create: (_) => PaymentsRepository(api, bus)),
        RepositoryProvider(create: (_) => ExpensesRepository(api, bus)),
        RepositoryProvider(create: (_) => CashBankRepository(api, bus)),
        RepositoryProvider(create: (_) => LoansRepository(api, bus)),
        RepositoryProvider(create: (_) => ReportsRepository(api)),
        RepositoryProvider(create: (_) => DashboardRepository(api)),
        RepositoryProvider(create: (_) => FilesRepository(api)),
        RepositoryProvider(create: (_) => LocationRepository(api)),
        RepositoryProvider(create: (_) => AccountingRepository(api, bus)),
        RepositoryProvider(create: (_) => UtilitiesRepository(api, bus)),
        RepositoryProvider(create: (_) => IntegrationsRepository(api, bus)),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (ctx) => AuthBloc(ctx.read())..add(const AuthStarted())),
          // Not lazy: it must hear the sign-in that happens before any screen asks for it.
          BlocProvider(lazy: false, create: (_) => LockCubit(PasscodeStore())..load()),
          BlocProvider(lazy: false, create: (ctx) => FirmCubit(ctx.read(), ctx.read(), ctx.read<AuthBloc>())),
          BlocProvider(lazy: false, create: (ctx) => TrackingCubit(ctx.read(), ctx.read<FirmCubit>().stream, initial: ctx.read<FirmCubit>().state, background: !kIsWeb)),
        ],
        child: const BillingApp(),
      ),
    ),
  );
}

/// Lets GoRouter re-run redirects when the auth state changes.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// New / edit / preview pages for one kind of invoice.
List<GoRoute> _invoiceRoutes(InvoiceKind kind) => [
  GoRoute(
    path: '${kind.basePath}/new',
    builder: (_, state) {
      // ?from=<id> pre-fills the new document from an estimate/order ("Convert to ...").
      final from = state.uri.queryParameters['from'];
      return InvoiceFormScreen(key: ValueKey('${kind.type}-new-$from'), kind: kind, fromDocumentId: from);
    },
  ),
  GoRoute(
    path: '${kind.basePath}/:id/edit',
    builder: (_, state) => InvoiceFormScreen(key: ValueKey(state.pathParameters['id']), kind: kind, invoiceId: state.pathParameters['id']),
  ),
  GoRoute(
    path: '${kind.basePath}/:id/preview',
    builder: (context, state) {
      final id = state.pathParameters['id']!;
      return PdfPreviewScreen(
        key: ValueKey(id),
        title: '${kind.documentTitle} Preview',
        fallbackPath: kind.basePath,
        editPath: '${kind.basePath}/$id/edit',
        // ?layout=thermal opens the receipt straight away (POS).
        initialLayout: state.uri.queryParameters['layout'] ?? settingsOf(context).invoiceTheme,
        layouts: [for (final e in invoiceThemes.entries) (e.key, 'A4 · ${e.value}'), (thermalLayout, 'Thermal receipt')],
        buildLayout: (ctx, layout) => renderInvoice(ctx, id, layout),
        directPrintLayout: thermalLayout,
        directPrint: (ctx, prefs) => renderReceiptBytes(ctx, id, prefs),
      );
    },
  ),
];

GoRoute _receiptRoute(PaymentKind kind) => GoRoute(
  path: '${kind.basePath}/:id/receipt',
  builder: (_, state) {
    final id = state.pathParameters['id']!;
    return PdfPreviewScreen(
      key: ValueKey(id),
      title: kind.type == 'in' ? 'Payment Receipt' : 'Payment Voucher',
      fallbackPath: kind.basePath,
      buildPdf: (ctx) async {
        final (payment, firm) = await (ctx.read<PaymentsRepository>().get(id), ctx.read<FirmRepository>().get()).wait;
        final signature = await ctx.read<FilesRepository>().bytesOrNull(firm.signatureFileId);
        return (
          '${kind.title.toLowerCase()}-${payment.number}.pdf',
          await buildPaymentPdf(payment, firm, options: PrintOptions(signature: signature)),
        );
      },
    );
  },
);

GoRouter buildRouter(AuthBloc auth) {
  const authPages = {'/login', '/register'};
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _StreamListenable(auth.stream),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      switch (auth.state.status) {
        case AuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.signedOut:
          return authPages.contains(loc) ? null : '/login';
        case AuthStatus.signedIn:
          return (authPages.contains(loc) || loc == '/splash') ? '/' : null;
      }
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      // Full-screen pages (no sidebar): invoice forms and PDF previews.
      for (final kind in InvoiceKind.all) ..._invoiceRoutes(kind),
      for (final kind in [PaymentKind.paymentIn, PaymentKind.paymentOut]) _receiptRoute(kind),
      GoRoute(
        path: '/expenses/new',
        builder: (_, state) => ExpenseFormScreen(categoryId: state.uri.queryParameters['categoryId']),
      ),
      GoRoute(
        path: '/expenses/:id/edit',
        builder: (_, state) => ExpenseFormScreen(key: ValueKey(state.pathParameters['id']), expenseId: state.pathParameters['id']),
      ),
      // Signed-in area; its blocs live for the session and are discarded on logout.
      ShellRoute(
        // Keyed by company: switching company discards every screen's blocs and loads the new company's data.
        builder: (context, state, child) => BlocSelector<AuthBloc, AuthState, String?>(
          selector: (auth) => auth.user?.firmId,
          builder: (context, firmId) => MultiBlocProvider(
            key: ValueKey('company-$firmId'),
            providers: [
              BlocProvider(create: (_) => NavCubit(state.uri.path)),
              BlocProvider(create: (ctx) => CatalogCubit(ctx.read(), ctx.read())..load()),
            ],
            child: AppShell(
              location: state.uri.path,
              child: KeyedSubtree(key: ValueKey('page-$firmId'), child: child),
            ),
          ),
        ),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
          GoRoute(
            path: '/parties',
            builder: (_, state) =>
                PartiesScreen(key: ValueKey('parties-${state.uri.queryParameters['open']}'), openId: state.uri.queryParameters['open']),
          ),
          GoRoute(
            path: '/items',
            builder: (_, state) => ItemsScreen(
              key: ValueKey('items-${state.uri.queryParameters['open']}'),
              openId: state.uri.queryParameters['open'],
              openType: state.uri.queryParameters['type'],
            ),
          ),
          for (final kind in InvoiceKind.all)
            GoRoute(
              path: kind.basePath,
              builder: (_, _) => InvoicesScreen(key: ValueKey(kind.type), kind: kind),
            ),
          for (final kind in [PaymentKind.paymentIn, PaymentKind.paymentOut])
            GoRoute(
              path: kind.basePath,
              builder: (_, _) => PaymentsScreen(key: ValueKey(kind.type), kind: kind),
            ),
          GoRoute(path: '/expenses', builder: (_, _) => const ExpensesScreen()),
          GoRoute(path: '/expense-items', builder: (_, _) => const ExpenseItemsScreen()),
          GoRoute(path: '/godowns', builder: (_, _) => const GodownsScreen()),
          GoRoute(path: '/team-locations', builder: (_, _) => const TeamLocationsScreen()),
          GoRoute(path: '/party-groups', builder: (_, _) => const PartyGroupsScreen()),
          GoRoute(path: '/journals', builder: (_, _) => const JournalsScreen()),
          GoRoute(path: '/ledger-accounts', builder: (_, _) => const LedgerAccountsScreen()),
          GoRoute(path: '/currencies', builder: (_, _) => const CurrenciesScreen()),
          GoRoute(path: '/payment-reminders', builder: (_, _) => const PaymentRemindersScreen()),
          GoRoute(path: '/service-reminders', builder: (_, _) => const ServiceRemindersScreen()),
          GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
          GoRoute(path: '/verify-data', builder: (_, _) => const VerifyDataScreen()),
          GoRoute(path: '/close-year', builder: (_, _) => const CloseYearScreen()),
          GoRoute(
            path: '/backup',
            builder: (_, state) =>
                BackupScreen(key: ValueKey('backup-${state.uri.queryParameters['drive']}'), driveResult: state.uri.queryParameters['drive']),
          ),
          GoRoute(path: '/integrations', builder: (_, _) => const IntegrationsScreen()),
          GoRoute(path: '/messages', builder: (_, _) => const MessagesScreen()),
          GoRoute(
            path: '/google-profile',
            builder: (_, state) => GoogleProfileScreen(key: ValueKey('google-${state.uri.queryParameters['connected']}')),
          ),
          GoRoute(path: '/companies', builder: (_, _) => const CompaniesScreen()),
          GoRoute(path: '/users', builder: (_, _) => const UsersScreen()),
          GoRoute(path: '/pos', builder: (_, _) => const PosScreen()),
          GoRoute(path: '/bank-accounts', builder: (_, _) => const BankAccountsScreen()),
          GoRoute(path: '/cash-in-hand', builder: (_, _) => const CashInHandScreen()),
          GoRoute(path: '/cheques', builder: (_, _) => const ChequesScreen()),
          GoRoute(path: '/loan-accounts', builder: (_, _) => const LoanAccountsScreen()),
          GoRoute(
            path: '/import-items',
            builder: (_, _) => ImportScreen(key: const ValueKey('items'), spec: itemImportSpec),
          ),
          GoRoute(
            path: '/import-parties',
            builder: (_, _) => ImportScreen(key: const ValueKey('parties'), spec: partyImportSpec),
          ),
          GoRoute(path: '/export-items', builder: (_, _) => const ExportItemsScreen()),
          GoRoute(path: '/bulk-update-items', builder: (_, _) => const BulkUpdateItemsScreen()),
          GoRoute(path: '/barcode', builder: (_, _) => const BarcodeGeneratorScreen()),
          GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
          GoRoute(
            path: '/reports/:id',
            builder: (_, state) => ReportViewScreen(key: ValueKey(state.pathParameters['id']), reportId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/company', builder: (_, _) => const CompanyScreen()),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        ],
      ),
    ],
  );
}

class BillingApp extends StatefulWidget {
  const BillingApp({super.key});

  @override
  State<BillingApp> createState() => _BillingAppState();
}

/// Stateful only so the router is created once.
class _BillingAppState extends State<BillingApp> {
  late final GoRouter _router = buildRouter(context.read<AuthBloc>());

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Billing',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    routerConfig: _router,
    // The PIN lock covers everything once someone is signed in; the sign-in pages are not locked.
    builder: (context, child) => BlocBuilder<AuthBloc, AuthState>(
      builder: (context, auth) => auth.status == AuthStatus.signedIn
          ? AppLock(
              onForgot: () {
                // Signing in again with the password proves it is the owner, so the PIN is cleared.
                context.read<LockCubit>().forgot();
                context.read<AuthBloc>().add(const AuthLogoutRequested());
              },
              child: child!,
            )
          : child!,
    ),
  );
}
