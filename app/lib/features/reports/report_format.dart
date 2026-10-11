import '../../data/models/report.dart';
import '../../shared/format.dart';

/// Formats one report cell for display, print and CSV.
String reportCell(Object? value, String type, {bool plain = false}) {
  if (value == null) return '';
  return switch (type) {
    'money' => plain ? (value as num).toStringAsFixed(2) : money(value as num),
    'qty' => plain ? numText(value as num) : qty(value as num),
    'number' => numText(value as num),
    'date' => displayDate(value as String),
    _ => value.toString(),
  };
}

/// RFC 4180 CSV of the report table, with raw numbers so spreadsheets can sum them.
String reportCsv(ReportData data) {
  String esc(String s) => s.contains(RegExp('[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  return [
    data.columns.map((c) => esc(c.label)).join(','),
    for (final row in data.rows) data.columns.map((c) => esc(reportCell(row[c.key], c.type, plain: true))).join(','),
  ].join('\r\n');
}
