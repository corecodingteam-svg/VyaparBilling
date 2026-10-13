import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Selectable, sql, Transaction } from 'kysely';
import { resolveBankAccount } from '../common/bank-account';
import { assertBooksOpen } from '../common/books-lock';
import { INVOICE_TYPES, InvoiceType, isQuote } from '../common/invoice-types';
import { num, today } from '../common/numbers';
import { partyBalanceSql, r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { Database, InvoicesTable, PaymentMode } from '../database/schema';
import { FirmService } from '../firm/firm.service';
import { Scope } from '../auth/scope';
import { computeDocument } from './invoice-math';
import { SaveInvoiceDto } from './invoice.dto';

type InvoiceRow = Selectable<InvoicesTable> & {
  converted_type: InvoiceType | null;
  linked: string;
  linked_fx: string;
  payment_modes: string | null;
};

/** "A1, A2 ,A2\nA3" → ['A1', 'A2', 'A3'] */
export const parseSerials = (text: string | null | undefined): string[] => [
  ...new Set((text ?? '').split(/[,\n]/).map((s) => s.trim()).filter(Boolean)),
];

const MODE_LABEL: Record<string, string> = { cash: 'Cash', bank: 'Bank', upi: 'UPI', cheque: 'Cheque', card: 'Card' };

const summary = (i: InvoiceRow) => {
  const linked = Number(i.linked);
  return {
    id: i.id,
    type: i.type,
    number: i.number,
    invoiceDate: i.invoice_date,
    dueDate: i.due_date,
    isCash: i.is_cash,
    partyId: i.party_id,
    partyName: i.party_name,
    total: num(i.total),
    /** Paid at billing time (possibly in several parts). */
    received: num(i.received),
    /** Paid later through Payment-In/Out entries linked to this invoice. */
    linkedAmount: linked,
    /** Still unpaid: total − received − linked payments − TDS held back − loyalty points redeemed. */
    balance: r2(Number(i.total) - Number(i.received) - linked - Number(i.tds_amount) - Number(i.loyalty_amount)),
    tdsAmount: num(i.tds_amount),
    tcsAmount: num(i.tcs_amount),
    loyaltyAmount: num(i.loyalty_amount),
    godownId: i.godown_id,
    einvoiceStatus: i.einvoice_status,
    irn: i.irn,
    ewayBillNo: i.eway_bill_no,
    // Foreign-currency documents: the same figures in that currency.
    currencyCode: i.currency_code,
    fxTotal: num(i.fx_total),
    fxBalance: i.fx_total === null ? null : r2(Number(i.fx_total) - Number(i.fx_received ?? 0) - Number(i.linked_fx)),
    paymentMode: i.payment_mode,
    /** e.g. "Cash + UPI" when the bill was paid in parts. */
    paymentLabel: i.payment_modes ?? MODE_LABEL[i.payment_mode],
    // Quotation-like documents: open until another document is created from them.
    status: isQuote(i.type) ? (i.converted_invoice_id ? 'converted' : 'open') : null,
    convertedInvoiceId: i.converted_invoice_id,
    convertedType: i.converted_type ?? null,
    createdBy: i.created_by,
  };
};

type Part = { mode: PaymentMode; bankAccountId: string | null; amount: number };

@Injectable()
export class InvoicesService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly firms: FirmService,
  ) {}

  private base(firmId: string) {
    return this.db
      .selectFrom('invoices')
      .selectAll()
      // For converted estimates/orders: what they were converted into.
      .select((eb) => eb.selectFrom('invoices as c').select('c.type').whereRef('c.id', '=', 'invoices.converted_invoice_id').as('converted_type'))
      .select(sql<string>`coalesce((select sum(a.amount) from payment_allocations a where a.invoice_id = invoices.id), 0)`.as('linked'))
      .select(sql<string>`coalesce((select sum(a.fx_amount) from payment_allocations a where a.invoice_id = invoices.id), 0)`.as('linked_fx'))
      .select(
        sql<string | null>`(select string_agg(case m.payment_mode when 'upi' then 'UPI' else initcap(m.payment_mode) end, ' + ' order by m.first) from (
          select ip.payment_mode, min(ip.sort_order) as first from invoice_payments ip where ip.invoice_id = invoices.id group by ip.payment_mode) m)`.as(
          'payment_modes',
        ),
      )
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null);
  }

  /** Limits a query to a salesman's own documents: the ones they entered and those of their parties. */
  private scoped<T extends ReturnType<InvoicesService['base']>>(q: T, scope: Scope): T {
    if (!scope.ownerUserId) return q;
    return q.where((eb) =>
      eb.or([
        eb('created_by', '=', scope.ownerUserId!),
        eb('party_id', 'in', eb.selectFrom('parties').select('parties.id').where('parties.assigned_user_id', '=', scope.ownerUserId!)),
      ]),
    ) as T;
  }

  async list(firmId: string, type: InvoiceType, opts: { from?: string; to?: string; partyId?: string; unpaidOnly?: boolean } = {}, scope: Scope = {}) {
    let q = this.scoped(this.base(firmId), scope).where('type', '=', type);
    if (opts.from) q = q.where('invoice_date', '>=', opts.from);
    if (opts.to) q = q.where('invoice_date', '<=', opts.to);
    if (opts.partyId) q = q.where('party_id', '=', opts.partyId);
    const rows = (await q.orderBy('invoice_date', 'desc').orderBy('created_at', 'desc').execute()).map(summary);
    return opts.unpaidOnly ? rows.filter((r) => (r.balance ?? 0) > 0) : rows;
  }

  /**
   * Next number = highest number in the series + 1, under the business's prefix for that kind of
   * document (e.g. "INV-12"); numbers that don't follow the series' pattern are skipped.
   */
  async nextNumber(firmId: string, type: InvoiceType) {
    // Prefixes are validated to letters, digits, "-" and "/", none of which are special in a regex.
    // The ::int cast matters: an untyped parameter would make Postgres pick substring(text FROM pattern).
    const settings = await this.firms.settings(firmId);
    const prefix = settings.prefixes[type] ?? (type === 'sale' ? settings.invoicePrefix : '');
    const row = await this.db
      .selectFrom('invoices')
      .select(sql<string>`coalesce(max(substring(number from ${prefix.length + 1}::int)::bigint), 0) + 1`.as('next'))
      .where('firm_id', '=', firmId)
      .where('type', '=', type)
      .where('deleted_at', 'is', null)
      .where(sql<boolean>`number ~ ${`^${prefix}[0-9]{1,15}$`}`)
      .executeTakeFirstOrThrow();
    return { number: `${prefix}${row.next}` };
  }

  async get(firmId: string, id: string, scope: Scope = {}) {
    const inv = await this.find(firmId, id, scope);
    const lines = await this.db.selectFrom('invoice_items').selectAll().where('invoice_id', '=', id).orderBy('sort_order').execute();
    const itemIds = lines.map((l) => l.item_id).filter((x): x is string => !!x);
    const images = new Map(
      itemIds.length ? (await this.db.selectFrom('items').select(['id', 'image_file_id']).where('id', 'in', itemIds).execute()).map((i) => [i.id, i.image_file_id] as const) : [],
    );
    const parts = await this.db.selectFrom('invoice_payments').selectAll().where('invoice_id', '=', id).orderBy('sort_order').execute();
    const linked = await this.db
      .selectFrom('payment_allocations as a')
      .innerJoin('payments as p', 'p.id', 'a.payment_id')
      .select(['p.id', 'p.number', 'p.payment_date', 'a.amount', 'a.fx_amount'])
      .where('a.invoice_id', '=', id)
      .where('p.deleted_at', 'is', null)
      .orderBy('p.payment_date')
      .execute();
    return {
      ...summary(inv),
      phone: inv.phone,
      ackNo: inv.ack_no,
      signedQr: inv.signed_qr,
      ewayValidUpto: inv.eway_valid_upto,
      billingAddress: inv.billing_address,
      shippingAddress: inv.shipping_address,
      stateOfSupply: inv.state_of_supply,
      pricesIncludeTax: inv.prices_include_tax,
      interState: inv.is_inter_state,
      partyGstin: inv.party_gstin,
      exchangeRate: num(inv.exchange_rate),
      fxReceived: num(inv.fx_received),
      discountPct: num(inv.discount_pct),
      discountAmount: num(inv.discount_amount),
      charges: inv.charges,
      chargesTotal: num(inv.charges_total),
      cess: num(inv.cess),
      tcsRate: num(inv.tcs_rate),
      tdsRate: num(inv.tds_rate),
      loyaltyEarned: inv.loyalty_earned,
      loyaltyRedeemed: inv.loyalty_redeemed,
      taxableAmount: num(inv.taxable_amount),
      cgst: num(inv.cgst),
      sgst: num(inv.sgst),
      igst: num(inv.igst),
      subtotal: num(inv.subtotal),
      roundOff: num(inv.round_off),
      description: inv.description,
      payments: parts.map((p) => ({ mode: p.payment_mode, bankAccountId: p.bank_account_id, amount: num(p.amount), fxAmount: num(p.fx_amount) })),
      linkedPayments: linked.map((l) => ({ paymentId: l.id, number: l.number, date: l.payment_date, amount: num(l.amount), fxAmount: num(l.fx_amount) })),
      lines: lines.map((l) => ({
        id: l.id,
        itemId: l.item_id,
        imageFileId: l.item_id ? (images.get(l.item_id) ?? null) : null,
        name: l.name,
        quantity: num(l.quantity),
        unit: l.unit,
        price: num(l.price),
        discountPct: num(l.discount_pct),
        discountAmount: num(l.discount_amount),
        hsnCode: l.hsn_code,
        gstRate: num(l.gst_rate),
        taxableValue: num(l.taxable_value),
        cgst: num(l.cgst),
        sgst: num(l.sgst),
        igst: num(l.igst),
        amount: num(l.amount),
        billDiscount: num(l.bill_discount),
        cessRate: num(l.cess_rate),
        cess: num(l.cess),
        batchNo: l.batch_no,
        mfgDate: l.mfg_date,
        expiryDate: l.expiry_date,
        mrp: num(l.mrp),
        serialNos: l.serial_nos,
        fxPrice: num(l.fx_price),
        fxAmount: num(l.fx_amount),
      })),
    };
  }

  async create(firmId: string, dto: SaveInvoiceDto, userId?: string) {
    await assertBooksOpen(this.db, firmId, dto.invoiceDate);
    const id = await this.db.transaction().execute(async (trx) => {
      const values = await this.prepare(trx, firmId, dto);
      const inv = await trx
        .insertInto('invoices')
        .values({ firm_id: firmId, type: dto.type, created_by: userId ?? null, ...values.header })
        .returning('id')
        .executeTakeFirstOrThrow();
      await this.writeLines(trx, firmId, inv.id, dto, values);
      await this.enforceCreditLimit(trx, firmId, dto, Number(values.header.total), Number(values.header.received));
      if (dto.fromDocumentId) await this.markConverted(trx, firmId, dto, inv.id);
      return inv.id;
    });
    return this.get(firmId, id);
  }

  async update(firmId: string, id: string, dto: SaveInvoiceDto, scope: Scope = {}) {
    const existing = await this.find(firmId, id, scope);
    this.assertNoIrn(existing);
    if (existing.type !== dto.type) throw new BadRequestException({ code: 'TYPE_MISMATCH', message: 'Invoice type cannot be changed.' });
    await assertBooksOpen(this.db, firmId, existing.invoice_date, dto.invoiceDate);
    await this.db.transaction().execute(async (trx) => {
      await this.reverseStock(trx, id);
      await trx.deleteFrom('invoice_items').where('invoice_id', '=', id).execute();
      await trx.deleteFrom('invoice_payments').where('invoice_id', '=', id).execute();
      const values = await this.prepare(trx, firmId, dto, id, Number(existing.linked));
      await trx.updateTable('invoices').set({ ...values.header, updated_at: new Date() }).where('id', '=', id).execute();
      await this.writeLines(trx, firmId, id, dto, values);
      await this.enforceCreditLimit(trx, firmId, dto, Number(values.header.total), Number(values.header.received));
    });
    return this.get(firmId, id);
  }

  async remove(firmId: string, id: string, scope: Scope = {}) {
    const existing = await this.find(firmId, id, scope);
    this.assertNoIrn(existing);
    await assertBooksOpen(this.db, firmId, existing.invoice_date);
    await this.db.transaction().execute(async (trx) => {
      await this.reverseStock(trx, id);
      // Payments that were linked to this invoice become unlinked (they still count for the party).
      await trx.deleteFrom('payment_allocations').where('invoice_id', '=', id).execute();
      await trx.updateTable('invoices').set({ deleted_at: new Date() }).where('id', '=', id).execute();
      // Deleting a document re-opens the estimate/order it was created from.
      await trx.updateTable('invoices').set({ converted_invoice_id: null }).where('converted_invoice_id', '=', id).execute();
    });
  }

  /** Links an open quotation-like document to the document just created from it. */
  private async markConverted(trx: Transaction<Database>, firmId: string, dto: SaveInvoiceDto, newId: string) {
    // Only types that are allowed to become dto.type (e.g. estimate → sale / sale order, purchase order → purchase).
    const sources = (Object.keys(INVOICE_TYPES) as InvoiceType[]).filter((t) =>
      (INVOICE_TYPES[t].convertsTo as readonly string[]).includes(dto.type),
    );
    if (!sources.length) {
      throw new BadRequestException({ code: 'NOT_CONVERTIBLE', message: `A ${INVOICE_TYPES[dto.type].label} cannot be created from another document.` });
    }
    const res = await trx
      .updateTable('invoices')
      .set({ converted_invoice_id: newId, updated_at: new Date() })
      .where('id', '=', dto.fromDocumentId!)
      .where('firm_id', '=', firmId)
      .where('type', 'in', sources)
      .where('deleted_at', 'is', null)
      .where('converted_invoice_id', 'is', null)
      .executeTakeFirst();
    if (!res.numUpdatedRows) {
      throw new ConflictException({ code: 'DOCUMENT_NOT_OPEN', message: 'This document was already converted or no longer exists.' });
    }
  }

  /** Validates references and computes every amount server-side. [linked] = payments already linked to it (edits). */
  private async prepare(trx: Transaction<Database>, firmId: string, dto: SaveInvoiceDto, exceptId?: string, linked = 0) {
    const isSale = dto.type === 'sale';
    const config = INVOICE_TYPES[dto.type];
    const quote = isQuote(dto.type);
    // Numbers we issue must be unique per type; a purchase carries the supplier's bill number (optional, may repeat).
    if (config.ownNumber) {
      if (!dto.number) throw new BadRequestException({ code: 'NUMBER_REQUIRED', message: 'Enter the number.' });
      const dup = await trx
        .selectFrom('invoices')
        .select('id')
        .where('firm_id', '=', firmId)
        .where('type', '=', dto.type)
        .where('number', '=', dto.number)
        .where('deleted_at', 'is', null)
        .$if(!!exceptId, (q) => q.where('id', '!=', exceptId!))
        .executeTakeFirst();
      if (dup) throw new ConflictException({ code: 'NUMBER_TAKEN', message: `${isSale ? 'Invoice' : config.label} number ${dto.number} is already used.` });
    }
    // Everything except a sale is always against a party; only sales can be walk-in cash.
    const isCash = isSale && dto.isCash;

    let partyName = dto.partyName?.trim() || null;
    let partyGstin: string | null = null;
    if (dto.partyId) {
      const party = await trx
        .selectFrom('parties')
        .select(['name', 'gstin'])
        .where('id', '=', dto.partyId)
        .where('firm_id', '=', firmId)
        .where('deleted_at', 'is', null)
        .executeTakeFirst();
      if (!party) throw new BadRequestException({ code: 'PARTY_NOT_FOUND', message: 'Selected party no longer exists.' });
      partyName = party.name;
      partyGstin = party.gstin;
    } else if (!isCash) {
      throw new BadRequestException({
        code: 'PARTY_REQUIRED',
        message: isSale ? 'Select a party for a credit invoice.' : `Select a party for the ${config.label.toLowerCase()}.`,
      });
    }

    const itemIds = [...new Set(dto.lines.map((l) => l.itemId).filter((v): v is string => !!v))];
    const items = itemIds.length
      ? await trx.selectFrom('items').select(['id', 'type']).where('firm_id', '=', firmId).where('id', 'in', itemIds).where('deleted_at', 'is', null).execute()
      : [];
    if (items.length !== itemIds.length) throw new BadRequestException({ code: 'ITEM_NOT_FOUND', message: 'One of the items no longer exists.' });
    const productIds = new Set(items.filter((i) => i.type === 'product').map((i) => i.id));

    // Supplying to (or buying from) another state than ours means IGST instead of CGST + SGST.
    const firm = await trx.selectFrom('firms').select('state_code').where('id', '=', firmId).executeTakeFirstOrThrow();
    const interState = !!firm.state_code && !!dto.stateOfSupply && firm.state_code !== dto.stateOfSupply;
    const pricesIncludeTax = dto.pricesIncludeTax ?? false;
    const settings = await this.firms.settings(firmId);

    // A foreign-currency document arrives in that currency and is booked at its exchange rate.
    const rate = dto.currencyCode ? (dto.exchangeRate ?? 0) : 0;
    if (dto.currencyCode && rate <= 0) throw new BadRequestException({ code: 'RATE_REQUIRED', message: `Enter the exchange rate for ${dto.currencyCode}.` });
    const foreign = rate > 0;
    const toBase = (v: number) => (foreign ? r2(v * rate) : v);
    const posting = !quote;
    const options = {
      pricesIncludeTax,
      interState,
      roundOff: dto.roundOff,
      billDiscountPct: dto.discountPct ?? null,
      tcsRate: posting && (dto.type === 'sale' || dto.type === 'purchase') ? (dto.tcsRate ?? 0) : 0,
      tdsRate: posting && (dto.type === 'sale' || dto.type === 'purchase') ? (dto.tdsRate ?? 0) : 0,
    };
    const charges = (dto.charges ?? []).filter((c) => c.amount > 0);
    const doc = computeDocument(
      dto.lines.map((l) => ({ ...l, price: toBase(l.price), discountAmount: l.discountAmount == null ? l.discountAmount : toBase(l.discountAmount) })),
      { ...options, billDiscountAmount: dto.discountAmount == null ? null : toBase(dto.discountAmount), charges: charges.reduce((s, c) => s + toBase(c.amount), 0) },
    );
    // The same document worked out in its own currency, for printing and for the party's foreign balance.
    const fxDoc = foreign
      ? computeDocument(dto.lines, { ...options, billDiscountAmount: dto.discountAmount ?? null, charges: charges.reduce((s, c) => s + c.amount, 0) })
      : null;

    // ---- godown
    if (dto.godownId) {
      const godown = await trx.selectFrom('godowns').select('id').where('id', '=', dto.godownId).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
      if (!godown) throw new BadRequestException({ code: 'GODOWN_NOT_FOUND', message: 'Selected godown no longer exists.' });
    }

    // ---- serial numbers: one per unit, and a unit cannot be sold twice or bought twice
    if (posting) await this.checkSerials(trx, firmId, dto, exceptId);

    // ---- loyalty points: earned on sales to a party, redeemed against the bill
    let loyaltyEarned = 0;
    let loyaltyRedeemed = 0;
    let loyaltyAmount = 0;
    if (isSale && dto.partyId && settings.loyaltyEnabled && !foreign) {
      loyaltyRedeemed = dto.loyaltyRedeem ?? 0;
      if (loyaltyRedeemed > 0) {
        const available = await this.loyaltyPoints(trx, dto.partyId, exceptId);
        if (loyaltyRedeemed > available) {
          throw new BadRequestException({ code: 'NOT_ENOUGH_POINTS', message: `The customer has only ${available} loyalty points.` });
        }
        loyaltyAmount = r2(loyaltyRedeemed * settings.loyaltyPointValue);
      }
      // Points are earned on what is actually paid for, not on the part covered by points.
      loyaltyEarned = Math.max(0, Math.floor((doc.total - loyaltyAmount) / settings.loyaltyEarnPer));
    }

    // ---- what was paid with the document
    const deductions = r2(doc.tdsAmount + loyaltyAmount);
    if (deductions > doc.total) throw new BadRequestException({ code: 'OVERPAID', message: 'TDS and points redeemed are more than the total.' });
    const due = r2(doc.total - deductions);
    const baseDto = foreign
      ? { ...dto, received: dto.received == null ? dto.received : toBase(dto.received), payments: dto.payments?.map((p) => ({ ...p, amount: toBase(p.amount) })) }
      : dto;
    let parts = quote ? [] : await this.paymentParts(trx, firmId, baseDto, isCash, due);
    let fxParts: number[] | null = null;
    if (fxDoc && parts.length) {
      // Their amounts in the document's currency. A bill paid in full in that currency is paid in full
      // in the books too, whatever the paise the conversion leaves over.
      const given = dto.payments?.length ? dto.payments.filter((p) => p.amount > 0).map((p) => p.amount) : [dto.received ?? 0];
      fxParts = isCash && parts.length === 1 ? [fxDoc.total] : given;
      if (r2(fxParts.reduce((s, v) => s + v, 0)) === fxDoc.total) {
        const drift = r2(due - parts.reduce((s, p) => s + p.amount, 0));
        parts = parts.map((p, i) => (i === parts.length - 1 ? { ...p, amount: r2(p.amount + drift) } : p));
      }
    }
    const received = r2(parts.reduce((s, p) => s + p.amount, 0));
    if (r2(received + linked + deductions) > doc.total) {
      throw new BadRequestException({
        code: 'OVERPAID',
        message: linked > 0
          ? `Payments of ${linked} are already linked to this invoice; with ${received} received it would exceed the total of ${doc.total}.`
          : 'Amount received is more than the total.',
      });
    }

    return {
      computed: doc.lines,
      fxLines: fxDoc?.lines ?? null,
      productIds,
      parts,
      fxParts,
      header: {
        number: dto.number,
        invoice_date: dto.invoiceDate ?? today(),
        due_date: quote ? null : (dto.dueDate ?? null),
        is_cash: isCash,
        party_id: dto.partyId ?? null,
        party_name: partyName ?? 'Cash Sale',
        phone: dto.phone ?? null,
        billing_address: dto.billingAddress ?? null,
        shipping_address: dto.shippingAddress ?? null,
        state_of_supply: dto.stateOfSupply ?? null,
        currency_code: dto.currencyCode ?? null,
        exchange_rate: foreign ? rate : null,
        fx_total: fxDoc?.total ?? null,
        fx_received: fxDoc ? r2((fxParts ?? []).reduce((s, v) => s + v, 0)) : null,
        godown_id: dto.godownId ?? null,
        prices_include_tax: pricesIncludeTax,
        is_inter_state: interState,
        party_gstin: partyGstin,
        taxable_amount: doc.taxableAmount,
        cgst: doc.cgst,
        sgst: doc.sgst,
        igst: doc.igst,
        cess: doc.cess,
        discount_pct: doc.discountPct,
        discount_amount: doc.discountAmount,
        charges: JSON.stringify(charges.map((c) => ({ name: c.name, amount: toBase(c.amount) }))),
        charges_total: doc.chargesTotal,
        tcs_rate: options.tcsRate,
        tcs_amount: doc.tcsAmount,
        tds_rate: options.tdsRate,
        tds_amount: doc.tdsAmount,
        loyalty_earned: loyaltyEarned,
        loyalty_redeemed: loyaltyRedeemed,
        loyalty_amount: loyaltyAmount,
        subtotal: doc.subtotal,
        round_off: doc.roundOff,
        total: doc.total,
        received,
        // The first part's mode, for lists; the full split lives in invoice_payments.
        payment_mode: parts[0]?.mode ?? dto.paymentMode ?? ('cash' as PaymentMode),
        description: dto.description ?? null,
      },
    };
  }

  /** A party's loyalty points: opening points + earned − redeemed on their sales (not counting [exceptInvoiceId]). */
  async loyaltyPoints(db: Transaction<Database> | Db, partyId: string, exceptInvoiceId?: string): Promise<number> {
    const row = await db
      .selectFrom('parties as p')
      .select(
        sql<string>`p.loyalty_opening + coalesce((select sum(i.loyalty_earned - i.loyalty_redeemed) from invoices i
                      where i.party_id = p.id and i.type = 'sale' and i.deleted_at is null
                        and i.id <> ${exceptInvoiceId ?? '00000000-0000-0000-0000-000000000000'}::uuid), 0)`.as('points'),
      )
      .where('p.id', '=', partyId)
      .executeTakeFirst();
    return Number(row?.points ?? 0);
  }

  /**
   * Serial numbers must be one per unit. A unit going out (sale, purchase return) must not already
   * be out; a unit coming in (purchase, sale return) must not already be in stock.
   */
  private async checkSerials(trx: Transaction<Database>, firmId: string, dto: SaveInvoiceDto, exceptId?: string) {
    const out = INVOICE_TYPES[dto.type].stock < 0;
    const seen = new Set<string>();
    for (const [i, l] of dto.lines.entries()) {
      const serials = parseSerials(l.serialNos);
      if (!serials.length) continue;
      if (!l.itemId) throw new BadRequestException({ code: 'SERIAL_NEEDS_ITEM', message: `Row ${i + 1}: serial numbers need a saved item.` });
      if (serials.length !== l.quantity) {
        throw new BadRequestException({
          code: 'SERIAL_COUNT',
          message: `Row ${i + 1}: enter one serial number per unit (quantity ${l.quantity}, serial numbers ${serials.length}).`,
        });
      }
      const earlier = await trx
        .selectFrom('invoice_items as ii')
        .innerJoin('invoices as inv', 'inv.id', 'ii.invoice_id')
        .select(['ii.serial_nos', 'inv.type'])
        .where('inv.firm_id', '=', firmId)
        .where('inv.deleted_at', 'is', null)
        .where('inv.type', 'in', ['sale', 'purchase', 'credit_note', 'debit_note'])
        .where('ii.item_id', '=', l.itemId)
        .where('ii.serial_nos', 'is not', null)
        .$if(!!exceptId, (q) => q.where('inv.id', '!=', exceptId!))
        .execute();
      for (const serial of serials) {
        const key = `${l.itemId}:${serial}`;
        if (seen.has(key)) throw new BadRequestException({ code: 'SERIAL_REPEATED', message: `Serial number ${serial} is entered twice.` });
        seen.add(key);
        let wentIn = 0;
        let wentOut = 0;
        for (const e of earlier) {
          if (!parseSerials(e.serial_nos).includes(serial)) continue;
          if (INVOICE_TYPES[e.type].stock > 0) wentIn++;
          else wentOut++;
        }
        if (out && wentOut > wentIn) throw new BadRequestException({ code: 'SERIAL_SOLD', message: `Serial number ${serial} of ${l.name} has already been sold.` });
        if (out && wentOut === wentIn && wentOut > 0) throw new BadRequestException({ code: 'SERIAL_SOLD', message: `Serial number ${serial} of ${l.name} has already been sold.` });
        if (!out && wentIn > wentOut) throw new BadRequestException({ code: 'SERIAL_IN_STOCK', message: `Serial number ${serial} of ${l.name} is already in stock.` });
      }
    }
  }

  /**
   * What was paid at billing time, as one or more parts (e.g. part cash, part UPI).
   * Older clients send a single received / paymentMode / bankAccountId instead of `payments`.
   */
  private async paymentParts(trx: Transaction<Database>, firmId: string, dto: SaveInvoiceDto, isCash: boolean, total: number): Promise<Part[]> {
    const raw = dto.payments?.length
      ? dto.payments.map((p) => ({ mode: p.mode, bankAccountId: p.bankAccountId ?? null, amount: p.amount }))
      : [{ mode: dto.paymentMode ?? ('cash' as PaymentMode), bankAccountId: dto.bankAccountId ?? null, amount: dto.received ?? 0 }];
    let parts = raw.filter((p) => p.amount > 0 || (isCash && raw.length === 1));
    if (isCash) {
      // A cash sale is fully paid: a single part is simply the whole total; several must add up to it.
      if (parts.length <= 1) {
        parts = [{ ...(parts[0] ?? raw[0]), amount: total }];
      } else if (r2(parts.reduce((s, p) => s + p.amount, 0)) !== total) {
        throw new BadRequestException({ code: 'SPLIT_MISMATCH', message: `For a cash sale the payments must add up to the total of ${total}.` });
      }
    }
    const resolved: Part[] = [];
    for (const p of parts.filter((x) => x.amount > 0)) {
      resolved.push({ mode: p.mode, amount: r2(p.amount), bankAccountId: await resolveBankAccount(trx, firmId, p.mode, p.bankAccountId) });
    }
    return resolved;
  }

  private async writeLines(
    trx: Transaction<Database>,
    firmId: string,
    invoiceId: string,
    dto: SaveInvoiceDto,
    values: Awaited<ReturnType<InvoicesService['prepare']>>,
  ) {
    await trx
      .insertInto('invoice_items')
      .values(
        dto.lines.map((l, i) => ({
          invoice_id: invoiceId,
          item_id: l.itemId ?? null,
          name: l.name,
          quantity: l.quantity,
          unit: l.unit ?? null,
          price: values.fxLines ? r2(l.price * Number(values.header.exchange_rate)) : l.price,
          discount_pct: values.computed[i].discountPct,
          discount_amount: values.computed[i].discountAmount,
          hsn_code: l.hsnCode ?? null,
          gst_rate: values.computed[i].gstRate,
          taxable_value: values.computed[i].taxableValue,
          cgst: values.computed[i].cgst,
          sgst: values.computed[i].sgst,
          igst: values.computed[i].igst,
          amount: values.computed[i].amount,
          bill_discount: values.computed[i].billDiscount,
          cess_rate: values.computed[i].cessRate,
          cess: values.computed[i].cess,
          batch_no: l.batchNo ?? null,
          mfg_date: l.mfgDate ?? null,
          expiry_date: l.expiryDate ?? null,
          mrp: l.mrp ?? null,
          serial_nos: parseSerials(l.serialNos).join(', ') || null,
          // Foreign-currency documents keep the typed price and the line amount in that currency.
          fx_price: values.fxLines ? l.price : null,
          fx_amount: values.fxLines ? values.fxLines[i].amount : null,
          sort_order: i,
        })),
      )
      .execute();

    if (values.parts.length) {
      await trx
        .insertInto('invoice_payments')
        .values(
          values.parts.map((p, i) => ({
            firm_id: firmId, invoice_id: invoiceId, payment_mode: p.mode, bank_account_id: p.bankAccountId, amount: p.amount,
            fx_amount: values.fxParts?.[i] ?? null, sort_order: i,
          })),
        )
        .execute();
    }

    // Sales and purchase returns take stock out; purchases and sale returns bring it in. Services,
    // free-text lines and quotation-like documents don't touch stock.
    const sign = INVOICE_TYPES[dto.type].stock;
    if (sign === 0 || isQuote(dto.type)) return;
    const movementType = dto.type as 'sale' | 'purchase' | 'credit_note' | 'debit_note';
    const { blockNegativeStock } = await this.firms.settings(firmId);
    const rate = values.fxLines ? Number(values.header.exchange_rate) : 1;
    for (const l of dto.lines) {
      if (!l.itemId || !values.productIds.has(l.itemId)) continue;
      const change = sign * l.quantity;
      await trx
        .insertInto('stock_movements')
        .values({
          firm_id: firmId, item_id: l.itemId, invoice_id: invoiceId, type: movementType, qty_change: change,
          price_per_unit: r2(l.price * rate), movement_date: dto.invoiceDate,
          godown_id: dto.godownId ?? null, batch_no: l.batchNo ?? null, expiry_date: l.expiryDate ?? null,
        })
        .execute();
      const item = await trx
        .updateTable('items')
        .set({ stock_qty: sql`stock_qty + ${change}` })
        .where('id', '=', l.itemId)
        .returning(['name', 'stock_qty'])
        .executeTakeFirstOrThrow();
      if (change < 0 && Number(item.stock_qty) < 0 && blockNegativeStock) {
        // Thrown inside the transaction, so nothing of this document is saved.
        throw new BadRequestException({
          code: 'INSUFFICIENT_STOCK',
          message: `Not enough stock of ${item.name}: short by ${-Number(item.stock_qty)}.`,
        });
      }
    }
  }

  private async reverseStock(trx: Transaction<Database>, invoiceId: string) {
    const moves = await trx.deleteFrom('stock_movements').where('invoice_id', '=', invoiceId).returning(['item_id', 'qty_change']).execute();
    for (const m of moves) {
      await trx.updateTable('items').set({ stock_qty: sql`stock_qty - ${m.qty_change}` }).where('id', '=', m.item_id).execute();
    }
  }

  /**
   * When the company refuses credit sales beyond the credit limit: called after the document is written, so the
   * party's balance already includes it. Orders and challans do not touch the balance, so their value is added.
   */
  private async enforceCreditLimit(trx: Transaction<Database>, firmId: string, dto: SaveInvoiceDto, total: number, received: number) {
    if (!dto.partyId || !['sale', 'sale_order', 'delivery_challan'].includes(dto.type)) return;
    // A sale paid in full adds nothing to what the customer owes, so it is never refused.
    if (dto.type === 'sale' && received >= total) return;
    if ((await this.firms.settings(firmId)).creditLimitMode !== 'block') return;
    const party = await trx
      .selectFrom('parties').select(['name', 'credit_limit'])
      .select(partyBalanceSql(sql.ref('parties.id'), sql.ref('parties.opening_balance')).as('balance'))
      .where('id', '=', dto.partyId).where('firm_id', '=', firmId).executeTakeFirst();
    if (!party || party.credit_limit === null) return;
    const after = r2(Number(party.balance) + (dto.type === 'sale' ? 0 : total));
    if (after > Number(party.credit_limit)) {
      throw new BadRequestException({
        code: 'CREDIT_LIMIT',
        message: `${party.name} would owe ${after}, over their credit limit of ${Number(party.credit_limit)}. Take a payment first or raise the limit.`,
      });
    }
  }

  /** An invoice registered with the e-invoice portal can no longer be changed; cancel its IRN first. */
  private assertNoIrn(inv: InvoiceRow) {
    if (inv.einvoice_status === 'generated') {
      throw new BadRequestException({ code: 'HAS_IRN', message: 'This invoice has an e-invoice (IRN) and can no longer be changed. Cancel the IRN first.' });
    }
  }

  private async find(firmId: string, id: string, scope: Scope = {}): Promise<InvoiceRow> {
    const inv = await this.scoped(this.base(firmId), scope).where('id', '=', id).executeTakeFirst();
    if (!inv) throw new NotFoundException({ code: 'INVOICE_NOT_FOUND', message: 'Invoice not found.' });
    return inv as InvoiceRow;
  }
}
