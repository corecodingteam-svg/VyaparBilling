import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/status.dart';
import '../../data/models/platform.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'tenant_users_cubit.dart';

final _stamp = DateFormat('d MMM y, h:mm a');

/// Everything the master admin has done, newest first; [firmId] narrows it to one business.
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key, this.firmId});
  final String? firmId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => AuditCubit(ctx.read(), firmId: firmId)..load(),
    child: BlocBuilder<AuditCubit, AuditState>(
      builder: (context, s) {
        if (s.status == LoadStatus.loading) return const LoadingView();
        if (s.status == LoadStatus.failure) return ErrorRetry(error: s.error ?? 'Could not load', onRetry: context.read<AuditCubit>().load);
        final business = firmId == null ? null : s.entries.where((e) => e.firmName != null).firstOrNull?.firmName;
        return ListView(
          padding: const EdgeInsets.all(AppSpace.md),
          children: [
            Wrap(
              spacing: AppSpace.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(firmId == null ? 'Audit log' : 'Audit log · ${business ?? 'this business'}', style: AppText.title),
                if (firmId != null) TextButton(onPressed: () => context.go('/platform-audit'), child: const Text('Show all businesses')),
                IconButton(tooltip: 'Refresh', onPressed: context.read<AuditCubit>().load, icon: const Icon(Icons.refresh)),
              ],
            ),
            Text('What the master admin did, and when. Passwords are never recorded.', style: AppText.helper),
            const SizedBox(height: AppSpace.md),
            if (s.entries.isEmpty) const EmptyState(icon: Icons.history, title: 'Nothing recorded yet'),
            for (final e in s.entries) _EntryTile(entry: e),
          ],
        );
      },
    ),
  );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final details = e.details.isEmpty ? null : const JsonEncoder().convert(e.details);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text([auditActionLabels[e.action] ?? e.action, if (e.firmName != null) e.firmName!].join(' · ')),
        subtitle: Text([
          '${_stamp.format(e.at)} by ${e.actor}',
          if (e.target != null) 'About: ${e.target}',
          ?details,
        ].join('\n')),
        isThreeLine: e.target != null || details != null,
      ),
    );
  }
}
