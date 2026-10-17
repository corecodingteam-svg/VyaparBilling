import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/license/license_info.dart';
import '../../core/status.dart';
import '../../data/models/firm.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/bloc/auth_bloc.dart';
import '../lock/lock_cubit.dart';
import '../lock/lock_screen.dart';
import '../../shell/nav.dart' show settingsGroups;
import 'settings_cubit.dart';

class _SettingsGroup extends InheritedWidget {
  const _SettingsGroup(this.group, {required super.child});
  final String group;

  static String of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_SettingsGroup>()?.group ?? 'general';

  @override
  bool updateShouldNotify(_SettingsGroup old) => old.group != group;
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.group = 'general'});
  final String group;

  @override
  Widget build(BuildContext context) {
    final current = settingsGroups.any((g) => g.$1 == group) ? group : 'general';
    return BlocProvider(
      create: (ctx) => SettingsCubit(ctx.read())..load(),
      child: _SettingsGroup(current, child: _SettingsView(group: current)),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.group});
  final String group;

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
        if (state.loadStatus == LoadStatus.loading) return const LoadingView();
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
          padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.sm),
          child: SizedBox(
            width: AppSize.fieldLg,
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

        final title = settingsGroups.firstWhere((g) => g.$1 == group).$2;
        final content = Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.md),
                children: [
                  Text(title, style: AppText.title),
                  const SizedBox(height: AppSpace.md),
                  _Section('License', 'general', [const LicenseInfo()]),
                  // Salesmen cannot change business settings; they only get their own account below.
                  if (!(user?.isSalesman ?? false)) ...[
                    _Section('Taxes & GST', 'tax', [
                      toggle(
                        'Enable GST',
                        'Show tax rate and tax columns on invoices, estimates, bills and expenses.',
                        s.gstEnabled,
                        (v) => s.copyWith(gstEnabled: v),
                      ),
                    ]),
                    _Section('Transactions', 'transaction', [
                      const Text('Number prefixes', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpace.xs),
                      const Text(
                        'Put before the running number of new documents, e.g. INV-1. Letters, digits, - and / only.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: AppSpace.md),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final e in prefixTypes.entries)
                            SizedBox(
                              width: AppSize.fieldSm,
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
                      const SizedBox(height: AppSpace.md),
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
                    _Section('Print', 'print', [
                      const Text('Invoice theme', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpace.sm),
                      SegmentedButton<String>(
                        segments: [for (final e in invoiceThemes.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                        selected: {s.invoiceTheme},
                        onSelectionChanged: (v) => cubit.change((d) => d.copyWith(invoiceTheme: v.first)),
                      ),
                      const SizedBox(height: AppSpace.md),
                      const Text('Accent colour (Modern and Minimal themes)', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpace.sm),
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
                                child: s.themeColor.toUpperCase() == hex ? const Icon(Icons.check, size: AppIconSize.sm, color: AppColors.onPrimary) : null,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.lg),
                      const Text('Thermal receipt paper', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpace.sm),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 58, label: Text('58 mm (2 inch)')),
                          ButtonSegment(value: 80, label: Text('80 mm (3 inch)')),
                        ],
                        selected: {s.thermalWidth},
                        onSelectionChanged: (v) => cubit.change((d) => d.copyWith(thermalWidth: v.first)),
                      ),
                      const SizedBox(height: AppSpace.lg),
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
                      const SizedBox(height: AppSpace.md),
                      SizedBox(
                        width: AppSize.fieldLg,
                        child: TextFormField(
                          key: ValueKey('sign-${state.rev}'),
                          initialValue: s.signatureLabel,
                          onChanged: (v) => cubit.change((d) => d.copyWith(signatureLabel: v)),
                          maxLength: 60,
                          decoration: const InputDecoration(labelText: 'Signature caption', counterText: ''),
                        ),
                      ),
                    ]),
                    _Section('Party', 'party', [
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
                      const SizedBox(height: AppSpace.md),
                      const Text('Additional party fields', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpace.xs),
                      const Text('Your own fields on every party, e.g. "Drug licence no." Up to four.', style: TextStyle(color: AppColors.textMuted)),
                      const SizedBox(height: AppSpace.sm),
                      for (var i = 0; i < s.partyFields.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.sm),
                          child: Row(
                            children: [
                              SizedBox(
                                width: AppSize.fieldMd,
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
                              const SizedBox(width: AppSpace.sm),
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
                                icon: const Icon(Icons.close, size: AppIconSize.sm),
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
                    _Section('Item', 'item', [
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
                      const SizedBox(height: AppSpace.sm),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: AppSize.fieldMd,
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
                            width: AppSize.fieldMd,
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
                    _Section('Stock', 'item', [
                      toggle(
                        'Godowns (several stores)',
                        'Every stock movement belongs to a store; transfer stock between them. Stock without a store is in the main store.',
                        s.godownsEnabled,
                        (v) => s.copyWith(godownsEnabled: v),
                      ),
                      toggle(
                        'Batch number and expiry',
                        'Enter a batch and expiry on purchase and sale lines; stock is kept per batch.',
                        s.batchTrackingEnabled,
                        (v) => s.copyWith(batchTrackingEnabled: v),
                      ),
                      toggle(
                        'Serial numbers / IMEI',
                        'Enter one serial number per unit; a unit cannot be sold twice.',
                        s.serialTrackingEnabled,
                        (v) => s.copyWith(serialTrackingEnabled: v),
                      ),
                      toggle('MRP', 'Keep the maximum retail price on items and lines.', s.mrpEnabled, (v) => s.copyWith(mrpEnabled: v)),
                      link(Icons.warehouse_outlined, 'Godowns', 'Add stores and transfer stock between them.', '/godowns'),
                    ]),
                    _Section('Taxes and charges', 'tax', [
                      toggle(
                        'Compensation cess',
                        'A cess rate per item, charged on the taxable value next to GST.',
                        s.cessEnabled,
                        (v) => s.copyWith(cessEnabled: v),
                      ),
                      toggle(
                        'Discount on the whole bill',
                        'A percentage or amount off the bill, taken off before tax.',
                        s.billDiscountEnabled,
                        (v) => s.copyWith(billDiscountEnabled: v),
                      ),
                      toggle(
                        'Additional charges',
                        'Freight, packing and the like, added to the bill after tax.',
                        s.additionalChargesEnabled,
                        (v) => s.copyWith(additionalChargesEnabled: v),
                      ),
                      if (s.additionalChargesEnabled)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.sm),
                          child: SizedBox(
                            width: AppSize.dialogMd,
                            child: TextFormField(
                              key: ValueKey('charges-${state.rev}'),
                              initialValue: s.chargeNames.join(', '),
                              onChanged: (v) => cubit.change((d) => d.copyWith(chargeNames: [for (final n in v.split(',')) n.trim()])),
                              decoration: const InputDecoration(
                                labelText: 'Charge names',
                                helperText: 'Comma-separated, e.g. Shipping, Packaging, Installation',
                              ),
                            ),
                          ),
                        ),
                      toggle(
                        'TCS',
                        'Collect tax at source on top of sale bills (and record it on purchases).',
                        s.tcsEnabled,
                        (v) => s.copyWith(tcsEnabled: v),
                      ),
                      toggle(
                        'TDS',
                        'Record tax the payer holds back; it reduces what is still to be paid on the bill.',
                        s.tdsEnabled,
                        (v) => s.copyWith(tdsEnabled: v),
                      ),
                    ]),
                    _Section('Loyalty points', 'party', [
                      toggle(
                        'Loyalty points',
                        'Customers earn points on sales and redeem them against later bills.',
                        s.loyaltyEnabled,
                        (v) => s.copyWith(loyaltyEnabled: v),
                      ),
                      if (s.loyaltyEnabled) ...[
                        number(
                          'earn-per',
                          'One point for every',
                          s.loyaltyEarnPer.toInt(),
                          (v) => s.copyWith(loyaltyEarnPer: v),
                          suffix: '₹ of sale',
                          min: 1,
                          max: 1000000,
                        ),
                        number(
                          'point-value',
                          'One point is worth',
                          s.loyaltyPointValue.toInt(),
                          (v) => s.copyWith(loyaltyPointValue: v),
                          suffix: '₹',
                          min: 1,
                          max: 10000,
                        ),
                      ],
                    ]),
                    _Section('Salesmen', 'general', [
                      toggle(
                        'Salesmen see only their own',
                        'A salesman sees the parties assigned to them and the documents they entered. Off: they see everyone\'s.',
                        s.salesmanOwnDataOnly,
                        (v) => s.copyWith(salesmanOwnDataOnly: v),
                      ),
                      toggle(
                        'Location tracking',
                        'Record where users are while they use the app, and where each sale or payment is saved. Users are asked for permission by their browser or phone.',
                        s.locationTrackingEnabled,
                        (v) => s.copyWith(locationTrackingEnabled: v),
                      ),
                      if (s.locationTrackingEnabled)
                        link(Icons.place_outlined, 'Where my team is', 'Latest position and today\'s trail of each user.', '/team-locations'),
                      toggle(
                        'Party groups',
                        'Put parties in groups and filter by them.',
                        s.partyGroupsEnabled,
                        (v) => s.copyWith(partyGroupsEnabled: v),
                      ),
                      if (s.partyGroupsEnabled) link(Icons.folder_outlined, 'Party groups', 'Add and rename groups.', '/party-groups'),
                    ]),
                    _Section('Credit limit and item pictures', 'transaction', [
                      const Text('When a sale would take a customer past their credit limit', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpace.sm),
                      SegmentedButton<String>(
                        segments: const [ButtonSegment(value: 'warn', label: Text('Warn and ask')), ButtonSegment(value: 'block', label: Text('Refuse the sale'))],
                        selected: {s.creditLimitMode},
                        onSelectionChanged: (v) => cubit.change((d) => d.copyWith(creditLimitMode: v.first)),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.sm),
                        child: Text('Applies to credit sales, sale orders and delivery challans. A sale paid in full is always allowed.', style: AppText.helper),
                      ),
                      toggle('Item pictures on invoices', 'Print each item\'s picture next to its name.', s.itemImagesOnInvoice, (v) => s.copyWith(itemImagesOnInvoice: v)),
                    ]),
                    _Section('Messages, e-invoice and online payments', 'message', [
                      link(Icons.hub_outlined, 'Integrations', 'Connect WhatsApp, SMS, the e-invoice portal, Razorpay and Google.', '/integrations'),
                      const Text('Send new sale invoices to the customer automatically', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpace.sm),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'off', label: Text('Off')),
                          ButtonSegment(value: 'whatsapp', label: Text('WhatsApp')),
                          ButtonSegment(value: 'sms', label: Text('SMS')),
                        ],
                        selected: {s.autoSendInvoices},
                        onSelectionChanged: (v) => cubit.change((d) => d.copyWith(autoSendInvoices: v.first)),
                      ),
                      const SizedBox(height: AppSpace.md),
                      const Text('Send a receipt for each Payment-In', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpace.sm),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'off', label: Text('Off')),
                          ButtonSegment(value: 'whatsapp', label: Text('WhatsApp')),
                          ButtonSegment(value: 'sms', label: Text('SMS')),
                        ],
                        selected: {s.autoSendPayments},
                        onSelectionChanged: (v) => cubit.change((d) => d.copyWith(autoSendPayments: v.first)),
                      ),
                      const SizedBox(height: AppSpace.md),
                      for (final (key, label, value, set) in <(String, String, String, FirmSettings Function(String))>[
                        ('invoiceMsg', 'Invoice message', s.invoiceMessage, (v) => s.copyWith(invoiceMessage: v)),
                        ('paymentMsg', 'Receipt message', s.paymentMessage, (v) => s.copyWith(paymentMessage: v)),
                        ('reminderMsg', 'Reminder message', s.reminderMessage, (v) => s.copyWith(reminderMessage: v)),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.sm),
                          child: TextFormField(
                            key: ValueKey('$key-${state.rev}'),
                            initialValue: value,
                            minLines: 2,
                            maxLines: 4,
                            maxLength: 500,
                            onChanged: (v) => cubit.change((_) => set(v)),
                            decoration: InputDecoration(labelText: label, helperText: 'Fills in {customer} {number} {amount} {balance} {business} {link}', helperMaxLines: 2),
                          ),
                        ),
                      toggle(
                        'E-invoice',
                        'Offer "E-invoice / e-way bill" on sale invoices and credit notes, and lock an invoice once it has an IRN.',
                        s.einvoiceEnabled,
                        (v) => s.copyWith(einvoiceEnabled: v),
                      ),
                      toggle('E-way bill', 'Ask for transport details and make e-way bills.', s.ewayEnabled, (v) => s.copyWith(ewayEnabled: v)),
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.sm),
                        child: SizedBox(
                          width: AppSize.fieldLg,
                          child: TextFormField(
                            key: ValueKey('upi-${state.rev}'),
                            initialValue: s.upiId,
                            onChanged: (v) => cubit.change((_) => s.copyWith(upiId: v.trim())),
                            decoration: const InputDecoration(labelText: 'Your UPI ID', helperText: 'For example shop@okbank'),
                          ),
                        ),
                      ),
                      toggle(
                        'UPI QR on invoices',
                        'Print a QR code with the amount due that customers can scan with any UPI app.',
                        s.upiQrOnInvoice,
                        (v) => s.copyWith(upiQrOnInvoice: v),
                      ),
                    ]),
                    _Section('Backup', 'general', [
                      const Text('Automatic backup', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: AppSpace.sm),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'off', label: Text('Off')),
                          ButtonSegment(value: 'daily', label: Text('Daily')),
                          ButtonSegment(value: 'weekly', label: Text('Weekly')),
                        ],
                        selected: {s.autoBackup},
                        onSelectionChanged: (v) => cubit.change((d) => d.copyWith(autoBackup: v.first)),
                      ),
                      if (s.autoBackup != 'off')
                        number('keep', 'Keep the latest', s.autoBackupKeep, (v) => s.copyWith(autoBackupKeep: v), suffix: 'backups', min: 1, max: 60),
                    ]),
                    _Section('Accounting', 'accounting', [
                      toggle(
                        'Accounting (journal entries)',
                        'Your own ledger accounts and journal entries, included in the Profit & Loss, Balance Sheet and Trial Balance.',
                        s.accountingEnabled,
                        (v) => s.copyWith(accountingEnabled: v),
                      ),
                      if (s.accountingEnabled) ...[
                        link(Icons.account_tree_outlined, 'Accounts', 'Your own ledger accounts.', '/ledger-accounts'),
                        link(Icons.menu_book_outlined, 'Journal entries', 'Capital, assets, depreciation and corrections.', '/journals'),
                      ],
                    ]),
                    _Section('Service reminders', 'service', [
                      toggle(
                        'Service reminders',
                        'Set a follow-up period on a service and get reminded after each sale of it.',
                        s.serviceRemindersEnabled,
                        (v) => s.copyWith(serviceRemindersEnabled: v),
                      ),
                      if (s.serviceRemindersEnabled) link(Icons.build_circle_outlined, 'Service reminders', 'Follow-ups due or overdue.', '/service-reminders'),
                    ]),
                    _Section('Multi currency', 'currency', [
                      link(
                        Icons.currency_exchange,
                        'Currencies',
                        'Print sale documents in another currency at your own exchange rate.',
                        '/currencies',
                      ),
                    ]),
                  ],
                  if (user?.isAdmin ?? false)
                    _Section('Company', 'general', [
                      link(Icons.group_outlined, 'Users', 'Give your accountant or salesmen their own login.', '/users'),
                      link(Icons.business_outlined, 'Companies', 'Switch company, add another one or restore a backup.', '/companies'),
                      link(Icons.backup_outlined, 'Backup', 'Backups on the server, Google Drive, download and restore.', '/backup'),
                    ]),
                  _Section('Keyboard Navigation', 'keyboard', [
                    BlocBuilder<KeyboardNavCubit, bool>(
                      builder: (context, enabled) => SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.keyboard_return),
                        title: const Text('Enter Key Navigation'),
                        subtitle: const Text('Press Enter to move to the next input field, like Tab. Multiline boxes, search boxes and fields that submit a form keep their own Enter. Saved for your login on this device.'),
                        value: enabled,
                        onChanged: context.read<KeyboardNavCubit>().set,
                      ),
                    ),
                  ]),
                  const _Section('Theme', 'theme', [_ThemeManager()]),
                  _Section('Account', 'general', [
                    BlocBuilder<LockCubit, AppLockState>(
                      builder: (context, lock) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(lock.hasPin ? Icons.lock : Icons.lock_open_outlined),
                        title: const Text('App lock (PIN)'),
                        subtitle: Text(
                          lock.hasPin
                              ? 'This device asks for a PIN when you open the app and after it has been away for a minute.'
                              : 'Ask for a PIN on this device before showing the books. Only for this device; it is not sent anywhere.',
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () => showPinDialog(context, hasPin: lock.hasPin, remove: false),
                              child: Text(lock.hasPin ? 'Change' : 'Set PIN'),
                            ),
                            if (lock.hasPin)
                              OutlinedButton(onPressed: () => showPinDialog(context, hasPin: true, remove: true), child: const Text('Remove')),
                          ],
                        ),
                      ),
                    ),
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
                color: AppColors.onPrimary,
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Expanded(child: Text('You have unsaved changes.')),
                      TextButton(onPressed: busy ? null : cubit.discard, child: const Text('Discard')),
                      const SizedBox(width: AppSpace.sm),
                      FilledButton(onPressed: busy ? null : cubit.save, child: const Text('Save Settings')),
                    ],
                  ),
                ),
              ),
          ],
        );
        return content;
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.group, this.children);
  final String title;
  final String group;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => group != _SettingsGroup.of(context) ? const SizedBox.shrink() : Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.md),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.subtitle),
            const SizedBox(height: AppSpace.sm),
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
    if (validateForm(context, _formKey, report: showError)) context.read<ChangePasswordCubit>().submit(current: _current.text, next: _next.text);
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
        content: Form(autovalidateMode: AutovalidateMode.onUserInteraction, 
          key: _formKey,
          child: SizedBox(
            width: AppSize.dialogSm,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _current,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Current password'),
                  validator: Validators.required('Current password'),
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  controller: _next,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters'),
                  validator: Validators.minLength('Password', 8),
                ),
                const SizedBox(height: AppSpace.md),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm new password'),
                  validator: Validators.matches('Passwords', () => _next.text),
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


/// Settings › Theme: pick the accent colour. It applies at once and is remembered for this user on this device.
class _ThemeManager extends StatefulWidget {
  const _ThemeManager();

  @override
  State<_ThemeManager> createState() => _ThemeManagerState();
}

class _ThemeManagerState extends State<_ThemeManager> {
  final _hex = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _applyHex(ThemeCubit cubit) {
    final c = parseAccent(_hex.text);
    setState(() => _error = c == null ? 'Enter a colour like #7C3AED (6 hex digits)' : null);
    if (c != null) cubit.choose(c);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ThemeCubit, Color>(
        builder: (context, accent) {
          final cubit = context.read<ThemeCubit>();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Accent colour', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.xs),
            const Text('Buttons, links, the active menu item and highlights use this colour. It is saved for your login on this device.', style: AppText.helper),
            const SizedBox(height: AppSpace.md),
            Wrap(spacing: AppSpace.md, runSpacing: AppSpace.md, children: [
              for (final (name, color) in themeAccentChoices)
                Tooltip(
                  message: name,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => cubit.choose(color),
                    child: CircleAvatar(
                      radius: AppSpace.lg,
                      backgroundColor: color,
                      child: accent.toARGB32() == color.toARGB32() ? const Icon(Icons.check, color: AppColors.onPrimary, size: AppIconSize.md) : null,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: AppSpace.lg),
            Wrap(spacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.start, runSpacing: AppSpace.sm, children: [
              SizedBox(
                width: AppSize.fieldMd,
                child: TextField(
                  controller: _hex,
                  onSubmitted: (_) => _applyHex(cubit),
                  decoration: InputDecoration(
                    labelText: 'Custom colour',
                    hintText: accentHex(accent),
                    errorText: _error,
                    prefixIcon: Padding(padding: const EdgeInsets.all(AppSpace.md), child: DecoratedBox(decoration: BoxDecoration(color: accent, shape: BoxShape.circle))),
                  ),
                ),
              ),
              OutlinedButton(onPressed: () => _applyHex(cubit), child: const Text('Apply')),
              TextButton(
                onPressed: () {
                  _hex.clear();
                  setState(() => _error = null);
                  cubit.reset();
                },
                child: const Text('Reset to default'),
              ),
            ]),
            const SizedBox(height: AppSpace.lg),
            const Text('Preview', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton(onPressed: () {}, child: const Text('Primary')),
              FilledButton(style: AppButtons.tonal, onPressed: () {}, child: const Text('Tonal')),
              OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
              const StatusBadge('Badge', tone: BadgeTone.brand),
              SizedBox(width: AppSize.fieldXs, child: LinearProgressIndicator(value: 0.6, borderRadius: AppRadius.smAll)),
            ]),
          ]);
        },
      );
}
