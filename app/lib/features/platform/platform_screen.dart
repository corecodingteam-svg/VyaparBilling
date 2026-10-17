import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/gst_states.dart';
import '../../core/status.dart';
import '../../data/models/platform.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../settings/settings_screen.dart' show showChangePasswordDialog;
import 'platform_cubit.dart';
import 'tenant_users_cubit.dart';

/// Provider only: the businesses on this server, signing one up, and switching what each may use.
class PlatformScreen extends StatelessWidget {
  const PlatformScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocProvider(create: (ctx) => PlatformCubit(ctx.read())..load(), child: const _PlatformView());
}

class _PlatformView extends StatelessWidget {
  const _PlatformView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlatformCubit, PlatformState>(
      listenWhen: (a, b) => a.errorRev != b.errorRev,
      listener: (context, s) => showError(context, s.error ?? 'Something went wrong'),
      builder: (context, s) {
        final cubit = context.read<PlatformCubit>();
        if (s.status == LoadStatus.loading) return const LoadingView();
        if (s.status == LoadStatus.failure) return ErrorRetry(error: s.error ?? 'Could not load', onRetry: cubit.load);
        return ListView(
          padding: const EdgeInsets.all(AppSpace.md),
          children: [
            Wrap(
              spacing: AppSpace.md,
              runSpacing: AppSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Businesses', style: AppText.title),
                SizedBox(
                  width: AppSize.fieldLg,
                  child: TextField(
                    onChanged: cubit.searchChanged,
                    decoration: const InputDecoration(hintText: 'Search name or owner email', prefixIcon: Icon(Icons.search)),
                  ),
                ),
                FilledButton.icon(
                  onPressed: s.busy || s.catalog == null ? null : () => _openDialog(context, null),
                  icon: const Icon(Icons.add),
                  label: const Text('New business'),
                ),
                TextButton.icon(onPressed: () => showChangePasswordDialog(context), icon: const Icon(Icons.key_outlined), label: const Text('Change my password')),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'What a business may use is decided here, not in its own settings, and the server enforces it on every request. '
              'A change takes effect on the next request; the business\'s app picks it up when it is next opened.',
              style: AppText.helper,
            ),
            const SizedBox(height: AppSpace.md),
            if (s.tenants.isEmpty) const EmptyState(icon: Icons.apartment_outlined, title: 'No businesses found'),
            for (final t in s.tenants) _TenantCard(tenant: t, catalog: s.catalog!, busy: s.busy),
          ],
        );
      },
    );
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.tenant, required this.catalog, required this.busy});
  final Tenant tenant;
  final PlatformCatalog catalog;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = tenant;
    final planLabel = catalog.plans.where((p) => p.id == t.plan).firstOrNull?.label ?? t.plan;
    final off = [for (final f in catalog.features) if (f.id != 'posOnly' && !(t.features[f.id] ?? true)) f.label];
    Widget chip(String text, {Color? color}) => Chip(label: Text(text), backgroundColor: color, visualDensity: VisualDensity.compact);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(t.name, style: AppText.subtitle),
                chip(planLabel),
                if (t.features['posOnly'] ?? false) chip('POS only'),
                if (t.license.status == 'suspended') chip('Suspended', color: AppColors.dangerSoft),
                if (t.license.status == 'revoked') chip('Revoked', color: AppColors.dangerSoft),
                if (t.license.expired) chip('Licence ended', color: AppColors.dangerSoft),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text('${t.ownerEmail ?? '-'} · ${t.members} ${t.members == 1 ? 'user' : 'users'} · ${t.sales30d} sale bills in 30 days', style: AppText.helper),
            Text(
              '${t.license.expiresOn == null ? 'Licence: no end date' : 'Licence valid until ${displayDate(t.license.expiresOn)}'}'
              ' · ${t.license.devices.length} of ${t.license.maxDevices} devices · version ${t.license.version}',
              style: t.license.expired ? AppText.error : AppText.helper,
            ),
            if (t.license.status != 'active' && (t.license.statusReason ?? '').isNotEmpty) Text('${t.license.status == 'revoked' ? 'Revoked' : 'Suspended'}: ${t.license.statusReason}', style: AppText.error),
            if (off.isNotEmpty) Text('Off: ${off.join(', ')}', style: AppText.helper),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                OutlinedButton(onPressed: busy ? null : () => _openDialog(context, t), child: const Text('Edit')),
                OutlinedButton(onPressed: () => _openUsers(context, t), child: const Text('Users')),
                OutlinedButton(onPressed: () => context.go('/platform-audit?firm=${t.id}'), child: const Text('History')),
                if (t.license.status != 'active')
                  OutlinedButton(onPressed: busy ? null : () => _resume(context, t), child: const Text('Reinstate'))
                else ...[
                  OutlinedButton(onPressed: busy ? null : () => _changeStatus(context, t, 'suspended'), child: const Text('Suspend')),
                  OutlinedButton(onPressed: busy ? null : () => _changeStatus(context, t, 'revoked'), child: const Text('Revoke')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _resume(BuildContext context, Tenant t) async {
  final error = await context.read<PlatformCubit>().setStatus(t, 'active');
  if (context.mounted && error != null) showError(context, error);
}

Future<void> _changeStatus(BuildContext context, Tenant t, String status) async {
  final cubit = context.read<PlatformCubit>();
  final reason = await showDialog<String>(context: context, builder: (_) => _ReasonDialog(revoke: status == 'revoked'));
  if (reason == null) return;
  final error = await cubit.setStatus(t, status, reason: reason.trim().isEmpty ? null : reason.trim());
  if (context.mounted && error != null) showError(context, error);
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.revoke});
  final bool revoke;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

/// Stateful only to own the text controller.
class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.revoke ? 'Revoke this licence' : 'Suspend this licence'),
    content: SizedBox(
      width: AppSize.dialogSm,
      child: TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Reason (shown to them, optional)')),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _reason.text), child: Text(widget.revoke ? 'Revoke' : 'Suspend')),
    ],
  );
}

Future<void> _openDialog(BuildContext context, Tenant? tenant) {
  final cubit = context.read<PlatformCubit>();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(value: cubit, child: _TenantDialog(tenant: tenant, catalog: cubit.state.catalog!)),
  );
}

class _TenantDialog extends StatefulWidget {
  const _TenantDialog({required this.tenant, required this.catalog});
  final Tenant? tenant;
  final PlatformCatalog catalog;
  @override
  State<_TenantDialog> createState() => _TenantDialogState();
}

/// Stateful only to own text controllers; the draft lives in [TenantDraftCubit].
class _TenantDialogState extends State<_TenantDialog> {
  final _name = TextEditingController();
  final _ownerName = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _password = TextEditingController();
  String _state = '07';
  String? _error;
  late final TenantDraftCubit _draft;

  bool get _creating => widget.tenant == null;

  @override
  void initState() {
    super.initState();
    final t = widget.tenant;
    final full = widget.catalog.plans.first;
    _draft = TenantDraftCubit(
      t == null
          ? TenantDraft(plan: full.id, features: {...full.features})
          : TenantDraft(plan: t.plan, features: {...t.features}, licenceExpiresOn: t.license.expiresOn, maxDevices: t.license.maxDevices),
      widget.catalog,
    );
  }

  @override
  void dispose() {
    for (final c in [_name, _ownerName, _ownerEmail, _password]) {
      c.dispose();
    }
    _draft.close();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context, String? current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null ? now.add(const Duration(days: 365)) : DateTime.parse(current),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) _draft.licenceChanged(isoDate(picked));
  }

  Future<void> _removeDevice(BuildContext context, LicenseDevice dev) async {
    final error = await context.read<PlatformCubit>().removeDevice(widget.tenant!, dev);
    if (!mounted) return;
    if (error != null) return setState(() => _error = error);
    Navigator.pop(this.context);
    showSuccess(this.context, 'Device removed. Its slot is free; that device must activate again.');
  }

  Future<void> _save() async {
    final d = _draft.state;
    final cubit = context.read<PlatformCubit>();
    if (_creating) {
      if (_name.text.trim().length < 2 || _ownerName.text.trim().length < 2) return setState(() => _error = 'Enter the business name and the owner\'s name.');
      if (!_ownerEmail.text.contains('@')) return setState(() => _error = 'Enter the owner\'s email.');
      if (_password.text.length < 8) return setState(() => _error = 'The first password needs at least 8 characters.');
    }
    final error = _creating
        ? await cubit.create({
            'firmName': _name.text.trim(),
            'stateCode': _state,
            'ownerName': _ownerName.text.trim(),
            'ownerEmail': _ownerEmail.text.trim(),
            'ownerPassword': _password.text,
            'plan': d.plan,
            'features': d.features,
            'licenceExpiresOn': d.licenceExpiresOn,
            'maxDevices': d.maxDevices,
          })
        : await cubit.update(widget.tenant!.id, {'plan': d.plan, 'features': d.features, 'licenceExpiresOn': d.licenceExpiresOn, 'maxDevices': d.maxDevices});
    if (!mounted) return;
    if (error != null) return setState(() => _error = error);
    Navigator.pop(context);
    showSuccess(context, _creating ? 'Business signed up. Give the owner the email and first password.' : 'Saved');
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _draft,
      child: AlertDialog(
        title: Text(_creating ? 'New business' : 'Edit ${widget.tenant!.name}'),
        content: SizedBox(
          width: AppSize.dialogMd,
          child: SingleChildScrollView(
            child: BlocBuilder<TenantDraftCubit, TenantDraft>(
              builder: (context, d) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_creating) ...[
                    TextField(controller: _name, decoration: const InputDecoration(labelText: 'Business name *')),
                    const SizedBox(height: AppSpace.md),
                    DropdownButtonFormField<String>(
                      initialValue: _state,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'State *'),
                      items: [for (final e in gstStates.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}'))],
                      onChanged: (v) => _state = v ?? _state,
                    ),
                    const SizedBox(height: AppSpace.md),
                    TextField(controller: _ownerName, decoration: const InputDecoration(labelText: 'Owner\'s name *')),
                    const SizedBox(height: AppSpace.md),
                    TextField(controller: _ownerEmail, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Owner\'s email (sign-in) *')),
                    const SizedBox(height: AppSpace.md),
                    TextField(controller: _password, decoration: const InputDecoration(labelText: 'First password *', helperText: 'The owner can change it after signing in.')),
                    const SizedBox(height: AppSpace.lg),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: d.plan,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Plan', helperText: 'Choosing a plan sets the switches below to what it includes.'),
                    items: [for (final p in widget.catalog.plans) DropdownMenuItem(value: p.id, child: Text(p.label))],
                    onChanged: (v) => v == null ? null : _draft.planChanged(v),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  for (final f in widget.catalog.features)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(f.label),
                      value: d.features[f.id] ?? f.id != 'posOnly',
                      onChanged: (v) => _draft.featureChanged(f.id, v),
                    ),
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      Expanded(child: Text(d.licenceExpiresOn == null ? 'Licence: no end date' : 'Licence ends ${displayDate(d.licenceExpiresOn)}')),
                      TextButton(onPressed: () => _pickDate(context, d.licenceExpiresOn), child: Text(d.licenceExpiresOn == null ? 'Set end date' : 'Change')),
                      if (d.licenceExpiresOn != null) TextButton(onPressed: () => _draft.licenceChanged(null), child: const Text('No end')),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(child: Text('Devices allowed')),
                      IconButton(onPressed: d.maxDevices > 1 ? () => _draft.maxDevicesChanged(d.maxDevices - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
                      Text('${d.maxDevices}', style: AppText.bodyStrong),
                      IconButton(onPressed: () => _draft.maxDevicesChanged(d.maxDevices + 1), icon: const Icon(Icons.add_circle_outline)),
                    ],
                  ),
                  if (!_creating && widget.tenant!.license.devices.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.sm),
                    Text('Activated devices', style: AppText.bodyStrong),
                    for (final dev in widget.tenant!.license.devices)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${dev.name ?? dev.platform ?? 'Device'} · ${dev.installationId.substring(0, 8)}'),
                        subtitle: Text(dev.lastSeenAt == null ? '' : 'Last seen ${displayDate(isoDate(dev.lastSeenAt!.toLocal()))}'),
                        trailing: TextButton(onPressed: () => _removeDevice(context, dev), child: const Text('Remove')),
                      ),
                  ],
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(_error!, style: AppText.error)),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          BlocBuilder<PlatformCubit, PlatformState>(
            builder: (context, s) => FilledButton(onPressed: s.busy ? null : _save, child: Text(_creating ? 'Sign up' : 'Save')),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- a business's users

Future<void> _openUsers(BuildContext context, Tenant t) => showDialog<void>(
  context: context,
  builder: (_) => BlocProvider(create: (ctx) => TenantUsersCubit(context.read(), t.id)..load(), child: _UsersDialog(tenant: t)),
);

const _roleNames = {'owner': 'Owner', 'admin': 'Admin', 'accountant': 'Accountant', 'salesman': 'Salesman'};

class _UsersDialog extends StatelessWidget {
  const _UsersDialog({required this.tenant});
  final Tenant tenant;

  Future<bool> _confirm(BuildContext context, String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SizedBox(width: AppSize.dialogSm, child: Text(message)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TenantUsersCubit, TenantUsersState>(
      listenWhen: (a, b) => (b.error != null && a.error != b.error) || (b.newPassword != null && a.newPassword != b.newPassword),
      listener: (context, s) {
        if (s.error != null) showError(context, s.error!);
        final np = s.newPassword;
        if (np != null) {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('New password'),
              content: SizedBox(
                width: AppSize.dialogSm,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Give this to ${np.email}. It is shown only now; they can change it after signing in.'),
                    const SizedBox(height: AppSpace.md),
                    SelectableText(np.password, style: AppText.headline),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: np.password)), child: const Text('Copy')),
                FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
              ],
            ),
          );
        }
      },
      builder: (context, s) {
        final cubit = context.read<TenantUsersCubit>();
        return AlertDialog(
          title: Text('Users · ${tenant.name}'),
          content: SizedBox(
            width: AppSize.dialogLg,
            child: switch (s.status) {
              LoadStatus.success => ListView(
                shrinkWrap: true,
                children: [
                  Text('Disabling a login stops it in every business it belongs to.', style: AppText.helper),
                  const SizedBox(height: AppSpace.sm),
                  for (final u in s.users)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: AppSpace.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(u.fullName, style: AppText.bodyStrong),
                                Chip(label: Text(_roleNames[u.role] ?? u.role), visualDensity: VisualDensity.compact),
                                if (u.disabled) Chip(label: const Text('Disabled'), backgroundColor: AppColors.dangerSoft, visualDensity: VisualDensity.compact),
                              ],
                            ),
                            Text(u.email, style: AppText.helper),
                            Wrap(
                              spacing: AppSpace.xs,
                              children: [
                                TextButton(
                                  onPressed: s.busy
                                      ? null
                                      : () async {
                                          if (await _confirm(context, 'Reset password', 'Make a new password for ${u.email}? The old one stops working.', 'Reset')) {
                                            await cubit.resetPassword(u);
                                          }
                                        },
                                  child: const Text('Reset password'),
                                ),
                                TextButton(
                                  onPressed: s.busy
                                      ? null
                                      : () async {
                                          final off = !u.disabled;
                                          if (!off || await _confirm(context, 'Disable login', '${u.email} will be signed out and cannot sign in, in any business.', 'Disable')) {
                                            await cubit.setDisabled(u, off);
                                          }
                                        },
                                  child: Text(u.disabled ? 'Enable' : 'Disable'),
                                ),
                                if (u.role != 'owner')
                                  TextButton(
                                    onPressed: s.busy
                                        ? null
                                        : () async {
                                            if (await _confirm(context, 'Change owner', 'Make ${u.email} the owner of ${tenant.name}? The current owner becomes an admin.', 'Make owner')) {
                                              await cubit.makeOwner(u);
                                            }
                                          },
                                    child: const Text('Make owner'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              LoadStatus.failure => Text(s.error ?? 'Could not load', style: AppText.error),
              _ => const SizedBox(height: 120, child: LoadingView()),
            },
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        );
      },
    );
  }
}
