import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/core/status.dart';
import 'package:billing_app/features/expenses/bloc/expense_form_cubit.dart';
import 'package:billing_app/features/expenses/bloc/expenses_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('new expense: preselects the category, totals and validation', () async {
    final repo = FakeExpensesRepository();
    final c = ExpenseFormCubit(repo, FakeCashBankRepository(), ChangeBus(), categoryId: 'x4');
    await c.load();
    expect(c.state.categoryId, 'x4');
    expect(c.validate(), 'Add at least one item.');

    final uid = c.state.lines.first.uid;
    c.lineNameChanged(uid, 'Office tea');
    expect(c.validate(), 'Row 1: enter a quantity greater than 0.');
    c
      ..lineQtyChanged(uid, '3')
      ..linePriceChanged(uid, '10.4');
    expect([c.state.subtotal, c.state.total, c.state.roundOffValue], [31.2, 31, -0.2]);
    c.roundOffToggled(false);
    expect(c.state.total, 31.2);

    c.categoryChanged(null);
    expect(c.validate(), 'Select an expense category.');
    await c.save(andNew: false);
    expect(repo.saved, isEmpty);

    c.categoryChanged('x4');
    await c.save(andNew: true);
    expect(repo.saved.single['lines'], [
      {'name': 'Office tea', 'quantity': 3, 'price': 10.4},
    ]);
    expect(c.state.result, ExpenseFormResult.savedAndNew);
    expect(c.state.categoryId, 'x4'); // stays in the same category for the next one
    expect(c.state.lines.single.isBlank, isTrue);
  });

  test('editing loads the saved expense', () async {
    final c = ExpenseFormCubit(FakeExpensesRepository(), FakeCashBankRepository(), ChangeBus(), expenseId: 'ex2');
    await c.load();
    expect([c.state.categoryId, c.state.number, c.state.paymentMode, c.state.total], ['x1', '2', 'upi', 800]);
    expect(c.validate(), 'Select the bank account.'); // UPI expense saved before any bank account existed
    c.bankAccountChanged('b1');
    expect(c.validate(), isNull);
    expect(c.state.lines.single.name, 'Diesel');
  });

  test('expenses bloc: selects the first category, loads its expenses, searches', () async {
    final bloc = ExpensesBloc(FakeExpensesRepository(), ChangeBus())..add(const ExpensesRequested());
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.status, LoadStatus.success);
    expect(bloc.state.selected?.name, 'Petrol');
    expect(bloc.state.expenses, hasLength(2));
    expect(bloc.state.total, 16680);
    bloc.add(const ExpenseCategorySearchChanged('tra'));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state.visible.single.name, 'Transport');
    await bloc.close();
  });
}
