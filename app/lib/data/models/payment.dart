import 'package:equatable/equatable.dart';

import 'invoice.dart' show PaymentPart, paymentModes;

class PaymentKind {
  const PaymentKind._(this.type, this.title, this.amountLabel, this.basePath);
  final String type;
  final String title;
  final String amountLabel;
  final String basePath;

  static const paymentIn = PaymentKind._('in', 'Payment-In', 'Received', '/payment-in');
  static const paymentOut = PaymentKind._('out', 'Payment-Out', 'Paid', '/payment-out');

  static PaymentKind of(String type) => type == 'out' ? paymentOut : paymentIn;
}

/// Part of a payment set against one invoice.
class PaymentAllocation extends Equatable {
  PaymentAllocation.fromJson(Map<String, dynamic> j)
      : invoiceId = j['invoiceId'] as String,
        amount = j['amount'] as num,
        number = (j['number'] as String?) ?? '',
        invoiceDate = j['invoiceDate'] as String?,
        total = (j['total'] as num?) ?? 0;

  final String invoiceId;
  final num amount;
  final String number;
  final String? invoiceDate;
  final num total;

  @override
  List<Object?> get props => [invoiceId, amount, number, invoiceDate, total];
}

class Payment extends Equatable {
  Payment.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        type = j['type'] as String,
        number = j['number'] as String,
        partyId = j['partyId'] as String,
        partyName = j['partyName'] as String,
        paymentDate = j['paymentDate'] as String,
        amount = j['amount'] as num,
        paymentMode = j['paymentMode'] as String,
        bankAccountId = j['bankAccountId'] as String?,
        linkedAmount = (j['linkedAmount'] as num?) ?? 0,
        currencyCode = j['currencyCode'] as String?,
        exchangeRate = j['exchangeRate'] as num?,
        baseAmount = (j['baseAmount'] as num?) ?? j['amount'] as num,
        fxGain = (j['fxGain'] as num?) ?? 0,
        paymentLabel = (j['paymentLabel'] as String?) ?? (paymentModes[j['paymentMode']] ?? j['paymentMode'] as String),
        parts = [for (final p in (j['parts'] as List?) ?? const []) PaymentPart.fromJson(p as Map<String, dynamic>)],
        allocations = [for (final a in (j['allocations'] as List?) ?? const []) PaymentAllocation.fromJson(a as Map<String, dynamic>)],
        description = j['description'] as String?;

  final String id;
  final String type;
  final String number;
  final String partyId;
  final String partyName;
  final String paymentDate;
  final num amount;
  final String paymentMode;
  final String? bankAccountId;

  /// Part of [amount] set against specific invoices; the rest only reduces the party's overall balance.
  final num linkedAmount;

  /// A foreign-currency payment: [amount], [parts] and [allocations] are in this currency.
  final String? currencyCode;
  final num? exchangeRate;

  /// What it came to in rupees.
  final num baseAmount;

  /// Exchange gain (+) or loss (−) against the rates its invoices were booked at.
  final num fxGain;

  /// How it was paid, e.g. "Cash + Cheque".
  final String paymentLabel;

  /// The modes it was paid in (only filled when a single payment is fetched).
  final List<PaymentPart> parts;

  /// The invoices it settles (only filled when a single payment is fetched).
  final List<PaymentAllocation> allocations;
  final String? description;

  num get unlinkedAmount => amount - linkedAmount;

  @override
  List<Object?> get props => [id, type, number, partyId, partyName, paymentDate, amount, paymentMode, bankAccountId, linkedAmount, allocations, description, currencyCode, exchangeRate, baseAmount, fxGain, paymentLabel, parts];
}

/// A payment that can be set against a document, seen from the document's side.
class LinkablePayment extends Equatable {
  LinkablePayment.fromJson(Map<String, dynamic> j)
      : paymentId = j['paymentId'] as String,
        number = j['number'] as String,
        date = j['date'] as String,
        amount = j['amount'] as num,
        free = j['free'] as num,
        linked = j['linked'] as num;

  final String paymentId;
  final String number;
  final String date;
  final num amount;

  /// What is not linked to other documents (so includes [linked]).
  final num free;

  /// Already linked to this document.
  final num linked;

  @override
  List<Object?> get props => [paymentId, number, date, amount, free, linked];
}

class LinkablePayments extends Equatable {
  LinkablePayments.fromJson(Map<String, dynamic> j)
      : due = j['due'] as num,
        payments = [for (final p in j['payments'] as List) LinkablePayment.fromJson(p as Map<String, dynamic>)];

  /// What the document leaves to be settled by payments.
  final num due;
  final List<LinkablePayment> payments;

  @override
  List<Object?> get props => [due, payments];
}
