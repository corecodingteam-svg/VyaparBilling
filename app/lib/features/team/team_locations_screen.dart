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
import 'team_map.dart';

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
        BlocProvider(create: (c) => ListCubit<DaySummary>(() async => [await repo.daySummary(m.userId, c.read<ValueCubit<String>>().state)])..load()),
        BlocProvider(create: (_) => ListCubit<Geofence>(repo.geofences)..load()),
      ],
      child: BlocListener<ValueCubit<String>, String>(
        listener: (context, _) {
          context.read<ListCubit<TrailPoint>>().load();
          context.read<ListCubit<DaySummary>>().load();
        },
        child: AlertDialog(
          title: Text("${m.fullName}'s day"),
          content: SizedBox(
            width: AppSize.dialogLg,
            height: 560,
            child: Column(
              children: [
                BlocBuilder<ValueCubit<String>, String>(
                  builder: (context, date) => DateField(label: 'Date', value: date, onChanged: context.read<ValueCubit<String>>().set),
                ),
                const SizedBox(height: AppSpace.sm),
                Expanded(
                  child: BlocBuilder<ListCubit<TrailPoint>, ListState<TrailPoint>>(
                    builder: (context, s) {
                      if (s.status != LoadStatus.success) return const LoadingView();
                      if (s.items.isEmpty) return const Center(child: Text('No locations recorded on this day.'));
                      final summary = context.watch<ListCubit<DaySummary>>().state.items.firstOrNull;
                      final zones = context.watch<ListCubit<Geofence>>().state.items;
                      return ListView(
                        children: [
                          TeamMap(
                            height: AppSize.mapSm,
                            zones: zones,
                            route: [for (final p in s.items) (p.latitude, p.longitude)],
                            pins: [
                              (latitude: s.items.first.latitude, longitude: s.items.first.longitude, label: 'Start', strong: false),
                              (latitude: s.items.last.latitude, longitude: s.items.last.longitude, label: 'Last', strong: true),
                            ],
                          ),
                          if (summary != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                              child: Text(
                                [
                                  'Travelled about ${summary.distanceKm.toStringAsFixed(1)} km',
                                  for (final v in summary.visits) '${v.zone} ${_time.format(v.from)}–${_time.format(v.to)}',
                                ].join('  ·  '),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          for (final p in s.items)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                p.context == 'ping' ? Icons.circle : Icons.place,
                                size: p.context == 'ping' ? 10 : 20,
                                color: p.context == 'ping' ? AppColors.textSubtle : AppColors.primary,
                              ),
                              title: Text('${_time.format(p.recordedAt)} · ${_contextLabel(p.context)}'),
                              subtitle: Text([p.ref ?? '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}', if (p.zone != null) 'in ${p.zone}'].join(' · ')),
                              trailing: IconButton(
                                tooltip: 'Open in maps',
                                icon: const Icon(Icons.open_in_new, size: AppIconSize.sm),
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
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (ctx) => ListCubit<TeamMemberLocation>(ctx.read<LocationRepository>().latest)..load()),
      BlocProvider(create: (ctx) => ListCubit<Geofence>(ctx.read<LocationRepository>().geofences)..load()),
    ],
    child: ListCubitView<TeamMemberLocation>(
      builder: (context, state) {
        final cubit = context.read<ListCubit<TeamMemberLocation>>();
        final zones = context.watch<ListCubit<Geofence>>().state.items;
        return TitledPage(
          title: 'Where My Team Is',
          subtitle:
              'The latest position each user shared, how far they went and what they did today. A position is recorded every few minutes '
              '(in the phone app also while it is in the background) and where they save each sale or payment.',
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                await _showZones(context);
                cubit.load();
              },
              icon: const Icon(Icons.radio_button_checked, size: AppIconSize.sm),
              label: Text('Zones (${zones.length})'),
            ),
            OutlinedButton.icon(onPressed: cubit.load, icon: const Icon(Icons.refresh, size: AppIconSize.sm), label: const Text('Refresh')),
          ],
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: TeamMap(
                  zones: zones,
                  pins: [
                    for (final m in state.items)
                      if (m.hasPosition) (latitude: m.latitude!, longitude: m.longitude!, label: m.fullName, strong: false),
                  ],
                ),
              ),
            ),
            RowsCard(
              texts: [for (final m in state.items) '${m.fullName} ${m.role}'],
              sorts: {'Name': [for (final m in state.items) m.fullName], 'Last seen': [for (final m in state.items) m.recordedAt]},
              empty: const EmptyState(icon: Icons.place_outlined, title: 'No users'),
              rows: [
                for (final m in state.items)
                  ListTile(
                    leading: CircleAvatar(child: Text(m.fullName.characters.first.toUpperCase())),
                    title: Text('${m.fullName} · ${roleLabels[m.role] ?? m.role}'),
                    subtitle: Text(
                      m.hasPosition
                          ? 'Last seen ${agoText(m.recordedAt!)}${m.zone == null ? '' : ' in ${m.zone}'} · ${m.distanceKmToday.toStringAsFixed(1)} km today · '
                                '${m.salesToday} sales, ${m.paymentsToday} payments · ${m.pointsToday} check-ins'
                          : 'No location shared yet',
                    ),
                    trailing: m.hasPosition
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(onPressed: () => _showTrail(context, m), child: const Text('Trail')),
                              IconButton(
                                tooltip: 'Open in maps',
                                icon: Icon(Icons.place, color: AppColors.primary),
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

// ---------------------------------------------------------------- zones

/// The spot and size picked for a new zone.
typedef _ZoneDraft = ({double? latitude, double? longitude, int radiusM});

/// Add and remove zones: tap the map where the zone is, name it and set how wide it is.
Future<void> _showZones(BuildContext context) {
  final repo = context.read<LocationRepository>();
  final zones = context.read<ListCubit<Geofence>>();
  final name = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: zones),
        BlocProvider(create: (_) => ValueCubit<_ZoneDraft>((latitude: null, longitude: null, radiusM: 200))),
      ],
      child: BlocBuilder<ListCubit<Geofence>, ListState<Geofence>>(
        builder: (ctx, list) => BlocBuilder<ValueCubit<_ZoneDraft>, _ZoneDraft>(
          builder: (ctx, draft) {
            final cubit = ctx.read<ValueCubit<_ZoneDraft>>();
            final placed = draft.latitude != null;
            return AlertDialog(
              title: const Text('Zones'),
              content: SizedBox(
                width: AppSize.dialogLg,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'A zone is a place you care about — the shop, a warehouse, a market. The team list shows who is in which zone, and each trail shows when they were there. Tap the map to place a new one.',
                        style: AppText.helper,
                      ),
                      const SizedBox(height: AppSpace.sm),
                      TeamMap(
                        height: AppSize.mapSm,
                        zones: list.items,
                        draft: placed ? (draft.latitude!, draft.longitude!, draft.radiusM) : null,
                        onTap: (lat, lon) => cubit.set((latitude: lat, longitude: lon, radiusM: draft.radiusM)),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final fix = await repo.currentFix();
                          if (fix == null) {
                            if (ctx.mounted) showError(ctx, 'This device will not share its location.');
                            return;
                          }
                          cubit.set((latitude: fix.latitude, longitude: fix.longitude, radiusM: draft.radiusM));
                        },
                        icon: const Icon(Icons.my_location, size: AppIconSize.sm),
                        label: const Text('Use where I am now'),
                      ),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Zone name', isDense: true))),
                          const SizedBox(width: AppSpace.md),
                          DropdownButton<int>(
                            value: draft.radiusM,
                            items: const [
                              DropdownMenuItem(value: 100, child: Text('100 m')),
                              DropdownMenuItem(value: 200, child: Text('200 m')),
                              DropdownMenuItem(value: 500, child: Text('500 m')),
                              DropdownMenuItem(value: 1000, child: Text('1 km')),
                              DropdownMenuItem(value: 5000, child: Text('5 km')),
                            ],
                            onChanged: (v) => cubit.set((latitude: draft.latitude, longitude: draft.longitude, radiusM: v ?? 200)),
                          ),
                          const SizedBox(width: AppSpace.md),
                          FilledButton(
                            onPressed: list.busy
                                ? null
                                : () async {
                                    if (!placed) return showError(ctx, 'Tap the map where the zone is.');
                                    if (name.text.trim().isEmpty) return showError(ctx, 'Give the zone a name.');
                                    final ok = await zones.run(
                                      () => repo.addGeofence(name: name.text.trim(), latitude: draft.latitude!, longitude: draft.longitude!, radiusM: draft.radiusM),
                                    );
                                    if (!ok) return;
                                    name.clear();
                                    cubit.set((latitude: null, longitude: null, radiusM: draft.radiusM));
                                  },
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.sm),
                      for (final z in list.items)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.radio_button_checked, color: AppColors.success, size: AppIconSize.sm),
                          title: Text(z.name),
                          subtitle: Text('${z.radiusM >= 1000 ? '${z.radiusM / 1000} km' : '${z.radiusM} m'} around ${z.latitude.toStringAsFixed(4)}, ${z.longitude.toStringAsFixed(4)}'),
                          trailing: IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: AppIconSize.sm), onPressed: () => zones.run(() => repo.removeGeofence(z.id))),
                        ),
                      if (list.error != null) Text(list.error!, style: const TextStyle(color: AppColors.dangerText)),
                    ],
                  ),
                ),
              ),
              actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
            );
          },
        ),
      ),
    ),
  );
}
