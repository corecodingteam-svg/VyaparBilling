import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:billing_app/data/models/report.dart';
import 'package:billing_app/features/reports/report_chart.dart';
import 'package:billing_app/shared/data_table_view.dart';
import 'package:billing_app/shared/page.dart';

TableRowData row(String name, num amount, {bool pinned = false}) => TableRowData(cells: [Text(name), Text('$amount')], sort: [name, amount], search: name, pinned: pinned);

Widget host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

/// A tall window, so every row and the pager are on screen.
void tall(WidgetTester t) {
  t.view.physicalSize = const Size(1400, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  group('sorting, searching and paging rules', () {
    final rows = [row('Charlie', 30), row('alpha', 10), row('Bravo', 20)];

    test('search is case-insensitive and every word must match', () {
      expect(visibleRows(rows, const TableViewState(query: 'AL')).map((r) => r.search), ['alpha']);
      expect(visibleRows([row('Sharma Stores', 1), row('Sharma Tea', 2)], const TableViewState(query: 'sharma tea')).length, 1);
    });

    test('sorts text ignoring case, numbers by value, in both directions', () {
      expect(visibleRows(rows, const TableViewState(sortColumn: 0)).map((r) => r.search), ['alpha', 'Bravo', 'Charlie']);
      expect(visibleRows(rows, const TableViewState(sortColumn: 1, ascending: false)).map((r) => r.search), ['Charlie', 'Bravo', 'alpha']);
    });

    test('empty values stay last whichever way it sorts', () {
      final withGap = [row('a', 5), const TableRowData(cells: [], sort: ['b', null]), row('c', 1)];
      expect(visibleRows(withGap, const TableViewState(sortColumn: 1)).map((r) => r.sort[0]), ['c', 'a', 'b']);
      expect(visibleRows(withGap, const TableViewState(sortColumn: 1, ascending: false)).map((r) => r.sort[0]), ['a', 'c', 'b']);
    });

    test('pinned rows are left out of searching and sorting', () {
      expect(visibleRows([row('x', 1), row('Total', 9, pinned: true)], const TableViewState()).length, 1);
    });

    test('cubit: searching or sorting goes back to page one; clicking a heading twice reverses it', () {
      final c = TableViewCubit()..goTo(3);
      c.search('a');
      expect(c.state.page, 0);
      c.sort(1);
      c.sort(1);
      expect([c.state.sortColumn, c.state.ascending], [1, false]);
      c.sort(0);
      expect([c.state.sortColumn, c.state.ascending], [0, true]);
      c.goTo(-4);
      expect(c.state.page, 0);
    });
  });

  group('PagedDataTable', () {
    final many = [for (var i = 1; i <= 60; i++) row('Item ${i.toString().padLeft(2, '0')}', i)];
    const cols = [TableColumnSpec('Name'), TableColumnSpec('Amount', numeric: true)];

    testWidgets('shows a page at a time and moves between pages', (t) async {
      tall(t);
      await t.pumpWidget(host(PagedDataTable(columns: cols, rows: many)));
      expect(find.text('Item 01'), findsOneWidget);
      expect(find.text('Item 26'), findsNothing);
      expect(find.text('1–25 of 60'), findsOneWidget);
      await t.tap(find.byTooltip('Next page'));
      await t.pump();
      expect(find.text('Item 26'), findsOneWidget);
      expect(find.text('Item 01'), findsNothing);
      await t.tap(find.byTooltip('Last page'));
      await t.pump();
      expect(find.text('51–60 of 60'), findsOneWidget);
    });

    testWidgets('clicking a heading sorts, and the search box filters', (t) async {
      tall(t);
      await t.pumpWidget(host(PagedDataTable(columns: cols, rows: many)));
      await t.tap(find.text('Amount'));
      await t.pump();
      await t.tap(find.text('Amount'));
      await t.pump();
      expect(find.text('Item 60'), findsOneWidget); // descending: the biggest first
      expect(find.text('Item 01'), findsNothing);
      await t.enterText(find.byType(TextField), 'item 07');
      await t.pump();
      expect(find.text('Item 07'), findsOneWidget);
      expect(find.text('Item 60'), findsNothing);
      expect(find.textContaining('(filtered)'), findsNothing); // 1 row: no pager at all
      await t.enterText(find.byType(TextField), 'zzz');
      await t.pump();
      expect(find.textContaining('Nothing matches'), findsOneWidget);
    });

    testWidgets('a statement (plain) shows every row in its own order with no search or pager', (t) async {
      tall(t);
      await t.pumpWidget(host(PagedDataTable(plain: true, columns: cols, rows: many)));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Item 60'), findsOneWidget);
      expect(find.byTooltip('Next page'), findsNothing);
    });

    testWidgets('totals stay at the bottom of the last page', (t) async {
      tall(t);
      await t.pumpWidget(host(PagedDataTable(columns: cols, rows: [...many, row('TOTAL', 1830, pinned: true)])));
      expect(find.text('TOTAL'), findsNothing);
      await t.tap(find.byTooltip('Last page'));
      await t.pump();
      expect(find.text('TOTAL'), findsOneWidget);
    });
  });

  group('RowsCard', () {
    testWidgets('searches, sorts and pages a list of rows', (t) async {
      tall(t);
      final names = [for (var i = 1; i <= 30; i++) 'Row ${i.toString().padLeft(2, '0')}'];
      await t.pumpWidget(host(RowsCard(
        rows: [for (final n in names) ListTile(title: Text(n))],
        texts: names,
        sorts: {'Name': names, 'Number': [for (var i = 1; i <= 30; i++) i]},
        empty: const Text('none'),
      )));
      expect(find.text('Row 01'), findsOneWidget);
      expect(find.text('Row 26'), findsNothing);
      await t.tap(find.byIcon(Icons.arrow_upward)); // flip to descending
      await t.pump();
      expect(find.text('Row 30'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'row 12');
      await t.pump();
      expect(find.text('Row 12'), findsOneWidget);
      expect(find.text('Row 30'), findsNothing);
    });
  });

  group('report charts', () {
    ReportData report(List<Map<String, dynamic>> rows, {List<List<String>>? cols}) => ReportData.fromJson({
          'id': 'x', 'title': 'X', 'subtitle': '',
          'columns': [for (final c in cols ?? [['party', 'Party', 'text'], ['total', 'Total', 'money'], ['paid', 'Paid', 'money']]) {'key': c[0], 'label': c[1], 'type': c[2]}],
          'rows': rows,
          'summary': <Map<String, dynamic>>[],
        });

    test('groups rows by the party, adds up the total column and skips total rows', () {
      final spec = deriveChart(report([
        {'party': 'A', 'total': 100, 'paid': 10},
        {'party': 'B', 'total': 50, 'paid': 5},
        {'party': 'A', 'total': 20, 'paid': 2},
        {'party': 'TOTAL', 'total': 170, 'paid': 17, '_bold': true},
      ]))!;
      expect(spec.valueColumn.key, 'total');
      expect([for (final p in spec.points) (p.label, p.value)], [('A', 120), ('B', 50)]);
      expect(spec.canPie, isTrue);
    });

    test('another value column can be chosen', () {
      final spec = deriveChart(report([{'party': 'A', 'total': 1, 'paid': 7}, {'party': 'B', 'total': 2, 'paid': 3}]), valueKey: 'paid')!;
      expect(spec.points.first.value, 7);
    });

    test('dates become a time line in date order', () {
      final spec = deriveChart(report([
        {'d': '2026-10-09', 'amt': 5}, {'d': '2026-10-03', 'amt': 7},
      ], cols: [['d', 'Date', 'date'], ['amt', 'Amount', 'money']]))!;
      expect(spec.byDate, isTrue);
      expect(spec.points.map((p) => p.value), [7, 5]);
    });

    test('no chart when there is nothing to compare', () {
      expect(deriveChart(report([{'party': 'A', 'total': 1, 'paid': 1}])), isNull);
      expect(deriveChart(report([{'party': 'A', 'total': 0, 'paid': 0}, {'party': 'B', 'total': 0, 'paid': 0}])), isNull);
      expect(deriveChart(report([{'party': 'A'}, {'party': 'B'}], cols: [['party', 'Party', 'text']])), isNull);
    });

    test('keeps the biggest 15 and says how many were left out', () {
      final spec = deriveChart(report([for (var i = 1; i <= 20; i++) {'party': 'P$i', 'total': i, 'paid': 0}]))!;
      expect(spec.points.length, maxChartPoints);
      expect(spec.hiddenCount, 5);
      expect(spec.points.first.label, 'P20');
      expect(spec.canPie, isFalse);
    });
  });

  testWidgets('clicking a slice selects its group; the detail line and Clear respond', (t) async {
    tall(t);
    final data = ReportData.fromJson({
      'id': 'x', 'title': 'X', 'subtitle': '',
      'columns': [
        {'key': 'party', 'label': 'Party', 'type': 'text'},
        {'key': 'total', 'label': 'Total', 'type': 'money'},
      ],
      'rows': [
        {'party': 'Gupta', 'total': 300}, {'party': 'Sharma', 'total': 100},
      ],
      'summary': <Map<String, dynamic>>[],
    });
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BlocProvider(create: (_) => ChartChoiceCubit(), child: ReportChartCard(data: data))))));
    expect(find.textContaining('rows highlighted'), findsNothing);
    await t.tap(find.byTooltip('Share'));
    await t.pumpAndSettle();
    await t.tap(find.text('Gupta'));
    await t.pumpAndSettle();
    expect(find.textContaining('Gupta  ·  Total'), findsOneWidget);
    expect(find.textContaining('1 row highlighted'), findsOneWidget);
    await t.tap(find.text('Clear'));
    await t.pumpAndSettle();
    expect(find.textContaining('rows highlighted'), findsNothing);
  });
}
