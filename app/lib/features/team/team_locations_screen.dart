import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/list_cubit.dart';
import '../../core/status.dart';
import '../../data/models/app_user.dart';
import '../../data/models/team_location.dart';
import '../../data/repositories/location_repository.dart';
import '../../shared/format.dart';
import '../../shared/page.dart';
import '../../shared/theme.dart';
import '../../shared/value_cubit.dart';
import '../../shared/widgets.dart';

final _time = DateFormat('h:mm a');

/// "5 min ago", "2 h ago", or the date for anything older than a day.
String agoText(DateTime at, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${displayDate(isoDate(at))} ${_time.format(at)}';
}

Uri mapUri(double lat, double lon) => Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');

Future<void> _openMap(BuildContext context, double lat, double lon) async {
  if (!await launchUrl(mapUri(lat, lon), mode: LaunchMode.externalApplication) && context.mounted) showError(context, 'Could not open the map.');
}

String _contextLabel(String c) => switch (c) {
  'sale' => 'Saved a sale',
  'payment' => 'Saved a payment',
  _ => 'Check-in',
};

/// One user's day: every recorded point, with the sale or payment saved there.
Future<void> _showTrail(BuildContext context, TeamMemberLocation m) {
  final repo = context.read<LocationRepository>();
  return showDialog<void>(
    context: context,
    builder: (ctx) => MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ValueCubit<String>(isoDate(DateTime.now()))),
        BlocProvider(create: (c) => ListCubit<TrailPoint>(() => repo.trail(m.userId, c.read<ValueCubit<String>>().state))..load()),
      ],
      child: BlocListener<ValueCubit<String>, String>(
        listener: (context, _) => context.read<ListCubit<TrailPoint>>().load(),
        child: AlertDialog(
          title: Text("${m.fullName}'s day"),
          content: SizedBox(
            width: 460,
            height: 420,
            child: Column(
              children: [
                BlocBuilder<ValueCubit<String>, String>(
                  builder: (context, date) => DateField(label: 'Date', value: date, onChanged: context.read<ValueCubit<String>>().set),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: BlocBuilder<ListCubit<TrailPoint>, ListState<TrailPoint>>(
                    builder: (context, s) {
                      if (s.status != LoadStatus.success) return const Center(child: CircularProgressIndicator());
                      if (s.items.isEmpty) return const Center(child: Text('No locations recorded on this day.'));
                      return ListView(
                        children: [
                          for (final p in s.items)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                p.context == 'ping' ? Icons.circle : Icons.place,
                                size: p.context == 'ping' ? 10 : 20,
                                color: p.context == 'ping' ? Colors.black38 : brandBlue,
                              ),
                              title: Text('${_time.format(p.recordedAt)} · ${_contextLabel(p.context)}'),
                              subtitle: Text(p.ref ?? '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'),
                              trailing: IconButton(
                                tooltip: 'Open in maps',
                                icon: const Icon(Icons.open_in_new, size: 18),
                                onPressed: () => _openMap(context, p.latitude, p.longitude),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      ),
    ),
  );
}

/// Where each user was last seen and how busy they were today. Positions are recorded only while
/// a user has the app open, so "last seen" can be hours old.
class TeamLocationsScreen extends StatelessWidget {
  const TeamLocationsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => ListCubit<TeamMemberLocation>(ctx.read<LocationRepository>().latest)..load(),
    child: ListCubitView<TeamMemberLocation>(
      builder: (context, state) {
        final cubit = context.read<ListCubit<TeamMemberLocation>>();
        return TitledPage(
          title: 'Where My Team Is',
          subtitle:
              'The latest position each user shared, and what they did today. A position is recorded while they have the app open — '
              'every few minutes, and where they save each sale or payment.',
          actions: [OutlinedButton.icon(onPressed: cubit.load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh'))],
          children: [
            RowsCard(
              empty: const EmptyState(icon: Icons.place_outlined, title: 'No users'),
              rows: [
                for (final m in state.items)
                  ListTile(
                    leading: CircleAvatar(child: Text(m.fullName.characters.first.toUpperCase())),
                    title: Text('${m.fullName} · ${roleLabels[m.role] ?? m.role}'),
                    subtitle: Text(
                      m.hasPosition
                          ? 'Last seen ${agoText(m.recordedAt!)} · ${m.salesToday} sales, ${m.paymentsToday} payments today · ${m.pointsToday} check-ins'
                          : 'No location shared yet',
                    ),
                    trailing: m.hasPosition
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(onPressed: () => _showTrail(context, m), child: const Text('Trail')),
                              IconButton(
                                tooltip: 'Open in maps',
                                icon: const Icon(Icons.place, color: brandBlue),
                                onPressed: () => _openMap(context, m.latitude!, m.longitude!),
                              ),
                            ],
                          )
                        : null,
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
