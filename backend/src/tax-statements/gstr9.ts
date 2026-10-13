/**
 * GSTR-9 (annual return) in the structure of the GST portal's GSTR-9 save API, which is what the GSTR-9 offline
 * tool reads and writes. Tables 4, 5, 6, 9, 17 and 18 are filled from the books; the rest (7, 8, 10–16) are left for
 * the taxpayer, as the books do not hold that information. Sources: the GSTN GSTR-9 save schema as published by
 * GST Suvidha Providers, and the GST portal's "GSTR-9 Offline Utility" guide.
 */

export interface Gstr9Line {
  type: string;
  registered: boolean;
  rate: number;
  hsn: string | null;
  unit: string | null;
  qty: number;
  service: boolean;
  taxable: number;
  igst: number;
  cgst: number;
  sgst: number;
  cess: number;
}

type Tax = { txval: number; iamt: number; camt: number; samt: number; csamt: number };
const r2 = (v: number) => Math.round((v + Number.EPSILON) * 100) / 100;
const zero = (): Tax => ({ txval: 0, iamt: 0, camt: 0, samt: 0, csamt: 0 });
const add = (t: Tax, l: Gstr9Line, sign = 1) => {
  t.txval = r2(t.txval + sign * l.taxable);
  t.iamt = r2(t.iamt + sign * l.igst);
  t.camt = r2(t.camt + sign * l.cgst);
  t.samt = r2(t.samt + sign * l.sgst);
  t.csamt = r2(t.csamt + sign * l.cess);
  return t;
};
const sum = (rows: Gstr9Line[], test: (l: Gstr9Line) => boolean) => rows.filter(test).reduce((t, l) => add(t, l), zero());
const taxOnly = ({ iamt, camt, samt, csamt }: Tax) => ({ iamt, camt, samt, csamt });

const UQC: Record<string, string> = { PCS: 'PCS', NOS: 'NOS', KG: 'KGS', KGS: 'KGS', GM: 'GMS', GMS: 'GMS', LTR: 'LTR', L: 'LTR', MTR: 'MTR', BOX: 'BOX', BAG: 'BAG', DOZ: 'DOZ', SET: 'SET', PAC: 'PAC', PKT: 'PAC', TON: 'TON', BTL: 'BTL', ROL: 'ROL' };

/** HSN-wise summary (tables 17 and 18): one row per HSN, unit and rate. */
function hsnSummary(rows: Gstr9Line[], sign: (l: Gstr9Line) => number) {
  const by = new Map<string, { hsn_sc: string; uqc: string; qty: number; rt: number; txval: number; iamt: number; camt: number; samt: number; csamt: number; isconcesstional: 'N' }>();
  for (const l of rows) {
    if (!l.hsn) continue;
    const uqc = l.service ? 'NA' : (UQC[(l.unit ?? '').toUpperCase()] ?? 'OTH');
    const key = `${l.hsn}|${uqc}|${l.rate}`;
    const e = by.get(key) ?? { hsn_sc: l.hsn, uqc, qty: 0, rt: l.rate, txval: 0, iamt: 0, camt: 0, samt: 0, csamt: 0, isconcesstional: 'N' as const };
    const s = sign(l);
    e.qty = r2(e.qty + s * (l.service ? 0 : l.qty));
    e.txval = r2(e.txval + s * l.taxable);
    e.iamt = r2(e.iamt + s * l.igst);
    e.camt = r2(e.camt + s * l.cgst);
    e.samt = r2(e.samt + s * l.sgst);
    e.csamt = r2(e.csamt + s * l.cess);
    by.set(key, e);
  }
  return [...by.values()].map(({ qty, uqc, ...rest }) => (uqc === 'NA' ? { ...rest, uqc } : { ...rest, uqc, qty }));
}

export function buildGstr9(o: { gstin: string; fyEnd: number; lines: Gstr9Line[]; expenseItc: { igst: number; cgst: number; sgst: number } }) {
  const taxed = (l: Gstr9Line) => l.rate > 0;
  const sales = o.lines.filter((l) => l.type === 'sale');
  const cn = o.lines.filter((l) => l.type === 'credit_note');
  const dn = o.lines.filter((l) => l.type === 'debit_note');
  const purchases = o.lines.filter((l) => l.type === 'purchase');

  // Table 6B: inward supplies other than imports and reverse charge, by inputs, capital goods (not told apart in the books) and services.
  const inputs = taxOnly(sum(purchases, (l) => taxed(l) && !l.service));
  const services = taxOnly(sum(purchases, (l) => taxed(l) && l.service));
  services.iamt = r2(services.iamt + o.expenseItc.igst);
  services.camt = r2(services.camt + o.expenseItc.cgst);
  services.samt = r2(services.samt + o.expenseItc.sgst);
  // Purchase returns (debit notes we raised) reduce the credit on inputs.
  const returned = taxOnly(sum(dn, taxed));
  for (const k of ['iamt', 'camt', 'samt', 'csamt'] as const) inputs[k] = r2(inputs[k] - returned[k]);

  const outward = sum(sales, taxed);
  for (const l of cn.filter(taxed)) add(outward, l, -1);

  return {
    gstin: o.gstin,
    fp: `03${o.fyEnd}`,
    table4: {
      b2c: sum(sales, (l) => taxed(l) && !l.registered),
      b2b: sum(sales, (l) => taxed(l) && l.registered),
      exp: { txval: 0, iamt: 0, csamt: 0 },
      sez: { txval: 0, iamt: 0, csamt: 0 },
      deemed: zero(),
      at: zero(),
      rchrg: zero(),
      cr_nt: sum(cn, taxed),
      dr_nt: zero(),
      amd_pos: zero(),
      amd_neg: zero(),
    },
    table5: {
      zero_rtd: { txval: 0 },
      sez: { txval: 0 },
      rchrg: { txval: 0 },
      // The books do not tell exempt and nil-rated supplies apart; all 0% supplies are reported as nil-rated.
      exmt: { txval: 0 },
      nil: { txval: sum(sales, (l) => !taxed(l)).txval },
      non_gst: { txval: 0 },
      cr_nt: { txval: sum(cn, (l) => !taxed(l)).txval },
      dr_nt: { txval: 0 },
      amd_pos: { txval: 0 },
      amd_neg: { txval: 0 },
    },
    table6: {
      supp_non_rchrg: [
        { itc_typ: 'ip', ...inputs },
        { itc_typ: 'cg', iamt: 0, camt: 0, samt: 0, csamt: 0 },
        { itc_typ: 'is', ...services },
      ],
    },
    table9: {
      iamt: { txpyble: outward.iamt },
      camt: { txpyble: outward.camt },
      samt: { txpyble: outward.samt },
      csamt: { txpyble: outward.csamt },
      intr: { txpyble: 0 },
      fee: { txpyble: 0 },
      pen: { txpyble: 0 },
      other: { txpyble: 0 },
    },
    table17: { items: hsnSummary([...sales, ...cn], (l) => (l.type === 'credit_note' ? -1 : 1)) },
    table18: { items: hsnSummary([...purchases, ...dn], (l) => (l.type === 'debit_note' ? -1 : 1)) },
  };
}
