import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../company/firm_cubit.dart';
import '../../data/models/app_user.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/change_bus.dart';
import '../../core/list_cubit.dart';
import '../../core/status.dart';
import '../../data/models/extras.dart';
import '../../data/repositories/utilities_repository.dart';
import '../../shared/file_io.dart';
import '../../shared/format.dart';
import '../../shared/page.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/bloc/auth_bloc.dart';
import '../team/team_screens.dart';
import 'tools_cubits.dart';

// ---------------------------------------------------------------- set up my business

/// The first-run checklist: what is done and a shortcut to each remaining step.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => ListCubit<SetupStep>(
      ctx.read<UtilitiesRepository>().setup,
      bus: ctx.read<ChangeBus>(),
      topics: const {DataTopic.firm, DataTopic.parties, DataTopic.items, DataTopic.accounts, DataTopic.invoices},
    )..load(),
    child: ListCubitView<SetupStep>(
      builder: (context, state) {
        final done = state.items.where((s) => s.done).length;
        final total = state.items.length;
        return TitledPage(
          title: 'Set Up My Business',
          subtitle: done == total ? 'All done. Your business is set up.' : '$done of $total steps done.',
          children: [
            ClipRRect(
              borderRadius: AppRadius.smAll,
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: AppColors.successText,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            RowsCard(
              empty: const EmptyState(icon: Icons.checklist, title: 'Nothing to set up'),
              rows: [
                for (final s in state.items)
                  ListTile(
                    leading: Icon(s.done ? Icons.check_circle : Icons.radio_button_unchecked, color: s.done ? AppColors.success : AppColors.textSubtle),
                    title: Text(
                      s.title,
                      style: TextStyle(decoration: s.done ? TextDecoration.lineThrough : null, color: s.done ? AppColors.textMuted : null),
                    ),
                    subtitle: Text(s.hint),
                    trailing: s.done
                        ? null
                        : FilledButton.tonal(
                            onPressed: () => s.route.endsWith('/new') ? context.push(s.route) : context.go(s.route),
                            child: const Text('Do it'),
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

// ---------------------------------------------------------------- verify my data

class VerifyDataScreen extends StatelessWidget {
  const VerifyDataScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => VerifyCubit(ctx.read())..check(),
    child: BlocConsumer<VerifyCubit, VerifyState>(
      listenWhen: (a, b) => a.fixed != b.fixed,
      listener: (context, s) => showSuccess(context, s.allOk ? 'Fixed. Everything adds up now.' : 'Fixed what could be fixed automatically.'),
      builder: (context, s) {
        final cubit = context.read<VerifyCubit>();
        if (s.status == LoadStatus.loading) return const LoadingView();
        if (s.status == LoadStatus.failure) return ErrorRetry(error: s.error ?? 'Could not check', onRetry: cubit.check);
        return TitledPage(
          title: 'Verify My Data',
          subtitle: s.allOk
              ? 'Everything adds up: stock, invoice totals and payments are consistent.'
              : 'Some figures do not add up. "Fix" recalculates stock and received amounts from the entries behind them.',
          actions: [
            OutlinedButton.icon(
              onPressed: s.fixing ? null : cubit.check,
              icon: const Icon(Icons.refresh, size: AppIconSize.sm),
              label: const Text('Check Again'),
            ),
            if (s.canFix)
              FilledButton.icon(
                onPressed: s.fixing ? null : cubit.fix,
                icon: const Icon(Icons.build_outlined, size: AppIconSize.sm),
                label: Text(s.fixing ? 'Fixing…' : 'Fix'),
              ),
          ],
          children: [
            for (final c in s.checks) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(c.ok ? Icons.check_circle : Icons.error_outline, color: c.ok ? AppColors.success : AppColors.danger),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          if (!c.ok) Text(c.fixable ? 'Can be fixed' : 'Needs a look', style: AppText.helper),
                        ],
                      ),
                      for (final i in c.issues.take(20))
                        Padding(padding: const EdgeInsets.only(left: AppSpace.xxxl, top: AppSpace.sm), child: Text('${i.label} — ${i.detail}')),
                      if (c.issues.length > 20)
                        Padding(
                          padding: const EdgeInsets.only(left: AppSpace.xxxl, top: AppSpace.sm),
                          child: Text('…and ${c.issues.length - 20} more', style: const TextStyle(color: AppColors.textMuted)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
        );
      },
    ),
  );
}

// ---------------------------------------------------------------- close financial year

class CloseYearScreen extends StatelessWidget {
  const CloseYearScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(create: (ctx) => CloseYearCubit(ctx.read(), ctx.read())..load(), child: const _CloseYearView());
}

class _CloseYearView extends StatefulWidget {
  const _CloseYearView();

  @override
  State<_CloseYearView> createState() => _CloseYearViewState();
}

/// Stateful only to own the new company's name controller; everything else lives in [CloseYearCubit].
class _CloseYearViewState extends State<_CloseYearView> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CloseYearCubit, CloseYearState>(
      listenWhen: (a, b) => a.status != b.status || a.loadStatus != b.loadStatus,
      listener: (context, s) {
        if (s.loadStatus == LoadStatus.success && _name.text.isEmpty) {
          _name.text = '${s.firmName} ${financialYearLabel(DateTime.parse(s.newYearStart))}';
        }
        if (s.status == SubmitStatus.failure) showError(context, s.error!);
        if (s.status == SubmitStatus.success && s.message != null) showSuccess(context, s.message!);
      },
      builder: (context, s) {
        final cubit = context.read<CloseYearCubit>();
        if (s.loadStatus == LoadStatus.loading) return const LoadingView();
        if (s.loadStatus == LoadStatus.failure) return ErrorRetry(error: s.error ?? 'Could not load', onRetry: cubit.load);
        final busy = s.status == SubmitStatus.submitting;
        final isAdmin = context.select((AuthBloc b) => b.state.user?.isAdmin ?? false);
        return TitledPage(
          title: 'Close Financial Year',
          subtitle: isAdmin ? null : 'Only the owner or an admin can close the books.',
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('1. Close the books', style: AppText.subtitle),
                    const SizedBox(height: AppSpace.xs),
                    const Text(
                      'Nothing dated on or before the closing date can be added, changed or deleted afterwards — by anyone. '
                      'You can re-open the books whenever you need to correct something.',
                    ),
                    const SizedBox(height: AppSpace.md),
                    Row(
                      children: [
                        Icon(s.lockDate == null ? Icons.lock_open_outlined : Icons.lock_outline, color: s.lockDate == null ? AppColors.textMuted : AppColors.danger),
                        const SizedBox(width: AppSpace.sm),
                        Text(
                          s.lockDate == null ? 'The books are open.' : 'Books are closed up to ${displayDate(s.lockDate)}.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: AppSize.fieldMd,
                          child: DateField(label: 'Close up to', value: s.lockUpTo, onChanged: cubit.lockUpToChanged),
                        ),
                        FilledButton(
                          onPressed: busy || !isAdmin
                              ? null
                              : () async {
                                  final ok = await _confirm('Close the books?', 'Transactions up to ${displayDate(s.lockUpTo)} will be locked.', 'Close Books');
                                  if (ok) cubit.closeBooks();
                                },
                          child: Text(s.lockDate == null ? 'Close Books' : 'Change Closing Date'),
                        ),
                        if (s.lockDate != null)
                          OutlinedButton(onPressed: busy || !isAdmin ? null : cubit.reopenBooks, child: const Text('Re-open Books')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('2. Start the new year with fresh books (optional)', style: AppText.subtitle),
                    const SizedBox(height: AppSpace.xs),
                    const Text(
                      'Creates a new company that opens with this one\'s position at the end of the day before the start date you pick: what each party owes, stock in hand, '
                      'bank and cash balances, outstanding loans and your own accounts. Parties, items, units, settings and users are copied. '
                      'Entries dated on or after the start date are not carried, so you can start a year late and re-enter them in the new company. '
                      'This company and all its transactions stay exactly as they are, and you can switch back to it at any time.',
                    ),
                    const SizedBox(height: AppSpace.xs),
                    const Text('Not carried over: open estimates and orders, and undeposited cheques.', style: TextStyle(color: AppColors.textMuted)),
                    const SizedBox(height: AppSpace.md),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: AppSize.fieldLg,
                          child: TextField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Name of the new company'),
                          ),
                        ),
                        SizedBox(
                          width: AppSize.fieldMd,
                          child: DateField(label: 'New books start on', value: s.newYearStart, onChanged: cubit.newYearStartChanged),
                        ),
                        FilledButton(
                          onPressed: busy || !isAdmin
                              ? null
                              : () async {
                                  if (_name.text.trim().length < 2) return showError(context, 'Enter a name for the new company.');
                                  if (await _confirm(
                                    'Start a new year?',
                                    'A new company "${_name.text.trim()}" will be created with opening balances from this one.',
                                    'Create',
                                  )) {
                                    cubit.startNewYear(_name.text);
                                  }
                                },
                          child: Text(busy ? 'Working…' : 'Create New Company'),
                        ),
                      ],
                    ),
                    if (s.created != null) ...[
                      const SizedBox(height: AppSpace.md),
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppColors.success),
                          const SizedBox(width: AppSpace.sm),
                          Flexible(child: Text('"${s.created!.name}" has been created.')),
                          const SizedBox(width: AppSpace.md),
                          OutlinedButton(onPressed: () => switchToCompany(context, s.created!.id), child: const Text('Open It')),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- backup

String _size(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()} KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key, this.driveResult});

  /// 'connected' or 'failed', when Google has just sent the user back here.
  final String? driveResult;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (ctx) => BackupCubit(ctx.read())),
      BlocProvider(create: (ctx) => ListCubit<ServerBackup>(ctx.read<UtilitiesRepository>().serverBackups)..load()),
      BlocProvider(create: (ctx) => DriveCubit(ctx.read())..load()),
    ],
    child: _BackupView(driveResult: driveResult),
  );
}

class _BackupView extends StatelessWidget {
  const _BackupView({this.driveResult});
  final String? driveResult;

  Future<void> _connect(BuildContext context) async {
    try {
      final url = await context.read<DriveCubit>().authUrl();
      // Google asks for consent in this same tab and then sends the user back here.
      if (!await launchUrl(Uri.parse(url), webOnlyWindowName: '_self') && context.mounted) showError(context, 'Could not open Google.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _download(BuildContext context, ServerBackup b) async {
    try {
      final (name, backup) = await context.read<UtilitiesRepository>().readServerBackup(b.id);
      await saveBytesFile(name, Uint8List.fromList(utf8.encode(jsonEncode(backup))), mimeType: 'application/json');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _restore(BuildContext context, ServerBackup b) async {
    final cubit = context.read<ListCubit<ServerBackup>>();
    final repo = context.read<UtilitiesRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text('${b.fileName} will be restored as a new company next to your existing ones. Nothing you have now is changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    Company? restored;
    final done = await cubit.run(() async => restored = await repo.restore((await repo.readServerBackup(b.id)).$2));
    if (done && context.mounted) showSuccess(context, 'Restored as "${restored?.name}". Open it from Companies.');
  }

  @override
  Widget build(BuildContext context) {
    final firmName = context.select((AuthBloc b) => b.state.user?.firmName ?? '');
    final settings = settingsOf(context, listen: true);
    return MultiBlocListener(
      listeners: [
        BlocListener<DriveCubit, DriveStatus?>(
          listenWhen: (a, b) => a == null && b != null && driveResult != null,
          listener: (context, _) => driveResult == 'connected'
              ? showSuccess(context, 'Google Drive connected')
              : showError(context, 'Could not connect Google Drive. Please try again.'),
        ),
        BlocListener<BackupCubit, BackupState>(
          listenWhen: (a, b) => a.status != b.status,
          listener: (context, s) async {
            if (s.status == SubmitStatus.failure) showError(context, s.error!);
            if (s.status == SubmitStatus.success) {
              try {
                await saveBytesFile(s.fileName!, s.bytes!, mimeType: 'application/json');
                if (context.mounted) showSuccess(context, 'Backup saved as ${s.fileName}');
              } catch (_) {
                if (context.mounted) showError(context, 'Could not save the file.');
              }
            }
          },
        ),
      ],
      child: ListCubitView<ServerBackup>(
        builder: (context, backups) {
          final list = context.read<ListCubit<ServerBackup>>();
          final repo = context.read<UtilitiesRepository>();
          final busy = backups.busy;
          final download = context.watch<BackupCubit>().state;
          return TitledPage(
            title: 'Backup & Restore',
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Backups on the server', style: AppText.subtitle),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        settings.autoBackup == 'off'
                            ? 'Automatic backup is off. Turn it on under Settings → Backup, or back up now.'
                            : 'A backup is made ${settings.autoBackup == 'daily' ? 'every day' : 'every week'} and the latest ${settings.autoBackupKeep} are kept. '
                                  'Backups made by hand are kept until you delete them.',
                      ),
                      const SizedBox(height: AppSpace.md),
                      FilledButton.icon(
                        onPressed: busy ? null : () => list.run(repo.createServerBackup),
                        icon: busy
                            ? const InlineSpinner()
                            : const Icon(Icons.backup_outlined, size: AppIconSize.sm),
                        label: Text(busy ? 'Working…' : 'Back Up Now'),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      if (backups.items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpace.md),
                          child: Text('No backups yet.', style: TextStyle(color: AppColors.textMuted)),
                        )
                      else
                        for (final b in backups.items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(b.kind == 'auto' ? Icons.schedule : Icons.touch_app_outlined, color: AppColors.textMuted),
                            title: Text(
                              '${displayDate(isoDate(b.createdAt))} ${DateFormat('h:mm a').format(b.createdAt)} · ${b.kind == 'auto' ? 'Automatic' : 'Manual'}',
                            ),
                            subtitle: Text(
                              [
                                _size(b.size),
                                if (b.onDrive) 'Copied to Google Drive',
                                if (b.driveError != null) 'Drive copy failed: ${b.driveError}',
                              ].join(' · '),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Download',
                                  icon: const Icon(Icons.download_outlined, size: AppIconSize.md),
                                  onPressed: () => _download(context, b),
                                ),
                                IconButton(
                                  tooltip: 'Restore as a new company',
                                  icon: const Icon(Icons.restore, size: AppIconSize.md),
                                  onPressed: busy ? null : () => _restore(context, b),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline, size: AppIconSize.md),
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          if (await confirmDelete(
                                            context,
                                            title: 'Delete backup',
                                            message: 'Delete this backup from the server? A copy in Google Drive is not deleted.',
                                          )) {
                                            list.run(() => repo.deleteServerBackup(b.id));
                                          }
                                        },
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: BlocBuilder<DriveCubit, DriveStatus?>(
                    builder: (context, drive) {
                      final cubit = context.read<DriveCubit>();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Google Drive', style: AppText.subtitle),
                          const SizedBox(height: AppSpace.xs),
                          if (drive == null)
                            const GradientProgressBar()
                          else if (!drive.configured)
                            const Text(
                              'Not set up on this server. Whoever runs the server adds a Google client ID and secret (see the deployment notes), '
                              'and then you can connect your Google account here. Until then backups stay on the server.',
                            )
                          else if (drive.connected) ...[
                            Text(
                              'Every backup is copied to the "Billing Backups" folder in ${drive.email ?? 'your Google Drive'}. The app can only see the files it puts there.',
                            ),
                            const SizedBox(height: AppSpace.md),
                            OutlinedButton(onPressed: cubit.disconnect, child: const Text('Disconnect Google Drive')),
                          ] else ...[
                            const Text(
                              'Copy every backup to your Google Drive too. You allow access on a Google page; the app can only see the files it puts there.',
                            ),
                            const SizedBox(height: AppSpace.md),
                            FilledButton.icon(
                              onPressed: () => _connect(context),
                              icon: const Icon(Icons.cloud_upload_outlined, size: AppIconSize.sm),
                              label: const Text('Connect Google Drive'),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Download a backup', style: AppText.subtitle),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        'Saves everything in "$firmName" — parties, items, every transaction, settings, logo and attachments — as one file you keep yourself. '
                        'Logins are not part of the backup.',
                      ),
                      const SizedBox(height: AppSpace.md),
                      FilledButton.icon(
                        onPressed: download.status == SubmitStatus.submitting ? null : () => context.read<BackupCubit>().create(firmName),
                        icon: download.status == SubmitStatus.submitting
                            ? const InlineSpinner()
                            : const Icon(Icons.download_outlined, size: AppIconSize.sm),
                        label: Text(download.status == SubmitStatus.submitting ? 'Preparing…' : 'Download Backup'),
                      ),
                      if (download.summary != null) ...[
                        const SizedBox(height: AppSpace.md),
                        Text('Last download: ${download.fileName}\nContains ${download.summary}.', style: const TextStyle(color: AppColors.textMuted)),
                      ],
                      const SizedBox(height: AppSpace.lg),
                      const Text('Restore from a file', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpace.xs),
                      const Text('A backup is restored as a new company next to your existing ones, so nothing you have now is overwritten.'),
                      const SizedBox(height: AppSpace.sm),
                      OutlinedButton.icon(
                        onPressed: () => context.go('/companies'),
                        icon: const Icon(Icons.restore, size: AppIconSize.sm),
                        label: const Text('Go to Companies to Restore'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
