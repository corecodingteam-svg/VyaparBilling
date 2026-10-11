import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/status.dart';
import '../../data/models/firm.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/bloc/auth_bloc.dart';
import 'settings_cubit.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(create: (ctx) => SettingsCubit(ctx.read())..load(), child: const _SettingsView());
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsCubit, SettingsState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, s) {
        if (s.status == SubmitStatus.failure) showError(context, s.error!);
        if (s.status == SubmitStatus.success) showSuccess(context, 'Settings saved');
      },
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();
        if (state.loadStatus == LoadStatus.loading) return const Center(child: CircularProgressIndicator());
        if (state.loadStatus == LoadStatus.failure) return ErrorRetry(error: state.error ?? 'Could not load', onRetry: cubit.load);
        final s = state.draft;
        final busy = state.status == SubmitStatus.submitting;

        Widget toggle(String title, String subtitle, bool value, FirmSettings Function(bool) set) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: (v) => cubit.change((_) => set(v)),
        );

        // A whole-number setting; out-of-range or unfinished input leaves the stored value alone.
        Widget number(
          String key,
          String label,
          int value,
          FirmSettings Function(int) set, {
          String? suffix,
          String? helper,
          int min = 0,
          int max = 9999,
        }) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: SizedBox(
            width: 320,
            child: TextFormField(
              key: ValueKey('$key-${state.rev}'),
              initialValue: '$value',
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final n = int.tryParse(v.trim());
                if (n != null && n >= min && n <= max) cubit.change((_) => set(n));
              },
              decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: helper),
            ),
          ),
        );

        Widget link(IconData icon, String title, String subtitle, String path) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go(path),
        );
        final user = context.select((AuthBloc b) => b.state.user);

        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  // Salesmen cannot change business settings; they only get their own account below.
                  if (!(user?.isSalesman ?? false)) ...[
                    _Section('Taxes & GST', [
                      toggle(
                        'Enable GST',
                        'Show tax rate and tax columns on invoices, estimates, bills and expenses.',
                        s.gstEnabled,
                        (v) => s.copyWith(gstEnabled: v),
                      ),
                    ]),
                    _Section('Transactions', [
                      const Text('Number prefixes', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text(
                        'Put before the running number of new documents, e.g. INV-1. Letters, digits, - and / only.',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final e in prefixTypes.entries)
                            SizedBox(
                              width: 200,
                              child: TextFormField(
                                key: ValueKey('prefix-${e.key}-${state.rev}'),
                                initialValue: s.prefixFor(e.key),
                                onChanged: (v) => cubit.change(
                                  (d) => d.copyWith(
                                    prefixes: {...d.prefixes, e.key: v.trim()}..removeWhere((_, p) => p.isEmpty),
                                    invoicePrefix: e.key == 'sale' ? '' : null,
                                  ),
                                ),
                                maxLength: 10,
                                decoration: InputDecoration(labelText: e.value, hintText: 'none', counterText: ''),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      toggle(
                        'Round off totals by default',
                        'New invoices start with "Round Off" ticked.',
                        s.defaultRoundOff,
                        (v) => s.copyWith(defaultRoundOff: v),
                      ),
                      toggle(
                        'Cash sale by default',
                        'New sale invoices start as fully-paid cash sales.',
                        s.defaultCashSale,
                        (v) => s.copyWith(defaultCashSale: v),
                      ),
                      toggle(
                        'Stop sale on negative stock',
                        'Refuse a sale when there is not enough stock of an item.',
                        s.blockNegativeStock,
                        (v) => s.copyWith(blockNegativeStock: v),
                      ),
                      toggle(
                        'Show the printable preview after saving',
                        'Opens the invoice ready to print or share. Off: go back to the list.',
                        s.showInvoicePreview,
                        (v) => s.copyWith(showInvoicePreview: v),
                      ),
                      toggle(
                        'Due dates on credit invoices',
                        'Adds a due date to credit sales and purchases; overdue invoices appear in payment reminders.',
                        s.dueDatesEnabled,
                        (v) => s.copyWith(dueDatesEnabled: v),
                      ),
                      if (s.dueDatesEnabled)
                        number(
                          'credit-days',
                          'Default credit period',
                          s.defaultCreditDays,
                          (v) => s.copyWith(defaultCreditDays: v),
                          suffix: 'days',
                          min: 0,
                          max: 365,
                        ),
                    ]),
                    _Section('Print', [
                      const Text('Invoice theme', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: [for (final e in invoiceThemes.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                        selected: {s.invoiceTheme},
                        onSelectionChanged: (v) => cubit.change((d) => d.copyWith(invoiceTheme: v.first)),
                      ),
                      const SizedBox(height: 12),
                      const Text('Accent colour (Modern and Minimal themes)', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final hex in themeColorChoices)
                            InkWell(
                              onTap: () => cubit.change((d) => d.copyWith(themeColor: hex)),
                              customBorder: const CircleBorder(),
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: colorFromHex(hex),
                                child: s.themeColor.toUpperCase() == hex ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Thermal receipt paper', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 58, label: Text('58 mm (2 inch)')),
                          ButtonSegment(value: 80, label: Text('80 mm (3 inch)')),
                        ],
                        selected: {s.thermalWidth},
                        onSelectionChanged: (v) => cubit.change((d) => d.copyWith(thermalWidth: v.first)),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: ValueKey('terms-${state.rev}'),
                        initialValue: s.invoiceTerms,
                        onChanged: (v) => cubit.change((d) => d.copyWith(invoiceTerms: v)),
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                          labelText: 'Terms and conditions',
                          hintText: 'e.g. Goods once sold will not be taken back.',
                          helperText: 'Printed at the bottom of every invoice.',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 320,
                        child: TextFormField(
                          key: ValueKey('sign-${state.rev}'),
                          initialValue: s.signatureLabel,
                          onChanged: (v) => cubit.change((d) => d.copyWith(signatureLabel: v)),
                          maxLength: 60,
                          decoration: const InputDecoration(labelText: 'Signature caption', counterText: ''),
                        ),
                      ),
                    ]),
                    _Section('Party', [
                      toggle(
                        'Shipping address',
                        'Keep a shipping address for parties and print it on sale documents.',
                        s.shippingAddressEnabled,
                        (v) => s.copyWith(shippingAddressEnabled: v),
                      ),
                      toggle(
                        'Payment reminders',
                        'List customers with overdue invoices under Reminders.',
                        s.paymentReminderDays != null,
                        (v) => s.copyWith(paymentReminderDays: () => v ? 7 : null),
                      ),
                      if (s.paymentReminderDays != null)
                        number(
                          'reminder-days',
                          'Remind when an invoice is unpaid for',
                          s.paymentReminderDays!,
                          (v) => s.copyWith(paymentReminderDays: () => v),
                          suffix: 'days',
                          min: 0,
                          max: 365,
                          helper: 'With a due date, that date is used instead.',
                        ),
                      const SizedBox(height: 12),
                      const Text('Additional party fields', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('Your own fields on every party, e.g. "Drug licence no." Up to four.', style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 8),
                      for (var i = 0; i < s.partyFields.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 260,
                                child: TextFormField(
                                  key: ValueKey('pf-$i-${state.rev}-${s.partyFields.length}'),
                                  initialValue: s.partyFields[i].name,
                                  maxLength: 30,
                                  onChanged: (v) => cubit.change(
                                    (d) => d.copyWith(
                                      partyFields: [
                                        for (var j = 0; j < d.partyFields.length; j++)
                                          j == i ? PartyFieldDef(v, showInPrint: d.partyFields[j].showInPrint) : d.partyFields[j],
                                      ],
                                    ),
                                  ),
                                  decoration: InputDecoration(labelText: 'Field ${i + 1} name', counterText: ''),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Checkbox(
                                value: s.partyFields[i].showInPrint,
                                onChanged: (v) => cubit.change(
                                  (d) => d.copyWith(
                                    partyFields: [
                                      for (var j = 0; j < d.partyFields.length; j++)
                                        j == i ? PartyFieldDef(d.partyFields[j].name, showInPrint: v!) : d.partyFields[j],
                                    ],
                                  ),
                                ),
                              ),
                              const Flexible(child: Text('Print on invoices')),
                              IconButton(
                                tooltip: 'Remove field',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => cubit.change((d) => d.copyWith(partyFields: [...d.partyFields]..removeAt(i))),
                              ),
                            ],
                          ),
                        ),
                      if (s.partyFields.length < 4)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => cubit.change((d) => d.copyWith(partyFields: [...d.partyFields, const PartyFieldDef('')])),
                            icon: const Icon(Icons.add),
                            label: const Text('Add field'),
                          ),
                        ),
                    ]),
                    _Section('Item', [
                      toggle(
                        'Stock maintenance',
                        'Show stock quantities and low-stock alerts for products.',
                        s.stockMaintenance,
                        (v) => s.copyWith(stockMaintenance: v),
                      ),
                      toggle(
                        'Item-wise discount',
                        'Show the discount columns on each line of a document.',
                        s.itemWiseDiscount,
                        (v) => s.copyWith(itemWiseDiscount: v),
                      ),
                      toggle(
                        'Wholesale price',
                        'Items can carry a wholesale price that applies from a minimum quantity.',
                        s.wholesalePriceEnabled,
                        (v) => s.copyWith(wholesalePriceEnabled: v),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 260,
                            child: DropdownButtonFormField<int>(
                              key: ValueKey('qd-${s.quantityDecimals}'),
                              initialValue: s.quantityDecimals,
                              decoration: const InputDecoration(labelText: 'Quantity decimal places'),
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('0  (whole numbers only)')),
                                DropdownMenuItem(value: 1, child: Text('1  (e.g. 2.5)')),
                                DropdownMenuItem(value: 2, child: Text('2  (e.g. 2.25)')),
                                DropdownMenuItem(value: 3, child: Text('3  (e.g. 2.125)')),
                              ],
                              onChanged: (v) => cubit.change((d) => d.copyWith(quantityDecimals: v)),
                            ),
                          ),
                          SizedBox(
                            width: 260,
                            child: TextFormField(
                              key: ValueKey('unit-${state.rev}'),
                              initialValue: s.defaultUnit,
                              onChanged: (v) => cubit.change((d) => d.copyWith(defaultUnit: v.trim().toUpperCase())),
                              maxLength: 20,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(labelText: 'Default unit for new items', hintText: 'e.g. PCS', counterText: ''),
                            ),
                          ),
                        ],
                      ),
                    ]),
                    _Section('More features', [
                      toggle(
                        'Accounting (journal entries)',
                        'Your own ledger accounts and journal entries, included in the Profit & Loss, Balance Sheet and Trial Balance.',
                        s.accountingEnabled,
                        (v) => s.copyWith(accountingEnabled: v),
                      ),
                      toggle(
                        'Service reminders',
                        'Set a follow-up period on a service and get reminded after each sale of it.',
                        s.serviceRemindersEnabled,
                        (v) => s.copyWith(serviceRemindersEnabled: v),
                      ),
                      link(
                        Icons.currency_exchange,
                        'Currencies',
                        'Print sale documents in another currency at your own exchange rate.',
                        '/currencies',
                      ),
                    ]),
                  ],
                  if (user?.isAdmin ?? false)
                    _Section('Company', [
                      link(Icons.group_outlined, 'Users', 'Give your accountant or salesmen their own login.', '/users'),
                      link(Icons.business_outlined, 'Companies', 'Switch company, add another one or restore a backup.', '/companies'),
                      link(Icons.backup_outlined, 'Backup', 'Download everything in this company as one file.', '/backup'),
                    ]),
                  _Section('Account', [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Change password'),
                      subtitle: Text(context.select((AuthBloc b) => b.state.user?.email ?? '')),
                      trailing: OutlinedButton(onPressed: () => showChangePasswordDialog(context), child: const Text('Change')),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.logout),
                      title: const Text('Log out'),
                      trailing: OutlinedButton(
                        onPressed: () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
                        child: const Text('Log out'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            if (state.dirty)
              Material(
                color: Colors.white,
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Expanded(child: Text('You have unsaved changes.')),
                      TextButton(onPressed: busy ? null : cubit.discard, child: const Text('Discard')),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: busy ? null : cubit.save, child: const Text('Save Settings')),
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

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    ),
  );
}

Future<void> showChangePasswordDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => BlocProvider(create: (_) => ChangePasswordCubit(context.read()), child: const _ChangePasswordDialog()),
);

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

/// Stateful only to own the text controllers; submission state lives in [ChangePasswordCubit].
class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) context.read<ChangePasswordCubit>().submit(current: _current.text, next: _next.text);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChangePasswordCubit, (SubmitStatus, String?)>(
      listener: (context, s) {
        if (s.$1 == SubmitStatus.failure) showError(context, s.$2!);
        if (s.$1 == SubmitStatus.success) {
          showSuccess(context, 'Password changed');
          Navigator.of(context).pop();
        }
      },
      builder: (context, s) => AlertDialog(
        title: const Text('Change Password'),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _current,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Current password'),
                  validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _next,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters'),
                  validator: (v) => (v ?? '').length < 8 ? 'Use at least 8 characters' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm new password'),
                  validator: (v) => v != _next.text ? 'Passwords do not match' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: s.$1 == SubmitStatus.submitting ? null : _submit, child: const Text('Change Password')),
        ],
      ),
    );
  }
}
