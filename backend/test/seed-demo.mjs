// Fills a local backend with a realistic demo company:  node backend/test/seed-demo.mjs   (BASE=http://localhost:3100)
const B = (process.env.BASE ?? 'http://localhost:3100') + '/api/v1';
const EMAIL = process.env.SEED_EMAIL ?? 'aman@amantraders.example', PASS = 'Demo@12345';
let H = { 'content-type': 'application/json' };
async function call(method, path, body, ok) {
  const r = await fetch(B + path, { method, headers: H, body: body ? JSON.stringify(body) : undefined });
  const t = await r.text(); let j; try { j = JSON.parse(t); } catch { j = t; }
  if (!r.ok && !(ok ?? []).includes(r.status)) throw new Error(`${method} ${path} -> ${r.status} ${t.slice(0, 300)}`);
  return j;
}
const day = (n) => { const d = new Date(); d.setDate(d.getDate() - n); return d.toISOString().slice(0, 10); };

let reg = await call('POST', '/auth/register', { firmName: 'Aman Traders', stateCode: '27', fullName: 'Aman Sharma', email: EMAIL, password: PASS }, [409, 400]);
if (!reg.accessToken) reg = await call('POST', '/auth/login', { email: EMAIL, password: PASS });
H.authorization = 'Bearer ' + reg.accessToken;
const existing = await call('GET', '/parties');
if (existing.length > 3) { console.log('Demo data already present. Login:', EMAIL, PASS); process.exit(0); }

await call('PATCH', '/firm', { name: 'Aman Traders', phone: '9820012345', email: 'accounts@amantraders.example', gstin: '27AABCA1234C1Z5', address: '12, Market Road, Andheri East, Mumbai 400069', settings: {
  gstEnabled: true, godownsEnabled: true, batchTrackingEnabled: false, serialTrackingEnabled: false, accountingEnabled: true, serviceRemindersEnabled: true, partyGroupsEnabled: true, stockMaintenance: true, paymentReminderDays: 7 } }).catch((e) => console.log('firm settings:', e.message));

// ---- masters
const banks = {};
for (const b of [{ name: 'HDFC Current', openingBalance: 150000, bankName: 'HDFC Bank', accountNumber: '50200012345678', ifsc: 'HDFC0001234', upiId: 'amantraders@hdfcbank' }, { name: 'SBI Savings', openingBalance: 40000, bankName: 'State Bank of India', accountNumber: '3012345678', ifsc: 'SBIN0000300' }])
  banks[b.name] = (await call('POST', '/bank-accounts', { ...b, openingDate: day(60) })).id;
const group = {};
for (const g of ['Retailers', 'Wholesalers', 'Suppliers']) { const l = await call('POST', '/party-groups', { name: g }); group[g] = l.find((x) => x.name === g).id; }
const gd = await call('POST', '/godowns', { name: 'Warehouse', address: 'Bhiwandi' }).catch(() => []);

const P = {};
const parties = [
  ['Gupta Wholesale', '9000000011', '27AAACG1111A1Z1', 'Wholesalers', 12000, 'Mumbai'], ['Sharma General Store', '9000000012', '', 'Retailers', 0, 'Thane'],
  ['Verma & Sons', '9000000013', '27AAACV2222B1Z2', 'Retailers', 4500, 'Pune'], ['Test Customer', '9000000014', '', 'Retailers', 0, 'Mumbai'],
  ['Kiran Super Mart', '9000000015', '27AAACK3333C1Z3', 'Retailers', 0, 'Nashik'], ['Reliable Foods Pvt Ltd', '9000000016', '27AAACR4444D1Z4', 'Wholesalers', 0, 'Mumbai'],
  ['Mega Supplier', '9000000021', '29AAAFM1111A1Z6', 'Suppliers', -8000, 'Bengaluru'], ['Agro Traders', '9000000022', '27AAACA5555E1Z5', 'Suppliers', 0, 'Pune'],
  ['Fresh Mills', '9000000023', '24AAACF6666F1Z6', 'Suppliers', 0, 'Surat'],
];
for (const [name, phone, gstin, g, ob, city] of parties) {
  P[name] = (await call('POST', '/parties', { name, phone, gstin, city, groupId: group[g], stateCode: gstin ? gstin.slice(0, 2) : '27', gstType: gstin ? 'regular' : 'unregistered', billingAddress: `${city} - shop address`, openingBalance: ob, openingBalanceDate: day(60) })).id;
}
const cats = {};
for (const c of ['Grocery', 'Beverages', 'Snacks', 'Household']) cats[c] = (await call('POST', '/categories', { name: c })).id;
const I = {};
const items = [
  ['Basmati Rice 5kg', 'Grocery', 'PCS', 520, 430, 5, '1006', 120], ['Toor Dal 1kg', 'Grocery', 'PCS', 165, 135, 5, '0713', 200], ['Sunflower Oil 1L', 'Grocery', 'PCS', 150, 125, 5, '1512', 150],
  ['Sugar 1kg', 'Grocery', 'PCS', 48, 40, 5, '1701', 300], ['Wheat Flour 10kg', 'Grocery', 'PCS', 410, 340, 0, '1101', 80], ['Tea Powder 500g', 'Beverages', 'PCS', 240, 190, 5, '0902', 90],
  ['Cola 2L', 'Beverages', 'PCS', 95, 72, 18, '2202', 160], ['Biscuits Family Pack', 'Snacks', 'PCS', 60, 44, 18, '1905', 220], ['Namkeen 400g', 'Snacks', 'PCS', 110, 82, 12, '2106', 8],
  ['Detergent 2kg', 'Household', 'PCS', 320, 255, 18, '3402', 70], ['Dish Wash Gel', 'Household', 'PCS', 99, 70, 18, '3402', 6],
];
for (const [name, c, unit, sale, buy, gst, hsn, qty] of items)
  I[name] = (await call('POST', '/items', { name, categoryId: cats[c], unit, salePrice: sale, purchasePrice: buy, gstRate: gst, hsnCode: hsn, openingQty: qty, openingPrice: buy, openingDate: day(60), minStock: 20, itemCode: hsn + name.slice(0, 2).toUpperCase() })).id;
for (const [name, price, gst] of [['Home Delivery', 80, 18], ['Installation Service', 500, 18]])
  I[name] = (await call('POST', '/items', { name, type: 'service', unit: 'NOS', salePrice: price, gstRate: gst, hsnCode: '9985', serviceReminderDays: 90 })).id;

// ---- sales & purchases over the last 45 days
const names = Object.keys(I).filter((n) => !['Home Delivery', 'Installation Service'].includes(n));
const customers = ['Gupta Wholesale', 'Sharma General Store', 'Verma & Sons', 'Test Customer', 'Kiran Super Mart', 'Reliable Foods Pvt Ltd'];
const suppliers = ['Mega Supplier', 'Agro Traders', 'Fresh Mills'];
const meta = Object.fromEntries(items.map((i) => [i[0], { sale: i[3], buy: i[4], gst: i[5] }]));
let saleNo = 0, billNo = 0; const saleIds = [];
for (let d = 44; d >= 0; d -= 2) {
  const cust = customers[(d / 2) % customers.length | 0];
  const lines = [0, 1, 2].map((k) => names[(d + k * 3) % names.length]).map((n, k) => ({ itemId: I[n], name: n, quantity: 2 + ((d + k) % 6), price: meta[n].sale, gstRate: meta[n].gst }));
  const total = lines.reduce((s, l) => s + l.quantity * l.price * (1 + l.gst / 100), 0);
  const mode = d % 3 === 0 ? 'upi' : 'cash';
  const r = await call('POST', '/invoices', { type: 'sale', number: String(++saleNo), invoiceDate: day(d), partyId: P[cust], isCash: false, paymentMode: mode, bankAccountId: mode === 'upi' ? banks['HDFC Current'] : null, roundOff: true, pricesIncludeTax: false, received: d % 4 === 0 ? 0 : Math.round(total * (d % 5 === 0 ? 0.5 : 1)), description: '', dueDate: day(d - 15), lines }).catch((e) => console.log('sale', e.message.slice(0, 160)));
  if (r?.id) saleIds.push(r.id);
}
for (let d = 40; d >= 3; d -= 6) {
  const sup = suppliers[(d / 6) % suppliers.length | 0];
  const lines = [0, 1].map((k) => names[(d + k * 4) % names.length]).map((n) => ({ itemId: I[n], name: n, quantity: 20 + (d % 15), price: meta[n].buy, gstRate: meta[n].gst }));
  const total = lines.reduce((s, l) => s + l.quantity * l.price * (1 + l.gst / 100), 0);
  await call('POST', '/invoices', { type: 'purchase', number: '', invoiceDate: day(d), partyId: P[sup], isCash: false, paymentMode: 'cash', roundOff: true, pricesIncludeTax: false, received: Math.round(total * 0.6), description: `Bill ${++billNo}`, lines }).catch((e) => console.log('purchase', e.message.slice(0, 160)));
}
// estimate, sale order
for (const type of ['estimate', 'sale_order']) {
  await call('POST', '/invoices', { type, number: '1', invoiceDate: day(4), partyId: P['Kiran Super Mart'], isCash: false, paymentMode: 'cash', roundOff: false, received: 0, description: '', lines: [{ itemId: I['Detergent 2kg'], name: 'Detergent 2kg', quantity: 10, price: 320, gstRate: 18 }] }).catch((e) => console.log(type, e.message.slice(0, 120)));
}
// ---- payments in / out
let pn = 0;
for (const [type, who, amt, dd, mode] of [['in', 'Gupta Wholesale', 6000, 20, 'upi'], ['in', 'Verma & Sons', 2500, 12, 'cash'], ['in', 'Reliable Foods Pvt Ltd', 4000, 6, 'bank'], ['out', 'Mega Supplier', 5000, 15, 'upi'], ['out', 'Agro Traders', 3000, 8, 'cash']])
  await call('POST', '/payments', { type, number: String(++pn), partyId: P[who], paymentDate: day(dd), amount: amt, paymentMode: mode === 'bank' ? 'upi' : mode, bankAccountId: mode === 'cash' ? null : banks['HDFC Current'], description: '' }).catch((e) => console.log('payment', e.message.slice(0, 140)));
// ---- expenses
const ec = await call('GET', '/expense-categories');
const ecid = (n) => ec.find((c) => c.name === n)?.id ?? ec[0].id;
for (const [cat, name, qty, price, dd] of [['Rent', 'Shop rent', 1, 25000, 30], ['Salary', 'Staff salary', 2, 15000, 28], ['Tea', 'Office tea', 30, 12, 10], ['Petrol', 'Delivery van fuel', 25, 105, 7], ['Transport', 'Freight', 1, 3200, 14], ['Rent', 'Shop rent', 1, 25000, 1]])
  await call('POST', '/expenses', { categoryId: ecid(cat), number: '', expenseDate: day(dd), roundOff: false, pricesIncludeTax: false, paymentMode: 'cash', bankAccountId: null, description: '', lines: [{ name, quantity: qty, price }] }).catch((e) => console.log('expense', e.message.slice(0, 140)));
// ---- loan, adjustments, accounting
const loan = await call('POST', '/loan-accounts', { name: 'Shop Loan', lender: 'HDFC Bank', openingBalance: 200000, balanceDate: day(55), bankAccountId: banks['HDFC Current'], interestRate: 11.5, termMonths: 36 });
await call('POST', `/loan-accounts/${loan.id}/transactions`, { kind: 'payment', principal: 5000, interest: 1900, date: day(25) }).catch((e) => console.log('loan', e.message.slice(0, 120)));
await call('POST', '/fund-adjustments', { kind: 'cash_add', amount: 20000, date: day(35), description: 'Owner capital' }).catch(() => {});
await call('POST', '/fund-adjustments', { kind: 'bank_to_cash', bankAccountId: banks['HDFC Current'], amount: 10000, date: day(18), description: 'Cash withdrawal' }).catch(() => {});
await call('PUT', '/currencies', { code: 'USD', symbol: '$', rate: 83.2 }).catch(() => {});
const la = await call('POST', '/ledger-accounts', { name: 'Furniture', type: 'asset' }).catch(() => []);
await call('POST', '/ledger-accounts', { name: 'Owner Capital', type: 'equity' }).catch(() => {});
const led = await call('GET', '/ledger-accounts').catch(() => []);
const fur = led.find((a) => a.name === 'Furniture'), cap = led.find((a) => a.name === 'Owner Capital');
if (fur && cap) {
  const number = (await call('GET', '/journals/next-number')).number;
  await call('POST', '/journals', { number, date: day(50), description: 'Furniture bought with capital', lines: [{ ledgerAccountId: fur.id, debit: 60000 }, { ledgerAccountId: cap.id, credit: 60000 }] }).catch((e) => console.log('journal', e.message.slice(0, 120)));
}
// stock adjustment + a team member
await call('POST', `/items/${I['Dish Wash Gel']}/adjust`, { type: 'reduce', quantity: 1, date: day(5), description: 'damaged' }).catch(() => {});
await call('POST', '/users', { fullName: 'Sam Salesman', email: 'sam@example.com', password: 'Demo@12345', role: 'salesman' }).catch(() => {});
console.log('Seeded. Login:', EMAIL, PASS);
