Checks the browser printer code (WebUSB / Web Serial in `lib/features/printing/thermal/platform_transports_web.dart`)
against fake browser APIs, run under Node. It is a separate project because it needs plain Dart, not Flutter:

    cd web_printer_test && dart pub get && dart test -p node

Not covered: real printers and real browsers.
