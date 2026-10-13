@TestOn('node')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:test/test.dart';
import '../../lib/features/printing/thermal/platform_transports_web.dart';
import '../../lib/features/printing/thermal/transport.dart';

/// Installs fake WebUSB / Web Serial objects that record what is written to them.
void install({bool usb = true, bool serial = true, bool cancel = false}) {
  globalContext.callMethod<JSAny?>('eval'.toJS, '''
    globalThis.__log = [];
    const fakeNav = {};
    if ($usb) {
      fakeNav.usb = {
        requestDevice: async (opts) => {
          __log.push(['requestDevice', JSON.stringify(opts)]);
          if ($cancel) { const e = new Error('No device selected.'); e.name = 'NotFoundError'; throw e; }
          return {
            configuration: null,
            open: async () => __log.push(['open']),
            selectConfiguration: async (n) => __log.push(['selectConfiguration', n]),
            claimInterface: async (n) => __log.push(['claimInterface', n]),
            transferOut: async (ep, data) => { __log.push(['transferOut', ep, Array.from(data)]); return {status: 'ok'}; },
            close: async () => __log.push(['close']),
          };
        },
      };
    }
    if ($serial) {
      fakeNav.serial = {
        requestPort: async () => {
          if ($cancel) { const e = new Error('No port selected by the user.'); e.name = 'NotFoundError'; throw e; }
          return {
            open: async (o) => __log.push(['serialOpen', o.baudRate]),
            writable: { getWriter: () => ({ write: async (d) => __log.push(['serialWrite', Array.from(d)]), releaseLock: () => __log.push(['releaseLock']) }) },
            close: async () => __log.push(['serialClose']),
          };
        },
      };
    }
    Object.defineProperty(globalThis, 'navigator', { value: fakeNav, configurable: true });
  '''.toJS);
}

List<List<Object?>> log() =>
    ((globalContext.getProperty<JSArray<JSArray<JSAny?>>>('__log'.toJS)).toDart).map((e) => e.toDart.map((v) => v.dartify()).toList()).toList();

void main() {
  test('USB: lists devices, picks the bulk-out endpoint, claims the interface and writes in order', () async {
    install();
    // After open(), the device reports its configuration (as WebUSB does after selectConfiguration).
    globalContext.callMethod<JSAny?>('eval'.toJS, '''
      const origRequest = navigator.usb.requestDevice;
      navigator.usb.requestDevice = async (o) => {
        const d = await origRequest(o);
        const origOpen = d.open;
        d.open = async () => { await origOpen(); };
        const origSelect = d.selectConfiguration;
        d.selectConfiguration = async (n) => {
          await origSelect(n);
          d.configuration = { interfaces: [
            { interfaceNumber: 0, alternates: [{ endpoints: [{ direction: 'in', type: 'bulk', endpointNumber: 1 }] }] },
            { interfaceNumber: 2, alternates: [{ endpoints: [{ direction: 'out', type: 'interrupt', endpointNumber: 3 }, { direction: 'out', type: 'bulk', endpointNumber: 5 }] }] },
          ] };
        };
        return d;
      };
    '''.toJS);
    final bytes = Uint8List.fromList(List.generate(9000, (i) => i % 256));
    expect(UsbTransport().available, isTrue);
    await UsbTransport().send(bytes);
    final l = log();
    expect(l.first, ['requestDevice', '{"filters":[]}']);
    expect(l.map((e) => e.first), ['requestDevice', 'open', 'selectConfiguration', 'claimInterface', 'transferOut', 'transferOut', 'transferOut', 'close']);
    expect(l[3], ['claimInterface', 2]);
    final writes = l.where((e) => e.first == 'transferOut').toList();
    expect(writes.every((w) => w[1] == 5), isTrue, reason: 'bulk-out endpoint, not the interrupt one');
    expect(writes.expand((w) => (w[2] as List)).toList(), bytes);
    expect(writes.map((w) => (w[2] as List).length), [4096, 4096, 808]);
  });

  test('serial: opens the port, writes everything and releases it', () async {
    install();
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    await SerialTransport().send(bytes);
    expect(log().map((e) => e.first), ['serialOpen', 'serialWrite', 'releaseLock', 'serialClose']);
    expect(log()[0][1], 9600);
    expect(log()[1][1], [1, 2, 3, 4, 5]);
  });

  test('a browser without WebUSB or Web Serial is reported as unavailable, with a readable error', () async {
    install(usb: false, serial: false);
    expect([UsbTransport().available, SerialTransport().available], [false, false]);
    await expectLater(UsbTransport().send(Uint8List(1)), throwsA(isA<PrinterException>().having((e) => e.message, 'm', contains('Chrome or Edge'))));
    await expectLater(SerialTransport().send(Uint8List(1)), throwsA(isA<PrinterException>().having((e) => e.message, 'm', contains('Chrome or Edge'))));
  });

  test('closing the browser\'s chooser is "no printer chosen", not a crash', () async {
    install(cancel: true);
    await expectLater(UsbTransport().send(Uint8List(1)), throwsA(isA<PrinterException>().having((e) => e.message, 'm', 'No printer was chosen.')));
    await expectLater(SerialTransport().send(Uint8List(1)), throwsA(isA<PrinterException>().having((e) => e.message, 'm', 'No printer was chosen.')));
  });
}
