import * as crypto from 'crypto';
import { BadRequestException } from '@nestjs/common';
import type { Credentials } from '../integrations/integrations.service';

const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
/** yyyy-mm-dd → dd/mm/yyyy, the format the portal wants. */
export const portalDate = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}`;

const UQC: Record<string, string> = {
  PCS: 'PCS', PC: 'PCS', PIECE: 'PCS', PIECES: 'PCS', NOS: 'NOS', NO: 'NOS', KG: 'KGS', KGS: 'KGS', GM: 'GMS', GMS: 'GMS', G: 'GMS', LTR: 'LTR', L: 'LTR',
  LITRE: 'LTR', ML: 'MLT', MTR: 'MTR', M: 'MTR', BOX: 'BOX', BAG: 'BAG', BAGS: 'BAG', DOZ: 'DOZ', PAIR: 'PRS', PRS: 'PRS', SET: 'SET', SETS: 'SET',
  TON: 'TON', TONS: 'TON', BTL: 'BTL', BOTTLE: 'BTL', CTN: 'CTN', CARTON: 'CTN', ROLL: 'ROL', ROL: 'ROL', PKT: 'PAC', PACK: 'PAC', PAC: 'PAC', SQF: 'SQF', SQM: 'SQM',
};
export const uqc = (unit: string | null | undefined) => UQC[(unit ?? '').trim().toUpperCase()] ?? 'OTH';

export interface DocData {
  type: 'sale' | 'credit_note' | 'debit_note' | string;
  number: string;
  date: string;
  total: number;
  roundOff: number;
  taxable: number;
  cgst: number;
  sgst: number;
  igst: number;
  cess: number;
  charges: number;
  interState: boolean;
  stateOfSupply: string | null;
  seller: { gstin: string | null; name: string; address: string | null; city: string | null; pincode: string | null; stateCode: string | null; phone: string | null; email: string | null };
  buyer: { gstin: string | null; name: string; address: string | null; city: string | null; pincode: string | null; stateCode: string | null; phone: string | null; email: string | null };
  shipTo: string | null;
  lines: {
    name: string; hsn: string | null; isService: boolean; qty: number; unit: string | null; price: number; discount: number; taxable: number; gstRate: number;
    cgst: number; sgst: number; igst: number; cessRate: number; cess: number; amount: number;
  }[];
  transport: { mode: string | null; transporterId: string | null; transporterName: string | null; docNo: string | null; docDate: string | null; vehicleNo: string | null; distanceKm: number | null };
}

const GSTIN = /^\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]$/;
const PIN = /^\d{6}$/;

/** What is missing or wrong before the portal would accept this invoice. */
export function einvoiceProblems(d: DocData): string[] {
  const p: string[] = [];
  if (!['sale', 'credit_note', 'debit_note'].includes(d.type)) p.push('Only sale invoices, credit notes and debit notes can be e-invoiced.');
  if (!d.seller.gstin || !GSTIN.test(d.seller.gstin)) p.push('Your company needs a valid GSTIN (Settings → Company).');
  if (!d.seller.address) p.push('Your company address is missing.');
  if (!d.seller.city) p.push('Your company city is missing.');
  if (!d.seller.pincode || !PIN.test(d.seller.pincode)) p.push('Your company needs a 6-digit pincode.');
  if (!d.seller.stateCode) p.push('Your company state is missing.');
  if (!d.buyer.gstin || !GSTIN.test(d.buyer.gstin)) p.push('The customer needs a valid GSTIN — e-invoices are for GST-registered buyers (B2B).');
  if (!d.buyer.address) p.push('The customer’s address is missing.');
  if (!d.buyer.city) p.push('The customer’s city is missing.');
  if (!d.buyer.pincode || !PIN.test(d.buyer.pincode)) p.push('The customer needs a 6-digit pincode.');
  if (!d.stateOfSupply) p.push('Place of supply (state) is missing on the invoice.');
  if (d.number.length > 16 || !/^[A-Za-z0-9][A-Za-z0-9/-]*$/.test(d.number)) p.push('The invoice number must be at most 16 characters of letters, digits, "/" and "-".');
  if (!d.lines.length) p.push('The invoice has no items.');
  d.lines.forEach((l, i) => {
    if (!l.hsn || !/^\d{4,8}$/.test(l.hsn)) p.push(`Line ${i + 1} (${l.name}) needs a 4–8 digit HSN/SAC code.`);
  });
  return p;
}

/** The NIC e-invoice schema (version 1.1) for one document. */
export function buildEinvoice(d: DocData) {
  const slash = (s: string | null) => (s ?? '').slice(0, 100);
  const items = d.lines.map((l, i) => ({
    SlNo: String(i + 1),
    PrdDesc: l.name.slice(0, 300),
    IsServc: l.isService ? 'Y' : 'N',
    HsnCd: l.hsn,
    Qty: r2(l.qty),
    Unit: uqc(l.unit),
    UnitPrice: r2(l.price),
    TotAmt: r2(l.qty * l.price),
    Discount: r2(l.discount),
    AssAmt: r2(l.taxable),
    GstRt: l.gstRate,
    IgstAmt: r2(l.igst),
    CgstAmt: r2(l.cgst),
    SgstAmt: r2(l.sgst),
    CesRt: l.cessRate,
    CesAmt: r2(l.cess),
    TotItemVal: r2(l.amount),
  }));
  return {
    Version: '1.1',
    TranDtls: { TaxSch: 'GST', SupTyp: 'B2B', RegRev: 'N', IgstOnIntra: 'N' },
    DocDtls: { Typ: d.type === 'credit_note' ? 'CRN' : d.type === 'debit_note' ? 'DBN' : 'INV', No: d.number, Dt: portalDate(d.date) },
    SellerDtls: {
      Gstin: d.seller.gstin, LglNm: d.seller.name, Addr1: slash(d.seller.address), Loc: d.seller.city, Pin: Number(d.seller.pincode), Stcd: d.seller.stateCode,
      ...(d.seller.phone ? { Ph: d.seller.phone.replace(/\D/g, '').slice(-12) } : {}), ...(d.seller.email ? { Em: d.seller.email } : {}),
    },
    BuyerDtls: {
      Gstin: d.buyer.gstin, LglNm: d.buyer.name, Pos: d.stateOfSupply, Addr1: slash(d.buyer.address), Loc: d.buyer.city, Pin: Number(d.buyer.pincode), Stcd: d.buyer.stateCode ?? d.stateOfSupply,
      ...(d.buyer.phone ? { Ph: d.buyer.phone.replace(/\D/g, '').slice(-12) } : {}), ...(d.buyer.email ? { Em: d.buyer.email } : {}),
    },
    ItemList: items,
    ValDtls: {
      AssVal: r2(d.taxable), CgstVal: r2(d.cgst), SgstVal: r2(d.sgst), IgstVal: r2(d.igst), CesVal: r2(d.cess), Discount: 0, OthChrg: r2(d.charges),
      RndOffAmt: r2(d.roundOff), TotInvVal: r2(d.total),
    },
  };
}

const MODES: Record<string, number> = { road: 1, rail: 2, air: 3, ship: 4 };

/** What is missing before an e-way bill can be made for this document. */
export function ewayProblems(d: DocData): string[] {
  const p: string[] = [];
  if (d.type !== 'sale' && d.type !== 'credit_note') p.push('An e-way bill is made for a sale invoice (or credit note).');
  if (!d.seller.gstin) p.push('Your company needs a GSTIN.');
  if (!d.seller.pincode || !PIN.test(d.seller.pincode)) p.push('Your company needs a 6-digit pincode.');
  if (!d.buyer.pincode || !PIN.test(d.buyer.pincode)) p.push('The customer needs a 6-digit pincode.');
  if (!d.buyer.stateCode && !d.stateOfSupply) p.push('The customer’s state is missing.');
  if (!d.transport.distanceKm && d.transport.distanceKm !== 0) p.push('Enter the distance in km.');
  if (!d.transport.mode) p.push('Choose the transport mode.');
  if (d.transport.mode === 'road' && !d.transport.vehicleNo && !d.transport.transporterId) p.push('For road transport enter the vehicle number or the transporter ID.');
  if (d.transport.mode && d.transport.mode !== 'road' && (!d.transport.docNo || !d.transport.docDate)) p.push('For rail, air or ship enter the transport document number and date.');
  d.lines.forEach((l, i) => {
    if (!l.hsn || !/^\d{4,8}$/.test(l.hsn)) p.push(`Line ${i + 1} (${l.name}) needs a 4–8 digit HSN code.`);
  });
  return p;
}

/** The e-way bill portal's bulk-upload JSON. */
export function buildEway(d: DocData) {
  const t = d.transport;
  const to = d.buyer.stateCode ?? d.stateOfSupply;
  return {
    version: '1.0.0621',
    billLists: [
      {
        userGstin: d.seller.gstin, supplyType: 'O', subSupplyType: 1, subSupplyDesc: '', docType: d.type === 'credit_note' ? 'CNT' : 'INV', docNo: d.number, docDate: portalDate(d.date),
        transType: 1, fromGstin: d.seller.gstin, fromTrdName: d.seller.name, fromAddr1: (d.seller.address ?? '').slice(0, 120), fromPlace: d.seller.city ?? '',
        fromPincode: Number(d.seller.pincode), fromStateCode: Number(d.seller.stateCode), actFromStateCode: Number(d.seller.stateCode),
        toGstin: d.buyer.gstin ?? 'URP', toTrdName: d.buyer.name, toAddr1: (d.shipTo ?? d.buyer.address ?? '').slice(0, 120), toPlace: d.buyer.city ?? '',
        toPincode: Number(d.buyer.pincode), toStateCode: Number(to), actToStateCode: Number(to),
        totalValue: r2(d.taxable), cgstValue: r2(d.cgst), sgstValue: r2(d.sgst), igstValue: r2(d.igst), cessValue: r2(d.cess), otherValue: r2(d.charges + d.roundOff), totInvValue: r2(d.total),
        transporterId: t.transporterId ?? '', transporterName: t.transporterName ?? '', transDocNo: t.docNo ?? '', transDocDate: t.docDate ? portalDate(t.docDate) : '',
        transMode: String(MODES[t.mode ?? 'road'] ?? 1), transDistance: String(t.distanceKm ?? 0), vehicleNo: (t.vehicleNo ?? '').replace(/\s+/g, '').toUpperCase(), vehicleType: 'R',
        itemList: d.lines.map((l, i) => ({
          itemNo: i + 1, productName: l.name.slice(0, 100), productDesc: l.name.slice(0, 100), hsnCode: Number(l.hsn), quantity: r2(l.qty), qtyUnit: uqc(l.unit),
          taxableAmount: r2(l.taxable), sgstRate: d.interState ? 0 : l.gstRate / 2, cgstRate: d.interState ? 0 : l.gstRate / 2, igstRate: d.interState ? l.gstRate : 0, cessRate: l.cessRate,
        })),
      },
    ],
  };
}

// ------------------------------------------------------------------ IRP client

const aesEcb = (key: Buffer, data: Buffer, decrypt: boolean) => {
  const c = (decrypt ? crypto.createDecipheriv : crypto.createCipheriv)('aes-256-ecb', key, null);
  return Buffer.concat([c.update(data), c.final()]);
};

interface Session {
  token: string;
  sek: Buffer;
  at: number;
}

/**
 * Talks to NIC's e-invoice (IRP) API: RSA-encrypted login, then AES-256 (ECB) encrypted requests under the
 * session key NIC returns. Written from NIC's published API description; it has not been run against NIC.
 */
export class IrpClient {
  private session?: Session;

  constructor(private readonly c: Credentials, private readonly gstin: string) {}

  private get base() {
    return this.c.config.apiBase.replace(/\/$/, '');
  }

  private headers(extra: Record<string, string> = {}) {
    return { 'Content-Type': 'application/json', client_id: this.c.config.clientId, client_secret: this.c.secrets.clientSecret, gstin: this.gstin, ...extra };
  }

  private async post(path: string, body: unknown, headers: Record<string, string>) {
    let res: Response;
    try {
      res = await fetch(`${this.base}${path}`, { method: 'POST', headers, body: JSON.stringify(body), signal: AbortSignal.timeout(30_000) });
    } catch (e) {
      throw new BadRequestException({ code: 'IRP_UNREACHABLE', message: `Could not reach the e-invoice portal: ${(e as Error).message}` });
    }
    const json: any = await res.json().catch(() => ({}));
    if (!res.ok || json.Status === 0) {
      const errs = json.ErrorDetails ?? (json.error ? [json.error] : []);
      const msg = errs.map((e: any) => `${e.ErrorCode ?? ''} ${e.ErrorMessage ?? e.message ?? ''}`.trim()).join('; ') || `HTTP ${res.status}`;
      throw new BadRequestException({ code: 'IRP_ERROR', message: `The e-invoice portal said: ${msg}` });
    }
    return json;
  }

  private async login(): Promise<Session> {
    if (this.session && Date.now() - this.session.at < 5 * 60 * 60 * 1000) return this.session;
    const appKey = crypto.randomBytes(32);
    const payload = JSON.stringify({ UserName: this.c.config.username, Password: this.c.secrets.password, AppKey: appKey.toString('base64'), ForceRefreshAccessToken: false });
    const encrypted = crypto.publicEncrypt({ key: this.c.secrets.publicKey, padding: crypto.constants.RSA_PKCS1_PADDING }, Buffer.from(payload));
    const json = await this.post('/eivital/v1.04/auth', { Data: encrypted.toString('base64') }, this.headers());
    const sek = aesEcb(appKey, Buffer.from(json.Data.Sek, 'base64'), true);
    this.session = { token: json.Data.AuthToken, sek, at: Date.now() };
    return this.session;
  }

  private async secure(path: string, payload: unknown) {
    const s = await this.login();
    const data = aesEcb(s.sek, Buffer.from(JSON.stringify(payload)), false).toString('base64');
    const json = await this.post(path, { Data: data }, this.headers({ user_name: this.c.config.username, AuthToken: s.token }));
    const out = json.Data;
    if (typeof out === 'string') {
      try {
        return JSON.parse(aesEcb(s.sek, Buffer.from(out, 'base64'), true).toString());
      } catch {
        return JSON.parse(out);
      }
    }
    return out;
  }

  /** Registers the invoice and returns the IRN and signed QR. */
  async generate(payload: unknown): Promise<{ irn: string; ackNo: string; ackDate: string; signedQr: string }> {
    const r = await this.secure('/eicore/v1.03/Invoice', payload);
    return { irn: r.Irn, ackNo: String(r.AckNo), ackDate: r.AckDt, signedQr: r.SignedQRCode };
  }

  async cancel(irn: string, reason: '1' | '2' | '3' | '4', remark: string) {
    await this.secure('/eicore/v1.03/Invoice/Cancel', { Irn: irn, CnlRsn: reason, CnlRem: remark });
  }

  /** An e-way bill made from an existing IRN. */
  async eway(irn: string, t: DocData['transport']): Promise<{ no: string; date: string; validUpto: string }> {
    const r = await this.secure('/eiewb/v1.03/ewaybill', {
      Irn: irn, Distance: t.distanceKm ?? 0, TransMode: String(MODES[t.mode ?? 'road'] ?? 1), TransId: t.transporterId ?? undefined, TransName: t.transporterName ?? undefined,
      TransDocDt: t.docDate ? portalDate(t.docDate) : undefined, TransDocNo: t.docNo ?? undefined, VehNo: t.vehicleNo?.replace(/\s+/g, '').toUpperCase() ?? undefined, VehType: 'R',
    });
    return { no: String(r.EwbNo), date: r.EwbDt, validUpto: r.EwbValidTill };
  }
}

/** "dd/mm/yyyy hh:mm:ss" or ISO → a Date, or null. */
export function parsePortalDate(s: string | null | undefined): Date | null {
  if (!s) return null;
  const m = /^(\d{2})\/(\d{2})\/(\d{4})(?:\s+(\d{2}):(\d{2}):(\d{2}))?$/.exec(s.trim());
  const d = m ? new Date(`${m[3]}-${m[2]}-${m[1]}T${m[4] ?? '00'}:${m[5] ?? '00'}:${m[6] ?? '00'}+05:30`) : new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}
