import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'bluetooth.dart';
import 'transport.dart';

/// Phones (and Macs) can reach Bluetooth printers directly.
final bool bluetoothSupported = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

bool get _android => defaultTargetPlatform == TargetPlatform.android;

/// Printers in range: those already paired in the phone's settings (Android's classic Bluetooth printers,
/// which most cheap receipt printers are) and Bluetooth Low Energy printers found by a short scan.
/// Each emission is the full list so far; the stream ends when the scan does.
Stream<List<BluetoothPrinterInfo>> scanBluetoothPrinters({Duration duration = const Duration(seconds: 8)}) {
  final found = <String, BluetoothPrinterInfo>{};
  late final StreamController<List<BluetoothPrinterInfo>> out;
  StreamSubscription<List<ScanResult>>? sub;

  void emit() => out.add(found.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  Future<void> run() async {
    try {
      if (_android) {
        try {
          for (final p in await PrintBluetoothThermal.pairedBluetooths) {
            found['classic:${p.macAdress}'] = BluetoothPrinterInfo(id: p.macAdress, name: p.name, classic: true);
          }
          emit();
        } catch (_) {
          // Not allowed to read paired devices, or Bluetooth is off; scanning below reports it.
        }
      }
      if (await FlutterBluePlus.isSupported == false) throw PrinterException('This device does not support Bluetooth.');
      sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
          if (name.isEmpty) continue; // unnamed beacons are never printers
          found['ble:${r.device.remoteId.str}'] = BluetoothPrinterInfo(id: r.device.remoteId.str, name: name, classic: false);
        }
        emit();
      });
      await FlutterBluePlus.startScan(timeout: duration);
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (e) {
      out.addError(e is PrinterException ? e : PrinterException('Could not search for Bluetooth printers: $e. Is Bluetooth on, and allowed for this app?'));
    } finally {
      await sub?.cancel();
      await out.close();
    }
  }

  out = StreamController<List<BluetoothPrinterInfo>>(
    onListen: () => unawaited(run()),
    onCancel: () async {
      await sub?.cancel();
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    },
  );
  return out.stream;
}

/// Sends print data to one chosen Bluetooth printer, classic (Android) or Low Energy.
class BluetoothTransport implements ReceiptTransport {
  BluetoothTransport(this.printer);
  final BluetoothPrinterInfo printer;

  @override
  String get label => 'Bluetooth: ${printer.name}';

  @override
  bool get available => bluetoothSupported;

  @override
  Future<void> send(Uint8List bytes) => printer.classic ? _sendClassic(bytes) : _sendBle(bytes);

  Future<void> _sendClassic(Uint8List bytes) async {
    try {
      if (!await PrintBluetoothThermal.bluetoothEnabled) throw PrinterException('Bluetooth is off. Turn it on and try again.');
      if (!await PrintBluetoothThermal.connect(macPrinterAddress: printer.id)) {
        throw PrinterException('Could not connect to ${printer.name}. Is it switched on, in range and paired?');
      }
      for (final chunk in splitBytes(bytes, printChunkSize)) {
        if (!await PrintBluetoothThermal.writeBytes(chunk)) throw PrinterException('${printer.name} stopped accepting data.');
      }
    } on PrinterException {
      rethrow;
    } catch (e) {
      throw PrinterException('Printing over Bluetooth failed: $e');
    } finally {
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (_) {}
    }
  }

  Future<void> _sendBle(Uint8List bytes) async {
    final device = BluetoothDevice.fromId(printer.id);
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      final services = await device.discoverServices();
      final pick = pickWriteCharacteristic([
        for (final s in services)
          BleServiceInfo(s.uuid.str, [
            for (final c in s.characteristics)
              BleCharacteristicInfo(c.uuid.str, write: c.properties.write, writeWithoutResponse: c.properties.writeWithoutResponse),
          ]),
      ]);
      if (pick == null) throw PrinterException('${printer.name} does not accept print data over Bluetooth Low Energy. Pair it in your phone’s Bluetooth settings and choose it from the paired list.');
      final characteristic = services.firstWhere((s) => s.uuid.str == pick.$1).characteristics.firstWhere((c) => c.uuid.str == pick.$2);
      final withoutResponse = characteristic.properties.writeWithoutResponse;
      final size = bleChunkSize(device.mtuNow);
      for (final chunk in splitBytes(bytes, size)) {
        await characteristic.write(chunk, withoutResponse: withoutResponse);
        // Give a small printer time to move each piece out of its buffer.
        if (withoutResponse) await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    } on PrinterException {
      rethrow;
    } catch (e) {
      throw PrinterException('Printing over Bluetooth failed: $e. Is ${printer.name} switched on, in range and not connected to another phone?');
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }
}
