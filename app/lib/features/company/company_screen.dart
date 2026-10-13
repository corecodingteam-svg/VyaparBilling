import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/gst_states.dart';
import '../../core/status.dart';
import '../../data/models/firm.dart';
import '../../shared/theme.dart';
import '../../shared/widgets.dart';
import '../auth/bloc/auth_bloc.dart';
import '../files/attachments.dart';
import 'company_cubit.dart';

final _gstinPattern = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

class CompanyScreen extends StatelessWidget {
  const CompanyScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => CompanyCubit(ctx.read(), ctx.read<AuthBloc>())..load(),
        child: const _CompanyForm(),
      );
}

class _CompanyForm extends StatefulWidget {
  const _CompanyForm();

  @override
  State<_CompanyForm> createState() => _CompanyFormState();
}

/// Stateful only to own the text controllers; all other state lives in [CompanyCubit].
class _CompanyFormState extends State<_CompanyForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _gstin = TextEditingController();
  final _email = TextEditingController();
  final _pincode = TextEditingController();
  final _city = TextEditingController();
  final _tan = TextEditingController();
  final _pan = TextEditingController();
  final _address = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _phone, _gstin, _email, _pincode, _city, _tan, _pan, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Firm f) {
    _name.text = f.name;
    _phone.text = f.phone ?? '';
    _gstin.text = f.gstin ?? '';
    _email.text = f.email ?? '';
    _pincode.text = f.pincode ?? '';
    _city.text = f.city ?? '';
    _tan.text = f.tan ?? '';
    _pan.text = f.pan ?? '';
    _address.text = f.address ?? '';
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    context.read<CompanyCubit>().save({
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'gstin': _gstin.text.trim().toUpperCase(),
      'email': _email.text.trim(),
      'pincode': _pincode.text.trim(),
      'city': _city.text.trim(),
      'tan': _tan.text.trim().toUpperCase(),
      'pan': _pan.text.trim().toUpperCase(),
      'address': _address.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CompanyCubit, CompanyState>(
      listenWhen: (a, b) => a.firm != b.firm || a.submitStatus != b.submitStatus,
      listener: (context, state) {
        if (state.firm != null) _fill(state.firm!);
        if (state.submitStatus == SubmitStatus.success) showSuccess(context, 'Company profile saved');
        if (state.submitStatus == SubmitStatus.failure) showError(context, state.error!);
      },
      builder: (context, state) {
        if (state.firm == null) {
          return state.loadStatus == LoadStatus.failure
              ? ErrorRetry(error: state.error!, onRetry: context.read<CompanyCubit>().load)
              : const Center(child: CircularProgressIndicator());
        }
        final cubit = context.read<CompanyCubit>();
        final saving = state.submitStatus == SubmitStatus.submitting;
        return Column(children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: LayoutBuilder(builder: (context, c) {
                      final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 600 ? 2 : 1);
                      final width = (c.maxWidth - (cols - 1) * 24) / cols;
                      Widget box(Widget child) => SizedBox(width: width, child: child);
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Edit Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 20),
                        Wrap(spacing: 24, runSpacing: 16, children: [
                          box(TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Business Name *'),
                            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your business name' : null,
                          )),
                          box(TextFormField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: 'Phone Number'),
                          )),
                          box(TextFormField(
                            controller: _gstin,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(labelText: 'GSTIN'),
                            validator: (v) {
                              final t = (v ?? '').trim().toUpperCase();
                              return t.isEmpty || _gstinPattern.hasMatch(t) ? null : 'Enter a valid 15-character GSTIN';
                            },
                            onChanged: (v) {
                              final t = v.trim().toUpperCase();
                              if (_gstinPattern.hasMatch(t) && gstStates.containsKey(t.substring(0, 2))) cubit.stateChanged(t.substring(0, 2));
                            },
                          )),
                          box(TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: 'Email ID'),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              return t.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Enter a valid email';
                            },
                          )),
                          box(DateField(label: 'Account Books Beginning Date', value: state.booksStartDate!, onChanged: cubit.booksStartDateChanged)),
                          box(_dropdown('Business Type', state.businessType, businessTypes, cubit.businessTypeChanged)),
                          box(_dropdown('Business Category', state.businessCategory, businessCategories, cubit.businessCategoryChanged)),
                          box(DropdownButtonFormField<String?>(
                            key: ValueKey('state-${state.stateCode}'),
                            initialValue: state.stateCode,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'State'),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Select State')),
                              for (final e in gstStates.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                            ],
                            onChanged: cubit.stateChanged,
                          )),
                          box(TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'City'))),
                          box(TextFormField(
                            controller: _pan,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(labelText: 'PAN', helperText: 'For TDS / TCS statements'),
                            validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[A-Za-z]{5}[0-9]{4}[A-Za-z]$').hasMatch(v!.trim()) ? null : 'PAN looks like ABCDE1234F',
                          )),
                          box(TextFormField(
                            controller: _tan,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(labelText: 'TAN', helperText: 'Needed only if you deduct or collect tax'),
                            validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[A-Za-z]{4}[0-9]{5}[A-Za-z]$').hasMatch(v!.trim()) ? null : 'TAN looks like PNEA12345B',
                          )),
                          box(TextFormField(
                            controller: _pincode,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Pincode'),
                            validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[1-9][0-9]{5}$').hasMatch(v!.trim()) ? null : 'Pincode must be 6 digits',
                          )),
                          SizedBox(
                            width: cols == 1 ? width : width * 2 + 24,
                            child: TextFormField(
                              controller: _address,
                              minLines: 3,
                              maxLines: 4,
                              decoration: const InputDecoration(labelText: 'Business Address', alignLabelWithHint: true),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 24),
                        const Text('Logo and signature', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        const Text('Printed on invoices and other documents. PNG, JPEG or WebP, up to 5 MB.', style: TextStyle(color: Colors.black54)),
                        const SizedBox(height: 12),
                        Wrap(spacing: 24, runSpacing: 16, children: [
                          ImageSlot(label: 'Business logo', fileId: state.logoFileId, onChanged: cubit.logoChanged, icon: Icons.storefront_outlined),
                          ImageSlot(label: 'Signature', fileId: state.signatureFileId, onChanged: cubit.signatureChanged, width: 220, icon: Icons.draw_outlined),
                        ]),
                      ]);
                    }),
                  ),
                ),
              ]),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: saving
                    ? null
                    : () {
                        cubit.reset();
                        _fill(state.firm!);
                      },
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: payRed),
                onPressed: saving ? null : _save,
                child: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes'),
              ),
            ]),
          ),
        ]);
      },
    );
  }

  Widget _dropdown(String label, String? value, List<String> options, ValueChanged<String?> onChanged) =>
      DropdownButtonFormField<String?>(
        key: ValueKey('$label-$value'),
        initialValue: options.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem(value: null, child: Text('Select $label')),
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: onChanged,
      );
}
