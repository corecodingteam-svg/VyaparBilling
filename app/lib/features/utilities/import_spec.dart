import '../../core/gst_states.dart';
import '../../data/models/item.dart' show gstRateOptions;
import '../../shared/format.dart';

/// One parsed import row: the API body, or what is wrong with it.
class ImportRow {
  ImportRow(this.line, this.name, this.body, this.error);

  /// Line number in the file (the header is line 1).
  final int line;
  final String name;
  final Map<String, dynamic> body;
  final String? error;
}

/// What a CSV import looks like for one kind of record.
class ImportSpec {
  const ImportSpec({
    required this.title,
    required this.noun,
    required this.endpoint,
    required this.bodyKey,
    required this.fileName,
    required this.headers,
    required this.sample,
    required this.parse,
  });

  final String title;
  final String noun;
  final String endpoint;

  /// Key of the array in the request body.
  final String bodyKey;
  final String fileName;
  final List<String> headers;
  final List<List<String>> sample;

  /// Turns one row (header → cell) into an API body, or throws a [FormatException] describing the problem.
  final Map<String, dynamic> Function(Map<String, String> cells) parse;

  /// Maps file rows to [ImportRow]s. Header names are matched ignoring case, spaces and punctuation.
  List<ImportRow> read(List<List<String>> rows) {
    if (rows.isEmpty) return [];
    String norm(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    final wanted = {for (final h in headers) norm(h): h};
    final columns = [for (final h in rows.first) wanted[norm(h)]];
    if (!columns.contains(headers.first)) {
      throw FormatException('The file has no "${headers.first}" column. Download the sample file to see the expected format.');
    }
    return [
      for (var i = 1; i < rows.length; i++)
        () {
          final cells = <String, String>{
            for (var c = 0; c < columns.length && c < rows[i].length; c++)
              if (columns[c] != null) columns[c]!: rows[i][c],
          };
          final name = cells[headers.first] ?? '';
          try {
            return ImportRow(i + 1, name, parse(cells), null);
          } on FormatException catch (e) {
            return ImportRow(i + 1, name, const {}, e.message);
          }
        }(),
    ];
  }
}

String _required(Map<String, String> c, String key) {
  final v = (c[key] ?? '').trim();
  if (v.isEmpty) throw FormatException('$key is required');
  return v;
}

num? _number(Map<String, String> c, String key, {bool allowNegative = false}) {
  final raw = (c[key] ?? '').trim();
  if (raw.isEmpty) return null;
  final n = parseNum(raw.replaceAll('₹', '').replaceAll('%', ''));
  if (n == null || (!allowNegative && n < 0)) throw FormatException('$key "$raw" is not a valid number');
  return n;
}

final itemImportSpec = ImportSpec(
  title: 'Import Items',
  noun: 'item',
  endpoint: '/items/import',
  bodyKey: 'items',
  fileName: 'items-sample.csv',
  headers: const [
    'Item Name', 'Type', 'Item Code', 'HSN', 'Unit', 'Category', 'Sale Price', 'Purchase Price', 'GST Rate', 'Opening Stock', 'Min Stock',
  ],
  sample: const [
    ['Basmati Rice 5kg', 'product', 'RICE5', '1006', 'BAG', 'Grocery', '650', '520', '5', '40', '10'],
    ['Home Delivery', 'service', '', '9968', '', 'Services', '50', '', '18', '', ''],
  ],
  parse: (c) {
    final type = (c['Type'] ?? '').trim().toLowerCase();
    if (type.isNotEmpty && type != 'product' && type != 'service') throw const FormatException('Type must be product or service');
    final hsn = (c['HSN'] ?? '').trim();
    if (hsn.isNotEmpty && !RegExp(r'^[0-9]{4,8}$').hasMatch(hsn)) throw const FormatException('HSN must be 4 to 8 digits');
    final gst = _number(c, 'GST Rate');
    if (gst != null && !gstRateOptions.contains(gst)) throw FormatException('GST Rate ${numText(gst)}% is not a valid GST slab');
    return {
      'name': _required(c, 'Item Name'),
      'type': type.isEmpty ? 'product' : type,
      'itemCode': (c['Item Code'] ?? '').trim(),
      'hsnCode': hsn,
      'unit': (c['Unit'] ?? '').trim().toUpperCase(),
      'categoryName': (c['Category'] ?? '').trim(),
      'salePrice': _number(c, 'Sale Price') ?? 0,
      'purchasePrice': _number(c, 'Purchase Price') ?? 0,
      'gstRate': gst,
      if (type != 'service') 'openingQty': _number(c, 'Opening Stock') ?? 0,
      if (type != 'service') 'minStock': _number(c, 'Min Stock'),
    };
  },
);

final partyImportSpec = ImportSpec(
  title: 'Import Parties',
  noun: 'party',
  endpoint: '/parties/import',
  bodyKey: 'parties',
  fileName: 'parties-sample.csv',
  headers: const ['Party Name', 'Phone', 'Email', 'GSTIN', 'State Code', 'Billing Address', 'Opening Balance', 'Balance Type'],
  sample: const [
    ['Sharma General Store', '9876543210', 'sharma@example.com', '07AAGCS1234L1Z9', '07', '12 Main Bazaar, Delhi', '1500', 'receive'],
    ['Gupta Wholesale', '9811122233', '', '', '09', 'Noida', '800', 'pay'],
  ],
  parse: (c) {
    final gstin = (c['GSTIN'] ?? '').trim().toUpperCase();
    if (gstin.isNotEmpty && !RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(gstin)) {
      throw const FormatException('GSTIN is not valid');
    }
    final state = (c['State Code'] ?? '').trim().padLeft(2, '0');
    if ((c['State Code'] ?? '').trim().isNotEmpty && !gstStates.containsKey(state)) throw const FormatException('State Code is not a GST state code');
    final balanceType = (c['Balance Type'] ?? '').trim().toLowerCase();
    if (balanceType.isNotEmpty && balanceType != 'receive' && balanceType != 'pay') {
      throw const FormatException('Balance Type must be receive or pay');
    }
    final opening = _number(c, 'Opening Balance') ?? 0;
    return {
      'name': _required(c, 'Party Name'),
      'phone': (c['Phone'] ?? '').trim(),
      'email': (c['Email'] ?? '').trim(),
      'gstin': gstin,
      'gstType': gstin.isEmpty ? 'unregistered' : 'regular',
      'stateCode': (c['State Code'] ?? '').trim().isEmpty ? null : state,
      'billingAddress': (c['Billing Address'] ?? '').trim(),
      'openingBalance': balanceType == 'pay' ? -opening : opening,
    };
  },
);
