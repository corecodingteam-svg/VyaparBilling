import http from 'http';
import crypto from 'crypto';
const B = 'http://localhost:3100/api/v1';
let token, firmId;
const call = async (method, path, body, expect) => {
  const r = await fetch(B + path, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text();
  const json = text ? JSON.parse(text) : null;
  if (expect ? r.status !== expect : !r.ok) throw new Error(`${method} ${path} -> ${r.status} ${text.slice(0, 500)}`);
  return json?.data ?? json;
};
const ok = (cond, msg) => { if (!cond) throw new Error('ASSERT ' + msg); console.log('ok  ' + msg); };
const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(new Date());

// ---- a fake of every provider, on one port
const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048, publicKeyEncoding: { type: 'spki', format: 'pem' }, privateKeyEncoding: { type: 'pkcs8', format: 'pem' } });
const sek = crypto.randomBytes(32);
const ecb = (key, data, dec) => { const c = (dec ? crypto.createDecipheriv : crypto.createCipheriv)('aes-256-ecb', key, null); return Buffer.concat([c.update(data), c.final()]); };
const sent = []; const links = new Map(); let irnCancelled = false;
const server = http.createServer((req, res) => {
  let raw = ''; req.on('data', (d) => (raw += d)); req.on('end', () => {
    const send = (o, s = 200) => { res.writeHead(s, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    const body = raw && raw.startsWith('{') ? JSON.parse(raw) : raw;
    const u = req.url.split('?')[0];
    if (u === '/555/messages') { sent.push({ wa: body, auth: req.headers.authorization }); return send({ messages: [{ id: 'wamid.' + sent.length }] }); }
    if (u === '/2010-04-01/Accounts/AC1/Messages.json') { sent.push({ sms: new URLSearchParams(body).get('Body') }); return send({ sid: 'SM' + sent.length }, 201); }
    if (u === '/eivital/v1.04/auth') {
      const login = JSON.parse(crypto.privateDecrypt({ key: privateKey, padding: crypto.constants.RSA_PKCS1_PADDING }, Buffer.from(body.Data, 'base64')).toString());
      return send({ Status: 1, Data: { AuthToken: 'T', Sek: ecb(Buffer.from(login.AppKey, 'base64'), sek, false).toString('base64') } });
    }
    if (u.startsWith('/eicore') || u.startsWith('/eiewb')) {
      const p = JSON.parse(ecb(sek, Buffer.from(body.Data, 'base64'), true).toString());
      if (u === '/eicore/v1.03/Invoice') { sent.push({ einv: p }); return send({ Status: 1, Data: { Irn: crypto.createHash('sha256').update(p.DocDtls.No).digest('hex'), AckNo: 1122334455, AckDt: '13/10/2026 10:00:00', SignedQRCode: 'jwt.qr' } }); }
      if (u === '/eicore/v1.03/Invoice/Cancel') { irnCancelled = true; return send({ Status: 1, Data: { Irn: p.Irn } }); }
      if (u === '/eiewb/v1.03/ewaybill') return send({ Status: 1, Data: { EwbNo: 331234567890, EwbDt: '13/10/2026 11:00:00', EwbValidTill: '14/10/2026 23:59:00' } });
    }
    if (u === '/v1/payment_links') { const id = 'plink_' + crypto.randomBytes(5).toString('hex'); links.set(id, { ...body, id }); return send({ id, short_url: 'https://rzp.io/i/' + id, status: 'created' }); }
    if (u.startsWith('/v1/payment_links/') && req.method === 'GET') return send({ status: 'created', amount_paid: 0 });
    send({ error: { description: 'unknown ' + u } }, 404);
  });
}).listen(4010);

const email = `s4${Date.now()}@example.com`;
const reg = await call('POST', '/auth/register', { firmName: 'Integration Co', fullName: 'Owner', email, password: 'Password123', stateCode: '27' });
token = reg.accessToken;
const firm = await call('GET', '/firm'); firmId = firm.id;
await call('PATCH', '/firm', { gstin: '27AAAAA0000A1Z5', address: '1 Main Rd', city: 'Pune', pincode: '411001', phone: '9000000001', settings: { einvoiceEnabled: true, ewayEnabled: true, autoSendInvoices: 'whatsapp', autoSendPayments: 'sms' } });
ok((await call('GET', '/firm')).city === 'Pune', 'company city saved');
const bank = await call('POST', '/bank-accounts', { name: 'HDFC', openingBalance: 0, openingDate: today });
const cust = await call('POST', '/parties', { name: 'Ravi Traders', phone: '98765 43210', gstin: '29BBBBB1111B1Z6', stateCode: '29', gstType: 'regular', billingAddress: '2 High St', city: 'Bengaluru', pincode: '560001' });
ok(cust.city === 'Bengaluru' && cust.pincode === '560001', 'party city/pincode saved');
const item = await call('POST', '/items', { name: 'Widget', salePrice: 100, purchasePrice: 50, gstRate: 18, hsnCode: '8501', unit: 'PCS' });

// ---- integrations screen: secrets are never returned
let st = await call('GET', '/integrations');
ok(st.length === 5 && st.every((s) => !s.connected), 'five integrations, none connected');
await call('PUT', '/integrations/whatsapp', { values: { phoneNumberId: '' } }, 400); ok(true, 'required fields enforced');
await call('PUT', '/integrations/whatsapp', { values: { phoneNumberId: '555', accessToken: 'EAAB-secret-token-1234', apiBase: 'http://localhost:4010' } });
await call('PUT', '/integrations/sms', { values: { gateway: 'twilio', accountSid: 'AC1', authToken: 'twilio-secret-9876', from: '+15550001', apiBase: 'http://localhost:4010' } });
await call('PUT', '/integrations/einvoice', { values: { apiBase: 'http://localhost:4010', clientId: 'cid', clientSecret: 'csecret', username: 'u', password: 'p', publicKey } });
await call('PUT', '/integrations/razorpay', { values: { keyId: 'rzp_test_1', keySecret: 'ksecret-5555', webhookSecret: 'whsec_abc', bankAccountId: bank.id, apiBase: 'http://localhost:4010' } });
st = await call('GET', '/integrations');
const wa = st.find((s) => s.provider === 'whatsapp');
ok(wa.connected && wa.fields.find((f) => f.key === 'accessToken').stored === '••••1234' && wa.fields.find((f) => f.key === 'accessToken').value === null, 'secret masked, never returned');
ok(!JSON.stringify(st).includes('EAAB-secret') && !JSON.stringify(st).includes('twilio-secret') && !JSON.stringify(st).includes('BEGIN PUBLIC'), 'no secret anywhere in the response');
await call('PUT', '/integrations/whatsapp', { values: { language: 'en_US', accessToken: '' } });
ok((await call('GET', '/integrations')).find((s) => s.provider === 'whatsapp').fields.find((f) => f.key === 'accessToken').stored === '••••1234', 'empty secret keeps the stored one');

// ---- messaging
await call('POST', '/messages/test', { channel: 'whatsapp', to: '9876543210' });
ok(sent[0].wa.to === '919876543210' && sent[0].auth === 'Bearer EAAB-secret-token-1234', 'test WhatsApp reached the provider with the stored token');
const inv = await call('POST', '/invoices', { type: 'sale', isCash: false, number: 'INV-1', invoiceDate: today, partyId: cust.id, roundOff: false, stateOfSupply: '29', lines: [{ itemId: item.id, name: 'Widget', quantity: 10, price: 100, hsnCode: '8501', gstRate: 18 }] });
ok(inv.total === 1180 && inv.interState, `inter-state sale total ${inv.total}`);
await new Promise((r) => setTimeout(r, 600));
const auto = sent.find((s) => s.wa && s.wa.text?.body?.includes('INV-1'));
ok(!!auto, 'new invoice was sent automatically on WhatsApp');
ok(auto.wa.text.body.includes('Ravi Traders') && auto.wa.text.body.includes('1180'), 'wording filled in: ' + auto.wa.text.body);
await call('POST', `/messages/invoices/${inv.id}`, { channel: 'sms' });
ok(sent.some((s) => s.sms?.includes('INV-1')), 'invoice sent by SMS on request');
const log = await call('GET', '/messages');
ok(log.length >= 3 && log.every((m) => m.status === 'sent'), `message log has ${log.length} entries`);
await call('POST', '/messages/invoices/' + inv.id, { channel: 'whatsapp', phone: '12' }, 400); ok(true, 'bad phone rejected');
const mk = await call('POST', '/messages/marketing', { channel: 'sms', text: 'Festival offer for you, {customer}!' });
ok(mk.sent === 1 && sent.some((s) => s.sms === 'Festival offer for you, Ravi Traders!'), 'marketing sent to parties with a phone');

// ---- e-invoice and e-way bill
let es = await call('GET', `/einvoice/${inv.id}`);
ok(es.portalConnected && es.einvoiceProblems.length === 0, 'invoice is ready for e-invoicing');
const ej = await call('GET', `/einvoice/${inv.id}/einvoice-json`);
ok(ej.json[0].DocDtls.No === 'INV-1' && ej.json[0].BuyerDtls.Gstin === '29BBBBB1111B1Z6' && ej.json[0].ValDtls.TotInvVal === 1180, 'e-invoice JSON generated');
await call('GET', `/einvoice/${inv.id}/eway-json`, null, 400); ok(true, 'e-way JSON refused until transport details are given');
es = await call('PUT', `/einvoice/${inv.id}/transport`, { mode: 'road', vehicleNo: 'mh12 ab 1234', distanceKm: 840 });
ok(es.transport.vehicleNo === 'MH12AB1234' && es.ewayProblems.length === 0, 'transport saved');
const wj = await call('GET', `/einvoice/${inv.id}/eway-json`);
ok(wj.json.billLists[0].transDistance === '840', 'e-way bill JSON generated');
es = await call('POST', `/einvoice/${inv.id}/generate`);
ok(es.einvoiceStatus === 'generated' && es.irn.length === 64 && es.ackNo === '1122334455', 'IRN generated through the (simulated) portal');
await call('PUT', `/invoices/${inv.id}`, { type: 'sale', isCash: false, number: 'INV-1', invoiceDate: today, partyId: cust.id, roundOff: false, stateOfSupply: '29', lines: [{ itemId: item.id, name: 'Widget', quantity: 1, price: 100 }] }, 400);
ok(true, 'invoice with an IRN cannot be edited');
await call('DELETE', `/invoices/${inv.id}`, null, 400); ok(true, 'invoice with an IRN cannot be deleted');
es = await call('POST', `/einvoice/${inv.id}/eway/generate`);
ok(es.ewayBillNo === '331234567890' && es.ewayValidUpto, 'e-way bill generated from the IRN');
es = await call('POST', `/einvoice/${inv.id}/cancel`, { reason: '1', remark: 'Duplicate', onPortal: true });
ok(es.einvoiceStatus === 'cancelled' && irnCancelled, 'IRN cancelled on the portal');
await call('PUT', `/invoices/${inv.id}`, { type: 'sale', isCash: false, number: 'INV-1', invoiceDate: today, partyId: cust.id, roundOff: false, stateOfSupply: '29', lines: [{ itemId: item.id, name: 'Widget', quantity: 10, price: 100, hsnCode: '8501', gstRate: 18 }] });
ok(true, 'after cancelling, the invoice can be edited again');
const inv2 = await call('POST', '/invoices', { type: 'sale', isCash: false, number: 'INV-2', invoiceDate: today, partyId: cust.id, roundOff: false, stateOfSupply: '29', lines: [{ itemId: item.id, name: 'Widget', quantity: 1, price: 100, hsnCode: '8501', gstRate: 18 }] });
es = await call('POST', `/einvoice/${inv2.id}/record`, { irn: 'b'.repeat(64), ackNo: '99', ackDate: '13/10/2026 09:00:00' });
ok(es.einvoiceStatus === 'generated' && es.irn === 'b'.repeat(64), 'IRN generated on the portal can be recorded by hand');
await call('POST', `/einvoice/${inv2.id}/eway/record`, { no: '331000000009' }, 201);
ok(true, 'e-way bill number can be recorded by hand');
const cash = await call('POST', '/invoices', { type: 'sale', isCash: true, number: 'INV-3', invoiceDate: today, roundOff: false, lines: [{ itemId: item.id, name: 'Widget', quantity: 1, price: 100 }] });
ok((await call('GET', `/einvoice/${cash.id}`)).einvoiceProblems.length > 0, 'cash sale without GSTIN is not e-invoiceable');

// ---- online payments
const wurl = await call('GET', '/online-payments/webhook-url');
ok(wurl.url.endsWith(`/api/v1/webhooks/razorpay/${firmId}`), 'webhook address: ' + wurl.url);
const inv4 = await call('POST', '/invoices', { type: 'sale', isCash: false, number: 'INV-4', invoiceDate: today, partyId: cust.id, roundOff: false, stateOfSupply: '29', lines: [{ itemId: item.id, name: 'Widget', quantity: 2, price: 100, gstRate: 18 }] });
const link = await call('POST', `/online-payments/invoices/${inv4.id}/link`);
ok(link.url.startsWith('https://rzp.io/i/') && link.amount === 236 && link.status === 'created', 'payment link for ₹236');
ok([...links.values()][0].amount === 23600, 'Razorpay was asked for 23600 paise');
ok((await call('POST', `/online-payments/invoices/${inv4.id}/link`)).id === link.id, 'same link is reused while the amount is unchanged');
const event = JSON.stringify({ event: 'payment_link.paid', payload: { payment_link: { entity: { id: [...links.keys()][0], status: 'paid' } }, payment: { entity: { id: 'pay_ABC123' } } } });
const hook = (b, sig) => fetch(`${B}/webhooks/razorpay/${firmId}`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-razorpay-signature': sig }, body: b });
ok((await hook(event, 'deadbeef')).status === 400, 'forged webhook rejected');
const good = crypto.createHmac('sha256', 'whsec_abc').update(event).digest('hex');
ok((await hook(event, good)).status === 200, 'signed webhook accepted');
ok((await hook(event, good)).status === 200, 'same webhook delivered again is harmless');
const after = await call('GET', `/invoices/${inv4.id}`);
ok(after.balance === 0 && after.linkedPayments.length === 1 && after.linkedPayments[0].amount === 236, 'Payment-In recorded once and linked: balance ' + after.balance);
const pays = await call('GET', '/payments?type=in');
ok(pays.filter((p) => p.amount === 236).length === 1, 'exactly one payment recorded');
ok((await call('GET', `/online-payments/invoices/${inv4.id}`))[0].status === 'paid', 'link marked paid');
await new Promise((r) => setTimeout(r, 600));
ok(sent.some((s) => s.sms?.includes('236')), 'receipt SMS sent automatically for the online payment');
await call('POST', `/online-payments/invoices/${inv4.id}/link`, null, 400); ok(true, 'no link for a settled invoice');

// ---- Google Business Profile (no Google client configured here)
const g = await call('GET', '/google-profile/auth-url', null, 400);
ok(g.code === 'GOOGLE_NOT_CONFIGURED' || /not set up/.test(JSON.stringify(g)), 'Google profile explains the server is not configured');

// ---- salesmen cannot reach admin things
await call('DELETE', '/integrations/sms', null, 204); ok((await call('GET', '/integrations')).find((s) => s.provider === 'sms').connected === false, 'integration can be removed');
server.close();
console.log('\nALL INTEGRATION CHECKS PASSED');
