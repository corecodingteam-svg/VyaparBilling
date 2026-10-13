import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../core/gst_states.dart';
import '../../shared/csv.dart';
import 'import_spec.dart';

/// A spreadsheet or CSV as rows of text; the first row is the header.
typedef Table = List<List<String>>;

String _norm(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Reads a CSV or an .xlsx (Excel) file into rows of text. Throws a [FormatException] saying what is wrong.
Table readTable(Uint8List bytes, String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  if (ext == 'xlsx') return _readXlsx(bytes);
  if (ext == 'xls') throw const FormatException('Old Excel files (.xls) cannot be read. In Excel choose Save As → Excel Workbook (.xlsx) or CSV, then try again.');
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  return parseCsv(text);
}

/// Column letters to a zero-based index: A → 0, Z → 25, AA → 26.
int _columnIndex(String cellRef) {
  var n = 0;
  for (final c in cellRef.codeUnits) {
    if (c < 65 || c > 90) break;
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

Table _readXlsx(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('That does not look like an Excel (.xlsx) file.');
  }
  String? read(String name) {
    final f = zip.findFile(name);
    return f == null ? null : utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final workbook = read('xl/workbook.xml');
  if (workbook == null) throw const FormatException('That does not look like an Excel (.xlsx) file.');
  // The first sheet, through the workbook's relationships (its file is not always sheet1.xml).
  final sheet = XmlDocument.parse(workbook).findAllElements('sheet').firstOrNull;
  final rid = sheet?.attributes.where((a) => a.name.local == 'id').firstOrNull?.value;
  String target = 'worksheets/sheet1.xml';
  final rels = read('xl/_rels/workbook.xml.rels');
  if (rels != null && rid != null) {
    for (final r in XmlDocument.parse(rels).findAllElements('Relationship')) {
      if (r.getAttribute('Id') == rid) target = r.getAttribute('Target')!;
    }
  }
  final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
  final sheetXml = read(path);
  if (sheetXml == null) throw const FormatException('The first sheet of the workbook is empty.');

  final shared = <String>[];
  final sst = read('xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in XmlDocument.parse(sst).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }
  final rows = <List<String>>[];
  for (final row in XmlDocument.parse(sheetXml).findAllElements('row')) {
    final cells = <String>[];
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final at = ref == null ? cells.length : _columnIndex(ref);
      while (cells.length < at) {
        cells.add('');
      }
      final type = c.getAttribute('t');
      final v = c.getElement('v')?.innerText ?? '';
      var text = switch (type) {
        's' => v.isEmpty ? '' : shared[int.parse(v)],
        'inlineStr' => c.findAllElements('t').map((t) => t.innerText).join(),
        'b' => v == '1' ? 'TRUE' : 'FALSE',
        _ => v,
      };
      // Numbers are stored as doubles: 40 is "40", 6.5 is "6.5", and long ones may use an exponent.
      if (type == null || type == 'n') {
        final d = double.tryParse(text);
        if (d != null) text = d == d.roundToDouble() && d.abs() < 1e15 ? d.round().toString() : double.parse(d.toStringAsFixed(6)).toString();
      }
      cells.add(text.trim());
    }
    if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
  }
  if (rows.isEmpty) throw const FormatException('The first sheet of the workbook is empty.');
  return rows;
}

// ---------------------------------------------------------------- matching columns

/// Other names the same column goes by in Vyapar, Tally exports, Busy, Excel templates, …
const _synonyms = <String, List<String>>{
  'Item Name': ['itemname', 'name', 'productname', 'product', 'item', 'particulars', 'itemdescription'],
  'Type': ['type', 'itemtype', 'producttype'],
  'Item Code': ['itemcode', 'code', 'sku', 'barcode', 'productcode', 'itemno'],
  'HSN': ['hsn', 'hsncode', 'hsnsac', 'hsnsaccode', 'sac'],
  'Unit': ['unit', 'baseunit', 'uom', 'basicunit', 'primaryunit', 'units'],
  'Category': ['category', 'itemcategory', 'group', 'itemgroup'],
  'Sale Price': ['saleprice', 'sellingprice', 'salesprice', 'sellprice', 'rate', 'price', 'salerate'],
  'Purchase Price': ['purchaseprice', 'costprice', 'buyprice', 'purchaserate', 'cost', 'buyingprice'],
  'GST Rate': ['gstrate', 'taxrate', 'gst', 'gstpercent', 'tax', 'igst', 'gsttaxrate', 'taxpercent'],
  'Opening Stock': ['openingstock', 'openingstockquantity', 'openingquantity', 'quantity', 'stock', 'currentstock', 'closingstock', 'qty', 'stockquantity', 'openingqty'],
  'Min Stock': ['minstock', 'minimumstock', 'minimumstockquantity', 'minimumquantity', 'reorderlevel', 'minqty', 'lowstock'],
  'Party Name': ['partyname', 'name', 'customername', 'party', 'ledgername', 'accountname', 'customer', 'suppliername', 'companyname', 'vendorname'],
  'Phone': ['phone', 'phoneno', 'phonenumber', 'mobile', 'contactnumber', 'contactno', 'mobilenumber', 'mobileno', 'contact', 'telephone'],
  'Email': ['email', 'emailid', 'emailaddress', 'mail'],
  'GSTIN': ['gstin', 'gstno', 'gstnumber', 'gstinuin', 'gstinno', 'gstregistrationnumber', 'partygstin', 'gstid'],
  'State Code': ['statecode', 'state', 'statename', 'placeofsupply', 'billingstate'],
  'Billing Address': ['billingaddress', 'address', 'partyaddress', 'billaddress', 'address1', 'fulladdress'],
  'Opening Balance': ['openingbalance', 'balance', 'amount', 'outstanding', 'openingamount', 'closingbalance', 'currentbalance'],
  'Balance Type': ['balancetype', 'receivablepayable', 'drcr', 'toreceivetopay', 'balancedirection'],
};

/// For each column the import wants, the index of the file column that probably holds it (null = none looks right).
Map<String, int?> autoMap(List<String> sourceHeaders, ImportSpec spec) {
  final src = [for (final h in sourceHeaders) _norm(h)];
  final used = <int>{};
  final out = <String, int?>{};
  // Exact names first, so "Name" is not taken for the party when "Party Name" is also there.
  for (final h in spec.headers) {
    final i = src.indexOf(_norm(h));
    if (i >= 0 && used.add(i)) out[h] = i;
  }
  for (final h in spec.headers) {
    if (out.containsKey(h)) continue;
    int? found;
    for (final s in _synonyms[h] ?? const <String>[]) {
      final i = src.indexOf(s);
      if (i >= 0 && !used.contains(i)) {
        found = i;
        break;
      }
    }
    if (found != null) used.add(found);
    out[h] = found;
  }
  return out;
}

String _balanceType(String raw) {
  final v = raw.trim().toLowerCase();
  if (v.isEmpty) return '';
  if (v.contains('receiv') || v == 'dr' || v.startsWith('debit') || v.contains('to collect')) return 'receive';
  if (v.contains('pay') || v == 'cr' || v.startsWith('credit')) return 'pay';
  return v;
}

String _stateCode(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return '';
  if (RegExp(r'^\d{1,2}$').hasMatch(v)) return v.padLeft(2, '0');
  // "27-Maharashtra" or "Maharashtra"
  final lead = RegExp(r'^(\d{2})\b').firstMatch(v)?.group(1);
  if (lead != null) return lead;
  final n = _norm(v);
  for (final e in gstStates.entries) {
    if (_norm(e.value) == n) return e.key;
  }
  return v;
}

/// The file's rows re-arranged into the columns the import expects, with the usual clean-ups (₹ and % signs,
/// "To Receive" → receive, state names → state codes).
Table applyMapping(Table source, ImportSpec spec, Map<String, int?> mapping) {
  final out = <List<String>>[spec.headers];
  for (final row in source.skip(1)) {
    out.add([
      for (final h in spec.headers)
        () {
          final i = mapping[h];
          var v = i == null || i >= row.length ? '' : row[i].trim();
          switch (h) {
            case 'Balance Type':
              v = _balanceType(v);
            case 'State Code':
              v = _stateCode(v);
            case 'Type':
              v = v.toLowerCase().contains('serv') ? 'service' : (v.isEmpty ? '' : 'product');
            case 'Sale Price' || 'Purchase Price' || 'Opening Balance' || 'Opening Stock' || 'Min Stock' || 'GST Rate':
              v = v.replaceAll(RegExp(r'[₹%,\s]|Rs\.?', caseSensitive: false), '');
              // Accounting exports write negatives as (500) or 500-.
              v = v.replaceAllMapped(RegExp(r'^\((.*)\)$'), (m) => '-${m[1]}');
          }
          return v;
        }(),
    ]);
  }
  return out;
}

// ---------------------------------------------------------------- Tally

/// What a Tally "List of Accounts" / masters XML export held, as import tables.
class TallyData {
  TallyData({required this.parties, required this.items, required this.skippedLedgers});
  final Table parties;
  final Table items;

  /// Ledgers that are not customers or suppliers (banks, cash, expenses, taxes…), left out.
  final int skippedLedgers;
}

String _text(XmlElement? e) => (e?.innerText ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// The first descendant [name] of [e] (any depth), as text.
String _find(XmlElement e, String name) => _text(e.findAllElements(name).firstOrNull);

/// Tally writes the name as an attribute, as a NAME element, or inside NAME.LIST.
String _tallyName(XmlElement e) {
  final a = e.getAttribute('NAME');
  if (a != null && a.trim().isNotEmpty) return a.trim();
  return _text(e.findAllElements('NAME').firstOrNull);
}

/// The number at the start of "40 Nos" or "-5000.00 Dr" and whether it was a debit (Dr, or negative as Tally exports them).
({double amount, bool debit}) _tallyAmount(String raw) {
  final m = RegExp(r'^\s*(-?)\s*([\d,]*\.?\d+)\s*(Dr|Cr)?', caseSensitive: false).firstMatch(raw);
  if (m == null) return (amount: 0, debit: false);
  final value = double.parse(m.group(2)!.replaceAll(',', ''));
  final suffix = m.group(3)?.toLowerCase();
  return (amount: value, debit: suffix == 'dr' || (suffix == null && m.group(1) == '-'));
}

String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

/// Reads a Tally XML master export. Customers and suppliers come from ledgers under Sundry Debtors / Sundry Creditors
/// (however deeply grouped), stock items from stock item masters. Written from Tally's documented export format; a
/// balance that comes out on the wrong side can be swapped in the app before importing.
TallyData parseTally(String xmlText) {
  // Tally escapes some control characters as &#4; which XML 1.0 forbids.
  final cleaned = xmlText.replaceAll(RegExp(r'&#(?:[0-8]|1[1-2]|1[4-9]|2\d|3[01]);'), '').replaceAll('﻿', '');
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(cleaned);
  } on XmlException catch (e) {
    throw FormatException('That file is not valid XML (${e.message}).');
  }
  if (doc.findAllElements('LEDGER').isEmpty && doc.findAllElements('STOCKITEM').isEmpty) {
    throw const FormatException('No ledgers or stock items found. In Tally use Display → List of Accounts → Export (XML), or Gateway → Export → Masters.');
  }
  final groupParent = <String, String>{};
  for (final g in doc.findAllElements('GROUP')) {
    final name = _tallyName(g);
    if (name.isNotEmpty) groupParent[name.toLowerCase()] = _find(g, 'PARENT').toLowerCase();
  }
  String? root(String group) {
    var g = group.toLowerCase();
    for (var i = 0; i < 20 && g.isNotEmpty; i++) {
      if (g == 'sundry debtors' || g == 'sundry creditors') return g;
      g = groupParent[g] ?? '';
    }
    return null;
  }

  final parties = <List<String>>[];
  var skipped = 0;
  final seen = <String>{};
  for (final l in doc.findAllElements('LEDGER')) {
    final name = _tallyName(l);
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    if (root(_find(l, 'PARENT')) == null) {
      skipped++;
      continue;
    }
    final address = l.findAllElements('ADDRESS').map(_text).where((a) => a.isNotEmpty).join(', ');
    final bal = _tallyAmount(_find(l, 'OPENINGBALANCE'));
    final phone = [_find(l, 'LEDGERMOBILE'), _find(l, 'LEDGERPHONE')].firstWhere((p) => p.isNotEmpty, orElse: () => '');
    final gstin = [_find(l, 'PARTYGSTIN'), _find(l, 'GSTIN')].firstWhere((g) => g.isNotEmpty, orElse: () => '');
    final state = _find(l, 'LEDSTATENAME');
    parties.add([
      name,
      phone.replaceAll(RegExp(r'[^\d+]'), ''),
      _find(l, 'EMAIL'),
      gstin.toUpperCase(),
      _stateCode(state.isEmpty && gstin.length >= 2 ? gstin.substring(0, 2) : state),
      address,
      _fmt(bal.amount),
      bal.amount == 0 ? '' : (bal.debit ? 'receive' : 'pay'),
    ]);
  }

  final items = <List<String>>[];
  final seenItems = <String>{};
  for (final s in doc.findAllElements('STOCKITEM')) {
    final name = _tallyName(s);
    if (name.isEmpty || !seenItems.add(name.toLowerCase())) continue;
    final parent = _find(s, 'PARENT');
    final qty = _tallyAmount(_find(s, 'OPENINGBALANCE'));
    final rateText = _find(s, 'OPENINGRATE');
    var rate = double.tryParse(RegExp(r'[\d.]+').firstMatch(rateText.split('/').first.replaceAll(',', ''))?.group(0) ?? '') ?? 0;
    if (rate == 0 && qty.amount > 0) rate = _tallyAmount(_find(s, 'OPENINGVALUE')).amount / qty.amount;
    // The most recent GST details are listed last.
    final gst = s.findAllElements('GSTDETAILS.LIST').lastOrNull;
    final hsn = gst == null ? _find(s, 'HSNCODE') : _find(gst, 'HSNCODE');
    String gstRate = '';
    if (gst != null) {
      for (final r in gst.findAllElements('RATEDETAILS.LIST')) {
        final head = _find(r, 'GSTRATEDUTYHEAD').toUpperCase();
        final v = double.tryParse(_find(r, 'GSTRATE').replaceAll('%', ''));
        if (v != null && head == 'IGST') gstRate = _fmt(v);
      }
    }
    final unit = _find(s, 'BASEUNITS').toUpperCase();
    items.add([
      name,
      'product',
      '',
      RegExp(r'^\d{4,8}$').hasMatch(hsn) ? hsn : '',
      unit,
      parent.isEmpty || parent.toLowerCase() == 'primary' ? '' : parent,
      '',
      rate == 0 ? '' : _fmt(rate),
      gstRate,
      _fmt(qty.amount),
      '',
    ]);
  }
  return TallyData(
    parties: [partyImportSpec.headers, ...parties],
    items: [itemImportSpec.headers, ...items],
    skippedLedgers: skipped,
  );
}
