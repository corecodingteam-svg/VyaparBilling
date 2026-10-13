import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:billing_app/features/utilities/file_readers.dart';
import 'package:billing_app/features/utilities/import_spec.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal .xlsx: a workbook, its relationships, shared strings and one sheet.
Uint8List xlsx(List<List<Object?>> rows, {String sheetFile = 'sheet7.xml'}) {
  final strings = <String>[];
  int s(String v) {
    final i = strings.indexOf(v);
    if (i >= 0) return i;
    strings.add(v);
    return strings.length - 1;
  }

  String col(int i) => String.fromCharCode(65 + i);
  final sheet = StringBuffer('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v == null) continue; // a gap: the cell is simply absent
      final ref = '${col(c)}${r + 1}';
      sheet.write(v is String ? '<c r="$ref" t="s"><v>${s(v)}</v></c>' : '<c r="$ref"><v>$v</v></c>');
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');
  final files = {
    'xl/workbook.xml':
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Items" sheetId="1" r:id="rId9"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId9" Target="worksheets/$sheetFile"/></Relationships>',
    'xl/sharedStrings.xml': '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">${strings.map((x) => '<si><t>${const HtmlEscape().convert(x)}</t></si>').join()}</sst>',
    'xl/worksheets/$sheetFile': sheet.toString(),
  };
  final archive = Archive();
  files.forEach((name, content) => archive.addFile(ArchiveFile.string(name, content)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const tally = '''<?xml version="1.0" encoding="UTF-8"?>
<ENVELOPE><BODY><IMPORTDATA><REQUESTDATA>
<TALLYMESSAGE xmlns:UDF="TallyUDF">
 <GROUP NAME="North Region Debtors"><PARENT>Sundry Debtors</PARENT></GROUP>
 <GROUP NAME="Bank Accounts"><PARENT>Current Assets</PARENT></GROUP>
</TALLYMESSAGE>
<TALLYMESSAGE>
 <LEDGER NAME="Ravi Traders &amp; Sons" RESERVEDNAME="">
  <PARENT>North Region Debtors</PARENT>
  <OPENINGBALANCE>-5000.00</OPENINGBALANCE>
  <PARTYGSTIN>27AAACR1234C1Z5</PARTYGSTIN>
  <LEDSTATENAME>Maharashtra</LEDSTATENAME>
  <EMAIL>ravi@example.com</EMAIL>
  <LEDGERMOBILE>+91 98765-43210</LEDGERMOBILE>
  <LEDMAILINGDETAILS.LIST><ADDRESS.LIST><ADDRESS>Shop 4, Laxmi Road</ADDRESS><ADDRESS>Pune</ADDRESS></ADDRESS.LIST></LEDMAILINGDETAILS.LIST>
 </LEDGER>
 <LEDGER NAME="Mega Supplier"><PARENT>Sundry Creditors</PARENT><OPENINGBALANCE>12000.00</OPENINGBALANCE><PARTYGSTIN>29AAAFM1111A1Z6</PARTYGSTIN></LEDGER>
 <LEDGER NAME="Advance Customer"><PARENT>Sundry Debtors</PARENT><OPENINGBALANCE>300.00 Cr</OPENINGBALANCE></LEDGER>
 <LEDGER NAME="HDFC Bank"><PARENT>Bank Accounts</PARENT><OPENINGBALANCE>-90000.00</OPENINGBALANCE></LEDGER>
 <LEDGER NAME="Cash"><PARENT>Cash-in-Hand</PARENT></LEDGER>
 <LEDGER NAME="Ravi Traders &amp; Sons"><PARENT>Sundry Debtors</PARENT></LEDGER>
 <STOCKITEM NAME="Basmati Rice 5kg">
  <PARENT>&#4; Primary</PARENT>
  <BASEUNITS>Bag</BASEUNITS>
  <OPENINGBALANCE> 40 Bag</OPENINGBALANCE>
  <OPENINGRATE>520.00/Bag</OPENINGRATE>
  <OPENINGVALUE>-20800.00</OPENINGVALUE>
  <GSTDETAILS.LIST><APPLICABLEFROM>20170401</APPLICABLEFROM><HSNCODE>1006</HSNCODE>
   <STATEWISEDETAILS.LIST><RATEDETAILS.LIST><GSTRATEDUTYHEAD>IGST</GSTRATEDUTYHEAD><GSTRATE> 5</GSTRATE></RATEDETAILS.LIST></STATEWISEDETAILS.LIST></GSTDETAILS.LIST>
  <GSTDETAILS.LIST><APPLICABLEFROM>20250401</APPLICABLEFROM><HSNCODE>10063020</HSNCODE>
   <STATEWISEDETAILS.LIST><RATEDETAILS.LIST><GSTRATEDUTYHEAD>CGST</GSTRATEDUTYHEAD><GSTRATE> 2.5</GSTRATE></RATEDETAILS.LIST>
   <RATEDETAILS.LIST><GSTRATEDUTYHEAD>IGST</GSTRATEDUTYHEAD><GSTRATE> 12</GSTRATE></RATEDETAILS.LIST></STATEWISEDETAILS.LIST></GSTDETAILS.LIST>
 </STOCKITEM>
 <STOCKITEM NAME="Wheat Flour"><PARENT>Grocery</PARENT><BASEUNITS>Kgs</BASEUNITS><OPENINGBALANCE>0 Kgs</OPENINGBALANCE></STOCKITEM>
</TALLYMESSAGE>
</REQUESTDATA></IMPORTDATA></BODY></ENVELOPE>''';

void main() {
  group('Excel files', () {
    test('reads the first sheet through the workbook\'s relationships, with numbers and gaps', () {
      final t = readTable(xlsx([
        ['Item name*', 'Sale price', 'Opening stock quantity', 'Note'],
        ['Rice', 650, 40.5, 'x'],
        ['Oil', 120, null, 'y'], // opening stock left empty
        ['Tea', 1e-7 * 3e9, 0.065, ''],
      ]), 'items.xlsx');
      expect(t[0], ['Item name*', 'Sale price', 'Opening stock quantity', 'Note']);
      expect(t[1], ['Rice', '650', '40.5', 'x']);
      expect(t[2], ['Oil', '120', '', 'y']);
      expect(t[3].sublist(0, 3), ['Tea', '300', '0.065']);
    });

    test('says plainly what is wrong with a file it cannot read', () {
      expect(() => readTable(Uint8List.fromList([1, 2, 3]), 'a.xlsx'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Excel'))));
      expect(() => readTable(Uint8List(0), 'old.xls'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('.xlsx'))));
    });

    test('CSV with a byte-order mark and quoted commas', () {
      final t = readTable(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Name,Phone\n"Sharma, R",9876543210\n')]), 'p.csv');
      expect(t, [['Name', 'Phone'], ['Sharma, R', '9876543210']]);
    });
  });

  group('matching columns', () {
    test('finds Vyapar-style item headers and does not take one column twice', () {
      final m = autoMap(['Item name*', 'Item code', 'HSN', 'Category', 'Sale price', 'Purchase price', 'Opening stock quantity', 'Minimum stock quantity', 'Tax rate', 'Base unit'], itemImportSpec);
      expect(m['Item Name'], 0);
      expect([m['Item Code'], m['HSN'], m['Category'], m['Sale Price'], m['Purchase Price'], m['Opening Stock'], m['Min Stock'], m['GST Rate'], m['Unit']], [1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(m['Type'], isNull);
    });

    test('party headers: an exact "Party Name" wins over a plain "Name"', () {
      final m = autoMap(['Name', 'Party Name', 'Mobile', 'State', 'Address', 'Opening Balance', 'Receivable/Payable'], partyImportSpec);
      expect([m['Party Name'], m['Phone'], m['State Code'], m['Billing Address'], m['Opening Balance'], m['Balance Type']], [1, 2, 3, 4, 5, 6]);
    });

    test('values are cleaned: rupee signs, brackets, state names, receive / pay words', () {
      final source = [
        ['Name', 'Mobile', 'State', 'Balance', 'Dr/Cr'],
        ['Ravi', '98765', 'Maharashtra', '₹ 1,500.50', 'To Receive'],
        ['Asha', '', '29-Karnataka', '(300)', 'Payable'],
        ['Vik', '', '7', 'Rs. 20', 'Cr'],
      ];
      final out = applyMapping(source, partyImportSpec, autoMap(source.first, partyImportSpec));
      expect(out.first, partyImportSpec.headers);
      String cell(int row, String h) => out[row][partyImportSpec.headers.indexOf(h)];
      expect([cell(1, 'Opening Balance'), cell(1, 'Balance Type'), cell(1, 'State Code')], ['1500.50', 'receive', '27']);
      expect([cell(2, 'Opening Balance'), cell(2, 'Balance Type'), cell(2, 'State Code')], ['-300', 'pay', '29']);
      expect([cell(3, 'Opening Balance'), cell(3, 'Balance Type'), cell(3, 'State Code')], ['20', 'pay', '07']);
      // The result goes straight through the normal import checks.
      final rows = partyImportSpec.read(out);
      expect(rows.map((r) => r.name), ['Ravi', 'Asha', 'Vik']);
    });
  });

  group('Tally export', () {
    test('customers and suppliers, however deeply grouped; banks, cash and repeats are left out', () {
      final t = parseTally(tally);
      expect(t.skippedLedgers, 2); // HDFC Bank and Cash
      final p = t.parties.skip(1).toList();
      expect(p.map((r) => r[0]), ['Ravi Traders & Sons', 'Mega Supplier', 'Advance Customer']);
      final h = partyImportSpec.headers;
      String c(int row, String name) => p[row][h.indexOf(name)];
      // A debit balance is money to receive; credit is money to pay, whichever group the ledger is in.
      expect([c(0, 'Opening Balance'), c(0, 'Balance Type'), c(0, 'State Code'), c(0, 'GSTIN')], ['5000', 'receive', '27', '27AAACR1234C1Z5']);
      expect([c(0, 'Phone'), c(0, 'Email'), c(0, 'Billing Address')], ['+919876543210', 'ravi@example.com', 'Shop 4, Laxmi Road, Pune']);
      expect([c(1, 'Opening Balance'), c(1, 'Balance Type'), c(1, 'State Code')], ['12000', 'pay', '29']); // state from the GSTIN
      expect([c(2, 'Opening Balance'), c(2, 'Balance Type')], ['300', 'pay']); // a customer who paid in advance
      // They all pass the usual checks.
      expect(partyImportSpec.read(t.parties).where((r) => r.error != null), isEmpty);
    });

    test('stock items: unit, category, latest HSN and IGST rate, opening rate and quantity', () {
      final t = parseTally(tally);
      final h = itemImportSpec.headers;
      final rice = t.items[1];
      String c(List<String> r, String name) => r[h.indexOf(name)];
      expect([c(rice, 'Item Name'), c(rice, 'Unit'), c(rice, 'Category'), c(rice, 'HSN'), c(rice, 'GST Rate'), c(rice, 'Purchase Price'), c(rice, 'Opening Stock')], ['Basmati Rice 5kg', 'BAG', '', '10063020', '12', '520', '40']);
      final flour = t.items[2];
      expect([c(flour, 'Category'), c(flour, 'Opening Stock'), c(flour, 'GST Rate')], ['Grocery', '0', '']);
      expect(itemImportSpec.read(t.items).where((r) => r.error != null), isEmpty);
    });

    test('a file that is not a Tally master export is explained', () {
      expect(() => parseTally('<ENVELOPE><BODY/></ENVELOPE>'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('List of Accounts'))));
      expect(() => parseTally('not xml <'), throwsA(isA<FormatException>()));
    });
  });
}
