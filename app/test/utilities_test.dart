import 'package:billing_app/core/api_client.dart';
import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/core/status.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/data/models/report.dart';
import 'package:billing_app/features/reports/report_format.dart';
import 'package:billing_app/features/settings/settings_cubit.dart';
import 'package:billing_app/features/utilities/import_spec.dart';
import 'package:billing_app/features/utilities/utilities_cubits.dart';
import 'package:billing_app/features/utilities/utilities_screens.dart';
import 'package:billing_app/shared/csv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('csv', () {
    test('parses quoted commas, escaped quotes, line breaks and blank lines', () {
      const text = 'Name,Note\r\n"Rice, 5kg","He said ""hi"""\n\n  Tea  ,"two\nlines"\n';
      expect(parseCsv(text), [
        ['Name', 'Note'],
        ['Rice, 5kg', 'He said "hi"'],
        ['Tea', 'two\nlines'],
      ]);
    });

    test('round-trips through toCsv', () {
      final rows = [
        ['a', 'b,c', 'd"e'],
        ['1', '', 'x\ny'],
      ];
      expect(parseCsv(toCsv(rows)), rows);
    });
  });

  group('import', () {
    test('items: flexible headers, defaults, and per-row problems', () {
      final rows = itemImportSpec.read(parseCsv(
        'item name,SALE PRICE,gst rate,Opening Stock,Type,HSN,Unit,Unknown Column\n'
        'Rice,650,5%,40,,1006,bag,x\n'
        'Delivery,50,18,7,service,,,\n'
        ',10,,,,,,\n'
        'Bad Tax,10,7,,,,,\n'
        'Bad Hsn,10,,,,12,,\n',
      ));
      expect(rows.map((r) => r.line), [2, 3, 4, 5, 6]);
      expect(rows[0].body, containsPair('name', 'Rice'));
      expect([rows[0].body['type'], rows[0].body['gstRate'], rows[0].body['openingQty'], rows[0].body['unit']], ['product', 5, 40, 'BAG']);
      expect(rows[1].body.containsKey('openingQty'), isFalse); // services have no stock
      expect(rows.sublist(2).map((r) => r.error), ['Item Name is required', 'GST Rate 7% is not a valid GST slab', 'HSN must be 4 to 8 digits']);
    });

    test('parties: balance type sets the sign; GSTIN makes the party registered', () {
      final rows = partyImportSpec.read(parseCsv(
        'Party Name,GSTIN,State Code,Opening Balance,Balance Type\n'
        'Gupta,27AAACR5055K1Z5,27,800,pay\n'
        'Walk In,,7,100,\n'
        'Broken,NOTAGSTIN,,,\n',
      ));
      expect([rows[0].body['openingBalance'], rows[0].body['gstType']], [-800, 'regular']);
      expect([rows[1].body['openingBalance'], rows[1].body['gstType'], rows[1].body['stateCode']], [100, 'unregistered', '07']);
      expect(rows[2].error, 'GSTIN is not valid');
    });

    test('a file without the name column is rejected with a helpful message', () {
      final cubit = ImportCubit(ApiClient(TokenStore()), ChangeBus(), itemImportSpec)..fileChosen('Foo,Bar\n1,2\n');
      expect(cubit.state.fileError, contains('no "Item Name" column'));
      cubit.fileChosen('Item Name\n');
      expect(cubit.state.fileError, 'The file has no data rows.');
      expect(parseCsv(cubit.sampleCsv).first, itemImportSpec.headers);
      // The sample file itself imports cleanly.
      cubit.fileChosen(cubit.sampleCsv);
      expect([cubit.state.valid.length, cubit.state.invalid.length], [2, 0]);
    });

    test('exported items use the import columns', () {
      final csv = itemsCsv([Item.fromJson(itemJson('i1', 'Rice, 5kg', stock: 12, minStock: 3, gstRate: 5))]);
      final rows = itemImportSpec.read(parseCsv(csv));
      expect(rows.single.error, isNull);
      expect([rows.single.body['name'], rows.single.body['openingQty'], rows.single.body['gstRate']], ['Rice, 5kg', 12, 5]);
    });
  });

  test('bulk update tracks only real changes and validates them', () async {
    final items = FakeItemsRepository([Item.fromJson(itemJson('i1', 'Sample Item')), Item.fromJson(itemJson('i2', 'Other'))]);
    final c = BulkUpdateCubit(items, ApiClient(TokenStore()), ChangeBus());
    await c.load();
    final item = c.state.items.first;
    c.edit(item, (e) => e.copyWith(salePrice: '100')); // same as saved → not a change
    expect(c.state.changed, isEmpty);
    c.edit(item, (e) => e.copyWith(salePrice: '125.50', gstRate: () => 12));
    expect(c.state.changed.single.id, 'i1');
    c.edit(item, (e) => e.copyWith(purchasePrice: 'abc'));
    await c.save();
    expect([c.state.status, c.state.error], [SubmitStatus.failure, 'Sample Item: Purchase price is not a valid number']);
    c.discard();
    expect(c.state.changed, isEmpty);
  });

  test('settings: draft vs saved, discard and save', () async {
    final firm = FakeFirmRepository();
    final c = SettingsCubit(firm);
    await c.load();
    expect([c.state.dirty, c.state.draft.gstEnabled, c.state.draft.signatureLabel], [false, true, 'Authorized Signatory']);
    c.change((s) => s.copyWith(invoicePrefix: 'INV-', blockNegativeStock: true));
    expect(c.state.dirty, isTrue);
    c.discard();
    expect([c.state.dirty, c.state.draft.invoicePrefix], [false, '']);
    c.change((s) => s.copyWith(invoicePrefix: 'INV-'));
    await c.save();
    expect([c.state.status, c.state.dirty, firm.settings['invoicePrefix']], [SubmitStatus.success, false, 'INV-']);
  });

  test('report cells and CSV export', () {
    expect([reportCell(1234.5, 'money'), reportCell('2026-10-03', 'date'), reportCell(null, 'money'), reportCell(2.5, 'qty')],
        ['₹ 1,234.50', '03/10/2026', '', '2.5']);
    final data = ReportData.fromJson({
      'id': 'x', 'title': 'T', 'subtitle': 'S',
      'columns': [
        {'key': 'name', 'label': 'Name', 'type': 'text'}, {'key': 'amount', 'label': 'Amount', 'type': 'money'},
      ],
      'rows': [
        {'name': 'Rice, 5kg', 'amount': 1234.5}, {'name': 'Total', 'amount': null, '_bold': true},
      ],
      'summary': <Map<String, dynamic>>[],
    });
    expect(reportCsv(data), 'Name,Amount\r\n"Rice, 5kg",1234.50\r\nTotal,');
  });
}
