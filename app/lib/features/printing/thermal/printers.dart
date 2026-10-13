import 'dart:typed_data';

import 'network_transport_stub.dart' if (dart.library.io) 'network_transport.dart';
import 'platform_transports_io.dart' if (dart.library.js_interop) 'platform_transports_web.dart';
import 'transport.dart';

export 'platform_transports_io.dart' if (dart.library.js_interop) 'platform_transports_web.dart' show supportsNetworkPrinter;
export 'bluetooth.dart';
export 'bluetooth_stub.dart' if (dart.library.io) 'bluetooth_io.dart' show BluetoothTransport, bluetoothSupported, scanBluetoothPrinters;
export 'transport.dart';

/// Every way this device can reach a receipt printer, given the saved network printer address (if any).
List<ReceiptTransport> availableTransports({String? networkHost, int networkPort = 9100}) => [
  if (supportsNetworkPrinter && networkHost != null && networkHost.isNotEmpty) NetworkTransport(host: networkHost, port: networkPort),
  ...platformTransports().where((t) => t.available),
];

/// A network printer for [host] ("192.168.1.50" or "192.168.1.50:9100").
ReceiptTransport networkPrinter(String host) {
  final parts = host.trim().split(':');
  return NetworkTransport(host: parts.first, port: parts.length > 1 ? int.tryParse(parts[1]) ?? 9100 : 9100);
}

Future<void> sendToPrinter(ReceiptTransport transport, Uint8List bytes) => transport.send(bytes);
