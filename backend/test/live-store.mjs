// Live checks for manufacturing, the online store and duplicate-save protection (PORT 3100).
const ORIGIN = process.env.BASE ?? 'http://localhost:3100';
const B = ORIGIN + '/api/v1';
let token;
const call = async (method, path, body, expect, headers = {}) => {
  const r = await fetch((path.startsWith('/store/') ? ORIGIN : B) + path, { method, headers: { 'content-type': 'application/json', ...(token && !path.startsWith('/store/') ? { authorization: `Bearer ${token}` } : {}), ...headers }, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text();
  let json = null; try { json = text ? JSON.parse(text) : null; } catch { json = text; }
  if (expect ? r.status !== expect : !r.ok) throw new Error(`${method} ${path} -> ${r.status} ${text.slice(0, 400)}`);
  return json?.data ?? json;
};
const ok = (c, m) => { if (!c) throw new Error('ASSERT ' + m); console.log('ok  ' + m); };
const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(new Date());

token = (await call('POST', '/auth/register', { firmName: 'Maker Co', fullName: 'Owner', email: `m${Date.now()}@example.com`, password: 'Password123', stateCode: '27' })).accessToken;
await call('PATCH', '/firm', { phone: '9000000001', address: '1 Main Rd', city: 'Pune' });

// ---- duplicate-save protection
const cust = await call('POST', '/parties', { name: 'Ravi', phone: '9876543210', stateCode: '27' });
const chair = await call('POST', '/items', { name: 'Chair', salePrice: 1000, purchasePrice: 0, gstRate: 18, hsnCode: '9401', unit: 'PCS' });
const wood = await call('POST', '/items', { name: 'Wood', salePrice: 100, purchasePrice: 60, gstRate: 18, unit: 'KG', openingQty: 100, openingPrice: 60, openingDate: today });
const nails = await call('POST', '/items', { name: 'Nails', salePrice: 5, purchasePrice: 2, openingQty: 500, openingPrice: 2, openingDate: today });
const key = 'k'.repeat(8) + 'abcdef0123456789';
const doc = { type: 'sale', isCash: false, number: 'S-1', invoiceDate: today, partyId: cust.id, roundOff: false, lines: [{ itemId: wood.id, name: 'Wood', quantity: 1, price: 100, gstRate: 18 }] };
const a = await call('POST', '/invoices', doc, null, { 'idempotency-key': key });
const b = await call('POST', '/invoices', doc, null, { 'idempotency-key': key });
ok(a.id === b.id, 'the same save sent twice gives the same invoice back');
ok((await call('GET', '/invoices?type=sale')).length === 1, 'and only one invoice exists');
ok((await call('GET', `/items/${wood.id}`)).stockQty === 99, 'stock moved once');
await call('POST', '/invoices', { ...doc, number: 'S-1' }, 409, { 'idempotency-key': 'z'.repeat(8) + 'abcdef0123456789' });
await call('POST', '/invoices', { ...doc, number: 'S-2' }, null, { 'idempotency-key': 'z'.repeat(8) + 'abcdef0123456789' });
ok(true, 'a refused save frees its key, so it can be sent again once fixed');
await call('POST', '/invoices', { ...doc, number: 'S-3' }, null, { 'idempotency-key': 'short' });
ok(true, 'a malformed key is ignored, not an error');

// ---- manufacturing
await call('PUT', `/manufacturing/bom/${chair.id}`, { lines: [{ componentId: chair.id, quantity: 1 }] }, 400); ok(true, 'an item cannot be made from itself');
let bom = await call('PUT', `/manufacturing/bom/${chair.id}`, { lines: [{ componentId: wood.id, quantity: 2 }, { componentId: nails.id, quantity: 20 }] });
ok(bom.costPerUnit === 160, 'bill of materials costs ₹' + bom.costPerUnit + ' per chair (2 kg wood at 60 + 20 nails at 2)');
await call('PUT', `/manufacturing/bom/${wood.id}`, { lines: [{ componentId: chair.id, quantity: 1 }] }, 400); ok(true, 'a loop (wood made from chairs) is refused');
const req = await call('GET', `/manufacturing/requirements?itemId=${chair.id}&quantity=60`);
ok(!req.canMake && req.lines.find((l) => l.name === 'Wood').short === 23, 'making 60 chairs would be 23 kg of wood short (120 needed, 97 left)');
await call('POST', '/manufacturing/entries', { itemId: wood.id, quantity: 1, entryDate: today }, 400); ok(true, 'an item with no bill of materials cannot be made');
const made = await call('POST', '/manufacturing/entries', { itemId: chair.id, quantity: 10, entryDate: today, extraCost: 200, description: 'First batch' });
ok(made.number === '1' && made.componentCost === 1600 && made.totalCost === 1800 && made.costPerUnit === 180, `10 chairs made at ₹${made.costPerUnit} each`);
ok(made.components.length === 2, 'the entry lists what was used');
ok((await call('GET', `/items/${chair.id}`)).stockQty === 10 && (await call('GET', `/items/${wood.id}`)).stockQty === 77 && (await call('GET', `/items/${nails.id}`)).stockQty === 300, 'chairs +10, wood −20, nails −200');
const history = await call('GET', `/reports/item-detail?itemId=${chair.id}&from=${today}&to=${today}`);
ok(history.rows.some((r) => r.type === 'Manufactured' && r.qtyIn === 10), 'item history shows the production');
await call('PATCH', '/firm', { settings: { blockNegativeStock: true } });
await call('POST', '/manufacturing/entries', { itemId: chair.id, quantity: 100, entryDate: today }, 400); ok(true, 'with "block negative stock" it refuses when components run short');
ok((await call('GET', '/utilities/verify')).ok, 'the books still verify after production');
await call('POST', '/invoices', { ...doc, number: 'S-9', lines: [{ itemId: chair.id, name: 'Chair', quantity: 8, price: 1000, gstRate: 18 }] });
await call('DELETE', `/manufacturing/entries/${made.id}`, null, 400); ok(true, 'a batch that was partly sold cannot be undone');
await call('POST', '/invoices', { ...doc, type: 'credit_note', number: 'CN-1', lines: [{ itemId: chair.id, name: 'Chair', quantity: 8, price: 1000, gstRate: 18 }] });
await call('DELETE', `/manufacturing/entries/${made.id}`, null, 204);
ok((await call('GET', `/items/${wood.id}`)).stockQty === 97 && (await call('GET', '/utilities/verify')).ok, 'undoing a batch returns the components');

// ---- online store
await call('POST', '/manufacturing/entries', { itemId: chair.id, quantity: 10, entryDate: today });
await call('PATCH', '/firm', { gstin: '27AAACA1234C1Z5', settings: { blockNegativeStock: false, stockMaintenance: true } });
await call('GET', '/store/nope', null, 404); ok(true, 'an unknown shop is a 404');
await call('PUT', '/store-admin', { enabled: true }, 400); ok(true, 'the shop cannot open without an address');
const slug = 'maker-' + Date.now().toString(36);
let st = await call('PUT', '/store-admin', { slug, enabled: true, tagline: 'Furniture', note: 'Delivery in Pune only' });
ok(st.path === `/store/${slug}`, 'shop address ' + st.path);
await call('PUT', '/store-admin/items', { itemIds: [chair.id, wood.id], inStore: true });
const page = await fetch(ORIGIN + `/store/${slug}`); const html = await page.text();
ok(page.status === 200 && html.includes('<script src="/store/_assets/store.js">') && !html.includes('onclick'), 'the shop page is served, with its script as a separate file');
const js = await fetch(ORIGIN + '/store/_assets/store.js'); ok(js.status === 200 && (await js.text()).includes('textContent'), 'the script is served and writes text, not markup');
const shop = await call('GET', `/store/${slug}/data`);
ok(shop.name === 'Maker Co' && shop.items.length === 2 && shop.items.find((i) => i.name === 'Chair').price === 1180, 'shop lists its 2 items; chair shows ₹1,180 with GST included');
ok(!JSON.stringify(shop).includes('purchase'), 'no purchase price or stock count is exposed');
const order = await call('POST', `/store/${slug}/orders`, { name: 'Asha <b>Rao</b>', phone: '+91 98765 11111', address: '5 Park St', lines: [{ itemId: chair.id, quantity: 2 }] }, 200);
ok(order.number, 'order placed as sale order ' + order.number);
const so = (await call('GET', '/invoices?type=sale_order'))[0];
ok(so.total === 2360 && so.partyName.includes('Asha'), 'it is a sale order of ₹2,360 for the new customer');
const asha = (await call('GET', '/parties')).find((p) => p.name.startsWith('Asha'));
ok(asha.phone.includes('98765 11111'), 'a customer was made from the order');
const again = await call('POST', `/store/${slug}/orders`, { name: 'Asha R', phone: '098765 11111', lines: [{ itemId: wood.id, quantity: 1 }] }, 200);
ok((await call('GET', '/parties')).filter((p) => p.name.startsWith('Asha')).length === 1, 'the same phone number finds the same customer');
await call('POST', `/store/${slug}/orders`, { name: 'X', phone: '9876500000', lines: [{ itemId: chair.id, quantity: 5000 }] }, 400); ok(true, 'quantity limit enforced');
await call('POST', `/store/${slug}/orders`, { name: 'X', phone: '9876500000', lines: [{ itemId: cust.id, quantity: 1 }] }, 400); ok(true, 'an item that is not in the shop is refused');
const bot = await call('POST', `/store/${slug}/orders`, { name: 'Bot', phone: '9876500001', website: 'spam', lines: [{ itemId: chair.id, quantity: 1 }] }, 200);
ok((await call('GET', '/invoices?type=sale_order')).length === 2 && bot.number === '0', 'a bot that fills the hidden field is told it worked and nothing is made');
const orders = await call('GET', '/store-admin/orders');
ok(orders.length === 2 && orders[0].status === 'new', 'the owner sees the 2 orders');
ok((await call('PUT', `/store-admin/orders/${orders[0].id}`, { status: 'accepted' })).find((o) => o.id === orders[0].id).status === 'accepted', 'an order can be accepted');
await call('PUT', '/store-admin', { enabled: false });
await call('GET', `/store/${slug}`, null, 404); ok(true, 'a closed shop is a 404 again');
console.log('\nALL STORE / MANUFACTURING / DEDUPE CHECKS PASSED');
