import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/core/status.dart';
import 'package:billing_app/data/models/cash_bank.dart';
import 'package:billing_app/features/cash_bank/bloc/bank_accounts_bloc.dart';
import 'package:billing_app/features/cash_bank/bloc/cash_bank_form_cubits.dart';
import 'package:billing_app/features/cash_bank/bloc/money_list_cubit.dart';
import 'package:billing_app/features/cash_bank/cash_bank_dialogs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('which payment types use a bank account', () {
    expect(['cash', 'bank', 'upi', 'cheque', 'card'].where(modeUsesBank), ['bank', 'upi', 'card']);
  });

  test('transfer dialog validates the accounts and sends only what the kind needs', () async {
    final repo = FakeCashBankRepository();
    final c = AdjustmentFormCubit(repo, kinds: bankAdjustmentKinds, bankAccountId: 'b1');
    await c.load();
    expect(c.state.kind, 'bank_to_cash');

    c.kindChanged('bank_to_bank');
    await c.submit(amount: 100, description: '');
    expect(c.state.error, 'Select the account to transfer to.');
    c.toBankAccountChanged('b1');
    await c.submit(amount: 100, description: '');
    expect(c.state.error, 'Choose two different accounts.');
    expect(repo.adjustments, isEmpty);

    c.toBankAccountChanged('b2');
    await c.submit(amount: 100, description: ' rent float ');
    expect(c.state.status, SubmitStatus.success);
    expect(repo.adjustments.single, containsPair('toBankAccountId', 'b2'));
    expect(repo.adjustments.single, containsPair('description', 'rent float'));
  });

  test('a kind chosen while the accounts are still loading is kept', () async {
    final c = AdjustmentFormCubit(FakeCashBankRepository(), kinds: bankAdjustmentKinds, bankAccountId: 'b1');
    final loading = c.load();
    c.kindChanged('bank_to_bank'); // as the "Deposit / Withdraw" menu does right after opening the dialog
    await loading;
    expect(c.state.kind, 'bank_to_bank');
    expect(c.state.accounts, hasLength(2));
  });

  test('cash adjustment never sends a bank account', () async {
    final repo = FakeCashBankRepository();
    final c = AdjustmentFormCubit(repo, kinds: cashAdjustmentKinds, bankAccountId: 'b1');
    await c.load();
    c.kindChanged('cash_reduce');
    await c.submit(amount: 40, description: '');
    expect(repo.adjustments.single['kind'], 'cash_reduce');
    expect(repo.adjustments.single['bankAccountId'], isNull);
  });

  test('bank accounts bloc selects the first account and loads its transactions', () async {
    final bloc = BankAccountsBloc(FakeCashBankRepository(), ChangeBus())..add(const BankAccountsRequested());
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.selected?.name, 'HDFC Current');
    expect(bloc.state.txns, hasLength(4));
    bloc.add(const BankAccountsSearchChanged('sbi'));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.visible.single.name, 'SBI Savings');
    await bloc.close();
  });

  test('cash and cheque lists load', () async {
    final cash = CashCubit(FakeCashBankRepository(), ChangeBus());
    await cash.load();
    expect(cash.state.balance, 620);
    final cheques = ChequesCubit(FakeCashBankRepository(), ChangeBus());
    await cheques.load();
    expect(cheques.state.txns.where((t) => t.isOpenCheque), hasLength(2));
    expect(cheques.state.accounts, hasLength(2));
  });
}
