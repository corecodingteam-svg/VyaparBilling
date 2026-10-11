import { computeDocument, computeLine } from '../src/invoices/invoice-math';

describe('whole-document maths', () => {
  it('spreads a bill discount over the lines before tax, exactly', () => {
    const doc = computeDocument(
      [
        { quantity: 1, price: 100, gstRate: 18 },
        { quantity: 1, price: 200, gstRate: 18 },
        { quantity: 1, price: 33.33, gstRate: 5 },
      ],
      { roundOff: false, billDiscountAmount: 50 },
    );
    expect(doc.discountAmount).toBe(50);
    expect(doc.lines.reduce((s, l) => s + l.billDiscount, 0)).toBeCloseTo(50, 2);
    // Tax is charged on what is left after the discount.
    expect(doc.taxableAmount).toBeCloseTo(333.33 - 50, 2);
    expect(doc.lines[0].taxableValue).toBeCloseTo(85, 2);
    expect(doc.lines[0].cgst + doc.lines[0].sgst).toBeCloseTo(15.3, 2);
  });

  it('takes a percentage bill discount over a fixed one', () => {
    const doc = computeDocument([{ quantity: 2, price: 500 }], { roundOff: false, billDiscountPct: 10, billDiscountAmount: 999 });
    expect([doc.discountAmount, doc.discountPct, doc.total]).toEqual([100, 10, 900]);
  });

  it('adds charges after tax, then TCS on the bill value; TDS is on the taxable value and leaves the total alone', () => {
    const doc = computeDocument([{ quantity: 10, price: 100, gstRate: 18 }], { roundOff: true, charges: 50, tcsRate: 1, tdsRate: 2 });
    expect(doc.subtotal).toBe(1180);
    expect(doc.chargesTotal).toBe(50);
    expect(doc.tcsAmount).toBe(12.3); // 1% of 1230
    expect(doc.total).toBe(1242); // 1242.30 rounded
    expect(doc.roundOff).toBe(-0.3);
    expect(doc.tdsAmount).toBe(20); // 2% of 1000
  });

  it('charges cess on the taxable value, on top of or inside the price', () => {
    const exclusive = computeLine({ quantity: 1, price: 1000, gstRate: 28, cessRate: 12 });
    expect([exclusive.taxableValue, exclusive.cgst + exclusive.sgst, exclusive.cess, exclusive.amount]).toEqual([1000, 280, 120, 1400]);
    const inclusive = computeLine({ quantity: 1, price: 1400, gstRate: 28, cessRate: 12 }, { pricesIncludeTax: true });
    expect([inclusive.taxableValue, inclusive.cgst + inclusive.sgst, inclusive.cess, inclusive.amount]).toEqual([1000, 280, 120, 1400]);
  });

  it('is unchanged for a plain document', () => {
    const doc = computeDocument([{ quantity: 3, price: 120, discountPct: 10, gstRate: 18 }], { roundOff: false });
    expect([doc.discountAmount, doc.chargesTotal, doc.tcsAmount, doc.tdsAmount, doc.cess]).toEqual([0, 0, 0, 0, 0]);
    expect(doc.total).toBe(382.32);
  });
});
