import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
        child: ListCubitView<SetupStep>(builder: (context, state) {
          final done = state.items.where((s) => s.done).length;
          final total = state.items.length;
          return TitledPage(
            title: 'Set Up My Business',
            subtitle: done == total ? 'All done. Your business is set up.' : '$done of $total steps done.',
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 8, backgroundColor: const Color(0xFFE3E8EF), color: receiveGreen),
              ),
              const SizedBox(height: 12),
              RowsCard(
                empty: const EmptyState(icon: Icons.checklist, title: 'Nothing to set up'),
                rows: [
                  for (final s in state.items)
                    ListTile(
                      leading: Icon(s.done ? Icons.check_circle : Icons.radio_button_unchecked, color: s.done ? receiveGreen : Colors.black38),
                      title: Text(s.title, style: TextStyle(decoration: s.done ? TextDecoration.lineThrough : null, color: s.done ? Colors.black54 : null)),
                      subtitle: Text(s.hint),
                      trailing: s.done ? null : FilledButton.tonal(onPressed: () => s.route.endsWith('/new') ? context.push(s.route) : context.go(s.route), child: const Text('Do it')),
                    ),
                ],
              ),
            ],
          );
        }),
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
            if (s.status == LoadStatus.loading) return const Center(child: CircularProgressIndicator());
            if (s.status == LoadStatus.failure) return ErrorRetry(error: s.error ?? 'Could not check', onRetry: cubit.check);
            return TitledPage(
              title: 'Verify My Data',
              subtitle: s.allOk
                  ? 'Everything adds up: stock, invoice totals and payments are consistent.'
                  : 'Some figures do not add up. "Fix" recalculates stock and received amounts from the entries behind them.',
              actions: [
                OutlinedButton.icon(onPressed: s.fixing ? null : cubit.check, icon: const Icon(Icons.refresh, size: 18), label: const Text('Check Again')),
                if (s.canFix)
                  FilledButton.icon(
                    onPressed: s.fixing ? null : cubit.fix,
                    icon: const Icon(Icons.build_outlined, size: 18),
                    label: Text(s.fixing ? 'Fixing…' : 'Fix'),
                  ),
              ],
              children: [
                for (final c in s.checks) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(c.ok ? Icons.check_circle : Icons.error_outline, color: c.ok ? receiveGreen : payRed),
                          const SizedBox(width: 10),
                          Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                          if (!c.ok) Text(c.fixable ? 'Can be fixed' : 'Needs a look', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ]),
                        for (final i in c.issues.take(20))
                          Padding(
                            padding: const EdgeInsets.only(left: 34, top: 6),
                            child: Text('${i.label} — ${i.detail}'),
                          ),
                        if (c.issues.length > 20)
                          Padding(padding: const EdgeInsets.only(left: 34, top: 6), child: Text('…and ${c.issues.length - 20} more', style: const TextStyle(color: Colors.black54))),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
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
        if (s.loadStatus == LoadStatus.loading) return const Center(child: CircularProgressIndicator());
        if (s.loadStatus == LoadStatus.failure) return ErrorRetry(error: s.error ?? 'Could not load', onRetry: cubit.load);
        final busy = s.status == SubmitStatus.submitting;
        final isAdmin = context.select((AuthBloc b) => b.state.user?.isAdmin ?? false);
        return TitledPage(
          title: 'Close Financial Year',
          subtitle: isAdmin ? null : 'Only the owner or an admin can close the books.',
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('1. Close the books', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Nothing dated on or before the closing date can be added, changed or deleted afterwards — by anyone. '
                      'You can re-open the books whenever you need to correct something.'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(s.lockDate == null ? Icons.lock_open_outlined : Icons.lock_outline, color: s.lockDate == null ? Colors.black54 : payRed),
                    const SizedBox(width: 8),
                    Text(
                      s.lockDate == null ? 'The books are open.' : 'Books are closed up to ${displayDate(s.lockDate)}.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(width: 220, child: DateField(label: 'Close up to', value: s.lockUpTo, onChanged: cubit.lockUpToChanged)),
                    FilledButton(
                      onPressed: busy || !isAdmin
                          ? null
                          : () async {
                              if (await _confirm('Close the books?', 'Transactions up to ${displayDate(s.lockUpTo)} will be locked.', 'Close Books')) cubit.closeBooks();
                            },
                      child: Text(s.lockDate == null ? 'Close Books' : 'Change Closing Date'),
                    ),
                    if (s.lockDate != null) OutlinedButton(onPressed: busy || !isAdmin ? null : cubit.reopenBooks, child: const Text('Re-open Books')),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('2. Start the new year with fresh books (optional)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Creates a new company that opens with today\'s position of this one: what each party owes, stock in hand, '
                      'bank and cash balances, outstanding loans and your own accounts. Parties, items, units, settings and users are copied. '
                      'This company and all its transactions stay exactly as they are, and you can switch back to it at any time.'),
                  const SizedBox(height: 4),
                  const Text('Not carried over: open estimates and orders, and undeposited cheques.', style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(width: 320, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name of the new company'))),
                    SizedBox(width: 220, child: DateField(label: 'New books start on', value: s.newYearStart, onChanged: cubit.newYearStartChanged)),
                    FilledButton(
                      onPressed: busy || !isAdmin
                          ? null
                          : () async {
                              if (_name.text.trim().length < 2) return showError(context, 'Enter a name for the new company.');
                              if (await _confirm('Start a new year?', 'A new company "${_name.text.trim()}" will be created with opening balances from this one.',
                                  'Create')) {
                                cubit.startNewYear(_name.text);
                              }
                            },
                      child: Text(busy ? 'Working…' : 'Create New Company'),
                    ),
                  ]),
                  if (s.created != null) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      const Icon(Icons.check_circle, color: receiveGreen),
                      const SizedBox(width: 8),
                      Flexible(child: Text('"${s.created!.name}" has been created.')),
                      const SizedBox(width: 12),
                      OutlinedButton(onPressed: () => switchToCompany(context, s.created!.id), child: const Text('Open It')),
                    ]),
                  ],
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- backup

class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => BackupCubit(ctx.read()),
        child: BlocConsumer<BackupCubit, BackupState>(
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
          builder: (context, s) {
            final firmName = context.select((AuthBloc b) => b.state.user?.firmName ?? '');
            final busy = s.status == SubmitStatus.submitting;
            return TitledPage(title: 'Backup & Restore', children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Download a backup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Saves everything in "$firmName" — parties, items, every transaction, settings, logo and attachments — as one file. '
                        'Keep it somewhere safe. Logins are not part of the backup.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: busy ? null : () => context.read<BackupCubit>().create(firmName),
                      icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_outlined, size: 18),
                      label: Text(busy ? 'Preparing…' : 'Download Backup'),
                    ),
                    if (s.summary != null) ...[
                      const SizedBox(height: 10),
                      Text('Last backup: ${s.fileName}\nContains ${s.summary}.', style: const TextStyle(color: Colors.black54)),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Restore a backup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text('A backup is restored as a new company next to your existing ones, so nothing you have now is overwritten. '
                        'After checking it you can keep working in whichever company you want.'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(onPressed: () => context.go('/companies'), icon: const Icon(Icons.restore, size: 18), label: const Text('Go to Companies to Restore')),
                  ]),
                ),
              ),
            ]);
          },
        ),
      );
}
