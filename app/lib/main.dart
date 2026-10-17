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
import 'data/repositories/platform_repository.dart';
import 'data/repositories/tax_statements_repository.dart';
import 'features/tax/tax_statements_screen.dart';
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
import 'features/platform/audit_screen.dart';
import 'features/platform/platform_screen.dart';
import 'features/sync/sync_screen.dart';
import 'data/models/firm.dart';
import 'core/offline.dart';
import 'core/license/license_cubit.dart';
import 'core/license/license_gate.dart';
import 'core/license/license_vault.dart';
import 'core/license/trusted_clock.dart';
import 'core/sync_cubit.dart';
import 'data/repositories/license_repository.dart';
import 'features/printing/invoice_print.dart';
import 'features/printing/pdf_documents.dart';
import 'features/reports/report_cubit.dart';
import 'features/reports/reports_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/utilities/import_spec.dart';
import 'features/utilities/utilities_screens.dart';
import 'features/printing/pdf_preview_screen.dart';
import 'shell/sidebar_cubit.dart';
import 'shared/theme.dart';
import 'shell/app_shell.dart';
import 'shell/nav.dart';
import 'shell/nav_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // What lets the counter work without a connection: the last answers, the saves waiting to be sent, the last user.
  final store = await PrefsStore.open();
  final api = ApiClient(TokenStore(), cache: ResponseCache(store, maxEntryBytes: 1500000), queue: SyncQueue(store));
  final bus = ChangeBus();
  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: bus),
        RepositoryProvider.value(value: api),
        RepositoryProvider.value(value: store),
        RepositoryProvider(create: (_) => AuthRepository(api, store)),
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
        RepositoryProvider(create: (_) => TaxStatementsRepository(api, bus)),
        RepositoryProvider(create: (_) => PlatformRepository(api)),
        RepositoryProvider(create: (_) => LicenseRepository(api)),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (ctx) => AuthBloc(ctx.read())..add(const AuthStarted())),
          BlocProvider(lazy: false, create: (_) => SidebarCubit()..load()),
          BlocProvider(
            lazy: false,
            create: (ctx) => KeyboardNavCubit(userIds: ctx.read<AuthBloc>().stream.map((a) => a.status == AuthStatus.signedIn ? a.user?.id : null).distinct())..loadFor(null),
          ),
          BlocProvider(
            lazy: false,
            create: (ctx) => ThemeCubit(userIds: ctx.read<AuthBloc>().stream.map((a) => a.status == AuthStatus.signedIn ? a.user?.id : null).distinct())..loadFor(null),
          ),
          // Not lazy: it must hear the sign-in that happens before any screen asks for it.
          BlocProvider(lazy: false, create: (_) => LockCubit(PasscodeStore())..load()),
          BlocProvider(lazy: false, create: (ctx) => FirmCubit(ctx.read(), ctx.read(), ctx.read<AuthBloc>())),
          // Decides offline, from the signed certificate kept on the device, whether the app may run at all.
          BlocProvider(
            lazy: false,
            create: (ctx) {
              final auth = ctx.read<AuthBloc>();
              final cubit = LicenseCubit(
                ctx.read(),
                LicenseVault(PlatformSecureStore()),
                policy: ClockTamperPolicy.parse(clockTamperPolicy),
                onlineChanges: api.onlineChanges,
              );
              // The certificate belongs to the business signed in; start again when that changes.
              auth.stream.map((a) => a.status == AuthStatus.signedIn ? a.user?.firmId : null).distinct().listen(cubit.start);
              if (auth.state.user != null) cubit.start(auth.state.user!.firmId);
              return cubit;
            },
          ),
          BlocProvider(
            lazy: false,
            create: (ctx) => SyncCubit(
              api,
              store,
              bus,
              // What the counter reads while offline: the company settings, items, accounts and the next bill number.
              refresh: () async {
                final (firm, items, accounts, invoices) =
                    (ctx.read<FirmRepository>(), ctx.read<ItemsRepository>(), ctx.read<CashBankRepository>(), ctx.read<InvoicesRepository>());
                await firm.get();
                await items.list('all');
                await accounts.accounts();
                await invoices.nextNumber('sale');
              },
              firmIds: ctx.read<AuthBloc>().stream.map((a) => a.status == AuthStatus.signedIn ? a.user?.firmId : null).distinct(),
            )..load(),
          ),
          BlocProvider(lazy: false, create: (ctx) => TrackingCubit(ctx.read(), ctx.read<FirmCubit>().stream, initial: ctx.read<FirmCubit>().state, background: !kIsWeb)),
        ],
        child: const BillingApp(),
      ),
    ),
  );
}

/// Lets GoRouter re-run redirects when the auth state changes.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(List<Stream<dynamic>> streams) {
    _subs = [for (final s in streams) s.listen((_) => notifyListeners())];
  }
  late final List<StreamSubscription<dynamic>> _subs;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
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
    refreshListenable: _StreamListenable([auth.stream]),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      switch (auth.state.status) {
        case AuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.signedOut:
          return authPages.contains(loc) ? null : '/login';
        case AuthStatus.signedIn:
          if (authPages.contains(loc) || loc == '/splash') return '/';
          // A POS-only business only gets the counter and the pages that serve it.
          final user = auth.state.user;
          if (user != null && user.master) return masterRedirect(loc);
          if (user != null && user.posOnly) return posOnlyRedirect(loc, admin: user.isAdmin, platformAdmin: user.platformAdmin);
          return null;
      }
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const Scaffold(body: Align(alignment: Alignment.topCenter, child: GradientProgressBar())),
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
              BlocProvider(create: (_) => NavCubit(state.uri.toString())),
              BlocProvider(create: (ctx) => CatalogCubit(ctx.read(), ctx.read())..load()),
              // The sidebar's Reports menu is built from this list.
              BlocProvider(create: (ctx) => ReportCatalogCubit(ctx.read())..load()),
            ],
            child: AppShell(
              location: state.uri.toString(),
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
          GoRoute(path: '/tax-statements', builder: (_, _) => const TaxStatementsScreen()),
          GoRoute(path: '/integrations', builder: (_, _) => const IntegrationsScreen()),
          GoRoute(path: '/messages', builder: (_, _) => const MessagesScreen()),
          GoRoute(
            path: '/google-profile',
            builder: (_, state) => GoogleProfileScreen(key: ValueKey('google-${state.uri.queryParameters['connected']}')),
          ),
          GoRoute(path: '/companies', builder: (_, _) => const CompaniesScreen()),
          GoRoute(path: '/users', builder: (_, _) => const UsersScreen()),
          GoRoute(path: '/pos', builder: (_, _) => const PosScreen()),
          GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
          GoRoute(path: '/platform', builder: (_, _) => const PlatformScreen()),
          GoRoute(
            path: '/platform-audit',
            builder: (_, state) => AuditScreen(key: ValueKey('audit-${state.uri.queryParameters['firm']}'), firmId: state.uri.queryParameters['firm']),
          ),
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
          GoRoute(path: '/settings', builder: (_, state) => SettingsScreen(group: state.uri.queryParameters['tab'] ?? 'general')),
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
  Widget build(BuildContext context) => BlocConsumer<ThemeCubit, Color>(
    // Tokens are read when a widget builds, so a new accent needs every widget rebuilt (state is kept).
    listener: (context, _) => WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll()),
    builder: (context, _) => MaterialApp.router(
    title: 'Billing',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    routerConfig: _router,
    // The PIN lock covers everything once someone is signed in; the sign-in pages are not locked.
    builder: (context, child) => BlocBuilder<KeyboardNavCubit, bool>(
      builder: (context, enterNav) => EnterKeyNavigation(enabled: enterNav, child: BlocBuilder<AuthBloc, AuthState>(
      builder: (context, auth) {
        if (auth.status != AuthStatus.signedIn) return child!;
        final locked = AppLock(
          onForgot: () {
            // Signing in again with the password proves it is the owner, so the PIN is cleared.
            context.read<LockCubit>().forgot();
            context.read<AuthBloc>().add(const AuthLogoutRequested());
          },
          child: child!,
        );
        // The master admin has no business, so there is no business licence to check.
        return (auth.user?.master ?? false) ? locked : LicenseGate(child: locked);
      },
    ))),
  ));
}

/// Marks every mounted widget dirty so it rebuilds with the current design tokens.
void _rebuildAll() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}
