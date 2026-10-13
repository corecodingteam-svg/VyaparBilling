import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/status.dart';
import '../../data/models/tax_statement.dart';
import '../../data/repositories/tax_statements_repository.dart';
import '../../shared/file_io.dart';
import '../../shared/format.dart';
import '../../shared/page.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import 'tax_statements_cubit.dart';

/// Quarterly TDS (Form 140) and TCS (Form 143) statement files, and the GSTR-9 file for the GST portal.
class TaxStatementsScreen extends StatelessWidget {
  const TaxStatementsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => TaxStatementsCubit(ctx.read())..load(),
    child: BlocConsumer<TaxStatementsCubit, TaxStatementsState>(
      listenWhen: (a, b) => a.rev != b.rev,
      listener: (context, s) {
        if (s.error != null) showError(context, s.error!);
        if (s.message != null) showSuccess(context, s.message!);
      },
      builder: (context, s) => s.status == LoadStatus.failure && s.statement == null
          ? ErrorRetry(error: s.error ?? 'Could not load', onRetry: context.read<TaxStatementsCubit>().load)
          : const _View(),
    ),
  );
}

class _View extends StatelessWidget {
  const _View();

  /// Tax years from 2026-27 (the first the new forms cover) to the current one.
  List<String> _years() {
    final now = taxYearOf(DateTime.now());
    final last = int.parse(now.substring(0, 4));
    return [for (var y = last; y >= 2026; y--) '$y${(y + 1).toString().substring(2)}'];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<TaxStatementsCubit>().state;
    final cubit = context.read<TaxStatementsCubit>();
    final st = s.statement;
    final years = {..._years(), s.taxYear}.toList()..sort((a, b) => b.compareTo(a));
    return TitledPage(
      title: 'TDS / TCS Statements',
      subtitle:
          'The quarterly statement file the Income Tax Department\'s File Validation Utility (FVU 1.2) reads, for tax year 2026-27 onwards. '
          'Run it through the FVU with the challan file (.csi) from the TIN site, then upload the result at a TIN facilitation centre or the e-filing portal.',
      actions: [OutlinedButton.icon(onPressed: s.busy ? null : () => _gstr9(context), icon: const Icon(Icons.download, size: 18), label: const Text('GSTR-9 file'))],
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<String>(
                  segments: const [ButtonSegment(value: '140', label: Text('TDS · Form 140 (26Q)')), ButtonSegment(value: '143', label: Text('TCS · Form 143 (27EQ)'))],
                  selected: {s.form},
                  onSelectionChanged: (v) => cubit.periodChanged(form: v.first),
                ),
                DropdownButton<String>(
                  value: s.taxYear,
                  items: [for (final y in years) DropdownMenuItem(value: y, child: Text('Tax year ${taxYearLabel(y)}'))],
                  onChanged: (v) => cubit.periodChanged(taxYear: v),
                ),
                DropdownButton<String>(
                  value: s.quarter,
                  items: const [
                    DropdownMenuItem(value: 'Q1', child: Text('Q1 · Apr–Jun')),
                    DropdownMenuItem(value: 'Q2', child: Text('Q2 · Jul–Sep')),
                    DropdownMenuItem(value: 'Q3', child: Text('Q3 · Oct–Dec')),
                    DropdownMenuItem(value: 'Q4', child: Text('Q4 · Jan–Mar')),
                  ],
                  onChanged: (v) => cubit.periodChanged(quarter: v),
                ),
                if (s.busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
        ),
        if (st != null) _StatementCard(state: s),
        _ChallansCard(state: s),
        _DeductorCard(key: ValueKey(s.deductor), state: s),
      ],
    );
  }

  Future<void> _gstr9(BuildContext context) async {
    final cubit = context.read<TaxStatementsCubit>();
    final repo = context.read<TaxStatementsRepository>();
    final now = DateTime.now();
    // The return is for the year that has ended.
    final start = (now.month >= 4 ? now.year : now.year - 1) - 1;
    final choices = [for (var y = start; y >= start - 3; y--) '$y-${(y + 1).toString().substring(2)}'];
    final year = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('GSTR-9 for which year?'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'A JSON file in the GST portal\'s GSTR-9 layout with tables 4, 5, 6, 9, 17 and 18 filled from your books. Open it in the GSTR-9 offline tool, check it against your GSTR-1 and GSTR-3B, complete the other tables, then upload.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          for (final y in choices) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, y), child: Text('Financial year $y')),
        ],
      ),
    );
    if (year == null) return;
    await cubit.download(() async {
      final (name, json) = await repo.gstr9(year);
      await saveBytesFile(name, Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(json))), mimeType: 'application/json');
    }, 'GSTR-9 file saved');
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.state});
  final TaxStatementsState state;

  @override
  Widget build(BuildContext context) {
    final st = state.statement!;
    final cubit = context.read<TaxStatementsCubit>();
    final what = state.form == '140' ? 'deducted' : 'collected';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${st.deductees} bill${st.deductees == 1 ? '' : 's'} with tax $what · ${money(st.tax)} $what · ${money(st.deposited)} deposited',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (st.problems.isEmpty)
              const Text('Ready. Download the file and run it through the FVU.', style: TextStyle(color: receiveGreen))
            else ...[
              const Text('Fix these first:', style: TextStyle(fontWeight: FontWeight.w600)),
              for (final p in st.problems) Padding(padding: const EdgeInsets.only(top: 2), child: Text('• $p', style: const TextStyle(fontSize: 13))),
            ],
            for (final w in st.warnings) Padding(padding: const EdgeInsets.only(top: 4), child: Text('⚠ $w', style: const TextStyle(fontSize: 12, color: payRed))),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: st.file == null || state.busy
                  ? null
                  : () => cubit.download(
                      // Plain ASCII without a byte-order mark, as the FVU expects.
                      () => saveBytesFile(st.fileName, Uint8List.fromList(ascii.encode(st.file!)), mimeType: 'text/plain'),
                      'Saved ${st.fileName}',
                    ),
              icon: const Icon(Icons.download, size: 18),
              label: Text('Download Form ${state.form} file'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChallansCard extends StatelessWidget {
  const _ChallansCard({required this.state});
  final TaxStatementsState state;

  Future<void> _add(BuildContext context) async {
    final cubit = context.read<TaxStatementsCubit>();
    final bsr = TextEditingController();
    final no = TextEditingController();
    final date = TextEditingController(text: isoDate(DateTime.now()));
    final tax = TextEditingController();
    final interest = TextEditingController();
    final fee = TextEditingController();
    final key = GlobalKey<FormState>();
    String? whole(String? v, {bool required = false}) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return required ? 'Required' : null;
      return RegExp(r'^\d+$').hasMatch(t) ? null : 'Whole rupees';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Challan for ${state.quarter} ${taxYearLabel(state.taxYear)}'),
        content: SizedBox(
          width: 380,
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('From the counterfoil of challan ITNS 281.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                TextFormField(controller: bsr, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'BSR code'),
                    validator: (v) => RegExp(r'^\d{7}$').hasMatch((v ?? '').trim()) ? null : '7 digits'),
                TextFormField(controller: no, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Challan serial number'),
                    validator: (v) => RegExp(r'^\d{1,5}$').hasMatch((v ?? '').trim()) ? null : 'Up to 5 digits'),
                TextFormField(controller: date, decoration: const InputDecoration(labelText: 'Date of deposit', hintText: 'yyyy-mm-dd'),
                    validator: (v) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch((v ?? '').trim()) ? null : 'yyyy-mm-dd'),
                TextFormField(controller: tax, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tax', prefixText: '₹ '),
                    validator: (v) => whole(v, required: true)),
                Row(children: [
                  Expanded(child: TextFormField(controller: interest, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Interest'), validator: whole)),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: fee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Late fee'), validator: whole)),
                ]),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => key.currentState!.validate() ? Navigator.pop(ctx, true) : null, child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    await cubit.addChallan(
      bsrCode: bsr.text.trim(),
      challanNo: no.text.trim(),
      depositDate: date.text.trim(),
      tax: int.parse(tax.text.trim()),
      interest: int.tryParse(interest.text.trim()) ?? 0,
      fee: int.tryParse(fee.text.trim()) ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TaxStatementsCubit>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('${state.form == '140' ? 'TDS' : 'TCS'} challans for ${state.quarter} ${taxYearLabel(state.taxYear)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              OutlinedButton.icon(onPressed: state.busy ? null : () => _add(context), icon: const Icon(Icons.add, size: 18), label: const Text('Add Challan')),
            ]),
            if (state.challans.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No challans recorded for this quarter.', style: TextStyle(color: Colors.black54))),
            for (final c in state.challans)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('BSR ${c.bsrCode} · Challan ${c.challanNo} · ${displayDate(c.depositDate)}'),
                subtitle: Text('Tax ${money(c.tax)}${c.interest > 0 ? ' · Interest ${money(c.interest)}' : ''}${c.fee > 0 ? ' · Fee ${money(c.fee)}' : ''}'),
                trailing: IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, size: 20), onPressed: state.busy ? null : () => cubit.removeChallan(c.id)),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeductorCard extends StatefulWidget {
  const _DeductorCard({super.key, required this.state});
  final TaxStatementsState state;

  @override
  State<_DeductorCard> createState() => _DeductorCardState();
}

/// Stateful only to own its text controllers.
class _DeductorCardState extends State<_DeductorCard> {
  late final d = widget.state.deductor;
  late final name = TextEditingController(text: d.name);
  late final designation = TextEditingController(text: d.designation);
  late final pan = TextEditingController(text: d.pan);
  late final mobile = TextEditingController(text: d.mobile);
  late final email = TextEditingController(text: d.email);
  late final tdsToken = TextEditingController(text: d.tdsPreviousToken);
  late final tcsToken = TextEditingController(text: d.tcsPreviousToken);
  late String type = deductorTypes.containsKey(d.type) ? d.type : 'K';
  late String section = d.tdsSection;
  late String tcs = d.tcsCode;
  final key = GlobalKey<FormState>();

  @override
  void dispose() {
    for (final c in [name, designation, pan, mobile, email, tdsToken, tcsToken]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _box(Widget w) => SizedBox(width: 300, child: w);

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Deductor details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Text('TAN, PAN, address and phone come from Settings → Company.', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _box(DropdownButtonFormField<String>(
                    initialValue: type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Deductor category'),
                    items: [for (final e in deductorTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => type = v ?? 'K',
                  )),
                  _box(TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Person responsible'))),
                  _box(TextFormField(controller: designation, maxLength: 20, decoration: const InputDecoration(labelText: 'Designation', counterText: ''))),
                  _box(TextFormField(
                    controller: pan,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Their PAN'),
                    validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[A-Za-z]{5}[0-9]{4}[A-Za-z]$').hasMatch(v!.trim()) ? null : 'PAN looks like ABCDE1234F',
                  )),
                  _box(TextFormField(
                    controller: mobile,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Their mobile'),
                    validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^\d{10}$').hasMatch(v!.trim()) ? null : '10 digits',
                  )),
                  _box(TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Their email'))),
                  _box(DropdownButtonFormField<String>(
                    initialValue: s.tdsSections.containsKey(section) ? section : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Usual TDS section', helperText: 'A party can have its own'),
                    items: [for (final e in s.tdsSections.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}', overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => section = v ?? '1031',
                  )),
                  _box(DropdownButtonFormField<String>(
                    initialValue: s.tcsCodes.containsKey(tcs) ? tcs : '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Usual TCS collection code', helperText: 'TCS now applies only to listed goods'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('None')),
                      for (final e in s.tcsCodes.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => tcs = v ?? '',
                  )),
                  _box(TextFormField(
                    controller: tdsToken,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Token no. of last Form 140', helperText: 'Leave empty for your first statement'),
                    validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^\d{15}$').hasMatch(v!.trim()) ? null : '15 digits',
                  )),
                  _box(TextFormField(
                    controller: tcsToken,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Token no. of last Form 143', helperText: 'Leave empty for your first statement'),
                    validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^\d{15}$').hasMatch(v!.trim()) ? null : '15 digits',
                  )),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: s.busy
                    ? null
                    : () {
                        if (!key.currentState!.validate()) return;
                        context.read<TaxStatementsCubit>().saveDeductor(Deductor(
                          type: type,
                          name: name.text.trim(),
                          designation: designation.text.trim(),
                          pan: pan.text.trim().toUpperCase(),
                          mobile: mobile.text.trim(),
                          email: email.text.trim(),
                          tdsSection: section,
                          tcsCode: tcs,
                          tdsPreviousToken: tdsToken.text.trim(),
                          tcsPreviousToken: tcsToken.text.trim(),
                        ));
                      },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
