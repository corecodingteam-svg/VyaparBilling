// End-to-end checks of the TDS/TCS statement files and the GSTR-9 JSON against a running backend (PORT 3100).
const B = 'http://localhost:3100/api/v1';
let token;
const call = async (method, path, body, expect) => {
  const r = await fetch(B + path, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text();
  const json = text ? JSON.parse(text) : null;
  if (expect ? r.status !== expect : !r.ok) throw new Error(`${method} ${path} -> ${r.status} ${text.slice(0, 500)}`);
  return json?.data ?? json;
};
const ok = (cond, msg) => { if (!cond) throw new Error('ASSERT ' + msg); console.log('ok  ' + msg); };

token = (await call('POST', '/auth/register', { firmName: 'Tax Co', fullName: 'Owner', email: `t${Date.now()}@example.com`, password: 'Password123', stateCode: '27' })).accessToken;
await call('PATCH', '/firm', { gstin: '27AAACA1234C1Z5', address: 'Shop 4, Laxmi Road', city: 'Pune', pincode: '411030', phone: '9876543210', email: 'a@acme.example', settings: { tdsEnabled: true, tcsEnabled: true } });
const supp = await call('POST', '/parties', { name: 'Mega Supplier', gstin: '29AAAFM1111A1Z6', gstType: 'regular', stateCode: '29' });
const scrap = await call('POST', '/parties', { name: 'Scrap Buyer', pan: 'aaacb5555c', tcsCode: '1073', stateCode: '27' });
ok(scrap.pan === 'AAACB5555C' && scrap.tcsCode === '1073', 'party PAN and TCS code saved');
const item = await call('POST', '/items', { name: 'Steel', salePrice: 1000, purchasePrice: 800, gstRate: 18, hsnCode: '7208' });
const L = (price) => [{ itemId: item.id, name: 'Steel', quantity: 100, price, gstRate: 18, hsnCode: '7208' }];
await call('POST', '/invoices', { type: 'purchase', isCash: false, number: 'B1', invoiceDate: '2026-08-14', partyId: supp.id, roundOff: false, stateOfSupply: '27', lines: L(800), tdsRate: 0.1 });
await call('POST', '/invoices', { type: 'sale', isCash: false, number: 'S1', invoiceDate: '2026-09-02', partyId: scrap.id, roundOff: false, lines: L(1000), tcsRate: 1 });

let st = await call('GET', '/tax-statements/statement?form=140&taxYear=202627&quarter=Q2');
ok(st.deductees === 1 && st.tax === 80 && st.file === null, `Form 140 Q2: 1 bill, TDS ${st.tax}, no file yet`);
ok(['TAN', 'responsible', 'challan'].every((w) => st.problems.join(' ').includes(w)), 'it says TAN, responsible person and challan are missing');
await call('PATCH', '/firm', { tan: 'pnea12345b', pan: 'AAACA1234C', settings: { responsibleName: 'R Sharma', responsibleDesignation: 'Director', responsiblePan: 'ABCPS1234D', responsibleMobile: '9876543210', responsibleEmail: 'r@acme.example' } });
await call('POST', '/tax-statements/challans', { kind: 'tds', bsrCode: '0510308', challanNo: '123', depositDate: '2026-10-05', tax: 50 }, 201);
st = await call('GET', '/tax-statements/statement?form=140&taxYear=202627&quarter=Q2');
ok(st.problems.length === 1 && st.problems[0].includes('does not fit'), 'a challan paid on 5 October counts for Q2, but 50 cannot hold 80 of tax: ' + st.problems.join(' | '));
const list = await call('POST', '/tax-statements/challans', { kind: 'tds', bsrCode: '0510308', challanNo: '124', depositDate: '2026-10-06', tax: 80, taxYear: '202627', quarter: 'Q2' }, 201);
ok(list.length === 2 && list.every((c) => c.quarter === 'Q2'), 'both challans belong to Q2');
st = await call('GET', '/tax-statements/statement?form=140&taxYear=202627&quarter=Q2');
ok(st.problems.length === 0 && st.file, 'Form 140 file made: ' + st.fileName);
const lines = st.file.split('\r\n').filter(Boolean).map((l) => l.split('^'));
ok(lines.map((l) => l[1]).join() === 'FH,BH,CD,DD' && lines.map((l) => l.length).join() === '18,72,30,45', 'records and field counts match the spec');
ok(lines[3][7] === 'AAAFM1111A' && lines[3][14] === '1031' && lines[3][19] === '80000.00' && lines[3][23] === '80.00' && lines[3][27] === '0.1000', 'deductee: PAN from GSTIN, section 1031, 80000 paid, 80 TDS at 0.1%');
ok(lines[1][25] === '19' && lines[1][12] === 'PNEA12345B' && lines[2][16] === '124', 'income-tax state code, TAN, and the challan with room for the tax');
ok(st.warnings.length === 0, 'no PAN warnings');

const tcs = await call('GET', '/tax-statements/statement?form=143&taxYear=202627&quarter=Q2');
ok(tcs.problems.some((p) => p.includes('challan')), 'Form 143 needs its own challan');
await call('POST', '/tax-statements/challans', { kind: 'tcs', bsrCode: '0510308', challanNo: '200', depositDate: '2026-10-07', tax: 1180, taxYear: '202627', quarter: 'Q2' }, 201);
const t2 = await call('GET', '/tax-statements/statement?form=143&taxYear=202627&quarter=Q2');
const dd = t2.file.split('\r\n')[3].split('^');
ok(t2.file.split('^')[2] === 'TC1' && dd[7] === 'AAACB5555C' && dd[11] === '1' && dd[14] === '1073' && dd[23] === '1180.00', 'Form 143 file: TC1, PAN, company collectee, scrap code, TCS 1180');

const g = await call('GET', '/reports/tds-return?from=2026-07-01&to=2026-09-30');
ok(g.rows[0].section === '1031' && g.rows[0].pan === 'AAAFM1111A', 'TDS report uses the new section code');
const g9 = await call('GET', '/tax-statements/gstr9?year=2026-27');
ok(g9.json.fp === '032027' && g9.json.table4.b2c.txval === 100000 && g9.json.table6.supp_non_rchrg[0].camt === 7200, `GSTR-9 JSON: B2C ${g9.json.table4.b2c.txval}, ITC CGST ${g9.json.table6.supp_non_rchrg[0].camt}`);
ok(g9.json.table17.items[0].hsn_sc === '7208' && g9.json.table17.items[0].qty === 100, 'GSTR-9 HSN summary');
await call('DELETE', `/tax-statements/challans/${list[0].id}`, null, 204);
ok((await call('GET', '/tax-statements/challans?kind=tds&taxYear=202627&quarter=Q2')).length === 1, 'challan removed');
console.log('\nALL TAX STATEMENT CHECKS PASSED');
