import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/keyboard/keyboard.dart';
import '../data/models/app_user.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/company/firm_cubit.dart';
import '../data/models/report.dart';
import '../features/lock/lock_cubit.dart';
import '../features/reports/report_cubit.dart';
import '../features/search/quick_search.dart';
import '../features/sync/sync_screen.dart';
import '../features/team/tracking_cubit.dart';
import '../shared/theme.dart';
import '../shared/widgets.dart';
import 'nav.dart';
import 'nav_cubit.dart';
import 'sidebar_cubit.dart';

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
    final collapsed = wide && context.watch<SidebarCubit>().state;
    final posOnly = context.select((AuthBloc b) => b.state.user?.posOnly ?? false);
    final master = context.select((AuthBloc b) => b.state.user?.master ?? false);
    // Bills kept on the device, or a daily sync not yet done, are shown above every page.
    final body = Column(
      children: [
        SyncBanner(onOpen: () => context.go('/sync')),
        Expanded(child: FocusFirstField(page: location, child: child)),
      ],
    );
    final sidebar = _Sidebar(location: location, closeOnNavigate: !wide, collapsed: collapsed);

    final topBar = AppBar(
      automaticallyImplyLeading: !wide,
      leading: wide
          ? IconButton(
              tooltip: collapsed ? 'Expand menu' : 'Collapse menu',
              icon: Icon(collapsed ? Icons.menu : Icons.menu_open),
              onPressed: context.read<SidebarCubit>().toggle,
            )
          : null,
      title: Text(firmName, style: AppText.title),
      actions: [
        BlocBuilder<TrackingCubit, TrackingState>(
          builder: (context, t) => switch (t.status) {
            TrackingStatus.active => const Tooltip(
              message: 'Your location is being recorded while this app is open.',
              child: Padding(padding: EdgeInsets.only(right: AppSpace.sm), child: Icon(Icons.my_location, size: AppIconSize.sm, color: AppColors.success)),
            ),
            TrackingStatus.denied => const Tooltip(
              message: 'Location tracking is on for this business, but this device is not sharing its location. Allow it in your browser or phone settings.',
              child: Padding(padding: EdgeInsets.only(right: AppSpace.sm), child: Icon(Icons.location_off_outlined, size: AppIconSize.sm, color: AppColors.danger)),
            ),
            TrackingStatus.off => const SizedBox.shrink(),
          },
        ),
        if (master)
          const SizedBox.shrink()
        else if (MediaQuery.sizeOf(context).width >= AppSize.compactBar)
          OutlinedButton.icon(
            onPressed: () => showQuickSearch(context),
            icon: const Icon(Icons.search),
            label: const ShortcutLabel('Search', AppCommand.quickSearch, always: true),
          )
        else
          IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: () => showQuickSearch(context)),
        const SizedBox(width: AppSpace.sm),
        if (!posOnly && !master && MediaQuery.sizeOf(context).width >= AppSize.phone) ...[
          FilledButton.icon(onPressed: () => context.push('/sale-invoices/new'), icon: const Icon(Icons.add), label: const Text('Add Sale')),
          const SizedBox(width: AppSpace.sm),
          if (!isSalesman)
            FilledButton.icon(style: AppButtons.tonal, onPressed: () => context.push('/purchase-bills/new'), icon: const Icon(Icons.add), label: const Text('Add Purchase')),
          const SizedBox(width: AppSpace.md),
        ],
      ],
    );

    Widget wrap(Widget w) => posOnly ? SyncPrompt(child: w) : w;
    // Tab goes through the page first, then the top bar, then the menu.
    final page = FocusSection(order: 1, child: body);
    final bar = PreferredSize(preferredSize: topBar.preferredSize, child: FocusSection(order: 2, child: topBar));
    if (!wide) {
      return wrap(_ShellKeys(
        child: OrderedFocus(
          child: Scaffold(
            appBar: bar,
            drawer: Drawer(child: sidebar),
            body: page,
          ),
        ),
      ));
    }
    return wrap(_ShellKeys(
      child: OrderedFocus(
        child: Scaffold(
          body: Row(
            children: [
              FocusSection(
                order: 3,
                child: AnimatedContainer(duration: AppMotion.fast, curve: Curves.easeOutCubic, width: collapsed ? AppSize.sidebarRail : AppSize.sidebar, child: sidebar),
              ),
              Expanded(
                child: Scaffold(appBar: bar, body: page),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

/// The app-wide shortcuts that need the shell, such as quick search. It also holds focus when nothing on the page has it
/// yet, so shortcuts work before anything is clicked.
class _ShellKeys extends StatelessWidget {
  const _ShellKeys({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => KeyboardScope(
        name: 'App',
        autofocus: true,
        commands: {AppCommand.quickSearch: () => showQuickSearch(context)},
        child: child,
      );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.location, required this.closeOnNavigate, required this.collapsed});
  final String location;
  final bool closeOnNavigate;
  final bool collapsed;

  void _go(BuildContext context, String path) {
    if (closeOnNavigate) Navigator.of(context).pop();
    context.go(path);
  }

  bool _active(String path) => navActive(location, path);

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    final expanded = context.watch<NavCubit>().state;
    final sections = navFor(user, settingsOf(context, listen: true));
    if (collapsed) return _rail(context, user, sections);
    return Material(
      color: AppColors.sidebar,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.md),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded, color: AppColors.onSidebar, size: AppIconSize.lg),
                  const SizedBox(width: AppSpace.sm),
                  Text('Billing', style: AppText.title.copyWith(color: AppColors.onSidebar, letterSpacing: -0.3)),
                ],
              ),
            ),
            const Divider(color: AppColors.sidebarDivider),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                children: [for (final s in sections) ..._section(context, s, expanded)],
              ),
            ),
            const Divider(color: AppColors.sidebarDivider),
            ListTile(
              contentPadding: const EdgeInsets.only(left: AppSpace.md, right: AppSpace.xs),
              horizontalTitleGap: AppSpace.sm,
              // Salesmen cannot change the company profile; for them this opens the list of companies.
              onTap: () => _go(context, (user?.isSalesman ?? false) ? '/companies' : '/company'),
              selected: _active('/company'),
              selectedTileColor: AppColors.sidebarHover,
              leading: CircleAvatar(
                radius: AppSpace.lg,
                backgroundColor: AppColors.primary,
                child: Text((user?.firmName ?? '?').characters.first.toUpperCase(), style: const TextStyle(color: AppColors.onPrimary, fontSize: AppFont.body, fontWeight: FontWeight.w600)),
              ),
              title: Text(user?.firmName ?? '', style: const TextStyle(color: AppColors.onSidebar, fontSize: AppFont.body, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${user?.fullName ?? ''} · ${roleLabels[user?.role] ?? ''}',
                style: const TextStyle(color: AppColors.sidebarText, fontSize: AppFont.caption),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BlocBuilder<LockCubit, AppLockState>(
                    builder: (context, lock) => lock.hasPin
                        ? IconButton(
                            tooltip: 'Lock now',
                            style: AppButtons.compactIcon,
                            icon: const Icon(Icons.lock_outline, color: AppColors.sidebarText),
                            onPressed: () => context.read<LockCubit>().lockNow(),
                          )
                        : const SizedBox.shrink(),
                  ),
                  _CompanyMenu(closeDrawer: closeOnNavigate),
                  IconButton(
                    tooltip: 'Log out',
                    style: AppButtons.compactIcon,
                    icon: const Icon(Icons.logout, color: AppColors.sidebarText),
                    onPressed: () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The collapsed sidebar: one icon per section (sections with pages open a menu), the company initial at the bottom.
  Widget _rail(BuildContext context, AppUser? user, List<NavSection> sections) {
    final reportGroups = _reportGroups(context);
    Widget item(NavSection s) {
      if (s.label == 'Reports' && reportGroups.isNotEmpty) {
        final onReport = RegExp(r'^/reports/([^/?]+)').firstMatch(location)?.group(1);
        final active = reportGroups.values.any((rs) => rs.any((r) => r.id == onReport));
        return PopupMenuButton<String>(
          tooltip: s.label,
          offset: const Offset(AppSize.sidebarRail, 0),
          constraints: const BoxConstraints(maxHeight: 520, minWidth: 240),
          onSelected: (path) => _go(context, path),
          itemBuilder: (_) => [
            for (final g in reportGroups.entries) ...[
              PopupMenuItem<String>(enabled: false, height: AppSize.control, child: Text(g.key.toUpperCase(), style: AppText.label)),
              for (final r in g.value) PopupMenuItem<String>(value: '/reports/${r.id}', height: AppSize.control, child: Text(r.title, style: TextStyle(fontWeight: r.id == onReport ? FontWeight.w700 : FontWeight.w400))),
            ],
          ],
          child: Container(
            height: AppSize.control + AppSpace.sm,
            margin: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 1),
            decoration: BoxDecoration(color: active ? AppColors.sidebarActive : Colors.transparent, borderRadius: AppRadius.mdAll),
            child: Icon(s.icon, color: active ? AppColors.onSidebar : AppColors.sidebarText, size: AppIconSize.lg),
          ),
        );
      }
      final active = s.children.isEmpty ? _active(s.path!) : s.children.any((c) => _active(c.path));
      final icon = Container(
        height: AppSize.control + AppSpace.sm,
        margin: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 1),
        decoration: BoxDecoration(color: active ? AppColors.sidebarActive : Colors.transparent, borderRadius: AppRadius.mdAll),
        child: Icon(s.icon, color: active ? AppColors.onSidebar : AppColors.sidebarText, size: AppIconSize.lg),
      );
      if (s.children.isEmpty) {
        return Tooltip(message: s.label, child: InkWell(borderRadius: AppRadius.mdAll, hoverColor: AppColors.sidebarHover, onTap: () => _go(context, s.path!), child: icon));
      }
      return PopupMenuButton<String>(
        tooltip: s.label,
        offset: const Offset(AppSize.sidebarRail, 0),
        onSelected: (path) => _go(context, path),
        itemBuilder: (_) => [
          PopupMenuItem<String>(enabled: false, height: AppSize.control, child: Text(s.label, style: AppText.label)),
          for (final c in s.children) PopupMenuItem<String>(value: c.path, child: Text(c.label, style: TextStyle(fontWeight: _active(c.path) ? FontWeight.w700 : FontWeight.w400))),
        ],
        child: icon,
      );
    }

    return Material(
      color: AppColors.sidebar,
      child: SafeArea(
        child: Column(children: [
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpace.lg), child: Icon(Icons.receipt_long_rounded, color: AppColors.onSidebar, size: AppIconSize.lg)),
          const Divider(color: AppColors.sidebarDivider),
          Expanded(child: ListView(padding: const EdgeInsets.symmetric(vertical: AppSpace.sm), children: [for (final s in sections) item(s)])),
          const Divider(color: AppColors.sidebarDivider),
          Tooltip(
            message: '${user?.firmName ?? ''} · ${user?.fullName ?? ''}',
            child: InkWell(
              onTap: () => _go(context, (user?.isSalesman ?? false) ? '/companies' : '/company'),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: CircleAvatar(
                  radius: AppSpace.lg,
                  backgroundColor: AppColors.primary,
                  child: Text((user?.firmName ?? '?').characters.first.toUpperCase(), style: const TextStyle(color: AppColors.onPrimary, fontSize: AppFont.body, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// The reports grouped as the server lists them: Reports › group › report.
  Map<String, List<ReportDef>> _reportGroups(BuildContext context) {
    final groups = <String, List<ReportDef>>{};
    for (final r in context.watch<ReportCatalogCubit>().state.$2) {
      groups.putIfAbsent(r.group, () => []).add(r);
    }
    return groups;
  }

  List<Widget> _reportsSection(BuildContext context, NavSection s, Set<String> expanded, Map<String, List<ReportDef>> groups) {
    const root = 'Reports';
    final onReport = RegExp(r'^/reports/([^/?]+)').firstMatch(location)?.group(1);
    final activeGroup = onReport == null ? null : groups.entries.where((g) => g.value.any((r) => r.id == onReport)).map((g) => g.key).firstOrNull;
    if (activeGroup != null && !expanded.contains('$root/$activeGroup')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.read<NavCubit>().reveal(location, [root, '$root/$activeGroup']);
      });
    }
    final open = expanded.contains(root);
    return [
      _tile(
        s.label,
        icon: s.icon,
        active: false,
        strong: open || onReport != null,
        trailing: Icon(open ? Icons.expand_less : Icons.expand_more, color: AppColors.sidebarLabel, size: AppIconSize.md),
        onTap: () => context.read<NavCubit>().toggle(root),
      ),
      if (open)
        for (final g in groups.entries) ...[
          _tile(
            g.key,
            icon: reportGroupIcons[g.key] ?? Icons.bar_chart,
            indent: true,
            active: false,
            strong: expanded.contains('$root/${g.key}') || g.value.any((r) => r.id == onReport),
            trailing: Icon(expanded.contains('$root/${g.key}') ? Icons.expand_less : Icons.expand_more, color: AppColors.sidebarLabel, size: AppIconSize.sm),
            onTap: () => context.read<NavCubit>().toggle('$root/${g.key}'),
          ),
          if (expanded.contains('$root/${g.key}'))
            for (final r in g.value) _tile(r.title, deep: true, active: onReport == r.id, onTap: () => _go(context, '/reports/${r.id}')),
        ],
    ];
  }

  List<Widget> _section(BuildContext context, NavSection s, Set<String> expanded) {
    if (s.label == 'Reports') {
      final groups = _reportGroups(context);
      // Until the list arrives (or if it cannot be had) Reports is a plain link to the reports page.
      if (groups.isNotEmpty) return _reportsSection(context, s, expanded, groups);
    }
    if (s.children.isEmpty) {
      return [_tile(s.label, icon: s.icon, active: _active(s.path!), onTap: () => _go(context, s.path!))];
    }
    final open = expanded.contains(s.label);
    return [
      _tile(
        s.label,
        icon: s.icon,
        active: false,
        strong: open,
        trailing: Icon(open ? Icons.expand_less : Icons.expand_more, color: AppColors.sidebarLabel, size: AppIconSize.md),
        onTap: () => context.read<NavCubit>().toggle(s.label),
      ),
      if (open) for (final c in s.children) _tile(c.label, indent: true, active: _active(c.path), onTap: () => _go(context, c.path)),
    ];
  }

  /// One sidebar row: a rounded pill that turns violet when it is the current page.
  Widget _tile(String label, {IconData? icon, required bool active, required VoidCallback onTap, Widget? trailing, bool indent = false, bool deep = false, bool strong = false}) {
    final color = active || strong ? AppColors.onSidebar : AppColors.sidebarText;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 1),
      child: Material(
        color: active ? AppColors.sidebarActive : Colors.transparent,
        borderRadius: AppRadius.mdAll,
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -1),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          hoverColor: AppColors.sidebarHover,
          contentPadding: EdgeInsets.only(left: deep ? AppSpace.huge + AppSpace.lg : (indent ? AppSpace.huge - AppSpace.xs : AppSpace.md), right: AppSpace.sm),
          leading: icon == null ? null : Icon(icon, color: color, size: indent ? AppIconSize.sm : AppIconSize.md),
          minLeadingWidth: AppIconSize.md,
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: AppFont.body, fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
          trailing: trailing,
          onTap: onTap,
        ),
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
    style: AppButtons.compactIcon,
    icon: const Icon(Icons.swap_horiz, color: AppColors.sidebarText),
    onPressed: () {
      if (closeDrawer) Navigator.of(context).pop();
      context.go('/companies');
    },
  );
}
