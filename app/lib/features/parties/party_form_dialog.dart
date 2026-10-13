import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/gst_states.dart';
import '../../core/status.dart';
import '../../data/models/firm.dart';
import '../../data/models/party.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../company/firm_cubit.dart';
import 'bloc/party_form_cubit.dart';

final _gstinPattern = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

/// Opens the add/edit party dialog.
Future<void> showPartyForm(BuildContext context, {Party? party}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider(
      create: (_) => PartyFormCubit(context.read(), party, auth: context.read(), accounting: context.read())..load(),
      child: PartyFormDialog(settings: settingsOf(context)),
    ),
  );
}

class PartyFormDialog extends StatefulWidget {
  const PartyFormDialog({super.key, this.settings = const FirmSettings()});

  /// The business's party settings: its own additional fields and whether shipping addresses are used.
  final FirmSettings settings;

  @override
  State<PartyFormDialog> createState() => _PartyFormDialogState();
}

/// Stateful only to own text and tab controllers; all other state lives in [PartyFormCubit].
class _PartyFormDialogState extends State<PartyFormDialog> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final _tabs = TabController(length: 3, vsync: this);

  final _name = TextEditingController();
  final _gstin = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _billing = TextEditingController();
  final _city = TextEditingController();
  final _pincode = TextEditingController();
  final _pan = TextEditingController();
  final _tdsSection = TextEditingController();
  final _tcsCode = TextEditingController();
  final _shipping = TextEditingController();
  final _opening = TextEditingController();
  final _creditLimit = TextEditingController();
  final _loyalty = TextEditingController();
  final _fieldNames = List.generate(4, (_) => TextEditingController());
  final _fieldValues = List.generate(4, (_) => TextEditingController());

  PartyFormCubit get _cubit => context.read<PartyFormCubit>();

  @override
  void initState() {
    super.initState();
    _fill(context.read<PartyFormCubit>().party);
  }

  void _fill(Party? p) {
    _name.text = p?.name ?? '';
    _gstin.text = p?.gstin ?? '';
    _phone.text = p?.phone ?? '';
    _email.text = p?.email ?? '';
    _billing.text = p?.billingAddress ?? '';
    _city.text = p?.city ?? '';
    _pincode.text = p?.pincode ?? '';
    _pan.text = p?.pan ?? '';
    _tdsSection.text = p?.tdsSection ?? '';
    _tcsCode.text = p?.tcsCode ?? '';
    _shipping.text = p?.shippingAddress ?? '';
    final ob = p?.openingBalance ?? 0;
    _opening.text = ob == 0 ? '' : numText(ob.abs());
    _creditLimit.text = numText(p?.creditLimit);
    _loyalty.text = (p?.loyaltyOpening ?? 0) == 0 ? '' : '${p!.loyaltyOpening}';
    // The fields defined in settings come first, each with this party's value; anything else the
    // party already carries follows.
    final defined = [for (final d in widget.settings.partyFields) d.name];
    final own = p?.additionalFields ?? const <AdditionalField>[];
    final rows = [
      for (final name in defined) AdditionalField(name, own.where((f) => f.name == name).firstOrNull?.value ?? ''),
      ...own.where((f) => !defined.contains(f.name)),
    ];
    for (var i = 0; i < 4; i++) {
      _fieldNames[i].text = i < rows.length ? rows[i].name : '';
      _fieldValues[i].text = i < rows.length ? rows[i].value : '';
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_name, _gstin, _phone, _email, _billing, _city, _pincode, _pan, _tdsSection, _tcsCode, _shipping, _opening, _creditLimit, _loyalty, ..._fieldNames, ..._fieldValues]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save({required bool andNew}) {
    if (!validateForm(context, _formKey, report: showError)) {
      // Errors on a hidden tab would otherwise be invisible, so switch to it.
      if (_emailError(_email.text) != null) {
        _tabs.animateTo(0);
      } else if (_amountError(_opening.text) != null || (_cubit.state.customLimit && parseNum(_creditLimit.text) == null)) {
        _tabs.animateTo(1);
      }
      return;
    }
    _cubit.save({
      'name': _name.text.trim(),
      'gstin': _gstin.text.trim().toUpperCase(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'billingAddress': _billing.text.trim(),
      'city': _city.text.trim(),
      'pincode': _pincode.text.trim(),
      'pan': _pan.text.trim().toUpperCase(),
      'tdsSection': _tdsSection.text.trim(),
      'tcsCode': _tcsCode.text.trim(),
      'shippingAddress': _shipping.text.trim(),
      'openingAmount': parseNum(_opening.text),
      'creditLimitAmount': parseNum(_creditLimit.text),
      'loyaltyOpening': int.tryParse(_loyalty.text.trim()) ?? 0,
      'additionalFields': [
        for (var i = 0; i < 4; i++)
          if (_fieldNames[i].text.trim().isNotEmpty) {'name': _fieldNames[i].text.trim(), 'value': _fieldValues[i].text.trim()},
      ],
    }, andNew: andNew);
  }

  Future<void> _delete() async {
    if (await confirmDelete(context, title: 'Delete party', message: 'Do you really want to delete this party?')) {
      _cubit.delete();
    }
  }

  void _onResult(BuildContext context, PartyFormState s) {
    if (s.status == SubmitStatus.failure) return showError(context, s.error!);
    switch (s.result) {
      case PartyFormResult.saved:
        showSuccess(context, _cubit.editing ? 'Party updated' : 'Party saved');
        Navigator.of(context).pop();
      case PartyFormResult.savedAndNew:
        showSuccess(context, 'Party saved');
        _fill(null);
        _formKey.currentState!.reset();
        _tabs.animateTo(0);
      case PartyFormResult.deleted:
        showSuccess(context, 'Party deleted');
        Navigator.of(context).pop();
      case PartyFormResult.none:
        break;
    }
  }

  String? _gstinError(String? v) {
    final t = (v ?? '').trim().toUpperCase();
    return t.isEmpty || _gstinPattern.hasMatch(t) ? null : 'GSTIN must be 15 characters, like 27AAACA1234C1Z5';
  }

  String? _phoneError(String? v) {
    final t = (v ?? '').trim();
    return t.isEmpty || RegExp(r'^[0-9+\- ]{6,20}$').hasMatch(t) ? null : 'Phone number must be 6 to 20 digits (digits, +, - and spaces only)';
  }

  String? _emailError(String? v) {
    final t = (v ?? '').trim();
    return t.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Email must be a valid address, like name@example.com';
  }

  String? _amountError(String? v) => (v ?? '').trim().isNotEmpty && parseNum(v!) == null ? 'Opening balance must be a number' : null;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final content = BlocConsumer<PartyFormCubit, PartyFormState>(
      listenWhen: (a, b) => a.status != b.status && (b.status == SubmitStatus.success || b.status == SubmitStatus.failure),
      listener: _onResult,
      builder: (context, state) => Form(autovalidateMode: AutovalidateMode.onUserInteraction, 
        key: _formKey,
        child: Column(
          children: [
            _header(),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topFields(narrow),
                    const SizedBox(height: AppSpace.lg),
                    TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: const [
                        Tab(text: 'GST & Address'),
                        Tab(text: 'Credit & Balance'),
                        Tab(text: 'Additional Fields'),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xl),
                    AnimatedBuilder(
                      animation: _tabs,
                      builder: (_, _) => IndexedStack(
                        index: _tabs.index,
                        sizing: StackFit.loose,
                        children: [_gstTab(state, narrow), _creditTab(state, narrow), _fieldsTab()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            _footer(state),
          ],
        ),
      ),
    );

    if (narrow) return Dialog.fullscreen(child: content);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: AppSize.dialogForm, maxHeight: AppSize.dialogMaxHeight), child: content),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.md, AppSpace.sm, AppSpace.md),
    child: Row(
      children: [
        Text(_cubit.editing ? 'Edit Party' : 'Add Party', style: AppText.title),
        const Spacer(),
        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ],
    ),
  );

  Widget _row(bool narrow, List<Widget> children) => narrow
      ? Column(
          children: [for (final c in children) Padding(padding: const EdgeInsets.only(bottom: AppSpace.md), child: c)],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: AppSpace.lg), Expanded(child: children[i])],
          ],
        );

  Widget _topFields(bool narrow) => _row(narrow, [
    TextFormField(
      controller: _name,
      autofocus: !_cubit.editing,
      decoration: const InputDecoration(labelText: 'Party Name *'),
      validator: Validators.required('Party name'),
    ),
    TextFormField(
      controller: _gstin,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(labelText: 'GSTIN'),
      validator: _gstinError,
      onChanged: (v) {
        final t = v.trim().toUpperCase();
        if (_gstinPattern.hasMatch(t) && gstStates.containsKey(t.substring(0, 2))) _cubit.gstinRecognised(t.substring(0, 2));
      },
    ),
    TextFormField(
      controller: _phone,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(labelText: 'Phone Number'),
      validator: _phoneError,
    ),
  ]);

  Widget _gstTab(PartyFormState state, bool narrow) {
    final left = Column(
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('gst-${state.gstType}'),
          initialValue: state.gstType,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'GST Type'),
          items: [for (final e in gstTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => _cubit.gstTypeChanged(v!),
        ),
        const SizedBox(height: AppSpace.md),
        DropdownButtonFormField<String>(
          key: ValueKey('state-${state.stateCode}'),
          initialValue: state.stateCode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'State'),
          items: [for (final e in gstStates.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: _cubit.stateChanged,
        ),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email ID'),
          validator: _emailError,
        ),
      ],
    );
    final billing = Column(
      children: [
        TextFormField(
          controller: _billing,
          minLines: 3,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Billing Address', alignLabelWithHint: true),
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(child: TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'City'))),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: TextFormField(
                controller: _pincode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Pincode'),
                validator: Validators.pincode(),
              ),
            ),
          ],
        ),
      ],
    );
    final shipping = state.shippingEnabled
        ? TextFormField(
            controller: _shipping,
            minLines: 4,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Shipping Address',
              alignLabelWithHint: true,
              suffixIcon: IconButton(
                tooltip: 'Remove shipping address',
                icon: const Icon(Icons.close, size: AppIconSize.sm),
                onPressed: () => _cubit.shippingToggled(false),
              ),
            ),
          )
        : Align(
            alignment: Alignment.topLeft,
            child: TextButton.icon(
              onPressed: () => _cubit.shippingToggled(true),
              icon: const Icon(Icons.add),
              label: const Text('Enable Shipping Address'),
            ),
          );
    // A party that already has a shipping address keeps showing it even if the setting was switched off.
    return _row(narrow, [left, billing, widget.settings.shippingAddressEnabled || state.shippingEnabled ? shipping : const SizedBox.shrink()]);
  }

  Widget _creditTab(PartyFormState state, bool narrow) {
    final taxFields = widget.settings.tdsEnabled || widget.settings.tcsEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (taxFields) ...[
          _row(narrow, [
            TextFormField(
              controller: _pan,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'PAN', helperText: 'Taken from the GSTIN when empty'),
              validator: Validators.pan(),
            ),
            if (widget.settings.tdsEnabled)
              TextFormField(
                controller: _tdsSection,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'TDS section code', helperText: 'Empty = company default (1031 goods)'),
                validator: Validators.pattern('TDS section code', RegExp(r'^1\d{3}$'), '4 digits starting with 1, like 1031'),
              )
            else
              const SizedBox.shrink(),
            if (widget.settings.tcsEnabled)
              TextFormField(
                controller: _tcsCode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'TCS collection code', helperText: 'e.g. 1073 scrap'),
                validator: Validators.pattern('TCS collection code', RegExp(r'^1\d{3}$'), '4 digits starting with 1, like 1073'),
              )
            else
              const SizedBox.shrink(),
          ]),
          const SizedBox(height: AppSpace.md),
        ],
        _row(narrow, [
          TextFormField(
            controller: _opening,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Opening Balance', prefixText: '₹ '),
            validator: _amountError,
          ),
          DateField(label: 'As Of Date', value: state.asOf, onChanged: _cubit.asOfChanged),
        ]),
        const SizedBox(height: AppSpace.md),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('To Receive'), icon: Icon(Icons.south_west, size: AppIconSize.xs)),
            ButtonSegment(value: false, label: Text('To Pay'), icon: Icon(Icons.north_east, size: AppIconSize.xs)),
          ],
          selected: {state.toReceive},
          onSelectionChanged: (s) => _cubit.balanceDirectionChanged(s.first),
        ),
        const SizedBox(height: AppSpace.xxl),
        const Text('Credit Limit', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpace.xs),
        Row(
          children: [
            Text(
              'No Limit',
              style: TextStyle(color: state.customLimit ? AppColors.textMuted : AppColors.primary, fontWeight: FontWeight.w600),
            ),
            Switch(value: state.customLimit, onChanged: _cubit.creditLimitToggled),
            Text(
              'Custom Limit',
              style: TextStyle(color: state.customLimit ? AppColors.primary : AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        if (state.customLimit)
          SizedBox(
            width: AppSize.fieldMd,
            child: TextFormField(
              controller: _creditLimit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Credit Limit', prefixText: '₹ '),
              validator: Validators.number('Credit limit', required: true),
            ),
          ),
        if (widget.settings.partyGroupsEnabled || state.salesmen.isNotEmpty || state.currencies.isNotEmpty || widget.settings.loyaltyEnabled) ...[
          const SizedBox(height: AppSpace.xxl),
          const Text('More', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: 16,
            runSpacing: 14,
            children: [
              if (widget.settings.partyGroupsEnabled)
                SizedBox(
                  width: AppSize.fieldMd,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('group-${state.groupId}-${state.groups.length}'),
                    initialValue: state.groups.any((g) => g.id == state.groupId) ? state.groupId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Party Group'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final g in state.groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
                    ],
                    onChanged: _cubit.groupChanged,
                  ),
                ),
              if (state.salesmen.isNotEmpty)
                SizedBox(
                  width: AppSize.fieldMd,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('salesman-${state.assignedUserId}-${state.salesmen.length}'),
                    initialValue: state.salesmen.any((m) => m.id == state.assignedUserId) ? state.assignedUserId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Salesman', helperText: 'Sees this party, and its sales, in their own login'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Nobody')),
                      for (final m in state.salesmen) DropdownMenuItem(value: m.id, child: Text(m.fullName)),
                    ],
                    onChanged: _cubit.salesmanChanged,
                  ),
                ),
              if (state.currencies.isNotEmpty)
                SizedBox(
                  width: AppSize.fieldMd,
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('currency-${state.currencyCode}-${state.currencies.length}'),
                    initialValue: state.currencies.any((c) => c.code == state.currencyCode) ? state.currencyCode : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Currency', helperText: 'A foreign party is billed and pays in it'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('₹ INR')),
                      for (final c in state.currencies) DropdownMenuItem(value: c.code, child: Text('${c.symbol} ${c.code}')),
                    ],
                    onChanged: _cubit.currencyChanged,
                  ),
                ),
              if (widget.settings.loyaltyEnabled)
                SizedBox(
                  width: AppSize.fieldMd,
                  child: TextFormField(
                    controller: _loyalty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Opening loyalty points'),
                    validator: Validators.number('Opening points', whole: true),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _fieldsTab() => Column(
    children: [
      for (var i = 0; i < 4; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _fieldNames[i],
                  // Names of the fields defined in Settings are fixed here so every party uses the same ones.
                  readOnly: i < widget.settings.partyFields.length,
                  decoration: InputDecoration(labelText: 'Field ${i + 1} Name', filled: i < widget.settings.partyFields.length, fillColor: AppColors.background),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: TextFormField(
                  controller: _fieldValues[i],
                  decoration: const InputDecoration(labelText: 'Value'),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _footer(PartyFormState state) {
    final busy = state.status == SubmitStatus.submitting;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_cubit.editing)
            OutlinedButton(
              onPressed: busy ? null : _delete,
              style: AppButtons.destructiveOutlined,
              child: const Text('Delete'),
            )
          else
            OutlinedButton(onPressed: busy ? null : () => _save(andNew: true), child: const Text('Save & New')),
          const SizedBox(width: AppSpace.md),
          FilledButton(
            onPressed: busy ? null : () => _save(andNew: false),
            child: busy
                ? const InlineSpinner()
                : Text(_cubit.editing ? 'Update' : 'Save'),
          ),
        ],
      ),
    );
  }
}
