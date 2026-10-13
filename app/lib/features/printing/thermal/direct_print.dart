import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/api_client.dart';
import '../../../core/status.dart';
import '../../../shared/widgets.dart';
import 'printers.dart';

/// The network printer's address, remembered on this device (it belongs to the device, not the company).
class PrinterStore {
  PrinterStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'receipt_printer_host';

  Future<String?> host() => _storage.read(key: _key);
  Future<void> saveHost(String host) => _storage.write(key: _key, value: host.trim());
  Future<void> clear() => _storage.delete(key: _key);
}

class DirectPrintState extends Equatable {
  const DirectPrintState({this.host = '', this.status = SubmitStatus.idle, this.message, this.rev = 0});
  final String host;
  final SubmitStatus status;

  /// What happened, shown once ([rev] changes with every result).
  final String? message;
  final int rev;

  @override
  List<Object?> get props => [host, status, message, rev];
}

/// Sends a receipt to a printer chosen by the user.
class DirectPrintCubit extends Cubit<DirectPrintState> {
  DirectPrintCubit(this._store) : super(const DirectPrintState());
  final PrinterStore _store;

  Future<void> load() async {
    final host = await _store.host();
    if (!isClosed && host != null) emit(DirectPrintState(host: host));
  }

  Future<void> saveHost(String host) async {
    await _store.saveHost(host);
    emit(DirectPrintState(host: host.trim(), rev: state.rev));
  }

  Future<void> print(ReceiptTransport transport, Future<Uint8List> Function() build) async {
    if (state.status == SubmitStatus.submitting) return;
    emit(DirectPrintState(host: state.host, status: SubmitStatus.submitting, rev: state.rev));
    try {
      await transport.send(await build());
      emit(DirectPrintState(host: state.host, status: SubmitStatus.success, message: 'Sent to the printer', rev: state.rev + 1));
    } catch (e) {
      emit(
        DirectPrintState(
          host: state.host,
          status: SubmitStatus.failure,
          message: e is PrinterException ? e.message : ApiException.from(e).message,
          rev: state.rev + 1,
        ),
      );
    }
  }
}

/// Button that prints a receipt straight to a thermal printer. [makeBytes] makes the ESC/POS bytes.
class DirectPrintButton extends StatelessWidget {
  const DirectPrintButton({super.key, required this.makeBytes});
  final Future<Uint8List> Function() makeBytes;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => DirectPrintCubit(PrinterStore())..load(),
    child: BlocConsumer<DirectPrintCubit, DirectPrintState>(
      listenWhen: (a, b) => a.rev != b.rev && b.message != null,
      listener: (context, s) => s.status == SubmitStatus.failure ? showError(context, s.message!) : showSuccess(context, s.message!),
      builder: (context, s) => TextButton.icon(
        onPressed: s.status == SubmitStatus.submitting ? null : () => _choose(context, s),
        icon: s.status == SubmitStatus.submitting
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.receipt_long_outlined),
        label: const Text('Print to Receipt Printer'),
      ),
    ),
  );

  Future<void> _choose(BuildContext context, DirectPrintState s) async {
    final cubit = context.read<DirectPrintCubit>();
    final picked = await showDialog<ReceiptTransport>(
      context: context,
      builder: (_) => BlocProvider.value(value: cubit, child: const _PrinterChoice()),
    );
    if (picked != null) cubit.print(picked, makeBytes);
  }
}

class _PrinterChoice extends StatefulWidget {
  const _PrinterChoice();

  @override
  State<_PrinterChoice> createState() => _PrinterChoiceState();
}

/// Stateful only to own the address field's controller.
class _PrinterChoiceState extends State<_PrinterChoice> {
  late final _host = TextEditingController(text: context.read<DirectPrintCubit>().state.host);

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DirectPrintCubit>();
    return BlocBuilder<DirectPrintCubit, DirectPrintState>(
      builder: (context, s) {
        final transports = availableTransports();
        return AlertDialog(
          title: const Text('Print to a receipt printer'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (supportsNetworkPrinter) ...[
                  const Text('Network printer', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _host,
                    decoration: const InputDecoration(
                      labelText: 'Printer address',
                      hintText: '192.168.1.50  or  192.168.1.50:9100',
                      helperText: 'Remembered on this device',
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () async {
                      final host = _host.text.trim();
                      if (host.isEmpty) return;
                      await cubit.saveHost(host);
                      if (context.mounted) Navigator.pop(context, networkPrinter(host));
                    },
                    child: const Text('Print'),
                  ),
                ],
                for (final t in transports) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: () => Navigator.pop(context, t), icon: const Icon(Icons.usb), label: Text(t.label)),
                ],
                if (!supportsNetworkPrinter && transports.isEmpty)
                  const Text(
                    'This browser cannot talk to a printer directly. Use Chrome or Edge on a computer (USB or serial printers), '
                    'the mobile or desktop app (network printers), or use the normal Print button.',
                  ),
                if (!supportsNetworkPrinter && transports.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Your browser will ask which printer to use. USB printers must not be claimed by another program.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
        );
      },
    );
  }
}
