// End-to-end checks of the "remaining gaps" batch against a running backend (PORT 3100).
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
const iso = (d) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(d);
const today = iso(new Date());
const daysAgo = (n) => iso(new Date(Date.now() - n * 86400000));
const report = (id, q = '') => call('GET', `/reports/${id}?from=${daysAgo(400)}&to=${today}${q}`);

const email = `g${Date.now()}@example.com`;
token = (await call('POST', '/auth/register', { firmName: 'Gap Co', fullName: 'Owner', email, password: 'Password123', stateCode: '27' })).accessToken;
const firm = await call('GET', '/firm');
const bank = await call('POST', '/bank-accounts', { name: 'HDFC', openingBalance: 1000, openingDate: daysAgo(60) });
const cust = await call('POST', '/parties', { name: 'Ravi Traders', phone: '9876543210', gstin: '27ABCDE1234F1Z5', gstType: 'regular', stateCode: '27', creditLimit: 5000 });
const supp = await call('POST', '/parties', { name: 'Mega Supplier', gstin: '29AAAAA1111A1Z6', gstType: 'regular', stateCode: '29' });
const item = await call('POST', '/items', { name: 'Widget', salePrice: 100, purchasePrice: 60, gstRate: 18, hsnCode: '8501', unit: 'PCS', openingQty: 100, openingPrice: 60, openingDate: daysAgo(60) });
const free = await call('POST', '/items', { name: 'Book', salePrice: 50, purchasePrice: 30, gstRate: 0, hsnCode: '4901', openingQty: 10, openingPrice: 30, openingDate: daysAgo(60) });
const doc = (type, number, party, lines, extra = {}) => call('POST', '/invoices', { type, isCash: false, number, invoiceDate: today, partyId: party.id, roundOff: false, lines, ...extra });
const L = (it, q, extra = {}) => ({ itemId: it.id, name: it.name, quantity: q, price: it.salePrice, hsnCode: it.hsnCode, gstRate: it.gstRate ?? 0, ...extra });

// ---- 1. payments: link to credit / debit notes, and from the invoice's side
const old = await doc('sale', 'S-1', cust, [L(item, 10)], { invoiceDate: daysAgo(45), dueDate: daysAgo(40) });      // 1180, 40 days overdue
const recent = await doc('sale', 'S-2', cust, [L(item, 5), L(free, 2)], { invoiceDate: daysAgo(5) });                // 590 + 100
const cn = await doc('credit_note', 'CN-1', cust, [L(item, 1)]);                                                     // 118
ok(old.total === 1180 && recent.total === 690 && cn.total === 118, 'documents made');
const refund = await call('POST', '/payments', { type: 'out', number: 'R-1', partyId: cust.id, paymentDate: today, amount: 118, paymentMode: 'cash', allocations: [{ invoiceId: cn.id, amount: 118 }] });
ok(refund.linkedAmount === 118 && refund.allocations[0].type === 'credit_note', 'refund linked to the credit note');
ok((await call('GET', `/invoices/${cn.id}`)).balance === 0, 'credit note shows as settled');
await call('POST', '/payments', { type: 'in', number: 'X-1', partyId: cust.id, paymentDate: today, amount: 50, allocations: [{ invoiceId: cn.id, amount: 50 }] }, 400);
ok(true, 'money in cannot be linked to a credit note');
const advance = await call('POST', '/payments', { type: 'in', number: 'A-1', partyId: cust.id, paymentDate: daysAgo(10), amount: 1000, paymentMode: 'bank', bankAccountId: bank.id });
let lk = await call('GET', `/payments/linkable?invoiceId=${old.id}`);
ok(lk.due === 1180 && lk.payments.length === 1 && lk.payments[0].free === 1000 && lk.payments[0].linked === 0, 'invoice lists the unlinked advance');
lk = await call('PUT', `/payments/invoice-links/${old.id}`, { links: [{ paymentId: advance.id, amount: 700 }] });
ok(lk.payments[0].linked === 700 && (await call('GET', `/invoices/${old.id}`)).balance === 480, 'linked 700 from the invoice screen; 480 left');
await call('PUT', `/payments/invoice-links/${recent.id}`, { links: [{ paymentId: advance.id, amount: 400 }] }, 400);
ok(true, 'cannot link more than the payment has free');
await call('PUT', `/payments/invoice-links/${recent.id}`, { links: [{ paymentId: advance.id, amount: 300 }] });
ok((await call('GET', `/payments/${advance.id}`)).unlinkedAmount === 0, 'payment fully linked across two invoices');
await call('PUT', `/payments/invoice-links/${old.id}`, { links: [] });
ok((await call('GET', `/invoices/${old.id}`)).balance === 1180, 'links can be removed from the invoice side');
await call('PUT', `/payments/invoice-links/${old.id}`, { links: [{ paymentId: advance.id, amount: 700 }] });

// ---- 4. search covers payments and expenses
const cats = await call('GET', '/expense-categories');
const exp = await call('POST', '/expenses', { categoryId: cats[0].id, expenseDate: today, lines: [{ name: 'Courier', quantity: 1, price: 1000, gstRate: 18 }], roundOff: false, description: 'Bluedart shipment', supplierState: '29', supplierGstin: '29AAAAA1111A1Z6' });
const local = await call('POST', '/expenses', { categoryId: cats[0].id, expenseDate: today, lines: [{ name: 'Stationery', quantity: 1, price: 500, gstRate: 12 }], roundOff: false });
ok(exp.supplierState === '29' && local.supplierState === null, 'supplier state saved on the expense');
let found = await call('GET', '/search?q=Bluedart');
ok(found.expenses.length === 1 && found.expenses[0].total === 1180, 'search finds an expense by its note');
found = await call('GET', '/search?q=A-1');
ok(found.payments.some((p) => p.number === 'A-1' && p.amount === 1000), 'search finds a payment by its number');

// ---- 5. expense GST: IGST for an out-of-state supplier
const g3 = await report('gstr3b');
const exRow = g3.rows.find((r) => String(r.particulars).includes('GST paid on expenses'));
ok(exRow.igst === 180 && exRow.cgst === 30 && exRow.sgst === 30, `expense ITC split: IGST ${exRow.igst}, CGST ${exRow.cgst}, SGST ${exRow.sgst}`);

// ---- 6. credit limit: warn by default, block when asked, on sales, orders and challans
await doc('sale', 'S-3', cust, [L(item, 40)]);                                    // +4720 → over 5000, allowed under "warn"
ok(true, 'over the limit is allowed while the setting is "warn"');
await call('PATCH', '/firm', { settings: { creditLimitMode: 'block' } });
const blocked = await call('POST', '/invoices', { type: 'sale', isCash: false, number: 'S-4', invoiceDate: today, partyId: cust.id, roundOff: false, lines: [L(item, 1)] }, 400);
ok(/credit limit/.test(JSON.stringify(blocked)), 'sale refused over the credit limit: ' + (blocked.error?.message ?? blocked.message));
await call('POST', '/invoices', { type: 'sale_order', number: 'SO-1', invoiceDate: today, partyId: cust.id, roundOff: false, lines: [L(item, 1)] }, 400);
await call('POST', '/invoices', { type: 'delivery_challan', number: 'DC-1', invoiceDate: today, partyId: cust.id, roundOff: false, lines: [L(item, 1)] }, 400);
ok(true, 'sale order and delivery challan refused too');
ok((await call('GET', '/invoices?type=sale')).every((i) => i.number !== 'S-4'), 'the refused sale left nothing behind');
ok((await call('GET', `/items/${item.id}`)).stockQty === 100 - 10 - 5 + 1 - 40, 'and did not move stock');
await call('POST', '/invoices', { type: 'sale', isCash: true, number: 'S-5', invoiceDate: today, partyId: cust.id, roundOff: false, lines: [L(item, 1)] });
ok(true, 'a fully paid cash sale is still allowed');
await call('PATCH', '/firm', { settings: { creditLimitMode: 'warn' } });

// ---- 2. reports
const pur = await doc('purchase', 'B-1', supp, [{ ...L(item, 20), price: 60 }], { invoiceDate: daysAgo(100), tdsRate: 1, stateOfSupply: '29' });
const age = await report('ageing');
const a = age.rows.find((r) => r.party === 'Ravi Traders');
ok(a.d60 === 480 && a.d30 === 390 && a.notDue === 4720 && a.older === 0, `ageing buckets: 31–60 days ${a.d60}, 1–30 days ${a.d30}, not due ${a.notDue}`);
ok(a.unlinked === 0 && a.total === a.net, 'ageing nets payments that are not linked');
const pay = await report('ageing-payable');
ok(pay.rows[0].party === 'Mega Supplier' && pay.rows[0].older === pur.balance, 'payables ageing: over 90 days ' + pay.rows[0].older);
const g9 = await report('gstr9');
const row = (t, part) => g9.rows.find((r) => r.table === t && (!part || String(r.particulars).includes(part)));
ok(row('4B').taxable === 1000 + 500 + 4000 + 100 && row('4I').taxable === 100 && row('4A').taxable === 0, `GSTR-9 4B taxable ${row('4B').taxable}, credit notes ${row('4I').taxable}`);
ok(row('5D–5F').taxable === 100, 'GSTR-9 exempt / nil-rated supplies ' + row('5D–5F').taxable);
ok(row('6B', 'purchases').igst === 216 && row('6B', 'expenses').igst === 180, 'GSTR-9 input tax credit from purchases and expenses');
ok(row('9').total === Math.round((5600 - 100) * 0.18 * 100) / 100, 'GSTR-9 tax payable ' + row('9').total);
const tds = await report('tds-return');
ok(tds.rows.length === 1 && tds.rows[0].pan === 'AAAAA1111A' && tds.rows[0].section === '194Q' && tds.rows[0].amount === 1200 && tds.rows[0].tax === 12, 'TDS return row: PAN from GSTIN, 1% of 1200');
await call('PATCH', '/firm', { settings: { tcsEnabled: true } });
const tcsSale = await doc('sale', 'S-6', cust, [L(item, 1)], { tcsRate: 1 });
const tcs = await report('tcs-return');
ok(tcs.rows.length === 1 && tcs.rows[0].pan === 'ABCDE1234F' && tcs.rows[0].tax === tcsSale.tcsAmount && tcs.rows[0].amount === 118, 'TCS return row');
const loan = await call('POST', '/loan-accounts', { name: 'Car loan', openingBalance: 10000, balanceDate: daysAgo(30) });
await call('POST', `/loan-accounts/${loan.id}/transactions`, { kind: 'payment', principal: 1000, interest: 100, date: daysAgo(3) });
const ls = await report('loan-statement');
ok(ls.rows.at(-1).balance === 9000 && ls.rows.at(-1).repaid === 1000 && ls.summary.find((s) => s.label.startsWith('Outstanding')).value === 9000, 'loan statement runs to a balance of 9000');
ok((await call('GET', '/reports')).some((r) => r.id === 'loan-statement'), 'new reports are in the catalogue');

// ---- 9. location: zones, distance
await call('PATCH', '/firm', { settings: { locationTrackingEnabled: true } });
let fences = await call('POST', '/locations/geofences', { name: 'Shop', latitude: 18.5204, longitude: 73.8567, radiusM: 200 });
ok(fences.length === 1 && fences[0].name === 'Shop', 'zone added');
for (const [lat, lng] of [[18.5204, 73.8567], [18.5300, 73.8567], [18.5400, 73.8567], [18.5204, 73.8567]]) await call('POST', '/locations', { latitude: lat, longitude: lng });
const sum = await call('GET', '/locations/summary');
ok(sum.points === 4 && Math.abs(sum.distanceKm - 4.36) < 0.05 && sum.visits.length === 2 && sum.visits[0].zone === 'Shop', `day summary: ${sum.distanceKm} km, ${sum.visits.length} visits to the shop`);
const latest = (await call('GET', '/locations/latest'))[0];
ok(latest.zone === 'Shop' && Math.abs(latest.distanceKmToday - 4.36) < 0.05, 'latest position shows the zone and distance today');
ok((await call('GET', '/locations/trail')).map((p) => p.zone).join() === 'Shop,,,Shop', 'trail points say which zone they are in');
fences = await call('DELETE', `/locations/geofences/${fences[0].id}`);
ok(fences.length === 0, 'zone removed');

// ---- 7. item image id travels with invoice lines
ok('imageFileId' in (await call('GET', `/invoices/${old.id}`)).lines[0], 'invoice lines carry the item image');

// ---- 11. new year as of a past date: only what happened before the start date is carried
const start = daysAgo(20);
const ny = await call('POST', '/utilities/new-year', { name: 'Gap Co New', startDate: start });
const oldToken = token;
token = (await call('POST', '/auth/switch-firm', { firmId: ny.id })).accessToken;
const p2 = (await call('GET', '/parties')).find((p) => p.name === 'Ravi Traders');
ok(p2.balance === 1180, `customer opens owing 1180 (only the 45-day-old sale), not today's balance: ${p2.balance}`);
const s2 = (await call('GET', '/parties')).find((p) => p.name === 'Mega Supplier');
ok(s2.balance === -pur.balance, 'supplier opens with the 100-day-old bill');
const i2 = (await call('GET', '/items')).find((i) => i.name === 'Widget');
ok(i2.stockQty === 100 - 10 + 20, `stock opens at ${i2.stockQty}: opening − old sale + old purchase`);
const b2 = (await call('GET', '/bank-accounts'))[0];
ok(b2.balance === 1000, 'bank opens without the later deposit: ' + b2.balance);
ok((await call('GET', '/loan-accounts'))[0].balance === 10000, 'loan opens before its later repayment');

// ---- 3. delete a company
await call('DELETE', `/firms/${ny.id}`, { name: 'Gap Co New' }, 400); ok(true, 'cannot delete the company you are working in');
token = oldToken;
await call('DELETE', `/firms/${ny.id}`, { name: 'wrong name' }, 400); ok(true, 'the name must be typed to confirm');
await call('DELETE', `/firms/${ny.id}`, { name: 'gap co new' }, 204);
ok((await call('GET', '/firms')).every((f) => f.id !== ny.id), 'company deleted');
ok((await call('GET', '/parties')).length === 2, 'the other company is untouched');
console.log('\nALL GAP CHECKS PASSED');
