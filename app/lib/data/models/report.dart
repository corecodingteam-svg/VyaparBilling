import 'package:equatable/equatable.dart';

/// A report on offer and the filters it takes ('period', 'party', 'party?', 'bank', 'item').
class ReportDef extends Equatable {
  ReportDef.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String,
        group = j['group'] as String,
        params = [for (final p in j['params'] as List) p as String];

  final String id;
  final String title;
  final String group;
  final List<String> params;

  bool get needsPeriod => params.contains('period');
  bool get needsParty => params.contains('party');

  /// A party can be chosen to narrow the report, but is not required.
  bool get optionalParty => params.contains('party?');
  bool get needsBank => params.contains('bank');
  bool get needsItem => params.contains('item');

  /// The report is filtered by one party, bank account or item picked from a list.
  bool get hasSelector => needsParty || optionalParty || needsBank || needsItem;

  /// It cannot run until one is picked.
  bool get selectionRequired => needsParty || needsBank || needsItem;

  /// What the selector chooses, for labels.
  String get selectorLabel => needsBank ? 'Bank Account' : (needsItem ? 'Item' : 'Party');

  @override
  List<Object?> get props => [id, title, group, params];
}

class ReportColumn extends Equatable {
  ReportColumn.fromJson(Map<String, dynamic> j)
      : key = j['key'] as String,
        label = j['label'] as String,
        type = j['type'] as String;

  final String key;
  final String label;

  /// text | date | money | qty | number
  final String type;

  bool get numeric => type == 'money' || type == 'qty' || type == 'number';

  @override
  List<Object?> get props => [key, label, type];
}

class ReportFigure extends Equatable {
  ReportFigure.fromJson(Map<String, dynamic> j)
      : label = j['label'] as String,
        value = j['value'],
        type = j['type'] as String;

  final String label;
  final Object? value;
  final String type;

  @override
  List<Object?> get props => [label, value, type];
}

/// A finished report: a table plus headline figures.
class ReportData extends Equatable {
  ReportData.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String,
        subtitle = j['subtitle'] as String,
        columns = [for (final c in j['columns'] as List) ReportColumn.fromJson(c as Map<String, dynamic>)],
        rows = [for (final r in j['rows'] as List) r as Map<String, dynamic>],
        summary = [for (final s in j['summary'] as List) ReportFigure.fromJson(s as Map<String, dynamic>)];

  final String id;
  final String title;
  final String subtitle;
  final List<ReportColumn> columns;

  /// Cell values by column key; `_bold` marks subtotal/heading rows.
  final List<Map<String, dynamic>> rows;
  final List<ReportFigure> summary;

  @override
  List<Object?> get props => [id, title, subtitle, columns, rows, summary];
}
