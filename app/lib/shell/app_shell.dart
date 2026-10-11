import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../data/models/app_user.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/company/firm_cubit.dart';
import '../features/search/quick_search.dart';
import '../shared/theme.dart';
import '../shared/widgets.dart';
import 'nav.dart';
import 'nav_cubit.dart';

/// Sidebar + top bar around every signed-in page. The sidebar becomes a drawer on narrow screens.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final firmName = context.select((AuthBloc b) => b.state.user?.firmName ?? '');
    final isSalesman = context.select((AuthBloc b) => b.state.user?.isSalesman ?? false);
    final sidebar = _Sidebar(location: location, closeOnNavigate: !wide);

    final topBar = AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      shape: const Border(bottom: BorderSide(color: Color(0xFFE3E8EF))),
      automaticallyImplyLeading: !wide,
      title: Text(firmName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
      actions: [
        if (MediaQuery.sizeOf(context).width >= 760)
          OutlinedButton.icon(
            onPressed: () => showQuickSearch(context),
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Search   Ctrl K'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.black54, shape: const StadiumBorder(), side: const BorderSide(color: Color(0xFFE3E8EF))),
          )
        else
          IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: () => showQuickSearch(context)),
        const SizedBox(width: 8),
        if (MediaQuery.sizeOf(context).width >= 600) ...[
          _QuickAction(label: 'Add Sale', color: payRed, onTap: () => context.push('/sale-invoices/new')),
          const SizedBox(width: 8),
          if (!isSalesman) _QuickAction(label: 'Add Purchase', color: brandBlue, onTap: () => context.push('/purchase-bills/new')),
          const SizedBox(width: 12),
        ],
      ],
    );

    if (!wide) {
      return QuickSearchShortcut(child: Scaffold(appBar: topBar, drawer: Drawer(width: 270, child: sidebar), body: child));
    }
    return QuickSearchShortcut(
      child: Scaffold(
        body: Row(children: [
          SizedBox(width: 250, child: sidebar),
          Expanded(child: Scaffold(appBar: topBar, body: child)),
        ]),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(backgroundColor: color.withValues(alpha: 0.1), foregroundColor: color, shape: const StadiumBorder()),
        icon: const Icon(Icons.add, size: 18),
        label: Text(label),
      );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.location, required this.closeOnNavigate});
  final String location;
  final bool closeOnNavigate;

  void _go(BuildContext context, String path) {
    if (closeOnNavigate) Navigator.of(context).pop();
    context.go(path);
  }

  bool _active(String path) => path == '/' ? location == '/' : location.startsWith(path);

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    final expanded = context.watch<NavCubit>().state;
    final sections = navFor(user, settingsOf(context, listen: true));
    return Material(
      color: sidebarBg,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(children: const [
              Icon(Icons.receipt_long_rounded, color: Colors.white, size: 26),
              SizedBox(width: 10),
              Text('Billing', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
              for (final s in sections) ..._section(context, s, expanded),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 14, right: 4),
            horizontalTitleGap: 10,
            // Salesmen cannot change the company profile; for them this opens the list of companies.
            onTap: () => _go(context, (user?.isSalesman ?? false) ? '/companies' : '/company'),
            selected: _active('/company'),
            selectedTileColor: Colors.white10,
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: brandBlue,
              child: Text((user?.firmName ?? '?').characters.first.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            title: Text(user?.firmName ?? '', style: const TextStyle(color: Colors.white), overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${user?.fullName ?? ''} · ${roleLabels[user?.role] ?? ''}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _CompanyMenu(closeDrawer: closeOnNavigate),
              IconButton(
                tooltip: 'Log out',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.logout, color: Colors.white54, size: 19),
                onPressed: () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _section(BuildContext context, NavSection s, Set<String> expanded) {
    if (s.children.isEmpty) {
      return [_tile(s.label, icon: s.icon, active: _active(s.path!), onTap: () => _go(context, s.path!))];
    }
    final open = expanded.contains(s.label);
    return [
      _tile(
        s.label,
        icon: s.icon,
        active: false,
        trailing: Icon(open ? Icons.expand_less : Icons.expand_more, color: Colors.white54, size: 20),
        onTap: () => context.read<NavCubit>().toggle(s.label),
      ),
      if (open)
        for (final c in s.children) _tile(c.label, indent: true, active: _active(c.path), onTap: () => _go(context, c.path)),
    ];
  }

  Widget _tile(String label, {IconData? icon, required bool active, required VoidCallback onTap, Widget? trailing, bool indent = false}) {
    return Material(
      color: active ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
      shape: Border(left: BorderSide(color: active ? brandBlue : Colors.transparent, width: 3)),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        contentPadding: EdgeInsets.only(left: indent ? 52 : 17, right: 12),
        leading: icon == null ? null : Icon(icon, color: active ? Colors.white : Colors.white70, size: 21),
        minLeadingWidth: 20,
        title: Text(label, style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: indent ? 13.5 : 14.5)),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

/// Sidebar button listing the companies under this login, to switch between them.
class _CompanyMenu extends StatelessWidget {
  const _CompanyMenu({required this.closeDrawer});
  final bool closeDrawer;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Switch company',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.swap_horiz, color: Colors.white54, size: 19),
        onPressed: () {
          if (closeDrawer) Navigator.of(context).pop();
          context.go('/companies');
        },
      );
}
