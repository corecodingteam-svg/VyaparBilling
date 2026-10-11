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
        validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the business name' : null,
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String?>(
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'State *'),
        items: [for (final e in gstStates.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => stateCode = v,
        validator: (v) => v == null ? 'Select the state' : null,
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
        child: ListCubitView<Company>(builder: (context, state) {
          final cubit = context.read<ListCubit<Company>>();
          return TitledPage(
            title: 'Companies',
            subtitle: 'Each company has its own parties, items, transactions and settings.',
            actions: [
              OutlinedButton.icon(
                onPressed: state.busy ? null : () => _restore(context),
                icon: const Icon(Icons.restore, size: 18),
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
                empty: const EmptyState(icon: Icons.business_outlined, title: 'No companies'),
                rows: [
                  for (final c in state.items)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: c.current ? brandBlue : brandBlue.withValues(alpha: 0.1),
                        child: Text(c.name.characters.first.toUpperCase(), style: TextStyle(color: c.current ? Colors.white : brandBlue)),
                      ),
                      title: Text(c.name),
                      subtitle: Text('You are: ${roleLabels[c.role] ?? c.role}'),
                      trailing: c.current
                          ? const Chip(label: Text('Open now'), visualDensity: VisualDensity.compact)
                          : OutlinedButton(onPressed: () => switchToCompany(context, c.id), child: const Text('Open')),
                    ),
                ],
              ),
            ],
          );
        }),
      );
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
        validator: (v) => (v ?? '').trim().length < 2 ? 'Enter their name' : null,
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email *', helperText: 'They sign in with this email'),
        validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Password *', helperText: 'At least 8 characters. Not used if they already have a login.'),
        validator: (v) => (v ?? '').length < 8 ? 'Use at least 8 characters' : null,
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        initialValue: role,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Role'),
        items: [for (final r in roleHints.keys) DropdownMenuItem(value: r, child: Text(roleLabels[r]!))],
        onChanged: (v) => role = v!,
      ),
      const SizedBox(height: 10),
      for (final e in roleHints.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('${roleLabels[e.key]}: ${e.value}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
        child: ListCubitView<Member>(builder: (context, state) {
          final cubit = context.read<ListCubit<Member>>();
          final repo = context.read<AuthRepository>();
          final me = context.select((AuthBloc b) => b.state.user?.id);
          return TitledPage(
            title: 'Users',
            subtitle: 'Give your accountant or salesmen their own login. Sales and payments record who entered them (see the "Sale by User" report).',
            actions: [FilledButton.icon(onPressed: () => _showAddUserDialog(context), icon: const Icon(Icons.person_add_alt), label: const Text('Add User'))],
            children: [
              RowsCard(
                empty: const EmptyState(icon: Icons.group_outlined, title: 'No users'),
                rows: [
                  for (final m in state.items)
                    ListTile(
                      leading: CircleAvatar(child: Text(m.fullName.characters.first.toUpperCase())),
                      title: Text(m.id == me ? '${m.fullName} (you)' : m.fullName),
                      subtitle: Text(m.email),
                      trailing: m.role == 'owner' || m.id == me
                          ? Chip(label: Text(roleLabels[m.role] ?? m.role), visualDensity: VisualDensity.compact)
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: m.role,
                                  items: [for (final r in roleHints.keys) DropdownMenuItem(value: r, child: Text(roleLabels[r]!))],
                                  onChanged: state.busy ? null : (v) => cubit.run(() => repo.setMemberRole(m.id, v!)),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove access',
                                icon: const Icon(Icons.person_remove_outlined, size: 20),
                                onPressed: () async {
                                  if (await confirmDelete(context, title: 'Remove user', message: 'Remove ${m.fullName}\'s access to this company?')) {
                                    cubit.run(() => repo.removeMember(m.id));
                                  }
                                },
                              ),
                            ]),
                    ),
                ],
              ),
            ],
          );
        }),
      );
}
