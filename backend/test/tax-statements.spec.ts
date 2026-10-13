import { allocate, buildStatement, collecteeCodeFromPan, itStateCode, problems, quarterOf, quarterRange, StatementInput } from '../src/tax-statements/fvu-file';
import { buildGstr9 } from '../src/tax-statements/gstr9';

const base = (over: Partial<StatementInput> = {}): StatementInput => ({
  form: '140', taxYear: '202627', quarter: 'Q2', created: '2026-10-13',
  firm: { tan: 'PNEA12345B', pan: 'AAACA1234C', name: 'Acme Traders Pvt Ltd', address: 'Shop 4, Laxmi Road, Sadashiv Peth near Mandai', city: 'Pune', stateCode: '27', pincode: '411030', email: 'accounts@acme.example', phone: '+91 98765 43210', gstin: '27AAACA1234C1Z5' },
  deductorType: 'K',
  responsible: { name: 'R. Sharma', designation: 'Director', pan: 'ABCPS1234D', mobile: '9876543210', email: 'r@acme.example' },
  previousToken: '',
  challans: [{ bsr: '0510308', number: '12345', date: '2026-10-05', tax: 5000, interest: 0, fee: 0, other: 0, minorHead: '200', ref: '0510308/12345' }],
  deductees: [
    { pan: 'AAAFM1111A', name: 'Mega Supplier', section: '1031', date: '2026-08-14', amount: 300000, tax: 300, rate: 0.1, ref: 'Bill B-1' },
    { pan: 'BBBPK2222B', name: 'Kumar & Sons', section: '1031', date: '2026-07-02', amount: 150000.5, tax: 150, rate: 0.1, ref: 'Bill B-2' },
  ],
  ...over,
});

describe('Form 140 / 143 statement file', () => {
  it('has one header, one batch, the used challans and every deductee, with the field counts the spec gives', () => {
    const file = buildStatement(base());
    expect(file.endsWith('\r\n')).toBe(true);
    const lines = file.split('\r\n').slice(0, -1);
    expect(lines.map((l) => l.split('^')[1])).toEqual(['FH', 'BH', 'CD', 'DD', 'DD']);
    expect(lines.map((l) => l.split('^').length)).toEqual([18, 72, 30, 45, 45]);
    expect(lines.map((l) => l.split('^')[0])).toEqual(['1', '2', '3', '4', '5']);
    expect(/^[\x20-\x7E\r\n]*$/.test(file)).toBe(true);
  });

  it('puts the values in the right places', () => {
    const [fh, bh, cd, dd1] = buildStatement(base()).split('\r\n').map((l) => l.split('^'));
    expect(fh.slice(1, 10)).toEqual(['FH', 'NS1', 'R', '13102026', '1', 'D', 'PNEA12345B', '1', 'Billing']);
    const f = (r: string[], i: number) => r[i - 1];
    expect([f(bh, 4), f(bh, 5), f(bh, 13), f(bh, 15), f(bh, 16), f(bh, 17), f(bh, 18)]).toEqual(['1', '140', 'PNEA12345B', 'AAACA1234C', '202728', '202627', 'Q2']);
    expect([f(bh, 20), f(bh, 21), f(bh, 22), f(bh, 25), f(bh, 26), f(bh, 27)]).toEqual(['INDIA', 'Shop 4 Laxmi Road', 'Sadashiv Peth near Mandai', 'Pune', '19', '411030']);
    expect([f(bh, 29), f(bh, 30), f(bh, 32), f(bh, 33), f(bh, 45), f(bh, 47), f(bh, 52), f(bh, 59), f(bh, 69)]).toEqual(['91', '9876543210', 'K', 'R. Sharma', '9876543210', '5000.00', 'N', 'ABCPS1234D', '27AAACA1234C1Z5']);
    expect([f(cd, 4), f(cd, 5), f(cd, 6), f(cd, 8), f(cd, 12), f(cd, 13), f(cd, 15), f(cd, 17), f(cd, 19), f(cd, 21), f(cd, 22), f(cd, 23)]).toEqual(
      ['1', '2', 'N', '5000.00', '5000.00', 'C', '0510308', '12345', '05102026', '450.00', '450.00', '200'],
    );
    // Oldest bill first.
    expect([f(dd1, 4), f(dd1, 5), f(dd1, 6), f(dd1, 8), f(dd1, 9), f(dd1, 15), f(dd1, 18), f(dd1, 19), f(dd1, 20), f(dd1, 24), f(dd1, 25), f(dd1, 27), f(dd1, 28)]).toEqual(
      ['1', '1', 'O', 'BBBPK2222B', 'Kumar & Sons', '1031', 'Y', '02072026', '150000.50', '150.00', '150.00', '02072026', '0.1000'],
    );
  });

  it('Form 143 says TC1, 143, and the collectee type', () => {
    const lines = buildStatement(base({ form: '143', deductees: [{ pan: 'AAACB5555C', name: 'Scrap Buyer', section: '1073', date: '2026-08-01', amount: 100000, tax: 1000, rate: 1, ref: 'Bill 9' }] }))
      .split('\r\n').map((l) => l.split('^'));
    expect([lines[0][2], lines[1][4]]).toEqual(['TC1', '143']);
    const dd = lines[3];
    expect([dd[10], dd[11], dd[12], dd[13], dd[14]]).toEqual(['N', '1', '', 'N', '1073']);
    expect(dd.length).toBe(45);
  });

  it('a previous statement token is carried and flagged', () => {
    const bh = buildStatement(base({ previousToken: '123456789012345' })).split('\r\n')[1].split('^');
    expect([bh[8], bh[51]]).toEqual(['123456789012345', 'Y']);
  });

  it('lists what is missing in plain words', () => {
    expect(problems(base())).toEqual([]);
    const p = problems(base({ firm: { ...base().firm, tan: null, pincode: null }, responsible: { ...base().responsible, pan: '' }, challans: [] }));
    expect(p.join('\n')).toMatch(/TAN/);
    expect(p.join('\n')).toMatch(/pincode/);
    expect(p.join('\n')).toMatch(/responsible person’s PAN/);
    expect(p.join('\n')).toMatch(/Record the challan/);
    expect(problems(base({ deductees: [{ ...base().deductees[0], section: '194Q' }] })).join()).toMatch(/not one the form allows/);
    expect(problems(base({ taxYear: '202526' })).join()).toMatch(/old Form 26Q/);
    expect(problems(base({ challans: [{ ...base().challans[0], tax: 100.5 }] })).join()).toMatch(/whole rupees/);
  });

  it('puts each bill under a challan with room for it, and reports what does not fit', () => {
    const c = (tax: number) => ({ ...base().challans[0], tax });
    const d = base().deductees;
    const { byChallan, unplaced } = allocate([c(200), c(300)], d);
    expect(byChallan.map((x) => x.map((r) => r.ref))).toEqual([['Bill B-2'], ['Bill B-1']]);
    expect(unplaced).toEqual([]);
    expect(allocate([c(200)], d).unplaced.map((x) => x.ref)).toEqual(['Bill B-1']);
    // An unused challan is left out of the file.
    const lines = buildStatement(base({ challans: [c(1000), c(9000)] })).split('\r\n');
    expect(lines.filter((l) => l.includes('^CD^')).length).toBe(1);
  });

  it('maps GST state codes to income-tax state codes, and PANs to collectee types', () => {
    expect([itStateCode('27'), itStateCode('07'), itStateCode('29'), itStateCode('36'), itStateCode('97')]).toEqual(['19', '09', '15', '36', null]);
    expect([collecteeCodeFromPan('AAACB1234C'), collecteeCodeFromPan('ABCPK1234D'), collecteeCodeFromPan('AAAFF1234E'), collecteeCodeFromPan(null)]).toEqual([1, 2, 7, 10]);
  });

  it('knows which quarter of which tax year a date is in', () => {
    expect([quarterOf('2026-04-01'), quarterOf('2026-09-30'), quarterOf('2027-03-31')]).toEqual([
      { taxYear: '202627', quarter: 'Q1' }, { taxYear: '202627', quarter: 'Q2' }, { taxYear: '202627', quarter: 'Q4' },
    ]);
    expect(quarterRange('202627', 'Q4')).toEqual({ from: '2027-01-01', to: '2027-03-31' });
  });
});

describe('GSTR-9 JSON', () => {
  const l = (type: string, taxable: number, rate: number, extra: Partial<Parameters<typeof buildGstr9>[0]['lines'][number]> = {}) => {
    const tax = (taxable * rate) / 100;
    return { type, registered: true, rate, hsn: '8501', unit: 'PCS', qty: 1, service: false, taxable, igst: 0, cgst: tax / 2, sgst: tax / 2, cess: 0, ...extra };
  };
  it('fills tables 4, 5, 6, 9, 17 and 18 in the portal’s structure', () => {
    const j = buildGstr9({
      gstin: '27AAACA1234C1Z5', fyEnd: 2026,
      lines: [l('sale', 1000, 18), l('sale', 500, 18, { registered: false }), l('sale', 200, 0, { hsn: '4901' }), l('credit_note', 100, 18), l('purchase', 600, 18, { igst: 108, cgst: 0, sgst: 0 }), l('purchase', 300, 18, { service: true, hsn: '9983' })],
      expenseItc: { igst: 18, cgst: 9, sgst: 9 },
    });
    expect(j.fp).toBe('032026');
    expect(j.table4.b2b).toEqual({ txval: 1000, iamt: 0, camt: 90, samt: 90, csamt: 0 });
    expect(j.table4.b2c.txval).toBe(500);
    expect(j.table4.cr_nt.txval).toBe(100);
    expect(j.table5.nil.txval).toBe(200);
    expect(j.table6.supp_non_rchrg).toEqual([
      { itc_typ: 'ip', iamt: 108, camt: 0, samt: 0, csamt: 0 },
      { itc_typ: 'cg', iamt: 0, camt: 0, samt: 0, csamt: 0 },
      { itc_typ: 'is', iamt: 18, camt: 36, samt: 36, csamt: 0 },
    ]);
    expect([j.table9.camt.txpyble, j.table9.samt.txpyble]).toEqual([126, 126]); // (1000 + 500 − 100) × 9%
    const h = j.table17.items.find((i) => i.hsn_sc === '8501' && i.rt === 18)!;
    expect([h.txval, (h as { qty?: number }).qty, h.uqc]).toEqual([1400, 1, 'PCS']);
    expect(j.table18.items.find((i) => i.hsn_sc === '9983')!.uqc).toBe('NA');
  });
});
