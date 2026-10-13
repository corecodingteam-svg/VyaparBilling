import * as crypto from 'crypto';
import { decryptSecrets, encryptSecrets, mask } from '../src/common/secrets';
import { normalizePhone, render, sendSms, sendWhatsApp } from '../src/messaging/clients';
import { buildEinvoice, buildEway, DocData, einvoiceProblems, ewayProblems, IrpClient, parsePortalDate, portalDate, uqc } from '../src/einvoice/nic';
import { upiUri, verifyWebhook } from '../src/payments-online/razorpay';

type Call = { url: string; init: RequestInit };
const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});
const respond = (calls: Call[], body: unknown, status = 200) => {
  globalThis.fetch = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return new Response(JSON.stringify(body), { status });
  }) as any;
};

describe('secrets', () => {
  it('round-trips and never decrypts with the wrong key', () => {
    const env = { JWT_SECRET: 'a'.repeat(32) } as NodeJS.ProcessEnv;
    const stored = encryptSecrets({ token: 'abc123456' }, env);
    expect(stored).not.toContain('abc123456');
    expect(decryptSecrets(stored, env)).toEqual({ token: 'abc123456' });
    expect(decryptSecrets(stored, { JWT_SECRET: 'b'.repeat(32) } as NodeJS.ProcessEnv)).toEqual({});
    expect(mask('abc123456')).toBe('••••3456');
  });
});

describe('messaging clients', () => {
  it('normalises phones and fills templates', () => {
    expect(normalizePhone('098765 43210')).toBe('919876543210');
    expect(normalizePhone('+91 98765-43210')).toBe('919876543210');
    expect(render('Hi {customer}, ₹{amount} {missing}', { customer: 'Ravi', amount: '10' })).toBe('Hi Ravi, ₹10 {missing}');
  });

  it('sends a WhatsApp template with its variables, or plain text without one', async () => {
    const calls: Call[] = [];
    respond(calls, { messages: [{ id: 'wamid.1' }] });
    const c = { config: { phoneNumberId: '555', language: 'en_US' }, secrets: { accessToken: 'tok' } };
    expect(await sendWhatsApp(c, '919876543210', { template: 'invoice_v1', params: ['Ravi', 'INV-1'], text: 'x' })).toEqual({ id: 'wamid.1' });
    expect(calls[0].url).toBe('https://graph.facebook.com/v20.0/555/messages');
    expect((calls[0].init.headers as any).Authorization).toBe('Bearer tok');
    const body = JSON.parse(calls[0].init.body as string);
    expect(body.type).toBe('template');
    expect(body.template).toEqual({ name: 'invoice_v1', language: { code: 'en_US' }, components: [{ type: 'body', parameters: [{ type: 'text', text: 'Ravi' }, { type: 'text', text: 'INV-1' }] }] });
    await sendWhatsApp(c, '919876543210', { text: 'hello' });
    expect(JSON.parse(calls[1].init.body as string)).toMatchObject({ type: 'text', text: { body: 'hello' } });
  });

  it('reports the provider’s own error', async () => {
    respond([], { error: { message: 'Recipient not in allowed list' } }, 400);
    await expect(sendWhatsApp({ config: { phoneNumberId: '1' }, secrets: { accessToken: 't' } }, '91', { text: 'x' })).rejects.toThrow(/Recipient not in allowed list/);
  });

  it('sends SMS through Twilio and MSG91', async () => {
    const calls: Call[] = [];
    respond(calls, { sid: 'SM1' });
    const tw = { config: { gateway: 'twilio', accountSid: 'AC1', from: '+1555' }, secrets: { authToken: 'secret' } };
    expect(await sendSms(tw, '919876543210', { text: 'Hi' })).toEqual({ id: 'SM1' });
    expect(calls[0].url).toBe('https://api.twilio.com/2010-04-01/Accounts/AC1/Messages.json');
    expect((calls[0].init.headers as any).Authorization).toBe(`Basic ${Buffer.from('AC1:secret').toString('base64')}`);
    expect(new URLSearchParams(calls[0].init.body as string).get('To')).toBe('+919876543210');
    expect(new URLSearchParams(calls[0].init.body as string).get('From')).toBe('+1555');

    respond(calls, { request_id: 'r1' });
    const m = { config: { gateway: 'msg91', msg91TemplateId: 'T1' }, secrets: { authToken: 'key' } };
    expect(await sendSms(m, '919876543210', { text: 'x', params: ['Ravi', '100'] })).toEqual({ id: 'r1' });
    expect((calls[1].init.headers as any).authkey).toBe('key');
    expect(JSON.parse(calls[1].init.body as string)).toEqual({ template_id: 'T1', recipients: [{ mobiles: '919876543210', var1: 'Ravi', var2: '100' }] });
  });
});

const doc = (over: Partial<DocData> = {}): DocData => ({
  type: 'sale', number: 'INV-12', date: '2026-04-05', total: 1180, roundOff: 0, taxable: 1000, cgst: 0, sgst: 0, igst: 180, cess: 0, charges: 0, interState: true, stateOfSupply: '29', shipTo: null,
  seller: { gstin: '27AAAAA0000A1Z5', name: 'Acme', address: '1 Main Rd', city: 'Pune', pincode: '411001', stateCode: '27', phone: '9876543210', email: null },
  buyer: { gstin: '29BBBBB1111B1Z6', name: 'Buyer Co', address: '2 High St', city: 'Bengaluru', pincode: '560001', stateCode: '29', phone: null, email: null },
  lines: [{ name: 'Widget', hsn: '8501', isService: false, qty: 10, unit: 'pcs', price: 100, discount: 0, taxable: 1000, gstRate: 18, cgst: 0, sgst: 0, igst: 180, cessRate: 0, cess: 0, amount: 1180 }],
  transport: { mode: 'road', transporterId: null, transporterName: null, docNo: null, docDate: null, vehicleNo: 'MH12AB1234', distanceKm: 840 },
  ...over,
});

describe('e-invoice and e-way bill JSON', () => {
  it('builds the NIC schema', () => {
    expect(einvoiceProblems(doc())).toEqual([]);
    const j = buildEinvoice(doc());
    expect(j.Version).toBe('1.1');
    expect(j.DocDtls).toEqual({ Typ: 'INV', No: 'INV-12', Dt: '05/04/2026' });
    expect(j.SellerDtls).toMatchObject({ Gstin: '27AAAAA0000A1Z5', Pin: 411001, Stcd: '27' });
    expect(j.BuyerDtls).toMatchObject({ Gstin: '29BBBBB1111B1Z6', Pos: '29', Pin: 560001 });
    expect(j.ItemList[0]).toMatchObject({ SlNo: '1', HsnCd: '8501', Unit: 'PCS', Qty: 10, UnitPrice: 100, TotAmt: 1000, AssAmt: 1000, GstRt: 18, IgstAmt: 180, TotItemVal: 1180, IsServc: 'N' });
    expect(j.ValDtls).toMatchObject({ AssVal: 1000, IgstVal: 180, TotInvVal: 1180 });
    expect(buildEinvoice(doc({ type: 'credit_note' })).DocDtls.Typ).toBe('CRN');
  });

  it('lists what is missing', () => {
    const p = einvoiceProblems(doc({ buyer: { ...doc().buyer, gstin: null, pincode: null }, number: 'THIS-NUMBER-IS-WAY-TOO-LONG' }));
    expect(p.join('\n')).toMatch(/customer needs a valid GSTIN/);
    expect(p.join('\n')).toMatch(/6-digit pincode/);
    expect(p.join('\n')).toMatch(/at most 16 characters/);
    expect(einvoiceProblems(doc({ lines: [{ ...doc().lines[0], hsn: null }] })).join()).toMatch(/HSN/);
    expect(einvoiceProblems(doc({ type: 'estimate' })).join()).toMatch(/Only sale invoices/);
  });

  it('builds the e-way bill bulk JSON', () => {
    expect(ewayProblems(doc())).toEqual([]);
    const b = buildEway(doc()).billLists[0];
    expect(b).toMatchObject({ userGstin: '27AAAAA0000A1Z5', supplyType: 'O', docNo: 'INV-12', docDate: '05/04/2026', fromPincode: 411001, toPincode: 560001, toStateCode: 29, transMode: '1', transDistance: '840', vehicleNo: 'MH12AB1234', totInvValue: 1180 });
    expect(b.itemList[0]).toMatchObject({ hsnCode: 8501, quantity: 10, igstRate: 18, cgstRate: 0 });
    expect(ewayProblems(doc({ transport: { ...doc().transport, vehicleNo: null } })).join()).toMatch(/vehicle number or the transporter/);
    expect(ewayProblems(doc({ transport: { ...doc().transport, mode: 'rail' } })).join()).toMatch(/transport document/);
  });

  it('maps units and dates', () => {
    expect(uqc('Kg')).toBe('KGS');
    expect(uqc('weird')).toBe('OTH');
    expect(portalDate('2026-01-09')).toBe('09/01/2026');
    expect(parsePortalDate('09/01/2026 10:30:00')?.toISOString()).toBe('2026-01-09T05:00:00.000Z');
  });
});

describe('IRP client against a simulated NIC server', () => {
  it('logs in with RSA, then exchanges AES-encrypted requests', async () => {
    const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048, publicKeyEncoding: { type: 'spki', format: 'pem' }, privateKeyEncoding: { type: 'pkcs8', format: 'pem' } });
    const sek = crypto.randomBytes(32);
    const ecb = (key: Buffer, data: Buffer, decrypt: boolean) => {
      const c = (decrypt ? crypto.createDecipheriv : crypto.createCipheriv)('aes-256-ecb', key, null);
      return Buffer.concat([c.update(data), c.final()]);
    };
    const seen: string[] = [];
    let received: any;
    globalThis.fetch = (async (url: string, init: RequestInit) => {
      const path = new URL(url).pathname;
      seen.push(path);
      const h = init.headers as Record<string, string>;
      const body = JSON.parse(init.body as string);
      const ok = (data: unknown) => new Response(JSON.stringify({ Status: 1, Data: data }));
      if (path === '/eivital/v1.04/auth') {
        expect(h.client_id).toBe('cid');
        expect(h.gstin).toBe('27AAAAA0000A1Z5');
        const login = JSON.parse(crypto.privateDecrypt({ key: privateKey, padding: crypto.constants.RSA_PKCS1_PADDING }, Buffer.from(body.Data, 'base64')).toString());
        expect(login).toMatchObject({ UserName: 'user', Password: 'pass' });
        return ok({ AuthToken: 'tok1', Sek: ecb(Buffer.from(login.AppKey, 'base64'), sek, false).toString('base64') });
      }
      expect(h.AuthToken).toBe('tok1');
      received = JSON.parse(ecb(sek, Buffer.from(body.Data, 'base64'), true).toString());
      if (path === '/eicore/v1.03/Invoice') return ok({ Irn: 'a'.repeat(64), AckNo: 112010000000001, AckDt: '05/04/2026 10:00:00', SignedQRCode: 'qr.jwt' });
      if (path === '/eiewb/v1.03/ewaybill') return ok(ecb(sek, Buffer.from(JSON.stringify({ EwbNo: 331000000001, EwbDt: '05/04/2026 11:00:00', EwbValidTill: '10/04/2026 23:59:00' })), false).toString('base64'));
      return new Response(JSON.stringify({ Status: 0, ErrorDetails: [{ ErrorCode: '2150', ErrorMessage: 'Duplicate IRN' }] }), { status: 200 });
    }) as any;

    const c = new IrpClient({ config: { apiBase: 'https://irp.test', clientId: 'cid', username: 'user' }, secrets: { clientSecret: 'cs', password: 'pass', publicKey } }, '27AAAAA0000A1Z5');
    const r = await c.generate(buildEinvoice(doc()));
    expect(r).toEqual({ irn: 'a'.repeat(64), ackNo: '112010000000001', ackDate: '05/04/2026 10:00:00', signedQr: 'qr.jwt' });
    expect(received.DocDtls.No).toBe('INV-12');
    const e = await c.eway(r.irn, doc().transport);
    expect(e).toEqual({ no: '331000000001', date: '05/04/2026 11:00:00', validUpto: '10/04/2026 23:59:00' });
    expect(received).toMatchObject({ Irn: r.irn, Distance: 840, TransMode: '1', VehNo: 'MH12AB1234' });
    expect(seen.filter((p) => p.includes('auth'))).toHaveLength(1); // one login serves both calls
    await expect(c.cancel(r.irn, '1', 'dup')).rejects.toThrow(/2150 Duplicate IRN/);
  });
});

describe('online payments helpers', () => {
  it('verifies the webhook signature over the raw bytes', () => {
    const raw = Buffer.from('{"event":"payment_link.paid"}');
    const sig = crypto.createHmac('sha256', 'whsec').update(raw).digest('hex');
    expect(verifyWebhook(raw, sig, 'whsec')).toBe(true);
    expect(verifyWebhook(raw, sig, 'other')).toBe(false);
    expect(verifyWebhook(Buffer.from('{"event":"payment_link.paid" }'), sig, 'whsec')).toBe(false);
    expect(verifyWebhook(raw, undefined, 'whsec')).toBe(false);
    expect(verifyWebhook(raw, 'short', 'whsec')).toBe(false);
  });

  it('builds a UPI payment string', () => {
    expect(upiUri({ upiId: 'shop@upi', name: 'My Shop', amount: 118.5, note: 'INV-1' })).toBe('upi://pay?pa=shop%40upi&pn=My%20Shop&cu=INR&am=118.50&tn=INV-1');
  });
});
