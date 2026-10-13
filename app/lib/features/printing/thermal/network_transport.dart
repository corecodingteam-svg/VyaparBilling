import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'transport.dart';

/// A receipt printer on the local network, reached over raw TCP (port 9100, the usual printer port).
/// Works in the mobile and desktop apps; browsers cannot open raw sockets.
class NetworkTransport implements ReceiptTransport {
  NetworkTransport({required this.host, this.port = 9100, this.timeout = const Duration(seconds: 6)});

  final String host;
  final int port;
  final Duration timeout;

  @override
  String get label => 'Network printer ($host)';

  @override
  bool get available => true;

  @override
  Future<void> send(Uint8List bytes) async {
    Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
    } on SocketException catch (e) {
      throw PrinterException(
        'Could not reach the printer at $host:$port (${e.osError?.message ?? e.message}). Check its IP address and that it is on.',
      );
    } on TimeoutException {
      throw PrinterException('The printer at $host:$port did not answer. Check its IP address and that it is on.');
    }
    try {
      for (var i = 0; i < bytes.length; i += printChunkSize) {
        socket.add(Uint8List.sublistView(bytes, i, i + printChunkSize > bytes.length ? bytes.length : i + printChunkSize));
      }
      await socket.flush().timeout(timeout);
    } on Exception catch (e) {
      throw PrinterException('Sending to the printer failed: $e');
    } finally {
      await socket.close();
      socket.destroy();
    }
  }
}
