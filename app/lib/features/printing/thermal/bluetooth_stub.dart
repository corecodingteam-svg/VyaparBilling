import 'dart:typed_data';

import 'bluetooth.dart';
import 'transport.dart';

/// Browsers talk to Bluetooth printers through Web Serial (see the serial printer); this is for the phone apps.
const bluetoothSupported = false;

Stream<List<BluetoothPrinterInfo>> scanBluetoothPrinters() => const Stream.empty();

class BluetoothTransport implements ReceiptTransport {
  BluetoothTransport(this.printer);
  final BluetoothPrinterInfo printer;

  @override
  String get label => 'Bluetooth: ${printer.name}';

  @override
  bool get available => false;

  @override
  Future<void> send(Uint8List bytes) => throw PrinterException('Bluetooth printing is for the phone apps.');
}
