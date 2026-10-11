import { computeLine, computeTotals } from '../src/invoices/invoice-math';

const pick = (l: ReturnType<typeof computeLine>) => [l.taxableValue, l.cgst, l.sgst, l.igst, l.amount];

describe('invoice math', () => {
  it('multiplies quantity by price', () => {
    expect(computeLine({ quantity: 2, price: 120 })).toMatchObject({ gross: 240, discountPct: 0, discountAmount: 0, amount: 240 });
  });

  it('applies a percentage discount and derives the amount', () => {
    expect(computeLine({ quantity: 3, price: 99.99, discountPct: 10 })).toMatchObject({ gross: 299.97, discountPct: 10, discountAmount: 30, amount: 269.97 });
  });

  it('applies a fixed discount and derives the percentage', () => {
    expect(computeLine({ quantity: 1, price: 200, discountAmount: 50 })).toMatchObject({ gross: 200, discountPct: 25, discountAmount: 50, amount: 150 });
  });

  it('never discounts more than the line value', () => {
    expect(computeLine({ quantity: 1, price: 10, discountAmount: 25 }).amount).toBe(0);
  });

  it('avoids float drift on fractional quantities', () => {
    expect(computeLine({ quantity: 0.1, price: 0.3 }).amount).toBe(0.03);
  });

  it('adds intra-state GST as equal CGST and SGST', () => {
    expect(pick(computeLine({ quantity: 2, price: 500, gstRate: 18 }))).toEqual([1000, 90, 90, 0, 1180]);
  });

  it('charges IGST for inter-state supply', () => {
    expect(pick(computeLine({ quantity: 2, price: 500, gstRate: 18 }, { interState: true }))).toEqual([1000, 0, 0, 180, 1180]);
  });

  it('takes GST out of tax-inclusive prices', () => {
    expect(pick(computeLine({ quantity: 1, price: 118, gstRate: 18 }, { pricesIncludeTax: true }))).toEqual([100, 9, 9, 0, 118]);
    // 100 incl. 18% → taxable 84.75, tax 15.25 (odd paisa to SGST), still totals exactly 100
    expect(pick(computeLine({ quantity: 1, price: 100, gstRate: 18 }, { pricesIncludeTax: true }))).toEqual([84.75, 7.62, 7.63, 0, 100]);
  });

  it('taxes the discounted value', () => {
    expect(pick(computeLine({ quantity: 1, price: 1000, discountPct: 10, gstRate: 5 }))).toEqual([900, 22.5, 22.5, 0, 945]);
  });

  it('puts the odd paisa on SGST', () => {
    const l = computeLine({ quantity: 1, price: 0.5, gstRate: 5 }); // tax 0.03 after rounding 0.025
    expect(l.cgst + l.sgst).toBeCloseTo(l.amount - l.taxableValue);
    expect(l.sgst).toBeGreaterThanOrEqual(l.cgst);
  });

  it('totals tax per component and rounds the invoice total', () => {
    const lines = [computeLine({ quantity: 1, price: 10.4, gstRate: 12 }), computeLine({ quantity: 1, price: 5.35 })];
    // 10.40 + 1.25 tax = 11.65 ; 5.35 → 17.00
    expect(computeTotals(lines, true)).toEqual({ taxableAmount: 15.75, cgst: 0.62, sgst: 0.63, igst: 0, subtotal: 17, total: 17, roundOff: 0 });
    const odd = [computeLine({ quantity: 1, price: 10.4 }), computeLine({ quantity: 1, price: 5.35 })];
    expect(computeTotals(odd, true)).toMatchObject({ subtotal: 15.75, total: 16, roundOff: 0.25 });
    expect(computeTotals(odd, false)).toMatchObject({ subtotal: 15.75, total: 15.75, roundOff: 0 });
  });
});
