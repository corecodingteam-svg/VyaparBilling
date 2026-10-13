import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'transport.dart';

const supportsNetworkPrinter = false;

List<ReceiptTransport> platformTransports() => [UsbTransport(), SerialTransport()];

JSObject? _navigatorMember(String name) {
  final navigator = globalContext.getProperty<JSObject?>('navigator'.toJS);
  if (navigator == null || !navigator.has(name)) return null;
  return navigator.getProperty<JSObject?>(name.toJS);
}

/// Calls a method that returns a promise and waits for it.
Future<JSAny?> _call(JSObject target, String method, [List<JSAny?> args = const []]) async {
  final result = target.callMethodVarArgs<JSAny?>(method.toJS, args);
  if (result.isA<JSPromise>()) return await (result as JSPromise).toDart;
  return result;
}

JSObject _object(Map<String, JSAny?> fields) {
  final o = JSObject();
  fields.forEach((k, v) => o.setProperty(k.toJS, v));
  return o;
}

/// Whether the user closed the browser's "choose a device" window without choosing.
bool _cancelled(Object e) =>
    e.toString().contains('NotFoundError') || e.toString().contains('No device selected') || e.toString().contains('No port selected');

/// A USB receipt printer, through the browser's WebUSB (Chrome and Edge, over HTTPS).
class UsbTransport implements ReceiptTransport {
  @override
  String get label => 'USB printer';

  @override
  bool get available => _navigatorMember('usb') != null;

  @override
  Future<void> send(Uint8List bytes) async {
    final usb = _navigatorMember('usb');
    if (usb == null) throw PrinterException('This browser cannot print over USB. Use Chrome or Edge, or print through the browser instead.');
    JSObject device;
    try {
      // An empty filter list shows every USB device; printers do not all announce themselves as printers.
      device =
          (await _call(usb, 'requestDevice', [
                _object({'filters': <JSAny?>[].toJS}),
              ]))!
              as JSObject;
    } catch (e) {
      throw PrinterException(_cancelled(e) ? 'No printer was chosen.' : 'Could not open the USB device list: $e');
    }
    try {
      await _call(device, 'open');
      if (device.getProperty<JSAny?>('configuration'.toJS).isNull) await _call(device, 'selectConfiguration', [1.toJS]);
      final config = device.getProperty<JSObject>('configuration'.toJS);
      int? interfaceNumber;
      int? endpoint;
      for (final iface in (config.getProperty<JSArray<JSObject>>('interfaces'.toJS)).toDart) {
        final alternates = iface.getProperty<JSArray<JSObject>>('alternates'.toJS).toDart;
        for (final alt in alternates) {
          for (final ep in alt.getProperty<JSArray<JSObject>>('endpoints'.toJS).toDart) {
            final isOut = ep.getProperty<JSString>('direction'.toJS).toDart == 'out';
            final isBulk = ep.getProperty<JSString>('type'.toJS).toDart == 'bulk';
            if (isOut && isBulk && interfaceNumber == null) {
              interfaceNumber = iface.getProperty<JSNumber>('interfaceNumber'.toJS).toDartInt;
              endpoint = ep.getProperty<JSNumber>('endpointNumber'.toJS).toDartInt;
            }
          }
        }
      }
      if (interfaceNumber == null || endpoint == null) {
        throw PrinterException('This USB device has no printing channel. Is it a receipt printer?');
      }
      await _call(device, 'claimInterface', [interfaceNumber.toJS]);
      for (var i = 0; i < bytes.length; i += printChunkSize) {
        final end = i + printChunkSize > bytes.length ? bytes.length : i + printChunkSize;
        await _call(device, 'transferOut', [endpoint.toJS, Uint8List.sublistView(bytes, i, end).toJS]);
      }
    } on PrinterException {
      rethrow;
    } catch (e) {
      throw PrinterException(
        'Printing over USB failed: $e. If another program is using the printer (or the system driver has claimed it), close it and try again.',
      );
    } finally {
      try {
        await _call(device, 'close');
      } catch (_) {}
    }
  }
}

/// A serial (COM / Bluetooth-serial) receipt printer, through the browser's Web Serial (Chrome and Edge, over HTTPS).
class SerialTransport implements ReceiptTransport {
  @override
  String get label => 'Serial / Bluetooth printer';

  @override
  bool get available => _navigatorMember('serial') != null;

  @override
  Future<void> send(Uint8List bytes) async {
    final serial = _navigatorMember('serial');
    if (serial == null) {
      throw PrinterException('This browser cannot print over a serial port. Use Chrome or Edge, or print through the browser instead.');
    }
    JSObject port;
    try {
      port = (await _call(serial, 'requestPort'))! as JSObject;
    } catch (e) {
      throw PrinterException(_cancelled(e) ? 'No printer was chosen.' : 'Could not open the port list: $e');
    }
    try {
      await _call(port, 'open', [
        _object({'baudRate': 9600.toJS}),
      ]);
      final writer = port.getProperty<JSObject>('writable'.toJS).callMethodVarArgs<JSObject>('getWriter'.toJS, const []);
      try {
        for (var i = 0; i < bytes.length; i += printChunkSize) {
          final end = i + printChunkSize > bytes.length ? bytes.length : i + printChunkSize;
          await _call(writer, 'write', [Uint8List.sublistView(bytes, i, end).toJS]);
        }
      } finally {
        writer.callMethodVarArgs<JSAny?>('releaseLock'.toJS, const []);
      }
    } catch (e) {
      throw PrinterException('Printing over the serial port failed: $e');
    } finally {
      try {
        await _call(port, 'close');
      } catch (_) {}
    }
  }
}
