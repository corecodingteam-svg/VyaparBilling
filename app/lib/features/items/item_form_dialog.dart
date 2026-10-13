import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/status.dart';
import '../../data/models/item.dart';
import '../../shared/format.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../company/firm_cubit.dart';
import '../files/attachments.dart';
import 'bloc/catalog_cubit.dart';
import 'bloc/item_form_cubit.dart';
import 'catalog_dialogs.dart';

/// Opens the add/edit item dialog. [context] must be below a [CatalogCubit].
Future<void> showItemForm(BuildContext context, {Item? item, String type = 'product'}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: context.read<CatalogCubit>()),
        BlocProvider(create: (_) => ItemFormCubit(context.read(), item, type, settings: settingsOf(context))),
      ],
      child: const ItemFormDialog(),
    ),
  );
}

class ItemFormDialog extends StatefulWidget {
  const ItemFormDialog({super.key});

  @override
  State<ItemFormDialog> createState() => _ItemFormDialogState();
}

/// Stateful only to own text and tab controllers; all other state lives in [ItemFormCubit].
class _ItemFormDialogState extends State<ItemFormDialog> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final _tabs = TabController(length: 2, vsync: this);

  final _name = TextEditingController();
  final _hsn = TextEditingController();
  final _code = TextEditingController();
  final _salePrice = TextEditingController();
  final _discount = TextEditingController();
  final _wholesalePrice = TextEditingController();
  final _wholesaleQty = TextEditingController();
  final _purchasePrice = TextEditingController();
  final _openingQty = TextEditingController();
  final _openingPrice = TextEditingController();
  final _minStock = TextEditingController();
  final _location = TextEditingController();
  final _reminderDays = TextEditingController();
  final _cess = TextEditingController();
  final _mrp = TextEditingController();

  ItemFormCubit get _cubit => context.read<ItemFormCubit>();

  @override
  void initState() {
    super.initState();
    _fill(context.read<ItemFormCubit>().item);
  }

  void _fill(Item? i) {
    _name.text = i?.name ?? '';
    _hsn.text = i?.hsnCode ?? '';
    _code.text = i?.itemCode ?? '';
    _salePrice.text = numText(i?.salePrice);
    _discount.text = (i?.saleDiscount ?? 0) == 0 ? '' : numText(i!.saleDiscount);
    _wholesalePrice.text = numText(i?.wholesalePrice);
    _wholesaleQty.text = numText(i?.wholesaleMinQty);
    _purchasePrice.text = numText(i?.purchasePrice);
    _openingQty.text = (i?.openingQty ?? 0) == 0 ? '' : numText(i!.openingQty);
    _openingPrice.text = numText(i?.openingPrice);
    _minStock.text = numText(i?.minStock);
    _location.text = i?.location ?? '';
    _reminderDays.text = i?.serviceReminderDays?.toString() ?? '';
    _cess.text = numText(i?.cessRate);
    _mrp.text = numText(i?.mrp);
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _name,
      _hsn,
      _code,
      _salePrice,
      _discount,
      _wholesalePrice,
      _wholesaleQty,
      _purchasePrice,
      _openingQty,
      _openingPrice,
      _minStock,
      _location,
      _reminderDays,
      _cess,
      _mrp,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save({required bool andNew}) {
    if (!validateForm(context, _formKey, report: showError)) {
      // Jump to the stock tab if that is where the error is.
      final stockInvalid = [_openingQty, _openingPrice, _minStock].any((c) => _amount(c.text) != null);
      if (_cubit.state.isProduct && stockInvalid) _tabs.animateTo(1);
      return;
    }
    _cubit.save({
      'name': _name.text.trim(),
      'hsnCode': _hsn.text.trim(),
      'itemCode': _code.text.trim(),
      'salePrice': parseNum(_salePrice.text),
      'saleDiscount': parseNum(_discount.text),
      'wholesalePrice': parseNum(_wholesalePrice.text),
      'wholesaleMinQty': parseNum(_wholesaleQty.text),
      'purchasePrice': parseNum(_purchasePrice.text),
      'openingQty': parseNum(_openingQty.text),
      'openingPrice': parseNum(_openingPrice.text),
      'minStock': parseNum(_minStock.text),
      'location': _location.text.trim(),
      'serviceReminderDays': int.tryParse(_reminderDays.text.trim()),
      'cessRate': parseNum(_cess.text),
      'mrp': parseNum(_mrp.text),
    }, andNew: andNew);
  }

  Future<void> _delete() async {
    if (await confirmDelete(context, title: 'Delete item', message: 'Do you really want to delete "${_cubit.item!.name}"?')) {
      _cubit.delete();
    }
  }

  void _onResult(BuildContext context, ItemFormState s) {
    if (s.status == SubmitStatus.failure) return showError(context, s.error!);
    switch (s.result) {
      case ItemFormResult.saved:
        showSuccess(context, _cubit.editing ? 'Item updated' : 'Item saved');
        Navigator.of(context).pop();
      case ItemFormResult.savedAndNew:
        showSuccess(context, 'Item saved');
        _fill(null);
        _formKey.currentState!.reset();
        _tabs.animateTo(0);
      case ItemFormResult.deleted:
        showSuccess(context, 'Item deleted');
        Navigator.of(context).pop();
      case ItemFormResult.none:
        break;
    }
  }

  String? _amount(String? v, [String label = 'This amount']) => (v ?? '').trim().isNotEmpty && parseNum(v!) == null ? '$label must be a number' : null;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final content = BlocConsumer<ItemFormCubit, ItemFormState>(
      listenWhen: (a, b) => a.status != b.status && (b.status == SubmitStatus.success || b.status == SubmitStatus.failure),
      listener: _onResult,
      builder: (context, state) {
        final catalog = context.watch<CatalogCubit>().state;
        return Form(autovalidateMode: AutovalidateMode.onUserInteraction, 
          key: _formKey,
          child: Column(
            children: [
              _header(state),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _row(narrow, [
                        TextFormField(
                          controller: _name,
                          autofocus: !_cubit.editing,
                          decoration: InputDecoration(labelText: state.isProduct ? 'Item Name *' : 'Service Name *'),
                          validator: Validators.required('Item name'),
                        ),
                        TextFormField(
                          controller: _hsn,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: state.isProduct ? 'Item HSN' : 'Service SAC'),
                          validator: Validators.hsn(),
                        ),
                        _unitField(state, catalog.units),
                      ]),
                      const SizedBox(height: AppSpace.md),
                      _row(narrow, [
                        _categoryField(state, catalog.categories),
                        _codeField(),
                        if (!state.isProduct && _cubit.settings.serviceRemindersEnabled)
                          TextFormField(
                            controller: _reminderDays,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Service reminder after',
                              suffixText: 'days',
                              helperText: 'Reminds you this long after each sale',
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              final n = int.tryParse(t);
                              return t.isEmpty || (n != null && n >= 1 && n <= 3650) ? null : 'Service reminder must be a whole number of days, from 1 to 3650';
                            },
                          )
                        else
                          const SizedBox.shrink(),
                      ]),
                      const SizedBox(height: AppSpace.md),
                      ImageSlot(
                        label: state.isProduct ? 'Item image' : 'Service image',
                        fileId: state.imageFileId,
                        onChanged: _cubit.imageChanged,
                        width: AppSize.fieldXs,
                        height: 90,
                      ),
                      const SizedBox(height: AppSpace.lg),
                      if (state.isProduct)
                        TabBar(
                          controller: _tabs,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: const [
                            Tab(text: 'Pricing'),
                            Tab(text: 'Stock'),
                          ],
                        )
                      else
                        Text(
                          'Pricing',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary),
                        ),
                      const SizedBox(height: AppSpace.xl),
                      AnimatedBuilder(
                        animation: _tabs,
                        builder: (_, _) => IndexedStack(
                          index: state.isProduct ? _tabs.index : 0,
                          sizing: StackFit.loose,
                          children: [_pricingTab(state, narrow), _stockTab(state, narrow)],
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
        );
      },
    );
    if (narrow) return Dialog.fullscreen(child: content);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: AppSize.dialogForm, maxHeight: AppSize.dialogMaxHeight), child: content),
    );
  }

  Widget _header(ItemFormState state) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.md, AppSpace.sm, AppSpace.md),
    child: Row(
      children: [
        Text(_cubit.editing ? 'Edit Item' : 'Add Item', style: AppText.title),
        const SizedBox(width: AppSpace.xl),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'product', label: Text('Product')),
            ButtonSegment(value: 'service', label: Text('Service')),
          ],
          selected: {state.type},
          onSelectionChanged: (s) {
            if (s.first == 'service') _tabs.index = 0;
            _cubit.typeChanged(s.first);
          },
        ),
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

  static const _addNew = '__new__';

  Widget _unitField(ItemFormState state, List<Unit> units) => DropdownButtonFormField<String?>(
    key: ValueKey('unit-${state.unit}-${units.length}'),
    initialValue: units.any((u) => u.shortName == state.unit) ? state.unit : null,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Unit'),
    items: [
      const DropdownMenuItem(value: null, child: Text('None')),
      for (final u in units) DropdownMenuItem(value: u.shortName, child: Text('${u.name} (${u.shortName})')),
      DropdownMenuItem(
        value: _addNew,
        child: Text('+ Add new unit', style: TextStyle(color: AppColors.primary)),
      ),
    ],
    onChanged: (v) async {
      if (v != _addNew) return _cubit.unitChanged(v);
      final created = await showUnitDialog(context);
      _cubit.unitChanged(created?.shortName ?? state.unit);
    },
  );

  Widget _categoryField(ItemFormState state, List<Category> cats) => DropdownButtonFormField<String?>(
    key: ValueKey('cat-${state.categoryId}-${cats.length}'),
    initialValue: cats.any((c) => c.id == state.categoryId) ? state.categoryId : null,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Category'),
    items: [
      const DropdownMenuItem(value: null, child: Text('None')),
      for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name)),
      DropdownMenuItem(
        value: _addNew,
        child: Text('+ Add new category', style: TextStyle(color: AppColors.primary)),
      ),
    ],
    onChanged: (v) async {
      if (v != _addNew) return _cubit.categoryChanged(v);
      final created = await showCategoryDialog(context);
      _cubit.categoryChanged(created?.id ?? state.categoryId);
    },
  );

  Widget _codeField() => TextFormField(
    controller: _code,
    decoration: InputDecoration(
      labelText: 'Item Code',
      suffixIcon: Padding(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: TextButton(
          // Random 11-digit numeric code, suitable for barcodes.
          onPressed: () {
            final r = Random();
            _code.text = '${r.nextInt(9) + 1}${List.generate(10, (_) => r.nextInt(10)).join()}';
          },
          child: const Text('Assign Code'),
        ),
      ),
    ),
  );

  Widget _taxToggle(bool value, ValueChanged<bool> onChanged) => DropdownButtonFormField<bool>(
    key: ValueKey('tax-$value'),
    initialValue: value,
    isExpanded: true,
    decoration: const InputDecoration(),
    items: const [
      DropdownMenuItem(value: false, child: Text('Without Tax')),
      DropdownMenuItem(value: true, child: Text('With Tax')),
    ],
    onChanged: (v) => onChanged(v!),
  );

  Widget _section(String title, Widget child) => Container(
    padding: const EdgeInsets.all(AppSpace.lg),
    decoration: BoxDecoration(color: AppColors.background, borderRadius: AppRadius.lgAll),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpace.md),
        child,
      ],
    ),
  );

  Widget _priceRow(TextEditingController c, String label, bool incl, ValueChanged<bool> setIncl) => Row(
    children: [
      Expanded(
        child: TextFormField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, prefixText: '₹ '),
          validator: (v) => _amount(v, label),
        ),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(child: _taxToggle(incl, setIncl)),
    ],
  );

  Widget _pricingTab(ItemFormState state, bool narrow) {
    final sale = _section(
      'Sale Price',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(narrow, [
            _priceRow(_salePrice, 'Sale Price', state.saleIncludesTax, _cubit.saleTaxChanged),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _discount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Disc. On Sale Price'),
                    validator: (v) {
                      final err = _amount(v, 'Discount');
                      if (err != null) return err;
                      final d = parseNum(v ?? '');
                      return state.discountType == 'percent' && d != null && d > 100 ? 'Discount cannot be more than 100%' : null;
                    },
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('disc-${state.discountType}'),
                    initialValue: state.discountType,
                    isExpanded: true,
                    decoration: const InputDecoration(),
                    items: const [
                      DropdownMenuItem(value: 'percent', child: Text('Percentage')),
                      DropdownMenuItem(value: 'amount', child: Text('Amount')),
                    ],
                    onChanged: (v) => _cubit.discountTypeChanged(v!),
                  ),
                ),
              ],
            ),
          ]),
          const SizedBox(height: AppSpace.sm),
          if (state.wholesale)
            _row(narrow, [
              TextFormField(
                controller: _wholesalePrice,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Wholesale Price', prefixText: '₹ '),
                validator: Validators.number('Wholesale price', required: true),
              ),
              TextFormField(
                controller: _wholesaleQty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Minimum Wholesale Qty',
                  suffixIcon: IconButton(icon: const Icon(Icons.close, size: AppIconSize.sm), onPressed: () => _cubit.wholesaleToggled(false)),
                ),
                validator: Validators.number('Minimum quantity', required: true, positive: true),
              ),
            ])
          else if (_cubit.settings.wholesalePriceEnabled)
            TextButton.icon(onPressed: () => _cubit.wholesaleToggled(true), icon: const Icon(Icons.add), label: const Text('Add Wholesale Price')),
        ],
      ),
    );
    final purchase = _section('Purchase Price', _priceRow(_purchasePrice, 'Purchase Price', state.purchaseIncludesTax, _cubit.purchaseTaxChanged));
    final showCess = _cubit.settings.cessEnabled || _cubit.item?.cessRate != null;
    final taxes = _section(
      'Taxes',
      Column(
        children: [
          DropdownButtonFormField<num?>(
            key: ValueKey('gst-${state.gstRate}'),
            initialValue: state.gstRate,
            decoration: const InputDecoration(labelText: 'Tax Rate'),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final r in gstRateOptions) DropdownMenuItem(value: r, child: Text('GST@${numText(r)}%')),
            ],
            onChanged: _cubit.gstRateChanged,
          ),
          if (showCess) ...[
            const SizedBox(height: AppSpace.md),
            TextFormField(
              controller: _cess,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Compensation Cess %'),
              validator: Validators.number('Cess rate', nonNegative: true, max: 300),
            ),
          ],
        ],
      ),
    );
    final mrp = _cubit.settings.mrpEnabled || _cubit.item?.mrp != null
        ? Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: AppSize.fieldMd,
                child: TextFormField(
                  controller: _mrp,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'MRP', prefixText: '₹ '),
                  validator: (v) => _amount(v, 'MRP'),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();
    return Column(
      children: [
        sale,
        const SizedBox(height: AppSpace.md),
        mrp,
        _row(narrow, [purchase, taxes]),
      ],
    );
  }

  Widget _stockTab(ItemFormState state, bool narrow) {
    final unit = state.unit ?? '';
    return Column(
      children: [
        _row(narrow, [
          TextFormField(
            controller: _openingQty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Opening Quantity', suffixText: unit),
            validator: (v) => _amount(v, 'Opening quantity'),
          ),
          TextFormField(
            controller: _openingPrice,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'At Price', prefixText: '₹ ', suffixText: unit.isEmpty ? null : '/ $unit'),
            validator: (v) => _amount(v, 'At price'),
          ),
          DateField(label: 'As Of Date', value: state.openingDate, onChanged: _cubit.openingDateChanged),
        ]),
        const SizedBox(height: AppSpace.md),
        _row(narrow, [
          TextFormField(
            controller: _minStock,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Min Stock To Maintain', suffixText: unit, helperText: 'Shows a low-stock alert at or below this'),
            validator: (v) => _amount(v, 'Minimum stock'),
          ),
          TextFormField(
            controller: _location,
            decoration: const InputDecoration(labelText: 'Location'),
          ),
          const SizedBox.shrink(),
        ]),
      ],
    );
  }

  Widget _footer(ItemFormState state) {
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
