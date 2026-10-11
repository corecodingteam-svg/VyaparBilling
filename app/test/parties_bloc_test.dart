import 'package:billing_app/core/status.dart';
import 'package:billing_app/data/models/party.dart';
import 'package:billing_app/features/parties/bloc/parties_bloc.dart';
import 'package:billing_app/features/parties/bloc/party_form_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakePartiesRepository repo;

  setUp(() {
    repo = FakePartiesRepository([
      Party.fromJson(partyJson('a', 'Test Customer', 500, phone: '9000000001')),
      Party.fromJson(partyJson('b', 'Test Supplier', -250)),
    ]);
  });

  test('loads parties, selects the first and loads its ledger', () async {
    final bloc = PartiesBloc(repo, repo.bus)..add(const PartiesRequested());
    await settle();
    expect(bloc.state.status, LoadStatus.success);
    expect(bloc.state.selectedId, 'a');
    expect(bloc.state.txns.single.balance, 500);
    await bloc.close();
  });

  test('search filters by name or phone', () async {
    final bloc = PartiesBloc(repo, repo.bus)..add(const PartiesRequested());
    await settle();
    bloc.add(const PartiesSearchChanged('suppl'));
    await settle();
    expect(bloc.state.visible.map((p) => p.id), ['b']);
    bloc.add(const PartiesSearchChanged('90000'));
    await settle();
    expect(bloc.state.visible.map((p) => p.id), ['a']);
    await bloc.close();
  });

  test('reloads after a repository write and drops a deleted selection', () async {
    final bloc = PartiesBloc(repo, repo.bus)..add(const PartiesRequested());
    await settle();
    await repo.delete('a');
    await settle();
    await settle();
    expect(bloc.state.parties.map((p) => p.id), ['b']);
    expect(bloc.state.selectedId, 'b');
    await bloc.close();
  });

  test('party form sends a negative opening balance for "To Pay" and null limit when unlimited', () async {
    final cubit = PartyFormCubit(repo, null)..balanceDirectionChanged(false);
    await cubit.save({'name': 'New Supplier', 'openingAmount': 300, 'creditLimitAmount': 1000, 'shippingAddress': 'X'}, andNew: false);
    expect(cubit.state.result, PartyFormResult.saved);
    expect(repo.saved.single['openingBalance'], -300);
    expect(repo.saved.single['creditLimit'], isNull);
    expect(repo.saved.single['shippingAddress'], ''); // shipping not enabled
  });

  test('valid GSTIN switches an unregistered party to regular in that state', () {
    final cubit = PartyFormCubit(repo, null)..gstinRecognised('27');
    expect(cubit.state.stateCode, '27');
    expect(cubit.state.gstType, 'regular');
  });

  test('save & new resets the form selections', () async {
    final cubit = PartyFormCubit(repo, null)
      ..balanceDirectionChanged(false)
      ..creditLimitToggled(true);
    await cubit.save({'name': 'X', 'openingAmount': 1, 'creditLimitAmount': 5}, andNew: true);
    expect(cubit.state.result, PartyFormResult.savedAndNew);
    expect(cubit.state.toReceive, isTrue);
    expect(cubit.state.customLimit, isFalse);
  });
}
