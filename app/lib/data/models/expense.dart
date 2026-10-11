import 'package:equatable/equatable.dart';

import 'invoice.dart' show PaymentPart, paymentModes;

class ExpenseCategory extends Equatable {
  ExpenseCategory.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        total = (j['total'] as num?) ?? 0;

  final String id;
  final String name;

  /// Total spent in this category.
  final num total;

  @override
  List<Object?> get props => [id, name, total];
}

class ExpenseSummary extends Equatable {
  ExpenseSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        categoryId = j['categoryId'] as String,
        categoryName = j['categoryName'] as String,
        number = j['number'] as String?,
        expenseDate = j['expenseDate'] as String,
        total = j['total'] as num,
        taxAmount = (j['taxAmount'] as num?) ?? 0,
        paymentMode = j['paymentMode'] as String,
        paymentLabel = (j['paymentLabel'] as String?) ?? (paymentModes[j['paymentMode']] ?? j['paymentMode'] as String),
        bankAccountId = j['bankAccountId'] as String?;

  /// How it was paid, e.g. "Cash + UPI".
  final String paymentLabel;
  final String id;
  final String categoryId;
  final String categoryName;
  final String? number;
  final String expenseDate;
  final num total;

  /// GST included in [total].
  final num taxAmount;
  final String paymentMode;
  final String? bankAccountId;

  @override
  List<Object?> get props => [id, categoryId, categoryName, number, expenseDate, total, taxAmount, paymentMode, bankAccountId];
}

class ExpenseLine extends Equatable {
  ExpenseLine.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String,
        quantity = j['quantity'] as num,
        price = j['price'] as num,
        gstRate = (j['gstRate'] as num?) ?? 0,
        tax = (j['tax'] as num?) ?? 0,
        amount = j['amount'] as num;

  final String name;
  final num quantity;
  final num price;

  /// GST %; 0 = none.
  final num gstRate;
  final num tax;

  /// Tax included.
  final num amount;

  @override
  List<Object?> get props => [name, quantity, price, gstRate, tax, amount];
}

class Expense extends ExpenseSummary {
  Expense.fromJson(super.j)
      : subtotal = j['subtotal'] as num,
        taxableAmount = (j['taxableAmount'] as num?) ?? j['subtotal'] as num,
        pricesIncludeTax = (j['pricesIncludeTax'] as bool?) ?? false,
        payments = [for (final p in (j['payments'] as List?) ?? const []) PaymentPart.fromJson(p as Map<String, dynamic>)],
        roundOff = j['roundOff'] as num,
        description = j['description'] as String?,
        lines = [for (final l in j['lines'] as List) ExpenseLine.fromJson(l as Map<String, dynamic>)],
        super.fromJson();

  final num subtotal;
  final num taxableAmount;
  final bool pricesIncludeTax;

  /// The modes it was paid in.
  final List<PaymentPart> payments;
  final num roundOff;
  final String? description;
  final List<ExpenseLine> lines;

  @override
  List<Object?> get props => [...super.props, subtotal, taxableAmount, pricesIncludeTax, roundOff, description, lines];
}

/// A reusable expense item ("Petrol", "Tea") offered while entering expenses.
class ExpenseItemDef extends Equatable {
  ExpenseItemDef.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        price = (j['price'] as num?) ?? 0,
        hsnCode = j['hsnCode'] as String?,
        gstRate = j['gstRate'] as num?,
        total = (j['total'] as num?) ?? 0;

  final String id;
  final String name;
  final num price;
  final String? hsnCode;
  final num? gstRate;

  /// Total spent on this item so far.
  final num total;

  @override
  List<Object?> get props => [id, name, price, hsnCode, gstRate, total];
}
