import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Selectable, sql } from 'kysely';
import { Scope } from '../auth/scope';
import { INVOICE_TYPES, POSTING_TYPES } from '../common/invoice-types';
import { num } from '../common/numbers';
import { partyBalanceSql } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { PartiesTable } from '../database/schema';
import { CreatePartyDto, UpdatePartyDto } from './party.dto';

type PartyRow = Selectable<PartiesTable> & {
  balance: string;
  group_name: string | null;
  assigned_user_name: string | null;
  loyalty_points: string;
  fx_balance: string | null;
};

const toApi = (p: PartyRow) => ({
  id: p.id,
  name: p.name,
  phone: p.phone,
  gstin: p.gstin,
  gstType: p.gst_type,
  stateCode: p.state_code,
  email: p.email,
  billingAddress: p.billing_address,
  shippingAddress: p.shipping_address,
  openingBalance: num(p.opening_balance),
  openingBalanceDate: p.opening_balance_date,
  creditLimit: num(p.credit_limit),
  additionalFields: p.additional_fields,
  groupId: p.group_id,
  groupName: p.group_name,
  assignedUserId: p.assigned_user_id,
  assignedUserName: p.assigned_user_name,
  currencyCode: p.currency_code,
  loyaltyOpening: p.loyalty_opening,
  loyaltyPoints: Number(p.loyalty_points),
  balance: num(p.balance),
  /** For a foreign party: what they owe in their own currency (the rupee balance is at booked rates). */
  fxBalance: p.currency_code ? Number(p.fx_balance ?? 0) : null,
});

@Injectable()
export class PartiesService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  private base(firmId: string) {
    return this.db
      .selectFrom('parties')
      .selectAll()
      .select(partyBalanceSql(sql.ref('parties.id'), sql.ref('parties.opening_balance')).as('balance'))
      .select(sql<string | null>`(select g.name from party_groups g where g.id = parties.group_id)`.as('group_name'))
      .select(sql<string | null>`(select u.full_name from users u where u.id = parties.assigned_user_id)`.as('assigned_user_name'))
      .select(
        sql<string>`parties.loyalty_opening + coalesce((select sum(i.loyalty_earned - i.loyalty_redeemed) from invoices i
                      where i.party_id = parties.id and i.type = 'sale' and i.deleted_at is null), 0)`.as('loyalty_points'),
      )
      // Documents and payments in the party's own currency, the same way the rupee balance is built.
      .select(
        sql<string | null>`(
          coalesce((select sum(case when i.type in ('sale', 'debit_note') then i.fx_total - coalesce(i.fx_received, 0)
                                    else -(i.fx_total - coalesce(i.fx_received, 0)) end)
                      from invoices i where i.party_id = parties.id and i.deleted_at is null and i.currency_code = parties.currency_code
                       and i.type in ('sale', 'purchase', 'credit_note', 'debit_note')), 0)
          + coalesce((select sum(case when pm.type = 'out' then pm.fx_amount else -pm.fx_amount end)
                        from payments pm where pm.party_id = parties.id and pm.deleted_at is null and pm.currency_code = parties.currency_code), 0))`.as(
          'fx_balance',
        ),
      )
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null);
  }

  /** A salesman limited to their own data only sees the parties assigned to them. */
  private scoped<T extends ReturnType<PartiesService['base']>>(q: T, scope: Scope): T {
    return (scope.ownerUserId ? q.where('assigned_user_id', '=', scope.ownerUserId) : q) as T;
  }

  async list(firmId: string, search?: string, scope: Scope = {}, groupId?: string) {
    let q = this.scoped(this.base(firmId), scope);
    if (groupId) q = q.where('group_id', '=', groupId);
    if (search?.trim()) {
      const term = `%${search.trim()}%`;
      q = q.where((eb) => eb.or([eb('name', 'ilike', term), eb('phone', 'ilike', term)]));
    }
    const rows = await q.orderBy(sql`lower(name)`).execute();
    return rows.map(toApi);
  }

  async get(firmId: string, id: string, scope: Scope = {}) {
    return toApi(await this.find(firmId, id, scope));
  }

  /**
   * Ledger: opening balance, invoices and payments, newest first. [balance] is the party's running
   * balance after each entry (positive = they owe us).
   */
  async transactions(firmId: string, id: string, scope: Scope = {}) {
    const rows = (await this.ledger(firmId, id, scope)).map(({ effect: _effect, ...row }) => row);
    return rows.reverse();
  }

  /**
   * The party's ledger in date order. [effect] is what the entry does to the balance
   * (+ they owe us more, − they owe us less) and [balance] the running balance after it.
   */
  async ledger(firmId: string, id: string, scope: Scope = {}) {
    const p = await this.find(firmId, id, scope);
    const invoices = await this.db
      .selectFrom('invoices')
      .select(['id', 'type', 'number', 'invoice_date as date', 'total', 'received', 'tds_amount', 'loyalty_amount', 'created_at'])
      .where('party_id', '=', id)
      .where('type', 'in', POSTING_TYPES) // quotation-like documents don't affect the ledger
      .where('deleted_at', 'is', null)
      .execute();
    const payments = await this.db
      .selectFrom('payments')
      .select(['id', 'type', 'number', 'payment_date as date', 'amount', 'fx_gain', 'created_at'])
      .where('party_id', '=', id)
      .where('deleted_at', 'is', null)
      .execute();

    type Entry = { id: string | null; kind: string; type: string; number: string | null; date: string; total: number; effect: number; at: number };
    const entries: Entry[] = [];
    const opening = Number(p.opening_balance);
    if (opening !== 0) {
      entries.push({ id: null, kind: 'opening', type: 'Opening Balance', number: null, date: p.opening_balance_date, total: Math.abs(opening), effect: opening, at: 0 });
    }
    for (const i of invoices) {
      // What it leaves owing: TDS held back and points redeemed settle part of it without money moving.
      const unpaid = Number(i.total) - Number(i.received) - Number(i.tds_amount) - Number(i.loyalty_amount);
      entries.push({
        id: i.id, kind: i.type, type: INVOICE_TYPES[i.type].label, number: i.number, date: i.date,
        total: Number(i.total), effect: INVOICE_TYPES[i.type].balance * unpaid, at: new Date(i.created_at).getTime(),
      });
    }
    for (const pm of payments) {
      entries.push({
        id: pm.id, kind: `payment_${pm.type}`, type: pm.type === 'in' ? 'Payment-In' : 'Payment-Out', number: pm.number, date: pm.date,
        // A foreign-currency payment settles invoices at their booked rate; the rest is exchange gain or loss.
        total: Number(pm.amount), effect: pm.type === 'in' ? -(Number(pm.amount) - Number(pm.fx_gain)) : Number(pm.amount) + Number(pm.fx_gain),
        at: new Date(pm.created_at).getTime(),
      });
    }
    entries.sort((a, b) => a.date.localeCompare(b.date) || a.at - b.at);
    let running = 0;
    return entries.map((e) => {
      running = Math.round((running + e.effect) * 100) / 100;
      return { id: e.id, kind: e.kind, type: e.type, number: e.number, date: e.date, total: e.total, effect: e.effect, balance: running };
    });
  }

  /** [creator] is set when a salesman adds the party: it then belongs to them. */
  async create(firmId: string, dto: CreatePartyDto, creator?: { userId: string; isSalesman: boolean }) {
    await this.assertNameFree(firmId, dto.name);
    await this.assertReferences(firmId, dto);
    const assigned = creator?.isSalesman ? creator.userId : dto.assignedUserId;
    const row = await this.db
      .insertInto('parties')
      .values({ firm_id: firmId, ...this.columns(dto), assigned_user_id: assigned ?? null, name: dto.name })
      .returning('id')
      .executeTakeFirstOrThrow();
    return this.get(firmId, row.id);
  }

  /** Creates many parties; a bad row (e.g. duplicate name) is reported and the rest still import. */
  async import(firmId: string, rows: CreatePartyDto[]) {
    const errors: Array<{ row: number; name: string; message: string }> = [];
    let created = 0;
    for (const [index, row] of rows.entries()) {
      try {
        await this.create(firmId, row);
        created++;
      } catch (e) {
        const res = (e as { getResponse?: () => unknown }).getResponse?.() as { message?: string } | undefined;
        errors.push({ row: index + 1, name: row.name, message: res?.message ?? 'Could not import this row.' });
      }
    }
    return { created, errors };
  }

  async update(firmId: string, id: string, dto: UpdatePartyDto, scope: Scope = {}) {
    await this.find(firmId, id, scope);
    if (dto.name !== undefined) await this.assertNameFree(firmId, dto.name, id);
    // A salesman cannot hand their party to someone else.
    if (scope.ownerUserId) dto = { ...dto, assignedUserId: undefined };
    await this.assertReferences(firmId, dto);
    await this.db
      .updateTable('parties')
      .set({ ...this.columns(dto), name: dto.name, updated_at: new Date() })
      .where('id', '=', id)
      .where('firm_id', '=', firmId)
      .execute();
    return this.get(firmId, id);
  }

  async remove(firmId: string, id: string) {
    await this.find(firmId, id);
    const used =
      (await this.db.selectFrom('invoices').select('id').where('party_id', '=', id).where('deleted_at', 'is', null).executeTakeFirst()) ??
      (await this.db.selectFrom('payments').select('id').where('party_id', '=', id).where('deleted_at', 'is', null).executeTakeFirst());
    if (used) {
      throw new ConflictException({ code: 'PARTY_IN_USE', message: 'This party has transactions. Delete them first.' });
    }
    await this.db.updateTable('parties').set({ deleted_at: new Date() }).where('id', '=', id).execute();
  }

  private columns(dto: UpdatePartyDto) {
    return {
      phone: dto.phone,
      gstin: dto.gstin,
      gst_type: dto.gstType,
      // A GSTIN's first two digits are its state code.
      state_code: dto.stateCode ?? (dto.gstin ? dto.gstin.slice(0, 2) : dto.stateCode),
      email: dto.email,
      billing_address: dto.billingAddress,
      shipping_address: dto.shippingAddress,
      opening_balance: dto.openingBalance,
      opening_balance_date: dto.openingBalanceDate,
      credit_limit: dto.creditLimit,
      group_id: dto.groupId,
      assigned_user_id: dto.assignedUserId,
      currency_code: dto.currencyCode,
      loyalty_opening: dto.loyaltyOpening,
      additional_fields: dto.additionalFields ? JSON.stringify(dto.additionalFields) : undefined,
    };
  }

  /** The group and the salesman named on a party must belong to this company. */
  private async assertReferences(firmId: string, dto: UpdatePartyDto) {
    if (dto.groupId) {
      const group = await this.db.selectFrom('party_groups').select('id').where('id', '=', dto.groupId).where('firm_id', '=', firmId).executeTakeFirst();
      if (!group) throw new BadRequestException({ code: 'GROUP_NOT_FOUND', message: 'Selected party group no longer exists.' });
    }
    if (dto.assignedUserId) {
      const member = await this.db.selectFrom('firm_members').select('user_id').where('user_id', '=', dto.assignedUserId).where('firm_id', '=', firmId).executeTakeFirst();
      if (!member) throw new BadRequestException({ code: 'USER_NOT_FOUND', message: 'Selected salesman no longer has access to this company.' });
    }
  }

  // ---------------------------------------------------------------- groups

  async groups(firmId: string) {
    const rows = await this.db
      .selectFrom('party_groups as g')
      .select(['g.id', 'g.name'])
      .select(sql<string>`(select count(*) from parties p where p.group_id = g.id and p.deleted_at is null)`.as('parties'))
      .where('g.firm_id', '=', firmId)
      .orderBy(sql`lower(g.name)`)
      .execute();
    return rows.map((g) => ({ id: g.id, name: g.name, partyCount: Number(g.parties) }));
  }

  async saveGroup(firmId: string, name: string, id?: string) {
    try {
      if (id) {
        const res = await this.db.updateTable('party_groups').set({ name }).where('id', '=', id).where('firm_id', '=', firmId).executeTakeFirst();
        if (!res.numUpdatedRows) throw new NotFoundException({ code: 'GROUP_NOT_FOUND', message: 'Party group not found.' });
      } else {
        await this.db.insertInto('party_groups').values({ firm_id: firmId, name }).execute();
      }
    } catch (e) {
      if ((e as { code?: string })?.code === '23505') throw new ConflictException({ code: 'GROUP_EXISTS', message: 'A party group with this name already exists.' });
      throw e;
    }
    return this.groups(firmId);
  }

  /** Parties in the group simply become ungrouped. */
  async deleteGroup(firmId: string, id: string) {
    const res = await this.db.deleteFrom('party_groups').where('id', '=', id).where('firm_id', '=', firmId).executeTakeFirst();
    if (!res.numDeletedRows) throw new NotFoundException({ code: 'GROUP_NOT_FOUND', message: 'Party group not found.' });
  }

  private async find(firmId: string, id: string, scope: Scope = {}) {
    const p = await this.scoped(this.base(firmId), scope).where('id', '=', id).executeTakeFirst();
    if (!p) throw new NotFoundException({ code: 'PARTY_NOT_FOUND', message: 'Party not found.' });
    return p;
  }

  private async assertNameFree(firmId: string, name: string, exceptId?: string) {
    let q = this.db
      .selectFrom('parties')
      .select('id')
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .where(sql`lower(name)`, '=', name.trim().toLowerCase());
    if (exceptId) q = q.where('id', '!=', exceptId);
    if (await q.executeTakeFirst()) {
      throw new ConflictException({ code: 'PARTY_EXISTS', message: 'A party with this name already exists.' });
    }
  }
}
