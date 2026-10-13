/**
 * Quarterly TDS (Form 140, formerly 26Q) and TCS (Form 143, formerly 27EQ) statements in the text format the
 * Income Tax Department's File Validation Utility (FVU 1.2) reads: "^"-delimited records FH, BH, CD and DD.
 * Built from Protean's published file formats "Form Number 140 - 26Q - Q1 to Q4" and "Form Number 143-27EQ -
 * Q1 to Q4" (version 1.1, dated 22-07-2026), for tax year 2026-27 onwards. The file still has to pass the FVU,
 * which also checks the challans against the .csi file downloaded from the TIN site.
 */

export type Form = '140' | '143';

/** Section codes (Annexure 2) a small business is likely to use; any code the department lists is accepted. */
export const TDS_SECTIONS: Record<string, string> = {
  '1031': 'Purchase of goods — 393(1) Table 8(ii)',
  '1023': 'Contract work, contractor an individual/HUF — 393(1) Table 6(i)(a)',
  '1024': 'Contract work, other contractors — 393(1) Table 6(i)(b)',
  '1006': 'Commission or brokerage — 393(1) Table 1(ii)',
  '1008': 'Rent of machinery — 393(1) Table 2(ii)(a)',
  '1009': 'Rent of land, building, furniture — 393(1) Table 2(ii)(b)',
  '1026': 'Fees for technical services — 393(1) Table 6(iii)(a)',
  '1027': 'Fees for professional services — 393(1) Table 6(iii)(b)',
  '1022': 'Interest other than on securities — 393(1) Table 5(iii)',
};

export const TCS_CODES: Record<string, string> = {
  '1073': 'Sale of scrap — 394(1) Table 4',
  '1074': 'Sale of coal, lignite or iron ore — 394(1) Table 5',
  '1068': 'Sale of alcoholic liquor — 394(1) Table 1',
  '1069': 'Sale of tendu leaves — 394(1) Table 2',
  '1070': 'Timber under a forest lease — 394(1) Table 3',
  '1071': 'Timber, other — 394(1) Table 3',
  '1072': 'Other forest produce — 394(1) Table 3',
  '1075': 'Motor vehicle above the threshold — 394(1) Table 6(a)',
  '1076': 'Wrist watch above the threshold — 394(1) Table 6(b)',
  '1077': 'Art piece above the threshold — 394(1) Table 6(b)',
  '1078': 'Collectibles above the threshold — 394(1) Table 6(b)',
  '1079': 'Yacht, boat, helicopter above the threshold — 394(1) Table 6(b)',
  '1080': 'Sunglasses above the threshold — 394(1) Table 6(b)',
  '1081': 'Handbag or purse above the threshold — 394(1) Table 6(b)',
  '1082': 'Shoes above the threshold — 394(1) Table 6(b)',
  '1083': 'Sportswear and equipment above the threshold — 394(1) Table 6(b)',
  '1084': 'Home theatre system above the threshold — 394(1) Table 6(b)',
  '1085': 'Horse for racing or polo above the threshold — 394(1) Table 6(b)',
};

/** Every code of Annexure 2 of each form, to accept codes not in the short lists above. */
const ALL_TDS = new Set('1004 1005 1006 1008 1009 1011 1012 1013 1014 1015 1016 1017 1018 1019 1020 1021 1022 1023 1024 1026 1027 1028 1029 1030 1031 1033 1034 1035 1037 1038 1058 1059 1060 1061 1062 1063 1064 1065 1066 1067'.split(' '));
const ALL_TCS = new Set(Array.from({ length: 25 }, (_, i) => String(1068 + i)));
export const validSection = (form: Form, code: string) => (form === '140' ? ALL_TDS : ALL_TCS).has(code);

/** Income-tax state codes (Annexure 1) differ from GST state codes; this maps GST code → income-tax code. */
const IT_STATE: Record<string, string> = {
  '35': '01', '37': '02', '12': '03', '18': '04', '10': '05', '04': '06', '26': '07', '07': '09', '30': '10', '24': '11', '06': '12',
  '02': '13', '01': '14', '29': '15', '32': '16', '31': '17', '23': '18', '27': '19', '14': '20', '17': '21', '15': '22', '13': '23',
  '21': '24', '34': '25', '03': '26', '08': '27', '11': '28', '33': '29', '16': '30', '09': '31', '19': '32', '22': '33', '05': '34',
  '20': '35', '36': '36', '38': '37',
};
export const itStateCode = (gstCode: string | null | undefined) => (gstCode ? (IT_STATE[gstCode] ?? null) : null);

/** Form 143 collectee type (Annexure 8) from the 4th letter of a PAN, which says what kind of holder it is. */
export function collecteeCodeFromPan(pan: string | null): number {
  switch (pan?.[3]) {
    case 'C': return 1;
    case 'P': return 2;
    case 'H': return 3;
    case 'A': return 4;
    case 'F': return 7;
    case 'B': return 8;
    case 'J': return 9;
    default: return 10;
  }
}

export const PAN = /^[A-Z]{5}[0-9]{4}[A-Z]$/;
export const TAN = /^[A-Z]{4}[0-9]{5}[A-Z]$/;

/** The quarter of a tax year (April–March) a date falls in, e.g. 2026-08-14 → { taxYear: '202627', quarter: 'Q2' }. */
export function quarterOf(iso: string): { taxYear: string; quarter: 'Q1' | 'Q2' | 'Q3' | 'Q4' } {
  const y = Number(iso.slice(0, 4));
  const m = Number(iso.slice(5, 7));
  const start = m >= 4 ? y : y - 1;
  return { taxYear: `${start}${String(start + 1).slice(2)}`, quarter: m >= 4 && m <= 6 ? 'Q1' : m >= 7 && m <= 9 ? 'Q2' : m >= 10 ? 'Q3' : 'Q4' };
}

/** First and last day of a quarter of a tax year such as '202627'. */
export function quarterRange(taxYear: string, quarter: string): { from: string; to: string } {
  const y = Number(taxYear.slice(0, 4));
  const r = { Q1: [`${y}-04-01`, `${y}-06-30`], Q2: [`${y}-07-01`, `${y}-09-30`], Q3: [`${y}-10-01`, `${y}-12-31`], Q4: [`${y + 1}-01-01`, `${y + 1}-03-31`] }[quarter]!;
  return { from: r[0], to: r[1] };
}

export interface Deductee {
  pan: string;
  name: string;
  section: string;
  /** yyyy-mm-dd: the bill date, used as both the date credited and the date of deduction. */
  date: string;
  amount: number;
  tax: number;
  rate: number;
  collecteeCode?: number;
  /** The bill it came from, for messages. */
  ref: string;
}

export interface Challan {
  bsr: string;
  number: string;
  date: string;
  tax: number;
  interest: number;
  fee: number;
  other: number;
  minorHead: string;
  ref: string;
}

export interface StatementInput {
  form: Form;
  taxYear: string;
  quarter: string;
  created: string;
  firm: {
    tan: string | null; pan: string | null; name: string; address: string | null; city: string | null; stateCode: string | null; pincode: string | null;
    email: string | null; phone: string | null; gstin: string | null;
  };
  deductorType: string;
  responsible: { name: string; designation: string; pan: string; mobile: string; email: string };
  previousToken: string;
  challans: Challan[];
  deductees: Deductee[];
}

/** Printable ASCII without the "^" delimiter, at most [size] characters. */
const text = (v: string | null | undefined, size: number) =>
  (v ?? '').normalize('NFKD').replace(/[^\x20-\x7E]/g, '').replace(/\^/g, ' ').replace(/\s+/g, ' ').trim().slice(0, size);
const amt = (n: number) => (Math.round(n * 100) / 100).toFixed(2);
const ddmmyyyy = (iso: string) => `${iso.slice(8, 10)}${iso.slice(5, 7)}${iso.slice(0, 4)}`;

/** An address cut into the form's 25-character lines at word breaks. */
function addressLines(address: string | null, count: number): string[] {
  const words = text(address, 500).split(/[ ,]+/).filter(Boolean);
  const lines: string[] = [];
  let line = '';
  for (const w of words) {
    if ((line ? `${line} ${w}` : w).length <= 25) line = line ? `${line} ${w}` : w;
    else {
      lines.push(line || w.slice(0, 25));
      line = line ? w.slice(0, 25) : '';
    }
  }
  if (line) lines.push(line);
  while (lines.length < count) lines.push('');
  return lines.slice(0, count);
}

/** Puts deductees under challans: each bill's tax goes wholly to the earliest challan that still has room for it. */
export function allocate(challans: Challan[], deductees: Deductee[]) {
  const left = challans.map((c) => c.tax);
  const byChallan: Deductee[][] = challans.map(() => []);
  const unplaced: Deductee[] = [];
  for (const d of [...deductees].sort((a, b) => a.date.localeCompare(b.date))) {
    const i = left.findIndex((l) => l + 0.005 >= d.tax);
    if (i < 0) unplaced.push(d);
    else {
      left[i] = Math.round((left[i] - d.tax) * 100) / 100;
      byChallan[i].push(d);
    }
  }
  return { byChallan, unplaced };
}

/** What stops the statement from being made or passing the FVU, in plain words. */
export function problems(s: StatementInput): string[] {
  const p: string[] = [];
  const who = s.form === '140' ? 'deductor' : 'collector';
  if (Number(s.taxYear.slice(0, 4)) < 2026) p.push('Statements before tax year 2026-27 use the old Form 26Q / 27EQ; prepare those in the department’s Return Preparation Utility.');
  if (!s.firm.tan || !TAN.test(s.firm.tan)) p.push('Add your TAN under Settings → Company (10 characters, e.g. PNEA12345B).');
  if (!s.firm.pan || !PAN.test(s.firm.pan)) p.push(`Add the ${who}'s PAN under Settings → Company.`);
  if (!s.firm.address) p.push('Your company address is missing.');
  if (!itStateCode(s.firm.stateCode)) p.push('Your company state is missing.');
  if (!s.firm.pincode || !/^[1-9]\d{5}$/.test(s.firm.pincode)) p.push('Your company needs a 6-digit pincode.');
  if (!s.firm.phone || s.firm.phone.replace(/\D/g, '').length < 10) p.push('Your company needs a contact number.');
  if (!s.firm.email && !s.responsible.email) p.push('Add an email for the company or the responsible person.');
  if (!s.responsible.name) p.push(`Add the name of the person responsible for ${s.form === '140' ? 'deducting' : 'collecting'} tax.`);
  if (!s.responsible.designation) p.push('Add the responsible person’s designation.');
  if (!PAN.test(s.responsible.pan)) p.push('Add the responsible person’s PAN.');
  if (!/^\d{10}$/.test(s.responsible.mobile)) p.push('Add the responsible person’s 10-digit mobile number.');
  if (!s.deductees.length) p.push(`No bills in this quarter have ${s.form === '140' ? 'TDS deducted' : 'TCS collected'}. The department does not accept a statement without any.`);
  for (const d of s.deductees) {
    if (!validSection(s.form, d.section)) {
      p.push(`${d.ref} (${d.name}): ${s.form === '140' ? 'TDS section' : 'TCS collection code'} ${d.section || 'is not set'}${d.section ? ' is not one the form allows' : ''}. Set it on the party or as the company default.`);
    }
  }
  if (!s.challans.length && s.deductees.length) p.push('Record the challan(s) you deposited this quarter’s tax with.');
  for (const c of s.challans) {
    if (!/^\d{7}$/.test(c.bsr)) p.push(`Challan ${c.ref}: the BSR code has 7 digits.`);
    if (!/^\d{1,5}$/.test(c.number)) p.push(`Challan ${c.ref}: the challan serial number has up to 5 digits.`);
    for (const [name, v] of [['tax', c.tax], ['interest', c.interest], ['fee', c.fee], ['other', c.other]] as const) {
      if (Math.round(v) !== v) p.push(`Challan ${c.ref}: the ${name} must be whole rupees, as on the challan.`);
    }
  }
  const { unplaced } = allocate(s.challans, s.deductees);
  for (const d of unplaced) p.push(`${d.ref} (${d.name}): ${amt(d.tax)} of tax does not fit in any challan of this quarter. Record the challan it was deposited with.`);
  return p;
}

/** The statement file. Call only when [problems] is empty. */
export function buildStatement(s: StatementInput, opts: { appName?: string; sequence?: number } = {}): string {
  const lines: string[] = [];
  const record = (fields: (string | number)[]) => lines.push([lines.length + 1, ...fields.slice(1)].join('^'));
  const sized = (n: number, set: Record<number, string | number>) => {
    const out: (string | number)[] = Array(n).fill('');
    for (const [k, v] of Object.entries(set)) out[Number(k) - 1] = v;
    return out;
  };
  const { byChallan } = allocate(s.challans, s.deductees);
  const used = s.challans.map((c, i) => ({ c, rows: byChallan[i] })).filter((x) => x.rows.length);
  const ty = Number(s.taxYear.slice(0, 4));
  const state = itStateCode(s.firm.stateCode)!;
  const addr = addressLines(s.firm.address, 4);
  const phone = (s.firm.phone ?? '').replace(/\D/g, '').slice(-10);
  const deposit = (c: Challan) => c.tax + c.interest + c.fee + c.other;

  // File header: 18 fields.
  record(sized(18, { 2: 'FH', 3: s.form === '140' ? 'NS1' : 'TC1', 4: 'R', 5: ddmmyyyy(s.created), 6: opts.sequence ?? 1, 7: 'D', 8: s.firm.tan!, 9: 1, 10: text(opts.appName ?? 'Billing', 75) }));
  // Batch header: 72 fields.
  record(sized(72, {
    2: 'BH', 3: 1, 4: used.length, 5: s.form,
    9: s.previousToken, 13: s.firm.tan!, 15: s.firm.pan!, 16: `${ty + 1}${String(ty + 2).slice(2)}`, 17: s.taxYear, 18: s.quarter,
    19: text(s.firm.name, 75), 20: 'INDIA', 21: addr[0], 22: addr[1], 23: addr[2], 24: addr[3], 25: text(s.firm.city, 25), 26: state, 27: s.firm.pincode!,
    28: text(s.firm.email, 75), 29: 91, 30: phone, 32: s.deductorType,
    33: text(s.responsible.name, 75), 34: text(s.responsible.designation, 20), 35: addr[0], 36: addr[1], 37: addr[2], 38: addr[3], 39: text(s.firm.city, 25),
    40: state, 41: s.firm.pincode!, 42: text(s.responsible.email, 75), 43: 'INDIA', 44: 91, 45: s.responsible.mobile,
    47: amt(used.reduce((t, x) => t + deposit(x.c), 0)), 52: s.previousToken ? 'Y' : 'N', 59: s.responsible.pan.toUpperCase(), 69: s.firm.gstin ?? '',
  }));
  let dd = 0;
  used.forEach(({ c, rows }, i) => {
    const total = rows.reduce((t, d) => t + d.tax, 0);
    // Challan detail: 30 fields.
    record(sized(30, {
      2: 'CD', 3: 1, 4: i + 1, 5: rows.length, 6: 'N', 8: amt(c.tax), 9: amt(c.interest), 10: amt(c.fee), 11: amt(c.other), 12: amt(deposit(c)), 13: 'C',
      15: c.bsr, 17: c.number, 19: ddmmyyyy(c.date), 21: amt(total), 22: amt(total), 23: c.minorHead, 24: amt(c.interest), 25: amt(c.other),
    }));
    for (const d of rows) {
      dd++;
      const base = { 2: 'DD', 3: 1, 4: dd, 5: i + 1, 6: 'O', 8: d.pan, 9: text(d.name, 75), 15: d.section, 18: 'Y', 19: ddmmyyyy(d.date), 20: amt(d.amount), 24: amt(d.tax), 25: amt(d.tax), 27: d.tax > 0 ? ddmmyyyy(d.date) : '', 28: d.rate.toFixed(4) };
      // Deductee / collectee detail: 45 fields. Form 143 also says whether the buyer is resident, their type, and the regime option.
      record(sized(45, s.form === '143' ? { ...base, 11: 'N', 12: d.collecteeCode ?? collecteeCodeFromPan(d.pan), 14: 'N' } : base));
    }
  });
  return lines.map((l) => `${l}\r\n`).join('');
}
