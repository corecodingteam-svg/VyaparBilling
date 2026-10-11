import 'package:billing_app/core/change_bus.dart';
import 'package:billing_app/core/status.dart';
import 'package:billing_app/data/models/item.dart';
import 'package:billing_app/features/pos/pos_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late FakeInvoicesRepository invoices;

  Future<PosCubit> build() async {
    invoices = FakeInvoicesRepository();
    final items = FakeItemsRepository([
      Item.fromJson(itemJson('i1', 'Sample Item', gstRate: 18)), // 100 excl. tax → 118 at the counter
      Item.fromJson(itemJson('s1', 'Home Delivery', type: 'service')), // 100, no tax
    ]);
    final cubit = PosCubit(invoices, items, FakeCashBankRepository(), ChangeBus());
    await cubit.load();
    return cubit;
  }

  test('cart: tapping adds and bumps quantity, minus removes at zero', () async {
    final c = await build();
    final item = c.state.items.first;
    c
      ..add(item)
      ..add(item)
      ..add(c.state.items.last);
    expect(c.state.cart.map((l) => l.qty), [2, 1]);
    expect(c.state.cart.first.unitPrice, 118);
    expect([c.state.itemCount, c.state.total], [3, 336]);
    c
      ..changeQty(item, -1)
      ..changeQty(item, -1);
    expect(c.state.cart.single.item.id, 's1');
  });

  test('saving posts a tax-inclusive cash sale and starts a new bill', () async {
    final c = await build();
    await c.save(print: false);
    expect(c.state.error, 'Add at least one item to the bill.');
    expect(invoices.saved, isEmpty);

    c
      ..add(c.state.items.first)
      ..customerNameChanged('Walk-in')
      ..paymentModeChanged('upi');
    await c.save(print: true);
    expect(c.state.error, 'Select the bank account.');
    c.bankAccountChanged('b1');
    await c.save(print: true);
    expect(c.state.submitStatus, SubmitStatus.success);

    final body = invoices.saved.single;
    expect([body['type'], body['isCash'], body['pricesIncludeTax'], body['partyName'], body['bankAccountId']], ['sale', true, true, 'Walk-in', 'b1']);
    expect((body['lines'] as List).single, containsPair('price', 118));
    expect((body['lines'] as List).single, containsPair('gstRate', 18));
    expect([c.state.cart, c.state.customerName, c.state.printAfterSave, c.state.paymentMode], [isEmpty, '', true, 'upi']);
  });
}
