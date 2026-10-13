import 'dart:typed_data';

/// A way to send raw bytes to a receipt printer.
abstract class ReceiptTransport {
  /// Shown on the button, e.g. "USB printer".
  String get label;

  /// Whether this device can use it at all (a browser without WebUSB cannot).
  bool get available;

  /// Sends the bytes. Where the user must pick the printer (browsers), this asks them first.
  /// Throws a [PrinterException] with a readable message on failure.
  Future<void> send(Uint8List bytes);
}

class PrinterException implements Exception {
  PrinterException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Bytes are sent in pieces so a slow printer's buffer is not overrun.
const printChunkSize = 4096;
