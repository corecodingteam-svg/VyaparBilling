import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/list_cubit.dart';
import '../../core/status.dart';
import '../../core/submit_cubit.dart';
import '../../data/models/integrations.dart';
import '../../data/repositories/integrations_repository.dart';
import '../../shared/file_io.dart';
import '../../shared/format.dart';
import '../../shared/page.dart';
import '../../shared/submit_dialog.dart';
import '../../shared/theme.dart';
import '../../shared/value_cubit.dart';
import '../../shared/widgets.dart';
import '../reminders/reminders_screens.dart' show whatsappNumber;
import 'integrations_cubits.dart';

const _channelNames = {'whatsapp': 'WhatsApp', 'sms': 'SMS'};

// ================================================================ Integrations settings

/// Connect the outside services: WhatsApp, SMS, e-invoice, online payments and Google.
class IntegrationsScreen extends StatelessWidget {
  const IntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => ListCubit<Integration>(ctx.read<IntegrationsRepository>().integrations)..load(),
    child: ListCubitView<Integration>(
      builder: (context, state) => TitledPage(
        title: 'Integrations',
        subtitle:
            'Connect the services you have an account with. Keys are stored encrypted on the server and are never shown again. '
            'Everything works without them; these add sending, filing and online payments.',
        actions: [
          OutlinedButton.icon(onPressed: () => context.push('/messages'), icon: const Icon(Icons.forum_outlined, size: 18), label: const Text('Messages')),
        ],
        children: [for (final i in state.items) _IntegrationCard(integration: i)],
      ),
    ),
  );
}

class _IntegrationCard extends StatelessWidget {
  const _IntegrationCard({required this.integration});
  final Integration integration;

  Future<void> _edit(BuildContext context) async {
    final list = context.read<ListCubit<Integration>>();
    final repo = context.read<IntegrationsRepository>();
    final controllers = {for (final f in integration.fields.where((f) => f.options == null)) f.key: TextEditingController(text: f.secret ? '' : f.value)};
    final picked = {for (final f in integration.fields.where((f) => f.options != null)) f.key: f.value};
    final saved = await showSubmitDialog<List<Integration>>(
      context,
      title: integration.title,
      action: () => repo.save(integration.provider, {for (final e in controllers.entries) e.key: e.value.text, ...picked}),
      fields: (submit) => [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(integration.help, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                const SizedBox(height: 12),
                for (final f in integration.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: f.options != null
                        ? DropdownButtonFormField<String>(
                            initialValue: f.options!.contains(f.value) ? f.value : null,
                            decoration: InputDecoration(labelText: f.required ? '${f.label} *' : f.label),
                            items: [for (final o in f.options!) DropdownMenuItem(value: o, child: Text(o))],
                            onChanged: (v) => picked[f.key] = v ?? '',
                            validator: (v) => f.required && v == null ? 'Choose one' : null,
                          )
                        : TextFormField(
                            controller: controllers[f.key],
                            obscureText: f.secret && f.key != 'publicKey',
                            minLines: f.key == 'publicKey' ? 3 : 1,
                            maxLines: f.key == 'publicKey' ? 6 : 1,
                            decoration: InputDecoration(
                              labelText: f.required ? '${f.label} *' : f.label,
                              helperText: f.secret && f.stored != null ? 'Saved (${f.stored}). Leave empty to keep it.' : f.help,
                              helperMaxLines: 3,
                            ),
                            validator: (v) => f.required && (v ?? '').trim().isEmpty && !(f.secret && f.stored != null) ? 'Required' : null,
                          ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    if (saved != null) {
      await list.load();
      if (context.mounted) showSuccess(context, '${integration.title} saved');
    }
  }

  Future<void> _test(BuildContext context) async {
    final repo = context.read<IntegrationsRepository>();
    final phone = TextEditingController();
    final sent = await showSubmitDialog<bool>(
      context,
      title: 'Send a test message',
      action: () async {
        await repo.testMessage(integration.provider, phone.text);
        return true;
      },
      fields: (submit) => [
        TextFormField(
          controller: phone,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Your mobile number', helperText: 'The test goes to this number.'),
          validator: (v) => RegExp(r'^[+\d\s()-]{7,20}$').hasMatch(v ?? '') ? null : 'Enter a phone number',
          onFieldSubmitted: (_) => submit(),
        ),
      ],
    );
    if (sent == true && context.mounted) showSuccess(context, 'Test message sent');
  }

  Future<void> _disconnect(BuildContext context) async {
    final list = context.read<ListCubit<Integration>>();
    final repo = context.read<IntegrationsRepository>();
    final ok = await confirmDelete(context, title: 'Disconnect ${integration.title}?', message: 'The saved keys are deleted. You can add them again later.');
    if (ok) await list.run(() => repo.disconnect(integration.provider));
  }

  @override
  Widget build(BuildContext context) {
    final i = integration;
    final isGoogle = i.provider == 'google_profile';
    final messaging = i.provider == 'whatsapp' || i.provider == 'sms';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(i.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                Chip(
                  label: Text(i.connected ? 'Connected' : 'Not set up'),
                  backgroundColor: (i.connected ? receiveGreen : Colors.grey).withValues(alpha: 0.15),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(i.help, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            if (isGoogle && i.email != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Account: ${i.email}${i.location == null ? '' : ' · ${i.location}'}')),
            if (i.provider == 'razorpay') const _WebhookUrl(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isGoogle)
                  FilledButton(onPressed: () => context.push('/google-profile'), child: Text(i.connected ? 'Open' : 'Connect'))
                else
                  FilledButton(onPressed: () => _edit(context), child: Text(i.connected ? 'Edit keys' : 'Set up')),
                if (messaging && i.connected) OutlinedButton(onPressed: () => _test(context), child: const Text('Send test message')),
                if (i.connected && !isGoogle) TextButton(onPressed: () => _disconnect(context), child: const Text('Disconnect')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The address to register with Razorpay so paid links come back as payments.
class _WebhookUrl extends StatelessWidget {
  const _WebhookUrl();

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) {
      final cubit = ValueCubit<String?>(null);
      ctx.read<IntegrationsRepository>().webhookUrl().then(cubit.set).catchError((_) {});
      return cubit;
    },
    child: BlocBuilder<ValueCubit<String?>, String?>(
      builder: (context, url) => url == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(child: SelectableText('Webhook address: $url', style: const TextStyle(fontSize: 12))),
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) showSuccess(context, 'Webhook address copied');
                    },
                  ),
                ],
              ),
            ),
    ),
  );
}

// ================================================================ Send a document

/// Asks how to send [title] (WhatsApp or SMS through the connected services) and sends it.
/// [send] makes the actual call; [manualMessage] is offered through the phone's own WhatsApp when nothing is connected.
Future<void> showSendDialog(
  BuildContext context, {
  required String title,
  required String? phone,
  required String manualMessage,
  required Future<void> Function(IntegrationsRepository repo, String channel, String? phone) send,
}) {
  final repo = context.read<IntegrationsRepository>();
  final phoneField = TextEditingController(text: phone ?? '');
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ListCubit<Integration>(repo.integrations)..load()),
        BlocProvider(create: (_) => SubmitCubit<void>()),
      ],
      child: BlocConsumer<SubmitCubit<void>, SubmitState<void>>(
        listener: (ctx, s) {
          if (s.status == SubmitStatus.success) {
            Navigator.pop(ctx);
            showSuccess(context, 'Sent');
          }
          if (s.status == SubmitStatus.failure) showError(ctx, s.error!);
        },
        builder: (ctx, submit) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 360,
            child: BlocBuilder<ListCubit<Integration>, ListState<Integration>>(
              builder: (ctx, list) {
                final channels = [for (final i in list.items) if ((i.provider == 'whatsapp' || i.provider == 'sms') && i.connected) i.provider];
                final busy = submit.status == SubmitStatus.submitting;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: phoneField, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
                    const SizedBox(height: 16),
                    if (list.status == LoadStatus.loading) const Center(child: CircularProgressIndicator()),
                    if (list.status != LoadStatus.loading && channels.isEmpty)
                      const Text('WhatsApp and SMS are not connected, so the app cannot send for you. Connect them under Settings → Integrations, or open WhatsApp on this device with the message ready.'),
                    for (final c in channels)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FilledButton.icon(
                          onPressed: busy ? null : () => ctx.read<SubmitCubit<void>>().run(() => send(repo, c, phoneField.text.trim())),
                          icon: Icon(c == 'sms' ? Icons.sms_outlined : Icons.chat_outlined, size: 18),
                          label: Text('Send by ${_channelNames[c]}'),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final number = whatsappNumber(phoneField.text);
                        if (number == null) return showError(ctx, 'Enter a valid mobile number.');
                        await launchUrl(Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(manualMessage)}'), mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open WhatsApp on this device'),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      ),
    ),
  );
}

// ================================================================ E-invoice and e-way bill

Future<void> showEinvoiceDialog(BuildContext context, {required String invoiceId, required String number}) {
  final repo = context.read<IntegrationsRepository>();
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) => EinvoiceCubit(repo, invoiceId)..load(),
      child: _EinvoiceDialog(number: number, invoiceId: invoiceId, repo: repo),
    ),
  );
}

class _EinvoiceDialog extends StatelessWidget {
  const _EinvoiceDialog({required this.number, required this.invoiceId, required this.repo});
  final String number;
  final String invoiceId;
  final IntegrationsRepository repo;

  Future<void> _download(BuildContext context, Future<(String, Object)> Function(String) load) => context.read<EinvoiceCubit>().attempt(() async {
    final (name, json) = await load(invoiceId);
    await saveBytesFile(name, Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(json))), mimeType: 'application/json');
  }, done: 'File saved. Upload it on the portal.');

  Future<void> _enter(BuildContext context, {required String title, required List<(String, String)> fields, required void Function(List<String>) done}) async {
    final controllers = [for (final _ in fields) TextEditingController()];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < fields.length; i++)
              TextField(controller: controllers[i], decoration: InputDecoration(labelText: fields[i].$1, helperText: fields[i].$2.isEmpty ? null : fields[i].$2)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) done([for (final c in controllers) c.text.trim()]);
  }

  Future<void> _cancel(BuildContext context) async {
    final cubit = context.read<EinvoiceCubit>();
    final remark = TextEditingController();
    final reason = ValueCubit<String>('1');
    final onPortal = ValueCubit<bool>(cubit.state.info?.portalConnected ?? false);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel the e-invoice'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('The portal allows this only within 24 hours of generating the IRN.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            BlocBuilder<ValueCubit<String>, String>(
              bloc: reason,
              builder: (_, v) => DropdownButtonFormField<String>(
                initialValue: v,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: const [
                  DropdownMenuItem(value: '1', child: Text('Duplicate')),
                  DropdownMenuItem(value: '2', child: Text('Data entry mistake')),
                  DropdownMenuItem(value: '3', child: Text('Order cancelled')),
                  DropdownMenuItem(value: '4', child: Text('Other')),
                ],
                onChanged: (x) => reason.set(x ?? '1'),
              ),
            ),
            TextField(controller: remark, decoration: const InputDecoration(labelText: 'Remark')),
            if (cubit.state.info?.portalConnected ?? false)
              BlocBuilder<ValueCubit<bool>, bool>(
                bloc: onPortal,
                builder: (_, v) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: v,
                  onChanged: (x) => onPortal.set(x ?? false),
                  title: const Text('Also cancel on the portal'),
                ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel e-invoice')),
        ],
      ),
    );
    if (ok == true) await cubit.cancel(reason.state, remark.text.trim().isEmpty ? 'Cancelled' : remark.text.trim(), onPortal: onPortal.state);
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<EinvoiceCubit, EinvoiceState>(
    listenWhen: (a, b) => a.rev != b.rev,
    listener: (context, s) {
      if (s.error != null) showError(context, s.error!);
      if (s.message != null) showSuccess(context, s.message!);
    },
    builder: (context, s) {
      final cubit = context.read<EinvoiceCubit>();
      final info = s.info;
      return AlertDialog(
        title: Text('E-invoice · $number'),
        content: SizedBox(
          width: 520,
          child: info == null
              ? (s.status == LoadStatus.failure ? Text(s.error ?? 'Could not load') : const Center(child: CircularProgressIndicator()))
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _section('E-invoice (IRN)'),
                      if (info.hasIrn) ...[
                        SelectableText('IRN: ${info.irn}', style: const TextStyle(fontSize: 12)),
                        if (info.ackNo != null) Text('Ack no. ${info.ackNo}', style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        const Text('This invoice is registered and cannot be edited or deleted unless the IRN is cancelled.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ] else ...[
                        if (info.status == 'cancelled') const Text('The earlier IRN was cancelled.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        _problems(info.einvoiceProblems),
                      ],
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (!info.hasIrn && info.portalConnected)
                          FilledButton(onPressed: s.busy || info.einvoiceProblems.isNotEmpty ? null : cubit.generate, child: const Text('Generate on portal')),
                        if (!info.hasIrn)
                          OutlinedButton(
                            onPressed: s.busy || info.einvoiceProblems.isNotEmpty ? null : () => _download(context, repo.einvoiceJson),
                            child: const Text('Download JSON'),
                          ),
                        if (!info.hasIrn)
                          OutlinedButton(
                            onPressed: s.busy
                                ? null
                                : () => _enter(
                                      context,
                                      title: 'Enter the IRN',
                                      fields: const [('IRN', '64 characters from the portal'), ('Ack no. (optional)', ''), ('Ack date (optional)', 'dd/mm/yyyy hh:mm:ss')],
                                      done: (v) => cubit.recordIrn(v[0], v[1], v[2]),
                                    ),
                            child: const Text('I have the IRN'),
                          ),
                        if (info.hasIrn) OutlinedButton(onPressed: s.busy ? null : () => _cancel(context), child: const Text('Cancel e-invoice')),
                      ]),
                      if (!info.portalConnected && !info.hasIrn)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('Filing directly needs the portal connected under Settings → Integrations. Otherwise download the JSON and upload it on the e-invoice portal.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        ),
                      const Divider(height: 28),
                      _section('Transport and e-way bill'),
                      _TransportForm(key: ValueKey(info.transport), initial: info.transport, busy: s.busy, onSave: cubit.saveTransport),
                      const SizedBox(height: 8),
                      if (info.ewayBillNo != null)
                        Text('E-way bill ${info.ewayBillNo}${info.ewayValidUpto == null ? '' : ' · valid until ${info.ewayValidUpto!.substring(0, 10)}'}', style: const TextStyle(fontWeight: FontWeight.w600))
                      else
                        _problems(info.ewayProblems),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (info.ewayBillNo == null && info.portalConnected && info.hasIrn)
                          FilledButton(onPressed: s.busy || info.ewayProblems.isNotEmpty ? null : cubit.generateEway, child: const Text('Generate e-way bill')),
                        OutlinedButton(onPressed: s.busy || info.ewayProblems.isNotEmpty ? null : () => _download(context, repo.ewayJson), child: const Text('Download JSON')),
                        if (info.ewayBillNo == null)
                          OutlinedButton(
                            onPressed: s.busy
                                ? null
                                : () => _enter(context, title: 'Enter the e-way bill number', fields: const [('E-way bill number', '12 digits')], done: (v) => cubit.recordEway(v[0])),
                            child: const Text('I have the number'),
                          ),
                      ]),
                      if (s.busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                    ],
                  ),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      );
    },
  );

  Widget _section(String text) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)));

  Widget _problems(List<String> problems) => problems.isEmpty
      ? const Text('Everything needed is filled in.', style: TextStyle(color: receiveGreen))
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fix these first:', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final p in problems) Padding(padding: const EdgeInsets.only(top: 2), child: Text('• $p', style: const TextStyle(fontSize: 12))),
          ],
        );
}

class _TransportForm extends StatefulWidget {
  const _TransportForm({super.key, required this.initial, required this.busy, required this.onSave});
  final Transport initial;
  final bool busy;
  final void Function(Transport) onSave;

  @override
  State<_TransportForm> createState() => _TransportFormState();
}

class _TransportFormState extends State<_TransportForm> {
  late final vehicle = TextEditingController(text: widget.initial.vehicleNo);
  late final distance = TextEditingController(text: widget.initial.distanceKm?.toString() ?? '');
  late final transporterId = TextEditingController(text: widget.initial.transporterId);
  late final transporterName = TextEditingController(text: widget.initial.transporterName);
  late final docNo = TextEditingController(text: widget.initial.docNo);
  late final docDate = TextEditingController(text: widget.initial.docDate);
  late final mode = ValueCubit<String?>(widget.initial.mode ?? 'road');

  @override
  void dispose() {
    for (final c in [vehicle, distance, transporterId, transporterName, docNo, docDate]) {
      c.dispose();
    }
    mode.close();
    super.dispose();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      BlocBuilder<ValueCubit<String?>, String?>(
        bloc: mode,
        builder: (_, v) => DropdownButtonFormField<String>(
          initialValue: v,
          decoration: const InputDecoration(labelText: 'Transport mode'),
          items: const [
            DropdownMenuItem(value: 'road', child: Text('Road')),
            DropdownMenuItem(value: 'rail', child: Text('Rail')),
            DropdownMenuItem(value: 'air', child: Text('Air')),
            DropdownMenuItem(value: 'ship', child: Text('Ship')),
          ],
          onChanged: mode.set,
        ),
      ),
      Row(children: [
        Expanded(child: TextField(controller: vehicle, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Vehicle number'))),
        const SizedBox(width: 12),
        Expanded(child: TextField(controller: distance, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Distance (km)'))),
      ]),
      Row(children: [
        Expanded(child: TextField(controller: transporterId, decoration: const InputDecoration(labelText: 'Transporter GSTIN'))),
        const SizedBox(width: 12),
        Expanded(child: TextField(controller: transporterName, decoration: const InputDecoration(labelText: 'Transporter name'))),
      ]),
      Row(children: [
        Expanded(child: TextField(controller: docNo, decoration: const InputDecoration(labelText: 'Transport doc no.'))),
        const SizedBox(width: 12),
        Expanded(child: TextField(controller: docDate, decoration: const InputDecoration(labelText: 'Doc date', hintText: 'yyyy-mm-dd'))),
      ]),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: widget.busy
              ? null
              : () => widget.onSave(Transport(
                    mode: mode.state,
                    vehicleNo: _text(vehicle),
                    distanceKm: int.tryParse(distance.text.trim()),
                    transporterId: _text(transporterId),
                    transporterName: _text(transporterName),
                    docNo: _text(docNo),
                    docDate: _text(docDate),
                  )),
          child: const Text('Save transport details'),
        ),
      ),
    ],
  );
}

// ================================================================ Payment link

Future<void> showPaymentLinkDialog(BuildContext context, {required String invoiceId, required String number, required String? phone, required String customer}) {
  final repo = context.read<IntegrationsRepository>();
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) => PaymentLinkCubit(repo, invoiceId)..load(),
      child: BlocConsumer<PaymentLinkCubit, PaymentLinkState>(
        listenWhen: (a, b) => a.rev != b.rev,
        listener: (ctx, s) {
          if (s.error != null) showError(ctx, s.error!);
        },
        builder: (ctx, s) {
          final link = s.link;
          return AlertDialog(
            title: Text('Pay online · $number'),
            content: SizedBox(
              width: 420,
              child: link != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(money(link.amount), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        SelectableText(link.url),
                        const SizedBox(height: 8),
                        Text(
                          link.paid ? 'Paid. A Payment-In was recorded against this invoice.' : 'Send this link to the customer. When they pay, the payment is recorded here by itself.',
                          style: TextStyle(color: link.paid ? receiveGreen : Colors.black54, fontSize: 12),
                        ),
                        if (s.busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                      ],
                    )
                  : s.status == LoadStatus.failure
                      ? Text(s.error ?? 'Could not make the link.')
                      : const Center(child: CircularProgressIndicator()),
            ),
            actions: [
              if (link != null && !link.paid) ...[
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link.url));
                    if (ctx.mounted) showSuccess(ctx, 'Link copied');
                  },
                  child: const Text('Copy'),
                ),
                TextButton(
                  onPressed: () => showSendDialog(
                    ctx,
                    title: 'Send the invoice with its link',
                    phone: phone,
                    manualMessage: 'Dear $customer, invoice $number for ${money(link.amount)} is ready. Pay online: ${link.url}',
                    send: (repo, channel, p) => repo.sendInvoice(invoiceId, channel, phone: p),
                  ),
                  child: const Text('Send'),
                ),
                TextButton(onPressed: s.busy ? null : ctx.read<PaymentLinkCubit>().check, child: const Text('Check payment')),
              ],
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      ),
    ),
  );
}

// ================================================================ Messages: marketing and history

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(create: (ctx) => ListCubit<MessageEntry>(ctx.read<IntegrationsRepository>().messages)..load()),
      BlocProvider(create: (_) => ValueCubit<String>('whatsapp')),
    ],
    child: const _MessagesView(),
  );
}

class _MessagesView extends StatefulWidget {
  const _MessagesView();

  @override
  State<_MessagesView> createState() => _MessagesViewState();
}

class _MessagesViewState extends State<_MessagesView> {
  final text = TextEditingController(text: 'Hello {customer}, ');

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> _send(BuildContext context) async {
    final channel = context.read<ValueCubit<String>>().state;
    final repo = context.read<IntegrationsRepository>();
    final list = context.read<ListCubit<MessageEntry>>();
    final ok = await confirmDelete(
      context,
      title: 'Send to all customers?',
      message: 'This sends the message by ${_channelNames[channel]} to every party that has a phone number (up to 500).',
    );
    if (!ok || !context.mounted) return;
    try {
      final r = await repo.marketing(channel, text.text.trim());
      await list.load();
      if (!context.mounted) return;
      if (r.failed.isEmpty) {
        showSuccess(context, 'Sent to ${r.sent} of ${r.recipients}');
      } else {
        showError(context, 'Sent ${r.sent} of ${r.recipients}. First failure: ${r.failed.first}');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => ListCubitView<MessageEntry>(
    builder: (context, state) {
      final channel = context.watch<ValueCubit<String>>().state;
      return TitledPage(
        title: 'Messages',
        subtitle: 'Everything sent from the app through WhatsApp and SMS.',
        actions: [OutlinedButton(onPressed: () => context.push('/integrations'), child: const Text('Integrations'))],
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Message all customers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text(
                    'WhatsApp only delivers a first message to customers through a template Meta has approved (set its name in the WhatsApp integration). SMS in India needs a DLT-approved template.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [ButtonSegment(value: 'whatsapp', label: Text('WhatsApp')), ButtonSegment(value: 'sms', label: Text('SMS'))],
                    selected: {channel},
                    onSelectionChanged: (v) => context.read<ValueCubit<String>>().set(v.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: text, minLines: 2, maxLines: 5, maxLength: 500, decoration: const InputDecoration(labelText: 'Message', helperText: 'Use {customer} and {business} to personalise.')),
                  FilledButton.icon(onPressed: () => _send(context), icon: const Icon(Icons.send, size: 18), label: const Text('Send')),
                ],
              ),
            ),
          ),
          RowsCard(
            empty: const EmptyState(icon: Icons.forum_outlined, title: 'Nothing sent yet', message: 'Messages you send show up here, with any error the provider gave.'),
            rows: [
              for (final m in state.items)
                ListTile(
                  leading: Icon(m.channel == 'sms' ? Icons.sms_outlined : Icons.chat_outlined, color: m.ok ? receiveGreen : payRed),
                  title: Text('${m.partyName ?? m.to} · ${m.kind}'),
                  subtitle: Text(m.ok ? m.body : '${m.error ?? 'Failed'}\n${m.body}', maxLines: 3, overflow: TextOverflow.ellipsis),
                  trailing: Text('${displayDate(isoDate(m.createdAt))}\n${TimeOfDay.fromDateTime(m.createdAt).format(context)}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ],
      );
    },
  );
}

// ================================================================ Google Business Profile

class GoogleProfileScreen extends StatelessWidget {
  const GoogleProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (ctx) => GoogleProfileCubit(ctx.read())..load(),
    child: BlocConsumer<GoogleProfileCubit, GoogleProfileState>(
      listenWhen: (a, b) => a.rev != b.rev,
      listener: (context, s) {
        if (s.error != null) showError(context, s.error!);
        if (s.message != null) showSuccess(context, s.message!);
      },
      builder: (context, s) => switch (s.stage) {
        GoogleStage.loading => const Center(child: CircularProgressIndicator()),
        GoogleStage.failure => ErrorRetry(error: s.error ?? 'Could not load', onRetry: context.read<GoogleProfileCubit>().load),
        GoogleStage.notConnected => TitledPage(
          title: 'Google Business Profile',
          children: [
            Card(
              child: SizedBox(
                height: 300,
                child: EmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'Connect your Google listing',
                  message: 'Update your business details, post offers and answer reviews from here. You sign in with Google; the app never sees your password.',
                  action: FilledButton(
                    onPressed: () async {
                      try {
                        final url = await context.read<GoogleProfileCubit>().authUrl();
                        if (!await launchUrl(Uri.parse(url), webOnlyWindowName: '_self') && context.mounted) showError(context, 'Could not open Google.');
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      }
                    },
                    child: const Text('Connect with Google'),
                  ),
                ),
              ),
            ),
          ],
        ),
        GoogleStage.pickLocation => TitledPage(
          title: 'Choose your business',
          subtitle: 'Signed in as ${s.email ?? 'Google'}. Pick the listing to manage.',
          children: [
            RowsCard(
              empty: const EmptyState(icon: Icons.storefront_outlined, title: 'No listings found', message: 'This Google account does not manage any business listing.'),
              rows: [
                for (final l in s.locations)
                  ListTile(
                    title: Text(l.title),
                    subtitle: l.address == null ? null : Text(l.address!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.read<GoogleProfileCubit>().choose(l),
                  ),
              ],
            ),
          ],
        ),
        GoogleStage.ready => _GoogleReady(state: s),
      },
    ),
  );
}

class _GoogleReady extends StatelessWidget {
  const _GoogleReady({required this.state});
  final GoogleProfileState state;

  Future<void> _reply(BuildContext context, GoogleReview r) async {
    final cubit = context.read<GoogleProfileCubit>();
    final c = TextEditingController(text: r.reply ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reply to ${r.name}'),
        content: SizedBox(width: 380, child: TextField(controller: c, autofocus: true, minLines: 3, maxLines: 6, maxLength: 4000)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Post reply')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) await cubit.reply(r.id, c.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GoogleProfileCubit>();
    final reviews = state.reviews;
    return TitledPage(
      title: state.profile?.title.isNotEmpty == true ? state.profile!.title : 'Google Business Profile',
      subtitle: 'Signed in as ${state.email ?? 'Google'}',
      actions: [TextButton(onPressed: state.busy ? null : cubit.disconnect, child: const Text('Disconnect'))],
      children: [
        _ProfileForm(key: ValueKey(state.profile), profile: state.profile!, busy: state.busy, onSave: cubit.saveProfile),
        _PostForm(busy: state.busy, onPost: cubit.post),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reviews == null ? 'Reviews' : 'Reviews · ${reviews.average?.toStringAsFixed(1) ?? '-'} ★ from ${reviews.total}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                if (reviews == null || reviews.reviews.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No reviews yet.', style: TextStyle(color: Colors.black54))),
                for (final r in reviews?.reviews ?? const <GoogleReview>[])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${r.name} · ${'★' * r.stars}${'☆' * (5 - r.stars)}'),
                    subtitle: Text([if (r.comment.isNotEmpty) r.comment, if (r.reply != null) 'Your reply: ${r.reply}'].join('\n')),
                    trailing: TextButton(onPressed: state.busy ? null : () => _reply(context, r), child: Text(r.reply == null ? 'Reply' : 'Edit reply')),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({super.key, required this.profile, required this.busy, required this.onSave});
  final GoogleProfileInfo profile;
  final bool busy;
  final void Function(String description, String website) onSave;

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  late final description = TextEditingController(text: widget.profile.description);
  late final website = TextEditingController(text: widget.profile.website);

  @override
  void dispose() {
    description.dispose();
    website.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Business details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (widget.profile.phone.isNotEmpty) Text('Phone ${widget.profile.phone}', style: const TextStyle(color: Colors.black54)),
          TextField(controller: description, minLines: 2, maxLines: 6, maxLength: 750, decoration: const InputDecoration(labelText: 'Description')),
          TextField(controller: website, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Website')),
          const SizedBox(height: 8),
          FilledButton(onPressed: widget.busy ? null : () => widget.onSave(description.text.trim(), website.text.trim()), child: const Text('Save')),
        ],
      ),
    ),
  );
}

class _PostForm extends StatefulWidget {
  const _PostForm({required this.busy, required this.onPost});
  final bool busy;
  final void Function(String summary, String url) onPost;

  @override
  State<_PostForm> createState() => _PostFormState();
}

class _PostFormState extends State<_PostForm> {
  final summary = TextEditingController();
  final url = TextEditingController();

  @override
  void dispose() {
    summary.dispose();
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Post an update', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          TextField(controller: summary, minLines: 2, maxLines: 6, maxLength: 1500, decoration: const InputDecoration(labelText: 'What’s new')),
          TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Learn-more link (optional)')),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: widget.busy
                ? null
                : () {
                    if (summary.text.trim().isEmpty) return showError(context, 'Write what you want to post.');
                    widget.onPost(summary.text.trim(), url.text.trim());
                    summary.clear();
                    url.clear();
                  },
            child: const Text('Post'),
          ),
        ],
      ),
    ),
  );
}
