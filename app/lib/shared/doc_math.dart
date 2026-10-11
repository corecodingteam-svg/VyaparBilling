/// Document totals as the form shows them while typing. This mirrors the server
/// (backend/src/invoices/invoice-math.ts); the server's figures are the ones that are saved.
library;

num _r2(num v) => (v * 100).round() / 100;

class DocLineInput {
  const DocLineInput({required this.gross, required this.discount, this.gstRate = 0, this.cessRate = 0});

  /// Quantity × price.
  final num gross;

  /// The line's own discount, as an amount.
  final num discount;
  final num gstRate;
  final num cessRate;
}

class DocLine {
  const DocLine({required this.billDiscount, required this.taxable, required this.tax, required this.cess});

  /// This line's share of the bill-level discount.
  final num billDiscount;
  final num taxable;

  /// GST only.
  final num tax;
  final num cess;

  /// What the customer pays for the line.
  num get amount => _r2(taxable + tax + cess);
}

class DocTotals {
  const DocTotals({
    required this.lines,
    required this.discountAmount,
    required this.charges,
    required this.tcs,
    required this.tds,
    required this.total,
    required this.roundOff,
  });

  final List<DocLine> lines;

  /// What the bill-level discount came to.
  final num discountAmount;
  final num charges;
  final num tcs;

  /// Held back by the payer; it does not change [total].
  final num tds;
  final num total;
  final num roundOff;

  num get taxable => _r2(lines.fold<num>(0, (s, l) => s + l.taxable));

  /// GST and cess together.
  num get tax => _r2(lines.fold<num>(0, (s, l) => s + l.tax + l.cess));
  num get cess => _r2(lines.fold<num>(0, (s, l) => s + l.cess));

  /// Sum of the line amounts (tax included), before charges, TCS and round-off.
  num get subtotal => _r2(lines.fold<num>(0, (s, l) => s + l.amount));
}

/// Lines, then the bill discount spread over them in proportion to their value (so tax is charged
/// on the discounted value), then charges, TCS and round-off.
DocTotals computeDoc(
  List<DocLineInput> lines, {
  bool pricesIncludeTax = false,
  bool roundOff = false,
  num? billDiscountPct,
  num? billDiscountAmount,
  num charges = 0,
  num tcsRate = 0,
  num tdsRate = 0,
}) {
  final nets = [for (final l in lines) _r2(l.gross - l.discount.clamp(0, l.gross))];
  final totalNet = _r2(nets.fold<num>(0, (s, n) => s + n));
  final discount = billDiscountPct != null && billDiscountPct > 0 ? _r2(totalNet * billDiscountPct / 100) : (billDiscountAmount ?? 0).clamp(0, totalNet);

  final shares = [for (final n in nets) totalNet > 0 ? _r2(n / totalNet * discount) : 0];
  final last = nets.lastIndexWhere((n) => n > 0);
  if (last >= 0) shares[last] = _r2(shares[last] + discount - shares.fold<num>(0, (s, v) => s + v));

  final computed = <DocLine>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final net = _r2(nets[i] - shares[i]);
    num taxable, tax, cess;
    if (pricesIncludeTax) {
      taxable = _r2(net / (1 + (l.gstRate + l.cessRate) / 100));
      tax = l.cessRate > 0 ? _r2(taxable * l.gstRate / 100) : _r2(net - taxable);
      cess = l.cessRate > 0 ? _r2(net - taxable - tax) : 0;
    } else {
      taxable = net;
      tax = _r2(net * l.gstRate / 100);
      cess = _r2(net * l.cessRate / 100);
    }
    computed.add(DocLine(billDiscount: shares[i], taxable: taxable, tax: tax, cess: cess));
  }
  final subtotal = _r2(computed.fold<num>(0, (s, l) => s + l.amount));
  final tcs = _r2((subtotal + charges) * tcsRate / 100);
  final before = _r2(subtotal + charges + tcs);
  final total = roundOff ? before.round() : before;
  final taxable = _r2(computed.fold<num>(0, (s, l) => s + l.taxable));
  return DocTotals(
    lines: computed,
    discountAmount: discount,
    charges: _r2(charges),
    tcs: tcs,
    tds: _r2(taxable * tdsRate / 100),
    total: total,
    roundOff: _r2(total - before),
  );
}
