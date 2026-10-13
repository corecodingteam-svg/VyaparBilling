import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/gst_states.dart';
import '../../core/list_cubit.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/utilities_repository.dart';
import '../../shared/file_io.dart';
import '../../shared/export.dart';
import '../../shared/page.dart';
import '../../shared/submit_dialog.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/bloc/auth_bloc.dart';

/// Starts working in [company]: the session's token is replaced and every screen reloads for it.
Future<void> switchToCompany(BuildContext context, String companyId) async {
  final auth = context.read<AuthBloc>();
  final router = GoRouter.of(context);
  try {
    final user = await context.read<AuthRepository>().switchCompany(companyId);
    auth.add(AuthSignedIn(user));
    router.go('/');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

Future<Company?> _showAddCompanyDialog(BuildContext context) {
  final repo = context.read<AuthRepository>();
  final name = TextEditingController();
  String? stateCode;
  return showSubmitDialog<Company>(
    context,
    title: 'Add Company',
    action: () => repo.createCompany(name: name.text, stateCode: stateCode!),
    fields: (submit) => [
      TextFormField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Business Name *'),
        validator: Validators.minLength('Business name', 2),
      ),
      const SizedBox(height: AppSpace.md),
      DropdownButtonFormField<String?>(
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'State *'),
        items: [for (final e in gstStates.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => stateCode = v,
        validator: Validators.choose('state'),
      ),
    ],
  );
}

/// The companies under this login: switch, add another, or restore one from a backup file.
class CompaniesScreen extends StatelessWidget {
  const CompaniesScreen({super.key});

  Future<void> _restore(BuildContext context) async {
    final cubit = context.read<ListCubit<Company>>();
    final utilities = context.read<UtilitiesRepository>();
    Map<String, dynamic> backup;
    try {
      final text = await pickJsonFile();
      if (text == null) return;
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      backup = decoded;
    } catch (_) {
      if (context.mounted) showError(context, ApiException('That file is not a backup from this app.'));
      return;
    }
    Company? restored;
    final ok = await cubit.run(() async => restored = await utilities.restore(backup));
    if (ok && context.mounted) showSuccess(context, 'Restored as "${restored?.name}". Open it from the list.');
  }

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => ListCubit<Company>(ctx.read<AuthRepository>().companies)..load(),
    child: ListCubitView<Company>(
      builder: (context, state) {
        final cubit = context.read<ListCubit<Company>>();
        return TitledPage(
          title: 'Companies',
          subtitle: 'Each company has its own parties, items, transactions and settings.',
          actions: [
            OutlinedButton.icon(
              onPressed: state.busy ? null : () => _restore(context),
              icon: const Icon(Icons.restore, size: AppIconSize.sm),
              label: Text(state.busy ? 'Restoring…' : 'Restore Backup'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final created = await _showAddCompanyDialog(context);
                if (created != null) cubit.load();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Company'),
            ),
          ],
          children: [
            RowsCard(
              texts: [for (final c in state.items) c.name],
              sorts: {'Name': [for (final c in state.items) c.name]},
              empty: const EmptyState(icon: Icons.business_outlined, title: 'No companies'),
              rows: [
                for (final c in state.items)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: c.current ? AppColors.primary : AppColors.primary.withValues(alpha: 0.1),
                      child: Text(c.name.characters.first.toUpperCase(), style: TextStyle(color: c.current ? AppColors.onPrimary : AppColors.primary)),
                    ),
                    title: Text(c.name),
                    subtitle: Text('You are: ${roleLabels[c.role] ?? c.role}'),
                    trailing: c.current
                        ? const Chip(label: Text('Open now'), visualDensity: VisualDensity.compact)
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            OutlinedButton(onPressed: () => switchToCompany(context, c.id), child: const Text('Open')),
                            if (c.role == 'owner')
                              IconButton(tooltip: 'Delete company', icon: const Icon(Icons.delete_outline, size: AppIconSize.md), onPressed: () => _deleteCompany(context, c)),
                          ]),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

/// Asks for the company's name before deleting it; there is no undo.
Future<void> _deleteCompany(BuildContext context, Company c) async {
  final repo = context.read<AuthRepository>();
  final cubit = context.read<ListCubit<Company>>();
  final name = TextEditingController();
  final done = await showSubmitDialog<bool>(
    context,
    title: 'Delete "${c.name}"?',
    action: () async {
      await repo.deleteFirm(c.id, name.text.trim());
      return true;
    },
    fields: (submit) => [
      const Text(
        'Everything in this company is deleted for good: parties, items, invoices, payments, reports and its backups on the server. '
        'People whose only company this is can no longer sign in. Download a backup first if you may need it.',
      ),
      const SizedBox(height: AppSpace.md),
      TextFormField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Type the company name to confirm'),
        validator: (v) => (v ?? '').trim().toLowerCase() == c.name.trim().toLowerCase() ? null : 'Type the company name exactly as shown',
        onFieldSubmitted: (_) => submit(),
      ),
    ],
  );
  if (done == true) {
    await cubit.load();
    if (context.mounted) showSuccess(context, '"${c.name}" was deleted');
  }
}

Future<void> _showAddUserDialog(BuildContext context) {
  final repo = context.read<AuthRepository>();
  final cubit = context.read<ListCubit<Member>>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  var role = 'accountant';
  return showSubmitDialog<Member>(
    context,
    title: 'Add User',
    action: () async {
      final m = await repo.addMember(fullName: name.text, email: email.text, password: password.text, role: role);
      cubit.load();
      return m;
    },
    fields: (submit) => [
      TextFormField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Full Name *'),
        validator: Validators.minLength('Name', 2),
      ),
      const SizedBox(height: AppSpace.md),
      TextFormField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email *', helperText: 'They sign in with this email'),
        validator: Validators.email(required: true),
      ),
      const SizedBox(height: AppSpace.md),
      TextFormField(
        controller: password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Password *', helperText: 'At least 8 characters. Not used if they already have a login.'),
        validator: Validators.minLength('Password', 8),
      ),
      const SizedBox(height: AppSpace.md),
      DropdownButtonFormField<String>(
        initialValue: role,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Role'),
        items: [for (final r in roleHints.keys) DropdownMenuItem(value: r, child: Text(roleLabels[r]!))],
        onChanged: (v) => role = v!,
      ),
      const SizedBox(height: AppSpace.md),
      for (final e in roleHints.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Text('${roleLabels[e.key]}: ${e.value}', style: AppText.helper),
        ),
    ],
  );
}

/// People with access to the current company and what each may do.
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => ListCubit<Member>(ctx.read<AuthRepository>().members)..load(),
    child: ListCubitView<Member>(
      builder: (context, state) {
        final cubit = context.read<ListCubit<Member>>();
        final repo = context.read<AuthRepository>();
        final me = context.select((AuthBloc b) => b.state.user?.id);
        return TitledPage(
          title: 'Users',
          subtitle: 'Give your accountant or salesmen their own login. Sales and payments record who entered them (see the "Sale by User" report).',
          actions: [ExportMenu(table: () => TableExport(title: 'Users', headers: ['Name', 'Email', 'Role'], rows: [for (final m in state.items) [m.fullName, m.email, roleLabels[m.role] ?? m.role]])),
            
            FilledButton.icon(onPressed: () => _showAddUserDialog(context), icon: const Icon(Icons.person_add_alt), label: const Text('Add User')),
          ],
          children: [
            RowsCard(
              texts: [for (final m in state.items) '${m.fullName} ${m.email} ${roleLabels[m.role] ?? m.role}'],
              sorts: {'Name': [for (final m in state.items) m.fullName], 'Role': [for (final m in state.items) roleLabels[m.role] ?? m.role]},
              empty: const EmptyState(icon: Icons.group_outlined, title: 'No users'),
              rows: [
                for (final m in state.items)
                  ListTile(
                    leading: CircleAvatar(child: Text(m.fullName.characters.first.toUpperCase())),
                    title: Text(m.id == me ? '${m.fullName} (you)' : m.fullName),
                    subtitle: Text(m.email),
                    trailing: m.role == 'owner' || m.id == me
                        ? Chip(label: Text(roleLabels[m.role] ?? m.role), visualDensity: VisualDensity.compact)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: m.role,
                                  items: [for (final r in roleHints.keys) DropdownMenuItem(value: r, child: Text(roleLabels[r]!))],
                                  onChanged: state.busy ? null : (v) => cubit.run(() => repo.setMemberRole(m.id, v!)),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove access',
                                icon: const Icon(Icons.person_remove_outlined, size: AppIconSize.md),
                                onPressed: () async {
                                  if (await confirmDelete(
                                    context,
                                    title: 'Remove user',
                                    message: 'Remove ${m.fullName}\'s access to this company?',
                                  )) {
                                    cubit.run(() => repo.removeMember(m.id));
                                  }
                                },
                              ),
                            ],
                          ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
