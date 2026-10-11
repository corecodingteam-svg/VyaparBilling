import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { sql, Transaction } from 'kysely';
import { resolveBankAccount } from '../common/bank-account';
import { assertBooksOpen } from '../common/books-lock';
import { num } from '../common/numbers';
import { r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { Scope } from '../auth/scope';
import { Database, PaymentMode } from '../database/schema';
import { FirmService } from '../firm/firm.service';
import { AllocationDto, SavePaymentDto } from './payment.dto';

type PaymentType = 'in' | 'out';
type Part = { mode: PaymentMode; bankAccountId: string | null; amount: number };

/** A Payment-In settles sale invoices; a Payment-Out settles purchase bills. */
const SETTLES = { in: 'sale', out: 'purchase' } as const;

@Injectable()
export class PaymentsService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly firms: FirmService,
  ) {}

  private base(firmId: string) {
    return this.db
      .selectFrom('payments')
      .innerJoin('parties', 'parties.id', 'payments.party_id')
      .selectAll('payments')
      .select('parties.name as party_name')
      .select(sql<string>`coalesce((select sum(a.amount) from payment_allocations a where a.payment_id = payments.id), 0)`.as('linked'))
      .select(sql<string>`coalesce((select sum(a.fx_amount) from payment_allocations a where a.payment_id = payments.id), 0)`.as('linked_fx'))
      .select(
        sql<string | null>`(select string_agg(case m.payment_mode when 'upi' then 'UPI' else initcap(m.payment_mode) end, ' + ' order by m.first) from (
          select pp.payment_mode, min(pp.sort_order) as first from payment_parts pp where pp.payment_id = payments.id group by pp.payment_mode) m)`.as(
          'payment_modes',
        ),
      )
      .where('payments.firm_id', '=', firmId)
      .where('payments.deleted_at', 'is', null);
  }

  /** A salesman limited to their own data sees the payments they entered and those of their parties. */
  private scoped<T extends ReturnType<PaymentsService['base']>>(q: T, scope: Scope): T {
    if (!scope.ownerUserId) return q;
    return q.where((eb) => eb.or([eb('payments.created_by', '=', scope.ownerUserId!), eb('parties.assigned_user_id', '=', scope.ownerUserId!)])) as T;
  }

  private toApi(p: Awaited<ReturnType<ReturnType<PaymentsService['base']>['executeTakeFirstOrThrow']>>) {
    // In the payment's own currency when it has one.
    const foreign = p.currency_code !== null;
    const amount = foreign ? Number(p.fx_amount) : Number(p.amount);
    const linked = foreign ? Number(p.linked_fx) : Number(p.linked);
    return {
      id: p.id,
      type: p.type,
      number: p.number,
      partyId: p.party_id,
      partyName: p.party_name,
      paymentDate: p.payment_date,
      amount,
      /** Set against specific invoices. */
      linkedAmount: linked,
      /** Not linked to any invoice (still reduces the party's overall balance). */
      unlinkedAmount: r2(amount - linked),
      currencyCode: p.currency_code,
      exchangeRate: num(p.exchange_rate),
      /** What the payment came to in the base currency. */
      baseAmount: num(p.amount),
      /** Exchange gain (+) or loss (−) against the rates its invoices were booked at. */
      fxGain: num(p.fx_gain),
      paymentMode: p.payment_mode,
      /** e.g. "Cash + UPI" when paid in parts. */
      paymentLabel: p.payment_modes ?? p.payment_mode,
      bankAccountId: p.bank_account_id,
      description: p.description,
    };
  }

  async list(firmId: string, type: PaymentType, from?: string, to?: string, scope: Scope = {}) {
    let q = this.scoped(this.base(firmId), scope).where('payments.type', '=', type);
    if (from) q = q.where('payments.payment_date', '>=', from);
    if (to) q = q.where('payments.payment_date', '<=', to);
    const rows = await q.orderBy('payments.payment_date', 'desc').orderBy('payments.created_at', 'desc').execute();
    return rows.map((r) => this.toApi(r));
  }

  async nextNumber(firmId: string, type: PaymentType) {
    // See InvoicesService.nextNumber for why the prefix is regex-safe and the ::int cast is needed.
    const prefix = (await this.firms.settings(firmId)).prefixes[`payment_${type}`] ?? '';
    const row = await this.db
      .selectFrom('payments')
      .select(sql<string>`coalesce(max(substring(number from ${prefix.length + 1}::int)::bigint), 0) + 1`.as('next'))
      .where('firm_id', '=', firmId)
      .where('type', '=', type)
      .where('deleted_at', 'is', null)
      .where(sql<boolean>`number ~ ${`^${prefix}[0-9]{1,15}$`}`)
      .executeTakeFirstOrThrow();
    return { number: `${prefix}${row.next}` };
  }

  async get(firmId: string, id: string, scope: Scope = {}) {
    const p = await this.scoped(this.base(firmId), scope).where('payments.id', '=', id).executeTakeFirst();
    if (!p) throw new NotFoundException({ code: 'PAYMENT_NOT_FOUND', message: 'Payment not found.' });
    const allocations = await this.db
      .selectFrom('payment_allocations as a')
      .innerJoin('invoices as i', 'i.id', 'a.invoice_id')
      .select(['a.invoice_id', 'a.amount', 'a.fx_amount', 'i.number', 'i.invoice_date', 'i.total', 'i.fx_total'])
      .where('a.payment_id', '=', id)
      .orderBy('i.invoice_date')
      .execute();
    const parts = await this.db.selectFrom('payment_parts').selectAll().where('payment_id', '=', id).orderBy('sort_order').execute();
    const foreign = p.currency_code !== null;
    const rate = Number(p.exchange_rate ?? 1);
    return {
      ...this.toApi(p),
      // Parts are kept in the base currency; a foreign payment shows them in its own.
      parts: parts.map((x) => ({ mode: x.payment_mode, bankAccountId: x.bank_account_id, amount: foreign ? r2(Number(x.amount) / rate) : num(x.amount) })),
      allocations: allocations.map((a) => ({
        invoiceId: a.invoice_id, amount: foreign ? num(a.fx_amount) : num(a.amount), number: a.number, invoiceDate: a.invoice_date,
        total: foreign ? num(a.fx_total) : num(a.total),
      })),
    };
  }

  async create(firmId: string, dto: SavePaymentDto, userId?: string) {
    await assertBooksOpen(this.db, firmId, dto.paymentDate);
    await this.validate(firmId, dto);
    const id = await this.db.transaction().execute(async (trx) => {
      const { parts, ...columns } = await this.columns(firmId, dto);
      const row = await trx.insertInto('payments').values({ firm_id: firmId, created_by: userId ?? null, ...columns }).returning('id').executeTakeFirstOrThrow();
      await this.writeParts(trx, firmId, row.id, parts);
      await this.writeAllocations(trx, firmId, row.id, dto, dto.allocations ?? []);
      return row.id;
    });
    return this.get(firmId, id);
  }

  async update(firmId: string, id: string, dto: SavePaymentDto, scope: Scope = {}) {
    const current = await this.get(firmId, id, scope);
    if (current.type !== dto.type) throw new BadRequestException({ code: 'TYPE_MISMATCH', message: 'Payment type cannot be changed.' });
    await assertBooksOpen(this.db, firmId, current.paymentDate, dto.paymentDate);
    await this.validate(firmId, dto, id);
    // Without a new list the existing links stay, unless the party changed (they would no longer make sense).
    const allocations =
      dto.allocations ?? (dto.partyId === current.partyId ? current.allocations.map((a) => ({ invoiceId: a.invoiceId, amount: a.amount ?? 0 })) : []);
    await this.db.transaction().execute(async (trx) => {
      const { parts, ...columns } = await this.columns(firmId, dto);
      await trx.updateTable('payments').set({ ...columns, updated_at: new Date() }).where('id', '=', id).execute();
      await trx.deleteFrom('payment_parts').where('payment_id', '=', id).execute();
      await this.writeParts(trx, firmId, id, parts);
      await trx.deleteFrom('payment_allocations').where('payment_id', '=', id).execute();
      await this.writeAllocations(trx, firmId, id, dto, allocations);
    });
    return this.get(firmId, id);
  }

  async remove(firmId: string, id: string, scope: Scope = {}) {
    const current = await this.get(firmId, id, scope);
    await assertBooksOpen(this.db, firmId, current.paymentDate);
    await this.db.transaction().execute(async (trx) => {
      await trx.deleteFrom('payment_allocations').where('payment_id', '=', id).execute();
      await trx.updateTable('payments').set({ deleted_at: new Date() }).where('id', '=', id).execute();
    });
  }

  private async writeParts(trx: Transaction<Database>, firmId: string, paymentId: string, parts: Part[]) {
    await trx
      .insertInto('payment_parts')
      .values(parts.map((p, i) => ({ firm_id: firmId, payment_id: paymentId, payment_mode: p.mode, bank_account_id: p.bankAccountId, amount: p.amount, sort_order: i })))
      .execute();
  }

  /**
   * Links the payment to invoices. Each must be an unpaid invoice of the same party, kind and
   * currency; no link may exceed what that invoice still owes, and together they cannot exceed the
   * payment. A foreign-currency payment settles each invoice at the rate the invoice was booked at;
   * the difference to what was actually paid is stored as the payment's exchange gain or loss.
   * Call after this payment's old links are removed, so its own previous links don't count against it.
   */
  private async writeAllocations(trx: Transaction<Database>, firmId: string, paymentId: string, dto: SavePaymentDto, allocations: AllocationDto[]) {
    const foreign = !!dto.currencyCode;
    const rate = foreign ? (dto.exchangeRate ?? 0) : 1;
    let gain = 0;
    if (allocations.length) {
      const total = r2(allocations.reduce((s, a) => s + a.amount, 0));
      if (total > dto.amount) {
        throw new BadRequestException({ code: 'OVER_ALLOCATED', message: `Linked amount ${total} is more than the payment of ${dto.amount}.` });
      }
      if (new Set(allocations.map((a) => a.invoiceId)).size !== allocations.length) {
        throw new BadRequestException({ code: 'DUPLICATE_INVOICE', message: 'An invoice is linked more than once.' });
      }
      const invoices = await trx
        .selectFrom('invoices as i')
        .select(['i.id', 'i.number', 'i.total', 'i.received', 'i.tds_amount', 'i.loyalty_amount', 'i.currency_code', 'i.fx_total', 'i.fx_received'])
        .select(sql<string>`coalesce((select sum(a.amount) from payment_allocations a where a.invoice_id = i.id), 0)`.as('linked'))
        .select(sql<string>`coalesce((select sum(a.fx_amount) from payment_allocations a where a.invoice_id = i.id), 0)`.as('linked_fx'))
        .where('i.firm_id', '=', firmId)
        .where('i.party_id', '=', dto.partyId)
        .where('i.type', '=', SETTLES[dto.type])
        .where('i.deleted_at', 'is', null)
        .where('i.id', 'in', allocations.map((a) => a.invoiceId))
        .execute();
      const rows = [];
      for (const a of allocations) {
        const inv = invoices.find((i) => i.id === a.invoiceId);
        if (!inv) throw new BadRequestException({ code: 'INVOICE_NOT_LINKABLE', message: "One of the invoices is not this party's, or no longer exists." });
        if ((inv.currency_code ?? null) !== (dto.currencyCode ?? null)) {
          throw new BadRequestException({
            code: 'CURRENCY_MISMATCH',
            message: `Invoice ${inv.number} is in ${inv.currency_code ?? 'rupees'}; record this payment in the same currency to link it.`,
          });
        }
        const due = r2(Number(inv.total) - Number(inv.received) - Number(inv.linked) - Number(inv.tds_amount) - Number(inv.loyalty_amount));
        if (!foreign) {
          if (a.amount > due) throw new BadRequestException({ code: 'OVER_INVOICE', message: `Invoice ${inv.number} only has ${due} left to pay.` });
          rows.push({ firm_id: firmId, payment_id: paymentId, invoice_id: a.invoiceId, amount: a.amount, fx_amount: null });
          continue;
        }
        const dueFx = r2(Number(inv.fx_total) - Number(inv.fx_received ?? 0) - Number(inv.linked_fx));
        if (a.amount > dueFx) {
          throw new BadRequestException({ code: 'OVER_INVOICE', message: `Invoice ${inv.number} only has ${dueFx} ${dto.currencyCode} left to pay.` });
        }
        // Settled at the invoice's own rate; paying it off in full clears whatever paise conversion left.
        const booked = a.amount === dueFx ? due : Math.min(due, r2((a.amount / dueFx) * due));
        const paid = r2(a.amount * rate);
        gain += dto.type === 'in' ? paid - booked : booked - paid;
        rows.push({ firm_id: firmId, payment_id: paymentId, invoice_id: a.invoiceId, amount: booked, fx_amount: a.amount });
      }
      await trx.insertInto('payment_allocations').values(rows).execute();
    }
    await trx.updateTable('payments').set({ fx_gain: r2(gain) }).where('id', '=', paymentId).execute();
  }

  /** Columns to store, in the base currency, and the parts the money came in. */
  private async columns(firmId: string, dto: SavePaymentDto) {
    const foreign = !!dto.currencyCode;
    const rate = foreign ? (dto.exchangeRate ?? 0) : 1;
    if (foreign && rate <= 0) throw new BadRequestException({ code: 'RATE_REQUIRED', message: `Enter the exchange rate for ${dto.currencyCode}.` });
    const amount = r2(dto.amount * rate);

    const given = dto.parts?.filter((p) => p.amount > 0) ?? [];
    const raw = given.length ? given : [{ mode: dto.paymentMode ?? ('cash' as const), bankAccountId: dto.bankAccountId ?? null, amount: dto.amount }];
    if (r2(raw.reduce((s, p) => s + p.amount, 0)) !== dto.amount) {
      throw new BadRequestException({ code: 'SPLIT_MISMATCH', message: `The payment types must add up to ${dto.amount}.` });
    }
    const parts: Part[] = [];
    for (const p of raw) {
      parts.push({ mode: p.mode, amount: r2(p.amount * rate), bankAccountId: await resolveBankAccount(this.db, firmId, p.mode, p.bankAccountId) });
    }
    // Conversion can leave the parts a paisa off the total; the last part absorbs it.
    parts[parts.length - 1].amount = r2(parts[parts.length - 1].amount + amount - parts.reduce((s, p) => s + p.amount, 0));
    return {
      type: dto.type,
      number: dto.number,
      party_id: dto.partyId,
      payment_date: dto.paymentDate,
      amount,
      currency_code: dto.currencyCode ?? null,
      exchange_rate: foreign ? rate : null,
      fx_amount: foreign ? dto.amount : null,
      // The first part, for lists; the full split lives in payment_parts.
      payment_mode: parts[0].mode,
      bank_account_id: parts[0].bankAccountId,
      description: dto.description ?? null,
      parts,
    };
  }

  private async validate(firmId: string, dto: SavePaymentDto, exceptId?: string) {
    const party = await this.db
      .selectFrom('parties')
      .select('id')
      .where('id', '=', dto.partyId)
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .executeTakeFirst();
    if (!party) throw new BadRequestException({ code: 'PARTY_NOT_FOUND', message: 'Selected party no longer exists.' });
    const dup = await this.db
      .selectFrom('payments')
      .select('id')
      .where('firm_id', '=', firmId)
      .where('type', '=', dto.type)
      .where('number', '=', dto.number)
      .where('deleted_at', 'is', null)
      .$if(!!exceptId, (q) => q.where('id', '!=', exceptId!))
      .executeTakeFirst();
    if (dup) throw new ConflictException({ code: 'NUMBER_TAKEN', message: `Receipt number ${dto.number} is already used.` });
  }
}
