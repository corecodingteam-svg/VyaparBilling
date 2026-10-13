import 'dart:typed_data';

import 'transport.dart';

/// Browsers cannot open raw sockets, so a network printer is only offered in the mobile and desktop apps.
class NetworkTransport implements ReceiptTransport {
  NetworkTransport({required this.host, this.port = 9100});

  final String host;
  final int port;

  @override
  String get label => 'Network printer ($host)';

  @override
  bool get available => false;

  @override
  Future<void> send(Uint8List bytes) async => throw PrinterException('A network printer needs the mobile or desktop app; a browser cannot reach it.');
}
