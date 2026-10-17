import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../core/offline.dart';
import '../../core/sync_cubit.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';

final _stamp = DateFormat('d MMM y, h:mm a');

String _lastSynced(DateTime? at) => at == null ? 'Never synced on this device' : 'Last synced ${_stamp.format(at)}';

/// The sync page: what is waiting on this device, when it was last sent, and a button to send it now.
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncCubit, SyncState>(
      builder: (context, s) {
        final cubit = context.read<SyncCubit>();
        return ListView(
          padding: const EdgeInsets.all(AppSpace.md),
          children: [
            Text('Sync', style: AppText.title),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Bills made without a connection are kept on this device. Sync sends them to the server and refreshes the items and prices '
              'this counter works from. Do it at least once a day.',
              style: AppText.helper,
            ),
            const SizedBox(height: AppSpace.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(s.online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: s.online ? AppColors.success : AppColors.danger),
                        const SizedBox(width: AppSpace.sm),
                        Text(s.online ? 'Connected' : 'No connection', style: AppText.bodyStrong),
                      ],
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(_lastSynced(s.lastSyncAt)),
                    if (s.dailyDue) Text('Today\'s sync has not been done.', style: AppText.error),
                    Text('${s.waiting} ${s.waiting == 1 ? 'bill' : 'bills'} waiting to be sent'),
                    if (s.error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(s.error!, style: AppText.error)),
                    if (s.lastResult != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(s.lastResult!)),
                    const SizedBox(height: AppSpace.md),
                    FilledButton.icon(
                      onPressed: s.syncing ? null : cubit.sync,
                      icon: s.syncing
                          ? const SizedBox(width: AppIconSize.sm, height: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync),
                      label: Text(s.syncing ? 'Syncing…' : 'Sync now'),
                    ),
                  ],
                ),
              ),
            ),
            if (s.pending.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text('On this device', style: AppText.subtitle),
              const SizedBox(height: AppSpace.xs),
              for (final p in s.pending) _PendingTile(save: p, onDiscard: () => cubit.discard(p.id)),
            ],
          ],
        );
      },
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.save, required this.onDiscard});
  final PendingSave save;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(save.failed ? Icons.error_outline : Icons.schedule, color: save.failed ? AppColors.danger : AppColors.textMuted),
      title: Text(save.label),
      subtitle: Text(save.failed ? 'Refused by the server: ${save.error}' : 'Made ${_stamp.format(save.createdAt)}'),
      trailing: save.failed ? TextButton(onPressed: onDiscard, child: const Text('Discard')) : null,
    ),
  );
}

/// A strip above the page when something needs syncing: bills waiting, or today's sync not yet done.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncCubit, SyncState>(
      builder: (context, s) {
        if (s.waiting == 0 && s.failed.isEmpty && !s.dailyDue) return const SizedBox.shrink();
        final text = [
          if (s.waiting > 0) '${s.waiting} ${s.waiting == 1 ? 'bill' : 'bills'} waiting to be sent',
          if (s.failed.isNotEmpty) '${s.failed.length} refused by the server',
          if (s.dailyDue) 'today\'s sync not done',
        ].join(' · ');
        return Material(
          color: s.dailyDue || s.failed.isNotEmpty ? AppColors.dangerSoft : AppColors.warningSoft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
            child: Row(
              children: [
                const Icon(Icons.sync_problem_outlined, size: AppIconSize.sm),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(text, style: AppText.bodyStrong)),
                TextButton(onPressed: s.syncing ? null : context.read<SyncCubit>().sync, child: Text(s.syncing ? 'Syncing…' : 'Sync now')),
                TextButton(onPressed: onOpen, child: const Text('Details')),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Asks for the daily sync when it is due; "Later" asks again in an hour. Wraps the signed-in area of a POS-only business.
class SyncPrompt extends StatelessWidget {
  const SyncPrompt({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<SyncCubit, SyncState>(
      listenWhen: (a, b) => !a.promptDue && b.promptDue,
      listener: (context, _) async {
        final cubit = context.read<SyncCubit>();
        final now = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Sync today\'s bills'),
            content: Text(
              'This counter has not synced today. Sync now to send the bills kept on this device and refresh items and prices.\n\n'
              '${_lastSynced(cubit.state.lastSyncAt)}.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sync now')),
            ],
          ),
        );
        if (now ?? false) {
          await cubit.sync();
          if (context.mounted && cubit.state.error != null) showError(context, cubit.state.error!);
        } else {
          cubit.later();
        }
      },
      child: child,
    );
  }
}
