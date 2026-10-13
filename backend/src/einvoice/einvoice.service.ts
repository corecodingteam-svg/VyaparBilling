import { BadRequestException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Scope } from '../auth/scope';
import { Db, KYSELY } from '../database/database.module';
import { IntegrationsService } from '../integrations/integrations.service';
import { buildEinvoice, buildEway, DocData, einvoiceProblems, ewayProblems, IrpClient, parsePortalDate } from './nic';

const n = (v: unknown) => Number(v ?? 0);

export interface Transport {
  mode?: 'road' | 'rail' | 'air' | 'ship' | null;
  transporterId?: string | null;
  transporterName?: string | null;
  docNo?: string | null;
  docDate?: string | null;
  vehicleNo?: string | null;
  distanceKm?: number | null;
}

@Injectable()
export class EinvoiceService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly integrations: IntegrationsService,
  ) {}

  private async load(firmId: string, id: string, scope: Scope = {}): Promise<{ data: DocData; row: any }> {
    const inv = await this.db
      .selectFrom('invoices').selectAll().where('id', '=', id).where('firm_id', '=', firmId).where('deleted_at', 'is', null)
      .$if(!!scope.ownerUserId, (q) => q.where('created_by', '=', scope.ownerUserId!))
      .executeTakeFirst();
    if (!inv) throw new NotFoundException({ code: 'INVOICE_NOT_FOUND', message: 'Invoice not found.' });
    const [firm, party, lines] = await Promise.all([
      this.db.selectFrom('firms').selectAll().where('id', '=', firmId).executeTakeFirstOrThrow(),
      inv.party_id ? this.db.selectFrom('parties').selectAll().where('id', '=', inv.party_id).executeTakeFirst() : Promise.resolve(undefined),
      this.db
        .selectFrom('invoice_items as l').leftJoin('items as i', 'i.id', 'l.item_id').select(['l.name', 'l.hsn_code', 'l.quantity', 'l.unit', 'l.price', 'l.discount_amount', 'l.bill_discount', 'l.taxable_value',
          'l.gst_rate', 'l.cgst', 'l.sgst', 'l.igst', 'l.cess_rate', 'l.cess', 'l.amount', 'i.type as item_type'])
        .where('l.invoice_id', '=', id).orderBy('l.sort_order').execute(),
    ]);
    const data: DocData = {
      type: inv.type, number: inv.number, date: inv.invoice_date, total: n(inv.total), roundOff: n(inv.round_off), taxable: n(inv.taxable_amount),
      cgst: n(inv.cgst), sgst: n(inv.sgst), igst: n(inv.igst), cess: n(inv.cess), charges: n(inv.charges_total) + n(inv.tcs_amount), interState: inv.is_inter_state,
      stateOfSupply: inv.state_of_supply, shipTo: inv.shipping_address,
      seller: { gstin: firm.gstin, name: firm.name, address: firm.address, city: firm.city, pincode: firm.pincode, stateCode: firm.state_code, phone: firm.phone, email: firm.email },
      buyer: {
        gstin: inv.party_gstin ?? party?.gstin ?? null, name: inv.party_name, address: inv.billing_address ?? party?.billing_address ?? null, city: party?.city ?? null,
        pincode: party?.pincode ?? null, stateCode: party?.state_code ?? inv.state_of_supply, phone: inv.phone ?? party?.phone ?? null, email: party?.email ?? null,
      },
      lines: lines.map((l) => ({
        name: l.name, hsn: l.hsn_code, isService: l.item_type === 'service', qty: n(l.quantity), unit: l.unit, price: n(l.price), discount: n(l.discount_amount) + n(l.bill_discount),
        taxable: n(l.taxable_value), gstRate: n(l.gst_rate), cgst: n(l.cgst), sgst: n(l.sgst), igst: n(l.igst), cessRate: n(l.cess_rate), cess: n(l.cess), amount: n(l.amount),
      })),
      transport: {
        mode: inv.transport_mode, transporterId: inv.transporter_id, transporterName: inv.transporter_name, docNo: inv.transport_doc_no, docDate: inv.transport_doc_date,
        vehicleNo: inv.vehicle_no, distanceKm: inv.distance_km,
      },
    };
    return { data, row: inv };
  }

  /** The portal-facing state of a document, and what stops it from being e-invoiced right now. */
  async status(firmId: string, id: string, scope: Scope = {}) {
    const { data, row } = await this.load(firmId, id, scope);
    const irp = await this.integrations.credentials(firmId, 'einvoice');
    return {
      einvoiceStatus: row.einvoice_status, irn: row.irn, ackNo: row.ack_no, ackDate: row.ack_date, signedQr: row.signed_qr,
      ewayBillNo: row.eway_bill_no, ewayBillDate: row.eway_bill_date, ewayValidUpto: row.eway_valid_upto,
      transport: data.transport, einvoiceProblems: einvoiceProblems(data), ewayProblems: ewayProblems(data), portalConnected: !!irp,
    };
  }

  async einvoiceJson(firmId: string, id: string, scope: Scope = {}) {
    const { data } = await this.load(firmId, id, scope);
    const problems = einvoiceProblems(data);
    if (problems.length) throw new BadRequestException({ code: 'EINVOICE_INCOMPLETE', message: problems.join('\n') });
    return { fileName: `einvoice-${data.number.replace(/[^\w-]/g, '_')}.json`, json: [buildEinvoice(data)] };
  }

  async ewayJson(firmId: string, id: string, scope: Scope = {}) {
    const { data } = await this.load(firmId, id, scope);
    const problems = ewayProblems(data);
    if (problems.length) throw new BadRequestException({ code: 'EWAY_INCOMPLETE', message: problems.join('\n') });
    return { fileName: `ewaybill-${data.number.replace(/[^\w-]/g, '_')}.json`, json: buildEway(data) };
  }

  async saveTransport(firmId: string, id: string, t: Transport, scope: Scope = {}) {
    await this.load(firmId, id, scope);
    await this.db
      .updateTable('invoices')
      .set({
        transport_mode: t.mode ?? null, transporter_id: t.transporterId || null, transporter_name: t.transporterName || null, transport_doc_no: t.docNo || null,
        transport_doc_date: t.docDate || null, vehicle_no: t.vehicleNo ? t.vehicleNo.replace(/\s+/g, '').toUpperCase() : null, distance_km: t.distanceKm ?? null,
      })
      .where('id', '=', id).where('firm_id', '=', firmId).execute();
    return this.status(firmId, id, scope);
  }

  private async client(firmId: string, gstin: string) {
    const c = await this.integrations.credentials(firmId, 'einvoice');
    if (!c) throw new BadRequestException({ code: 'NOT_CONNECTED', message: 'The e-invoice portal is not set up. Add it under Settings → Integrations, or download the JSON and upload it on the portal.' });
    return new IrpClient(c, c.config.gstin || gstin);
  }

  private assertNotDone(row: any) {
    if (row.einvoice_status === 'generated') throw new BadRequestException({ code: 'EINVOICE_EXISTS', message: 'This invoice already has an IRN.' });
  }

  /** Registers the invoice with the portal and keeps the IRN. */
  async generate(firmId: string, id: string, scope: Scope = {}) {
    const { data, row } = await this.load(firmId, id, scope);
    this.assertNotDone(row);
    const problems = einvoiceProblems(data);
    if (problems.length) throw new BadRequestException({ code: 'EINVOICE_INCOMPLETE', message: problems.join('\n') });
    const r = await (await this.client(firmId, data.seller.gstin!)).generate(buildEinvoice(data));
    await this.store(firmId, id, r);
    return this.status(firmId, id, scope);
  }

  /** Keeps an IRN that was generated on the portal itself. */
  async record(firmId: string, id: string, r: { irn: string; ackNo?: string; ackDate?: string; signedQr?: string }, scope: Scope = {}) {
    const { row } = await this.load(firmId, id, scope);
    this.assertNotDone(row);
    await this.store(firmId, id, { irn: r.irn, ackNo: r.ackNo ?? '', ackDate: r.ackDate ?? '', signedQr: r.signedQr ?? '' });
    return this.status(firmId, id, scope);
  }

  private store(firmId: string, id: string, r: { irn: string; ackNo: string; ackDate: string; signedQr: string }) {
    return this.db
      .updateTable('invoices')
      .set({ einvoice_status: 'generated', irn: r.irn, ack_no: r.ackNo || null, ack_date: parsePortalDate(r.ackDate) ?? new Date(), signed_qr: r.signedQr || null, irn_cancelled_at: null })
      .where('id', '=', id).where('firm_id', '=', firmId).execute();
  }

  /** Cancels the IRN (the portal allows this within 24 hours of generating it). */
  async cancel(firmId: string, id: string, reason: '1' | '2' | '3' | '4', remark: string, onPortal: boolean, scope: Scope = {}) {
    const { data, row } = await this.load(firmId, id, scope);
    if (row.einvoice_status !== 'generated' || !row.irn) throw new BadRequestException({ code: 'NO_IRN', message: 'This invoice has no active IRN.' });
    if (onPortal) await (await this.client(firmId, data.seller.gstin!)).cancel(row.irn, reason, remark);
    await this.db.updateTable('invoices').set({ einvoice_status: 'cancelled', irn_cancelled_at: new Date() }).where('id', '=', id).where('firm_id', '=', firmId).execute();
    return this.status(firmId, id, scope);
  }

  /** Makes an e-way bill from the invoice's IRN. */
  async generateEway(firmId: string, id: string, scope: Scope = {}) {
    const { data, row } = await this.load(firmId, id, scope);
    if (row.eway_bill_no) throw new BadRequestException({ code: 'EWAY_EXISTS', message: 'This invoice already has an e-way bill.' });
    if (row.einvoice_status !== 'generated' || !row.irn) {
      throw new BadRequestException({ code: 'NO_IRN', message: 'Generate the e-invoice first; the portal makes the e-way bill from its IRN. Otherwise download the JSON and upload it on the e-way bill portal.' });
    }
    const problems = ewayProblems(data);
    if (problems.length) throw new BadRequestException({ code: 'EWAY_INCOMPLETE', message: problems.join('\n') });
    const r = await (await this.client(firmId, data.seller.gstin!)).eway(row.irn, data.transport);
    await this.storeEway(firmId, id, r.no, r.date, r.validUpto);
    return this.status(firmId, id, scope);
  }

  async recordEway(firmId: string, id: string, r: { no: string; date?: string; validUpto?: string }, scope: Scope = {}) {
    await this.load(firmId, id, scope);
    await this.storeEway(firmId, id, r.no, r.date ?? '', r.validUpto ?? '');
    return this.status(firmId, id, scope);
  }

  private storeEway(firmId: string, id: string, no: string, date: string, validUpto: string) {
    return this.db
      .updateTable('invoices')
      .set({ eway_bill_no: no, eway_bill_date: parsePortalDate(date) ?? new Date(), eway_valid_upto: parsePortalDate(validUpto) })
      .where('id', '=', id).where('firm_id', '=', firmId).execute();
  }

  async clearEway(firmId: string, id: string, scope: Scope = {}) {
    await this.load(firmId, id, scope);
    await this.db.updateTable('invoices').set({ eway_bill_no: null, eway_bill_date: null, eway_valid_upto: null }).where('id', '=', id).where('firm_id', '=', firmId).execute();
    return this.status(firmId, id, scope);
  }
}
