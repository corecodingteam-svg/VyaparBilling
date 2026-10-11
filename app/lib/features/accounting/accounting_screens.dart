import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/change_bus.dart';
import '../../core/list_cubit.dart';
import '../../core/status.dart';
import '../../data/models/accounting.dart';
import '../../data/repositories/accounting_repository.dart';
import '../../shared/format.dart';
import '../../shared/page.dart';
import '../../shared/submit_dialog.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'journal_form_cubit.dart';

const _numeric = TextInputType.numberWithOptions(decimal: true);

// ---------------------------------------------------------------- ledger accounts

Future<void> showLedgerAccountDialog(BuildContext context, {LedgerAccount? account}) {
  final repo = context.read<AccountingRepository>();
  final name = TextEditingController(text: account?.name);
  var type = account?.type ?? 'expense';
  return showSubmitDialog<List<LedgerAccount>>(
    context,
    title: account == null ? 'Add Account' : 'Edit Account',
    action: () => repo.saveLedgerAccount(account?.id, name: name.text.trim(), type: type),
    fields: (submit) => [
      TextFormField(
        controller: name,
        autofocus: account == null,
        decoration: const InputDecoration(labelText: 'Account Name *', hintText: 'e.g. Furniture, Capital, Commission received'),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
        onFieldSubmitted: (_) => submit(),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        initialValue: type,
        decoration: const InputDecoration(labelText: 'Type', helperText: 'Decides where it appears: Balance Sheet (asset, liability, equity) or Profit & Loss (income, expense)'),
        items: [for (final e in ledgerTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => type = v!,
      ),
    ],
  );
}

/// The business's own accounts, used in journal entries, with their balances.
class LedgerAccountsScreen extends StatelessWidget {
  const LedgerAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => ListCubit<LedgerAccount>(ctx.read<AccountingRepository>().ledgerAccounts, bus: ctx.read<ChangeBus>(), topics: const {DataTopic.journals})..load(),
        child: ListCubitView<LedgerAccount>(builder: (context, state) {
          final cubit = context.read<ListCubit<LedgerAccount>>();
          final repo = context.read<AccountingRepository>();
          return TitledPage(
            title: 'Accounts',
            subtitle: 'Accounts of your own for journal entries. Cash, banks, parties, sales, purchases and expenses are kept for you already.',
            actions: [FilledButton.icon(onPressed: () => showLedgerAccountDialog(context), icon: const Icon(Icons.add), label: const Text('Add Account'))],
            children: [
              RowsCard(
                empty: const EmptyState(icon: Icons.account_tree_outlined, title: 'No accounts yet', message: 'Add an account, then post journal entries to it.'),
                rows: [
                  for (final a in state.items)
                    ListTile(
                      title: Text(a.name),
                      subtitle: Text(ledgerTypes[a.type] ?? a.type),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          a.balance == 0 ? money(0) : '${money(a.balance.abs())} ${a.balance > 0 ? 'Dr' : 'Cr'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => showLedgerAccountDialog(context, account: a)),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            if (await confirmDelete(context, title: 'Delete account', message: 'Delete the account "${a.name}"?')) {
                              cubit.run(() => repo.deleteLedgerAccount(a.id));
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

// ---------------------------------------------------------------- journal entries

Future<void> showJournalForm(BuildContext context, {String? entryId}) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider(
        create: (_) => JournalFormCubit(context.read(), context.read(), entryId: entryId)..load(),
        child: const _JournalDialog(),
      ),
    );

class _JournalDialog extends StatelessWidget {
  const _JournalDialog();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JournalFormCubit>();
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final content = BlocConsumer<JournalFormCubit, JournalFormState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == SubmitStatus.failure) showError(context, s.error!);
        if (s.status == SubmitStatus.success) {
          showSuccess(context, 'Journal entry saved');
          Navigator.of(context).pop();
        }
      },
      builder: (context, s) {
        final options = s.accountOptions;
        const cell = InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12));
        return Column(mainAxisSize: narrow ? MainAxisSize.max : MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
            child: Row(children: [
              Text(cubit.editing ? 'Edit Journal Entry' : 'Journal Entry', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
          const Divider(),
          Flexible(
            child: switch (s.loadStatus) {
              LoadStatus.failure => SizedBox(height: 240, child: ErrorRetry(error: s.error ?? 'Could not load', onRetry: cubit.load)),
              LoadStatus.success => SingleChildScrollView(
                  key: ValueKey('journal-${s.formRev}'),
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      SizedBox(
                        width: 160,
                        child: TextFormField(initialValue: s.number, onChanged: cubit.numberChanged, decoration: const InputDecoration(labelText: 'Journal No.')),
                      ),
                      SizedBox(width: 180, child: DateField(label: 'Date', value: s.date, onChanged: cubit.dateChanged)),
                      SizedBox(
                        width: 320,
                        child: TextFormField(
                          initialValue: s.description,
                          onChanged: cubit.descriptionChanged,
                          decoration: const InputDecoration(labelText: 'Narration', hintText: 'What this entry is for'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    for (final l in s.lines)
                      Padding(
                        key: ValueKey('jl-${l.uid}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            flex: 5,
                            child: DropdownButtonFormField<String?>(
                              key: ValueKey('jl-acc-${l.uid}-${l.account}-${options.length}'),
                              initialValue: options.any((o) => o.$1 == l.account) ? l.account : null,
                              isExpanded: true,
                              decoration: cell.copyWith(labelText: 'Account'),
                              items: [for (final (key, label) in options) DropdownMenuItem(value: key, child: Text(label, overflow: TextOverflow.ellipsis))],
                              onChanged: (v) => cubit.accountChanged(l.uid, v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              key: ValueKey('jl-dr-${l.uid}-${l.rev}'),
                              initialValue: l.debit,
                              onChanged: (v) => cubit.debitChanged(l.uid, v),
                              keyboardType: _numeric,
                              textAlign: TextAlign.right,
                              decoration: cell.copyWith(labelText: 'Debit'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              key: ValueKey('jl-cr-${l.uid}-${l.rev}'),
                              initialValue: l.credit,
                              onChanged: (v) => cubit.creditChanged(l.uid, v),
                              keyboardType: _numeric,
                              textAlign: TextAlign.right,
                              decoration: cell.copyWith(labelText: 'Credit'),
                            ),
                          ),
                          IconButton(tooltip: 'Remove line', icon: const Icon(Icons.close, size: 18), onPressed: () => cubit.removeLine(l.uid)),
                        ]),
                      ),
                    Row(children: [
                      TextButton.icon(onPressed: cubit.addLine, icon: const Icon(Icons.add), label: const Text('Add line')),
                      const Spacer(),
                      Text('Debit ${money(s.debitTotal)}   Credit ${money(s.creditTotal)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 48),
                    ]),
                    if (s.difference != 0)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 48, top: 4),
                          child: Text('Out by ${money(s.difference.abs())}', style: const TextStyle(color: payRed, fontSize: 12)),
                        ),
                      ),
                    if (s.ledgerAccounts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('Tip: add your own accounts (e.g. Furniture, Capital) under Accounting › Accounts to post to them here.',
                            style: TextStyle(color: Colors.black54, fontSize: 12)),
                      ),
                  ]),
                ),
              _ => const SizedBox(height: 240, child: Center(child: CircularProgressIndicator())),
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              FilledButton(
                onPressed: s.status == SubmitStatus.submitting || s.loadStatus != LoadStatus.success ? null : cubit.save,
                style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
                child: Text(cubit.editing ? 'Update' : 'Save'),
              ),
            ]),
          ),
        ]);
      },
    );
    if (narrow) return Dialog.fullscreen(child: content);
    return Dialog(clipBehavior: Clip.antiAlias, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: content));
  }
}

class JournalsScreen extends StatelessWidget {
  const JournalsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => ListCubit<JournalEntry>(ctx.read<AccountingRepository>().journals, bus: ctx.read<ChangeBus>(), topics: const {DataTopic.journals})..load(),
        child: ListCubitView<JournalEntry>(builder: (context, state) {
          final cubit = context.read<ListCubit<JournalEntry>>();
          final repo = context.read<AccountingRepository>();
          return TitledPage(
            title: 'Journal Entries',
            subtitle: 'For anything that is not a sale, purchase, payment or expense: capital brought in, assets bought, depreciation, corrections.',
            actions: [FilledButton.icon(onPressed: () => showJournalForm(context), icon: const Icon(Icons.add), label: const Text('Add Journal Entry'))],
            children: [
              RowsCard(
                empty: const EmptyState(icon: Icons.menu_book_outlined, title: 'No journal entries yet'),
                rows: [
                  for (final e in state.items)
                    ListTile(
                      onTap: () => showJournalForm(context, entryId: e.id),
                      title: Text('Journal ${e.number}${(e.description ?? '').isEmpty ? '' : '  ·  ${e.description}'}', overflow: TextOverflow.ellipsis),
                      subtitle: Text(displayDate(e.date)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(money(e.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => showJournalForm(context, entryId: e.id)),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            if (await confirmDelete(context, title: 'Delete journal entry', message: 'Delete journal ${e.number} of ${money(e.amount)}?')) {
                              cubit.run(() => repo.deleteJournal(e.id));
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

// ---------------------------------------------------------------- currencies

Future<void> _showCurrencyDialog(BuildContext context, {Currency? currency}) {
  final repo = context.read<AccountingRepository>();
  final cubit = context.read<ListCubit<Currency>>();
  final code = TextEditingController(text: currency?.code);
  final symbol = TextEditingController(text: currency?.symbol);
  final rate = TextEditingController(text: numText(currency?.rate));
  return showSubmitDialog<List<Currency>>(
    context,
    title: currency == null ? 'Add Currency' : 'Edit ${currency.code}',
    action: () async {
      final list = await repo.saveCurrency(code: code.text.trim().toUpperCase(), symbol: symbol.text.trim(), rate: parseNum(rate.text)!);
      cubit.load();
      return list;
    },
    fields: (submit) => [
      TextFormField(
        controller: code,
        autofocus: currency == null,
        readOnly: currency != null,
        textCapitalization: TextCapitalization.characters,
        maxLength: 3,
        decoration: const InputDecoration(labelText: 'Currency Code *', hintText: 'USD', counterText: ''),
        validator: (v) => RegExp(r'^[A-Za-z]{3}$').hasMatch((v ?? '').trim()) ? null : '3 letters, e.g. USD',
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: symbol,
        maxLength: 6,
        decoration: const InputDecoration(labelText: 'Symbol *', hintText: r'$', counterText: ''),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the symbol' : null,
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: rate,
        keyboardType: _numeric,
        decoration: const InputDecoration(labelText: 'Value of 1 unit in ₹ *', hintText: '83.50', prefixText: '₹ '),
        validator: (v) => (parseNum(v ?? '') ?? 0) <= 0 ? 'Enter the exchange rate' : null,
        onFieldSubmitted: (_) => submit(),
      ),
    ],
  );
}

/// Foreign currencies sale documents can be printed in.
class CurrenciesScreen extends StatelessWidget {
  const CurrenciesScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => ListCubit<Currency>(ctx.read<AccountingRepository>().currencies)..load(),
        child: ListCubitView<Currency>(builder: (context, state) {
          final cubit = context.read<ListCubit<Currency>>();
          final repo = context.read<AccountingRepository>();
          return TitledPage(
            title: 'Currencies',
            subtitle: 'Add a currency to print sale documents in it. You pick the currency and rate on the invoice; '
                'your books, party balances and reports stay in rupees.',
            actions: [FilledButton.icon(onPressed: () => _showCurrencyDialog(context), icon: const Icon(Icons.add), label: const Text('Add Currency'))],
            children: [
              RowsCard(
                empty: const EmptyState(icon: Icons.currency_exchange, title: 'No currencies added', message: 'Everything is in rupees.'),
                rows: [
                  for (final c in state.items)
                    ListTile(
                      leading: CircleAvatar(backgroundColor: brandBlue.withValues(alpha: 0.1), child: Text(c.symbol, style: const TextStyle(color: brandBlue))),
                      title: Text(c.code),
                      subtitle: Text('1 ${c.code} = ${money(c.rate)}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: 'Change rate', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _showCurrencyDialog(context, currency: c)),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            if (await confirmDelete(context, title: 'Delete currency', message: 'Delete ${c.code}? Documents already made in it keep their rate.')) {
                              cubit.run(() => repo.deleteCurrency(c.id));
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
