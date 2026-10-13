import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billing_app/shared/export.dart';

void main() {
  test('xlsx has the header, numbers stay numeric and text is escaped', () {
    final bytes = buildXlsx(const TableExport(title: 'Sale Invoices', headers: ['Party', 'Amount'], rows: [
      ['A & B <Co>', 1250.5],
      ['Plain', null],
    ]));
    final zip = ZipDecoder().decodeBytes(bytes);
    String read(String name) => String.fromCharCodes(zip.findFile(name)!.content as List<int>);
    final sheet = read('xl/worksheets/sheet1.xml');
    expect(sheet, contains('A &amp; B &lt;Co&gt;'));
    expect(sheet, contains('<c r="B2"><v>1250.5</v></c>'));
    expect(sheet, contains('<c r="A1" s="1" t="inlineStr">'));
    expect(read('xl/workbook.xml'), contains('name="Sale Invoices"'));
  });

  test('file name is a safe slug', () {
    expect(const TableExport(title: 'Sale Invoices / 2026', headers: [], rows: []).fileBase, 'sale-invoices-2026');
  });
}
