import 'dart:convert';
import 'dart:typed_data';

/// A Bluetooth receipt printer: [classic] ones are paired in the phone's settings (Android only); the rest
/// are Bluetooth Low Energy and are found by scanning. [id] is a MAC address or, on iOS, the device's UUID.
class BluetoothPrinterInfo {
  const BluetoothPrinterInfo({required this.id, required this.name, required this.classic});

  factory BluetoothPrinterInfo.fromJson(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return BluetoothPrinterInfo(id: j['id'] as String, name: j['name'] as String, classic: j['classic'] as bool);
  }

  final String id;
  final String name;
  final bool classic;

  String toJson() => jsonEncode({'id': id, 'name': name, 'classic': classic});

  @override
  bool operator ==(Object other) => other is BluetoothPrinterInfo && other.id == id && other.classic == classic;

  @override
  int get hashCode => Object.hash(id, classic);
}

/// What a Bluetooth Low Energy characteristic can do, as far as printing is concerned.
class BleCharacteristicInfo {
  const BleCharacteristicInfo(this.uuid, {required this.write, required this.writeWithoutResponse});
  final String uuid;
  final bool write;
  final bool writeWithoutResponse;
}

class BleServiceInfo {
  const BleServiceInfo(this.uuid, this.characteristics);
  final String uuid;
  final List<BleCharacteristicInfo> characteristics;
}

/// Services that the common receipt printers (and their bundled chips) use for print data.
const _printerServices = ['18f0', 'e7810a71-73ae-499d-8c15-faa9aef0c3f2', '49535343-fe7d-4ae5-8fa9-9fafd205e455', 'ff00', 'fff0', 'ffe0'];

String _short(String uuid) {
  final u = uuid.toLowerCase();
  // 128-bit Bluetooth base UUIDs shorten to their 16-bit form.
  final m = RegExp(r'^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$').firstMatch(u);
  return m?.group(1) ?? u;
}

/// The (service, characteristic) to write print data to: a writable one in a known printer service if
/// there is one, otherwise the first writable one. Prefers writing without waiting for a reply, which is faster.
(String, String)? pickWriteCharacteristic(List<BleServiceInfo> services) {
  (String, String)? best;
  var bestScore = 0;
  for (final s in services) {
    final known = _printerServices.contains(_short(s.uuid));
    for (final c in s.characteristics) {
      if (!c.write && !c.writeWithoutResponse) continue;
      final score = (known ? 2 : 1) * 10 + (c.writeWithoutResponse ? 1 : 0);
      if (score > bestScore) {
        bestScore = score;
        best = (s.uuid, c.uuid);
      }
    }
  }
  return best;
}

/// [bytes] cut into pieces of at most [size] bytes.
List<Uint8List> splitBytes(Uint8List bytes, int size) => [
  for (var i = 0; i < bytes.length; i += size) Uint8List.sublistView(bytes, i, i + size > bytes.length ? bytes.length : i + size),
];

/// How many bytes to write at once: what the connection allows (MTU less the 3 bytes of overhead),
/// kept modest because many printers' buffers are small.
int bleChunkSize(int mtu) => (mtu - 3).clamp(20, 180);
