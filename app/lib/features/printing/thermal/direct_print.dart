import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/api_client.dart';
import '../../../core/status.dart';
import '../../../shared/theme.dart';
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

  static const _bluetoothKey = 'receipt_printer_bluetooth';

  /// The Bluetooth printer chosen on this device, if any.
  Future<BluetoothPrinterInfo?> bluetooth() async {
    final json = await _storage.read(key: _bluetoothKey);
    if (json == null) return null;
    try {
      return BluetoothPrinterInfo.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveBluetooth(BluetoothPrinterInfo printer) => _storage.write(key: _bluetoothKey, value: printer.toJson());
}

class DirectPrintState extends Equatable {
  const DirectPrintState({this.host = '', this.bluetooth, this.status = SubmitStatus.idle, this.message, this.rev = 0});
  final String host;

  /// The Bluetooth printer chosen on this device.
  final BluetoothPrinterInfo? bluetooth;
  final SubmitStatus status;

  /// What happened, shown once ([rev] changes with every result).
  final String? message;
  final int rev;

  @override
  List<Object?> get props => [host, bluetooth, status, message, rev];
}

/// Sends a receipt to a printer chosen by the user.
class DirectPrintCubit extends Cubit<DirectPrintState> {
  DirectPrintCubit(this._store) : super(const DirectPrintState());
  final PrinterStore _store;

  Future<void> load() async {
    final (host, bluetooth) = await (_store.host(), _store.bluetooth()).wait;
    if (!isClosed && (host != null || bluetooth != null)) emit(DirectPrintState(host: host ?? '', bluetooth: bluetooth));
  }

  Future<void> saveBluetooth(BluetoothPrinterInfo printer) async {
    await _store.saveBluetooth(printer);
    emit(DirectPrintState(host: state.host, bluetooth: printer, rev: state.rev));
  }

  Future<void> saveHost(String host) async {
    await _store.saveHost(host);
    emit(DirectPrintState(host: host.trim(), bluetooth: state.bluetooth, rev: state.rev));
  }

  Future<void> print(ReceiptTransport transport, Future<Uint8List> Function() build) async {
    if (state.status == SubmitStatus.submitting) return;
    emit(DirectPrintState(host: state.host, bluetooth: state.bluetooth, status: SubmitStatus.submitting, rev: state.rev));
    try {
      await transport.send(await build());
      emit(DirectPrintState(host: state.host, bluetooth: state.bluetooth, status: SubmitStatus.success, message: 'Sent to the printer', rev: state.rev + 1));
    } catch (e) {
      emit(
        DirectPrintState(
          host: state.host,
          bluetooth: state.bluetooth,
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
                if (bluetoothSupported) ...[
                  const SizedBox(height: 16),
                  const Text('Bluetooth printer', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (s.bluetooth != null)
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context, BluetoothTransport(s.bluetooth!)),
                      icon: const Icon(Icons.bluetooth),
                      label: Text('Print to ${s.bluetooth!.name}'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDialog<BluetoothPrinterInfo>(context: context, builder: (_) => const _BluetoothPicker());
                      if (picked == null) return;
                      await cubit.saveBluetooth(picked);
                      if (context.mounted) Navigator.pop(context, BluetoothTransport(picked));
                    },
                    icon: const Icon(Icons.bluetooth_searching),
                    label: Text(s.bluetooth == null ? 'Choose a Bluetooth printer' : 'Choose another'),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Switch the printer on first. Printers that need a PIN must be paired in the phone’s Bluetooth settings (Android); they then show up in the list.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
                for (final t in transports) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: () => Navigator.pop(context, t), icon: const Icon(Icons.usb), label: Text(t.label)),
                ],
                if (!supportsNetworkPrinter && !bluetoothSupported && transports.isEmpty)
                  const Text(
                    'This browser cannot talk to a printer directly. Use Chrome or Edge on a computer (USB or serial printers), '
                    'the mobile or desktop app (network printers), or use the normal Print button.',
                  ),
                if (!supportsNetworkPrinter && !bluetoothSupported && transports.isNotEmpty)
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


// ---------------------------------------------------------------- picking a Bluetooth printer

class _ScanState extends Equatable {
  const _ScanState({this.printers = const [], this.scanning = true, this.error});
  final List<BluetoothPrinterInfo> printers;
  final bool scanning;
  final String? error;

  @override
  List<Object?> get props => [printers, scanning, error];
}

/// Looks for Bluetooth printers and keeps the list current while the scan runs.
class _ScanCubit extends Cubit<_ScanState> {
  _ScanCubit(this._scan) : super(const _ScanState()) {
    scan();
  }
  final Stream<List<BluetoothPrinterInfo>> Function() _scan;
  StreamSubscription<List<BluetoothPrinterInfo>>? _sub;

  void scan() {
    _sub?.cancel();
    emit(_ScanState(printers: state.printers));
    _sub = _scan().listen(
      (list) => emit(_ScanState(printers: list)),
      onError: (Object e) => emit(_ScanState(printers: state.printers, scanning: false, error: e.toString())),
      onDone: () {
        if (!isClosed && state.error == null) emit(_ScanState(printers: state.printers, scanning: false));
      },
    );
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}

class _BluetoothPicker extends StatelessWidget {
  const _BluetoothPicker();

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => _ScanCubit(scanBluetoothPrinters),
    child: BlocBuilder<_ScanCubit, _ScanState>(
      builder: (context, s) => AlertDialog(
        title: const Text('Choose a Bluetooth printer'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s.scanning) const LinearProgressIndicator(),
              if (s.error != null) Padding(padding: const EdgeInsets.all(8), child: Text(s.error!, style: const TextStyle(color: payRed))),
              if (!s.scanning && s.error == null && s.printers.isEmpty)
                const Padding(padding: EdgeInsets.all(12), child: Text('No printers found. Switch the printer on, keep it close, and search again.')),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in s.printers)
                      ListTile(
                        leading: Icon(p.classic ? Icons.bluetooth_connected : Icons.bluetooth),
                        title: Text(p.name),
                        subtitle: Text(p.classic ? 'Paired' : 'Bluetooth Low Energy'),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: s.scanning ? null : context.read<_ScanCubit>().scan, child: const Text('Search again')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    ),
  );
}
