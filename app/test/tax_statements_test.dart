import 'package:billing_app/core/status.dart';
import 'package:billing_app/data/models/party.dart';
import 'package:billing_app/data/models/tax_statement.dart';
import 'package:billing_app/features/tax/tax_statements_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('opens on the quarter that has just ended, which is the one usually due', () {
    final c = TaxStatementsCubit(FakeTaxStatementsRepository(), now: DateTime(2026, 10, 13));
    expect([c.state.form, c.state.taxYear, c.state.quarter], ['140', '202627', 'Q2']);
    final jan = TaxStatementsCubit(FakeTaxStatementsRepository(), now: DateTime(2027, 1, 20));
    expect([jan.state.taxYear, jan.state.quarter], ['202627', 'Q3']);
  });

  test('a statement becomes downloadable once the challans cover the tax', () async {
    final repo = FakeTaxStatementsRepository();
    final c = TaxStatementsCubit(repo, now: DateTime(2026, 10, 13));
    await c.load();
    expect([c.state.status, c.state.statement!.file, c.state.statement!.problems.length, c.state.tdsSections.keys.first], [LoadStatus.success, null, 1, '1031']);
    await c.addChallan(bsrCode: '0510308', challanNo: '124', depositDate: '2026-10-06', tax: 80);
    expect([c.state.challans.length, c.state.statement!.file, c.state.message], [1, isNotNull, 'Challan added']);
    expect(repo.calls, contains('add tds 202627 Q2 0510308 80'));
    await c.periodChanged(form: '143');
    expect([c.state.form, c.state.kind, repo.calls.last], ['143', 'tcs', 'challans tcs 202627 Q2']);
    await c.removeChallan('c1');
    expect(c.state.challans, isEmpty);
    await c.close();
  });

  test('deductor details are saved into the company settings', () async {
    final repo = FakeTaxStatementsRepository();
    final c = TaxStatementsCubit(repo);
    await c.load();
    const d = Deductor(type: 'F', name: 'R Sharma', designation: 'Partner', pan: 'abcps1234d', mobile: '9876543210', tdsSection: '1027', tcsCode: '1073', tdsPreviousToken: '123456789012345');
    await c.saveDeductor(d);
    expect([repo.saved, c.state.deductor, c.state.message], [d, d, 'Saved']);
    expect(d.toSettings()['responsiblePan'], 'ABCPS1234D');
    expect(Deductor.fromSettings(d.toSettings()).tdsPreviousToken, '123456789012345');
    expect(Deductor.fromSettings(const {}), const Deductor());
    await c.close();
  });

  test('tax years and quarters', () {
    expect([taxYearOf(DateTime(2026, 4, 1)), taxYearOf(DateTime(2027, 3, 31)), quarterOfDate(DateTime(2027, 2, 1)), taxYearLabel('202627')], ['202627', '202627', 'Q4', '2026-27']);
  });

  test('parties carry their PAN and section codes', () {
    final p = Party.fromJson({...partyJson('a', 'Mega', 0), 'pan': 'AAAFM1111A', 'tdsSection': '1031', 'tcsCode': null, 'collecteeCode': 7});
    expect([p.pan, p.tdsSection, p.tcsCode, p.collecteeCode], ['AAAFM1111A', '1031', null, 7]);
  });
}
