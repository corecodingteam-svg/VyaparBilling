import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/change_bus.dart';
import '../../core/list_cubit.dart';
import '../../data/models/party.dart';
import '../../data/repositories/parties_repository.dart';
import '../../shared/export.dart';
import '../../shared/page.dart';
import '../../shared/submit_dialog.dart';
import '../../shared/widgets.dart';
import '../../shared/theme.dart';

Future<void> _showGroupDialog(BuildContext context, {PartyGroup? group}) {
  final repo = context.read<PartiesRepository>();
  final cubit = context.read<ListCubit<PartyGroup>>();
  final name = TextEditingController(text: group?.name);
  return showSubmitDialog<List<PartyGroup>>(
    context,
    title: group == null ? 'Add Party Group' : 'Rename Party Group',
    action: () async {
      final groups = await repo.saveGroup(group?.id, name.text.trim());
      cubit.load();
      return groups;
    },
    fields: (submit) => [
      TextFormField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Group Name', hintText: 'e.g. Retailers, Wholesalers, Mumbai'),
        validator: Validators.required('Name'),
        onFieldSubmitted: (_) => submit(),
      ),
    ],
  );
}

/// Groups to put parties in. A party's group is chosen on the party form.
class PartyGroupsScreen extends StatelessWidget {
  const PartyGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) =>
        ListCubit<PartyGroup>(ctx.read<PartiesRepository>().groups, bus: ctx.read<ChangeBus>(), topics: const {DataTopic.parties})..load(),
    child: ListCubitView<PartyGroup>(
      builder: (context, state) {
        final cubit = context.read<ListCubit<PartyGroup>>();
        final repo = context.read<PartiesRepository>();
        return TitledPage(
          title: 'Party Groups',
          subtitle: 'Group parties (retailers, wholesalers, a city) and filter the party list by group.',
          actions: [ExportMenu(table: () => TableExport(title: 'Party Groups', headers: ['Group', 'Parties'], rows: [for (final g in state.items) [g.name, g.partyCount]])),
            FilledButton.icon(onPressed: () => _showGroupDialog(context), icon: const Icon(Icons.add), label: const Text('Add Group'))],
          children: [
            RowsCard(
              texts: [for (final g in state.items) g.name],
              sorts: {'Name': [for (final g in state.items) g.name], 'Parties': [for (final g in state.items) g.partyCount]},
              empty: const EmptyState(icon: Icons.folder_outlined, title: 'No groups yet', message: 'Add a group, then pick it on a party.'),
              rows: [
                for (final g in state.items)
                  ListTile(
                    title: Text(g.name),
                    subtitle: Text('${g.partyCount} ${g.partyCount == 1 ? 'party' : 'parties'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Rename',
                          icon: const Icon(Icons.edit_outlined, size: AppIconSize.sm),
                          onPressed: () => _showGroupDialog(context, group: g),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline, size: AppIconSize.md),
                          onPressed: () async {
                            if (await confirmDelete(
                              context,
                              title: 'Delete group',
                              message: 'Delete "${g.name}"? Its parties stay, without a group.',
                            )) {
                              cubit.run(() => repo.deleteGroup(g.id));
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
