import 'package:flutter/material.dart';

import '../data/models/app_user.dart';
import '../data/models/firm.dart';

/// The settings pages, in the order of the sidebar's Settings group. `/settings?tab=<key>` opens one.
const settingsGroups = <(String, String, IconData)>[
  ('general', 'General', Icons.tune),
  ('transaction', 'Transaction', Icons.receipt_long_outlined),
  ('print', 'Print', Icons.print_outlined),
  ('tax', 'Taxes & GST', Icons.percent),
  ('message', 'Transaction message', Icons.chat_outlined),
  ('party', 'Party', Icons.people_outline),
  ('item', 'Item', Icons.inventory_2_outlined),
  ('service', 'Service reminders', Icons.notifications_outlined),
  ('accounting', 'Accounting', Icons.account_balance_outlined),
  ('currency', 'Multi currency', Icons.currency_exchange),
  ('keyboard', 'Keyboard', Icons.keyboard_outlined),
  ('theme', 'Theme', Icons.palette_outlined),
];

/// Whether the sidebar entry [path] (which may carry `?tab=`) is the page at [location] (path and query).
bool navActive(String location, String path) {
  final loc = Uri.parse(location);
  final target = Uri.parse(path);
  if (target.path == '/') return loc.path == '/';
  if (target.queryParameters.containsKey('tab')) {
    final tab = loc.queryParameters['tab'] ?? 'general';
    return loc.path == target.path && tab == target.queryParameters['tab'];
  }
  return loc.path.startsWith(target.path);
}

/// Icons for the report groups in the sidebar's Reports menu.
const reportGroupIcons = {
  'Transaction': Icons.receipt_long_outlined,
  'Party': Icons.people_outline,
  'GST': Icons.account_balance_outlined,
  'Item / Stock': Icons.inventory_2_outlined,
  'Business Status': Icons.insights_outlined,
};

class NavLeaf {
  const NavLeaf(this.label, this.path);
  final String label;
  final String path;
}

class NavSection {
  const NavSection(this.label, this.icon, {this.path, this.children = const []});
  final String label;
  final IconData icon;
  final String? path;
  final List<NavLeaf> children;
}

/// The sidebar for [user] with the company's [settings]: salesmen only see the sale side, and
/// optional modules (accounting, service reminders) appear once switched on.
List<NavSection> navFor(AppUser? user, FirmSettings settings) {
  final salesman = user?.isSalesman ?? false;
  final admin = user?.isAdmin ?? false;
  return [
    const NavSection('Home', Icons.home_outlined, path: '/'),
    const NavSection('Parties', Icons.people_outline, path: '/parties'),
    const NavSection('Items', Icons.inventory_2_outlined, path: '/items'),
    const NavSection(
      'Sale',
      Icons.receipt_long_outlined,
      children: [
        NavLeaf('Sale Invoices', '/sale-invoices'),
        NavLeaf('Estimate / Quotation', '/estimates'),
        NavLeaf('Payment-In', '/payment-in'),
        NavLeaf('Sale Order', '/sale-orders'),
        NavLeaf('Delivery Challan', '/delivery-challans'),
        NavLeaf('Proforma Invoice', '/proforma-invoices'),
        NavLeaf('Sale Return / Credit Note', '/credit-notes'),
        NavLeaf('POS', '/pos'),
      ],
    ),
    if (!salesman)
      const NavSection(
        'Purchase & Expense',
        Icons.shopping_cart_outlined,
        children: [
          NavLeaf('Purchase Bills', '/purchase-bills'),
          NavLeaf('Payment-Out', '/payment-out'),
          NavLeaf('Expenses', '/expenses'),
          NavLeaf('Expense Items', '/expense-items'),
          NavLeaf('Purchase Order', '/purchase-orders'),
          NavLeaf('Purchase Return / Debit Note', '/debit-notes'),
        ],
      ),
    if (!salesman)
      const NavSection(
        'Cash & Bank',
        Icons.account_balance_outlined,
        children: [
          NavLeaf('Bank Accounts', '/bank-accounts'),
          NavLeaf('Cash In Hand', '/cash-in-hand'),
          NavLeaf('Cheques', '/cheques'),
          NavLeaf('Loan Accounts', '/loan-accounts'),
        ],
      ),
    if (!salesman && settings.accountingEnabled)
      const NavSection(
        'Accounting',
        Icons.menu_book_outlined,
        children: [NavLeaf('Journal Entries', '/journals'), NavLeaf('Accounts', '/ledger-accounts')],
      ),
    NavSection(
      'Reminders',
      Icons.notifications_none_outlined,
      children: [
        const NavLeaf('Payment Reminders', '/payment-reminders'),
        if (settings.serviceRemindersEnabled) const NavLeaf('Service Reminders', '/service-reminders'),
      ],
    ),
    if (!salesman) const NavSection('Reports', Icons.bar_chart_outlined, path: '/reports'),
    if (!salesman)
      NavSection(
        'Utilities',
        Icons.build_outlined,
        children: [
          const NavLeaf('Set Up My Business', '/setup'),
          const NavLeaf('Import Items', '/import-items'),
          const NavLeaf('Import Parties', '/import-parties'),
          if (settings.godownsEnabled) const NavLeaf('Godowns', '/godowns'),
          if (settings.partyGroupsEnabled) const NavLeaf('Party Groups', '/party-groups'),
          if (settings.locationTrackingEnabled && admin) const NavLeaf('Team Locations', '/team-locations'),
          const NavLeaf('Barcode Generator', '/barcode'),
          const NavLeaf('Bulk Update Items', '/bulk-update-items'),
          const NavLeaf('Export Items', '/export-items'),
          const NavLeaf('Verify My Data', '/verify-data'),
          const NavLeaf('Close Financial Year', '/close-year'),
          if (settings.tdsEnabled || settings.tcsEnabled) const NavLeaf('TDS / TCS Statements', '/tax-statements'),
          if (admin) const NavLeaf('Integrations', '/integrations'),
          if (admin) const NavLeaf('Google Business Profile', '/google-profile'),
          if (admin) const NavLeaf('Backup & Restore', '/backup'),
        ],
      ),
    NavSection('Settings', Icons.settings_outlined, children: [
      for (final g in settingsGroups)
        // Salesmen cannot change business settings: only their account and theme.
        if (!salesman || g.$1 == 'general' || g.$1 == 'keyboard' || g.$1 == 'theme') NavLeaf(g.$2, '/settings?tab=${g.$1}'),
    ]),
  ];
}

/// Every section there can be, whatever the role or settings.
final navSections = navFor(
  const AppUser(id: '', email: '', fullName: '', firmId: '', firmName: ''),
  const FirmSettings(accountingEnabled: true, serviceRemindersEnabled: true),
);
