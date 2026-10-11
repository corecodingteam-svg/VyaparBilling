import { r2 } from '../common/party-balance';

export interface LineInput {
  quantity: number;
  price: number;
  discountPct?: number | null;
  discountAmount?: number | null;
  gstRate?: number | null;
  /** Compensation cess %, charged on the taxable value like GST. */
  cessRate?: number | null;
}

export interface TaxOptions {
  /** The typed unit prices already include GST (and cess). */
  pricesIncludeTax?: boolean;
  /** Supply to a different state: IGST instead of CGST + SGST. */
  interState?: boolean;
  /** This line's share of a bill-level discount, taken off before tax. */
  billDiscount?: number;
}

export interface ComputedLine {
  gross: number;
  discountPct: number;
  discountAmount: number;
  /** Share of the bill-level discount. */
  billDiscount: number;
  gstRate: number;
  cessRate: number;
  taxableValue: number;
  cgst: number;
  sgst: number;
  igst: number;
  cess: number;
  /** Taxable value + tax: what the customer pays for this line. */
  amount: number;
}

/** gross − the line's own discount (a percentage wins over a fixed amount). */
function lineDiscount(l: LineInput) {
  const gross = r2(l.quantity * l.price);
  if (l.discountPct) return { gross, discountPct: l.discountPct, discountAmount: r2((gross * l.discountPct) / 100) };
  const discountAmount = Math.min(l.discountAmount ?? 0, gross);
  return { gross, discountAmount, discountPct: gross > 0 ? r2((discountAmount / gross) * 100) : 0 };
}

/**
 * gross = qty × price; the line discount and then its share of any bill discount come off;
 * GST (and cess) is then either added on top or, for tax-inclusive prices, taken out of that value.
 * Intra-state tax is split equally into CGST and SGST, with any odd paisa going to SGST.
 */
export function computeLine(l: LineInput, opts: TaxOptions = {}): ComputedLine {
  const { gross, discountPct, discountAmount } = lineDiscount(l);
  const afterLine = r2(gross - discountAmount);
  const billDiscount = Math.min(opts.billDiscount ?? 0, afterLine);
  const net = r2(afterLine - billDiscount);

  const gstRate = l.gstRate ?? 0;
  const cessRate = l.cessRate ?? 0;
  let taxableValue: number;
  let tax: number;
  let cess: number;
  if (opts.pricesIncludeTax) {
    taxableValue = r2(net / (1 + (gstRate + cessRate) / 100));
    // Without cess all of the difference is GST; with cess, cess takes what GST leaves.
    tax = cessRate ? r2((taxableValue * gstRate) / 100) : r2(net - taxableValue);
    cess = cessRate ? r2(net - taxableValue - tax) : 0;
  } else {
    taxableValue = net;
    tax = r2((net * gstRate) / 100);
    cess = r2((net * cessRate) / 100);
  }
  const cgst = opts.interState ? 0 : Math.floor(Math.round(tax * 100) / 2) / 100;
  const sgst = opts.interState ? 0 : r2(tax - cgst);
  const igst = opts.interState ? tax : 0;

  return { gross, discountPct, discountAmount, billDiscount, gstRate, cessRate, taxableValue, cgst, sgst, igst, cess, amount: r2(taxableValue + tax + cess) };
}

/** Invoice totals; with [roundOff] the total is rounded to the nearest rupee. */
export function computeTotals(lines: ComputedLine[], roundOff: boolean) {
  const sum = (k: keyof ComputedLine) => r2(lines.reduce((s, l) => s + l[k], 0));
  const subtotal = sum('amount');
  const total = roundOff ? Math.round(subtotal) : subtotal;
  return {
    taxableAmount: sum('taxableValue'),
    cgst: sum('cgst'),
    sgst: sum('sgst'),
    igst: sum('igst'),
    subtotal,
    total,
    roundOff: r2(total - subtotal),
  };
}

export interface DocumentOptions {
  pricesIncludeTax?: boolean;
  interState?: boolean;
  roundOff: boolean;
  /** Bill-level discount: a percentage wins over a fixed amount. */
  billDiscountPct?: number | null;
  billDiscountAmount?: number | null;
  /** Freight, packing and the like, added after tax. */
  charges?: number;
  /** TCS %, collected on the bill value (items + tax + charges). */
  tcsRate?: number | null;
  /** TDS %, held back by the payer on the taxable value; it does not change the bill total. */
  tdsRate?: number | null;
}

/**
 * A whole document: lines, then the bill discount spread over them in proportion to their value
 * (so GST is charged on the discounted value), then charges, TCS and round-off.
 */
export function computeDocument(lines: LineInput[], opts: DocumentOptions) {
  const nets = lines.map((l) => {
    const d = lineDiscount(l);
    return r2(d.gross - d.discountAmount);
  });
  const totalNet = r2(nets.reduce((s, n) => s + n, 0));
  const discountAmount = opts.billDiscountPct ? r2((totalNet * opts.billDiscountPct) / 100) : Math.min(opts.billDiscountAmount ?? 0, totalNet);

  // Each line's share, with the last line taking whatever rounding leaves over.
  const shares = nets.map((n) => (totalNet > 0 ? r2((n / totalNet) * discountAmount) : 0));
  const last = nets.reduce((idx, n, i) => (n > 0 ? i : idx), -1);
  if (last >= 0) shares[last] = r2(shares[last] + discountAmount - shares.reduce((s, v) => s + v, 0));

  const computed = lines.map((l, i) => computeLine(l, { pricesIncludeTax: opts.pricesIncludeTax, interState: opts.interState, billDiscount: shares[i] }));
  const sum = (k: keyof ComputedLine) => r2(computed.reduce((s, l) => s + l[k], 0));
  const subtotal = sum('amount');
  const chargesTotal = r2(opts.charges ?? 0);
  const tcsAmount = r2(((subtotal + chargesTotal) * (opts.tcsRate ?? 0)) / 100);
  const beforeRound = r2(subtotal + chargesTotal + tcsAmount);
  const total = opts.roundOff ? Math.round(beforeRound) : beforeRound;
  const taxableAmount = sum('taxableValue');
  return {
    lines: computed,
    taxableAmount,
    cgst: sum('cgst'),
    sgst: sum('sgst'),
    igst: sum('igst'),
    cess: sum('cess'),
    /** Sum of the line amounts (tax included), before charges, TCS and round-off. */
    subtotal,
    discountAmount,
    discountPct: opts.billDiscountPct ?? (totalNet > 0 ? Math.round((discountAmount / totalNet) * 1e6) / 1e4 : 0),
    chargesTotal,
    tcsAmount,
    tdsAmount: r2((taxableAmount * (opts.tdsRate ?? 0)) / 100),
    total,
    roundOff: r2(total - beforeRound),
  };
}
