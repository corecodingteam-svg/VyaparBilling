import 'transport.dart';

/// Transports besides the network printer: none on mobile and desktop.
List<ReceiptTransport> platformTransports() => const [];

/// Raw TCP sockets exist here.
const supportsNetworkPrinter = true;
