import { Inject, Injectable } from '@nestjs/common';
import { sql, Transaction } from 'kysely';
import { JwtPayload } from '../auth/jwt.strategy';
import { partyBalanceSql, r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { Database } from '../database/schema';
import { exportFirm, restoreFirm } from './backup';
import { NewYearDto } from './utilities.dto';

interface Check {
  id: string;
  title: string;
  /** "Fix" can repair it; otherwise the listed transactions need a look. */
  fixable: boolean;
  issues: Array<{ label: string; detail: string }>;
}

@Injectable()
export class UtilitiesService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  // ---------------------------------------------------------------- set up my business

  /** The first-run checklist: what is already done and where to go for the rest. */
  async setup(firmId: string) {
    const firm = await this.db.selectFrom('firms').selectAll().where('id', '=', firmId).executeTakeFirstOrThrow();
    const count = async (table: 'parties' | 'items' | 'bank_accounts' | 'invoices') =>
      Number((await this.db.selectFrom(table).select(sql<string>`count(*)`.as('n')).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirstOrThrow()).n);
    const members = await this.db.selectFrom('firm_members').select(sql<string>`count(*)`.as('n')).where('firm_id', '=', firmId).executeTakeFirstOrThrow();
    const steps = [
      { id: 'profile', title: 'Complete your company profile', hint: 'Phone, address and state print on every invoice.', route: '/company', done: !!(firm.phone && firm.address && firm.state_code) },
      { id: 'logo', title: 'Add your logo and signature', hint: 'Shown on printed invoices.', route: '/company', done: !!(firm.logo_file_id || firm.signature_file_id) },
      { id: 'gst', title: 'Enter your GSTIN', hint: 'Needed for tax invoices and GST reports. Skip if you are not registered.', route: '/company', done: !!firm.gstin },
      { id: 'party', title: 'Add your first party', hint: 'Customers and suppliers you deal with.', route: '/parties', done: (await count('parties')) > 0 },
      { id: 'item', title: 'Add your first item', hint: 'Products you stock or services you offer.', route: '/items', done: (await count('items')) > 0 },
      { id: 'bank', title: 'Add a bank account', hint: 'To track bank, UPI and card payments.', route: '/bank-accounts', done: (await count('bank_accounts')) > 0 },
      { id: 'invoice', title: 'Create your first invoice', hint: 'Record a sale and print or share it.', route: '/sale-invoices/new', done: (await count('invoices')) > 0 },
      { id: 'team', title: 'Invite your accountant or staff', hint: 'Give others their own login.', route: '/users', done: Number(members.n) > 1 },
    ];
    return { done: steps.filter((s) => s.done).length, total: steps.length, steps };
  }

  // ---------------------------------------------------------------- verify my data

  async verify(firmId: string): Promise<{ ok: boolean; checks: Check[] }> {
    const stock = await sql<{ name: string; stock_qty: string; moved: string }>`
      select i.name, i.stock_qty, coalesce(sum(m.qty_change), 0) as moved
        from items i left join stock_movements m on m.item_id = i.id
       where i.firm_id = ${firmId} and i.deleted_at is null and i.type = 'product'
       group by i.id having i.stock_qty <> coalesce(sum(m.qty_change), 0) order by lower(i.name)`.execute(this.db);
    const received = await sql<{ number: string; party_name: string; received: string; parts: string }>`
      select i.number, i.party_name, i.received, coalesce(sum(ip.amount), 0) as parts
        from invoices i left join invoice_payments ip on ip.invoice_id = i.id
       where i.firm_id = ${firmId} and i.deleted_at is null
       group by i.id having i.received <> coalesce(sum(ip.amount), 0) order by i.invoice_date`.execute(this.db);
    const totals = await sql<{ number: string; party_name: string; total: string; lines: string }>`
      select i.number, i.party_name, i.total, coalesce(sum(ii.amount), 0) + i.charges_total + i.tcs_amount + i.round_off as lines
        from invoices i left join invoice_items ii on ii.invoice_id = i.id
       where i.firm_id = ${firmId} and i.deleted_at is null
       group by i.id having i.total <> coalesce(sum(ii.amount), 0) + i.charges_total + i.tcs_amount + i.round_off order by i.invoice_date`.execute(this.db);
    const paymentParts = await sql<{ number: string; amount: string; parts: string }>`
      select p.number, p.amount, coalesce(sum(pp.amount), 0) as parts
        from payments p left join payment_parts pp on pp.payment_id = p.id
       where p.firm_id = ${firmId} and p.deleted_at is null
       group by p.id having p.amount <> coalesce(sum(pp.amount), 0)`.execute(this.db);
    const expenseParts = await sql<{ number: string | null; expense_date: string; total: string; parts: string }>`
      select e.number, e.expense_date, e.total, coalesce(sum(ep.amount), 0) as parts
        from expenses e left join expense_payments ep on ep.expense_id = e.id
       where e.firm_id = ${firmId} and e.deleted_at is null
       group by e.id having e.total <> coalesce(sum(ep.amount), 0)`.execute(this.db);
    const overpaid = await sql<{ number: string; party_name: string; total: string; paid: string }>`
      select i.number, i.party_name, i.total,
             i.received + i.tds_amount + i.loyalty_amount + coalesce((select sum(a.amount) from payment_allocations a join payments p on p.id = a.payment_id
                                     where a.invoice_id = i.id and p.deleted_at is null), 0) as paid
        from invoices i
       where i.firm_id = ${firmId} and i.deleted_at is null
         and i.received + i.tds_amount + i.loyalty_amount + coalesce((select sum(a.amount) from payment_allocations a join payments p on p.id = a.payment_id
                                     where a.invoice_id = i.id and p.deleted_at is null), 0) > i.total
       order by i.invoice_date`.execute(this.db);
    const overLinked = await sql<{ number: string; amount: string; linked: string }>`
      select p.number, p.amount, sum(a.amount) as linked
        from payments p join payment_allocations a on a.payment_id = p.id
       where p.firm_id = ${firmId} and p.deleted_at is null
       group by p.id having sum(a.amount) > p.amount`.execute(this.db);
    const orphanLinks = await sql<{ n: string }>`
      select count(*) as n from payment_allocations a
        join payments p on p.id = a.payment_id join invoices i on i.id = a.invoice_id
       where a.firm_id = ${firmId} and (p.deleted_at is not null or i.deleted_at is not null)`.execute(this.db);

    const checks: Check[] = [
      {
        id: 'stock', title: 'Stock quantities match stock movements', fixable: true,
        issues: stock.rows.map((r) => ({ label: r.name, detail: `Shows ${Number(r.stock_qty)}, movements add up to ${Number(r.moved)}` })),
      },
      {
        id: 'received', title: 'Amounts received match the payment split on each invoice', fixable: true,
        issues: received.rows.map((r) => ({ label: `${r.number} · ${r.party_name}`, detail: `Received ${Number(r.received)}, payment parts add up to ${Number(r.parts)}` })),
      },
      {
        id: 'links', title: 'No payment links point at deleted transactions', fixable: true,
        issues: Number(orphanLinks.rows[0].n) ? [{ label: `${orphanLinks.rows[0].n} link(s)`, detail: 'Linked to a deleted payment or invoice' }] : [],
      },
      {
        id: 'totals', title: 'Invoice totals match their line items', fixable: false,
        issues: totals.rows.map((r) => ({ label: `${r.number} · ${r.party_name}`, detail: `Total ${Number(r.total)}, lines add up to ${Number(r.lines)}` })),
      },
      {
        id: 'overpaid', title: 'No invoice is paid more than its total', fixable: false,
        issues: overpaid.rows.map((r) => ({ label: `${r.number} · ${r.party_name}`, detail: `Total ${Number(r.total)}, paid ${Number(r.paid)}` })),
      },
      {
        id: 'parts', title: 'Payments and expenses match the modes they were paid in', fixable: false,
        issues: [
          ...paymentParts.rows.map((r) => ({ label: `Receipt ${r.number}`, detail: `Amount ${Number(r.amount)}, payment types add up to ${Number(r.parts)}` })),
          ...expenseParts.rows.map((r) => ({ label: `Expense ${r.number ?? r.expense_date}`, detail: `Total ${Number(r.total)}, payment types add up to ${Number(r.parts)}` })),
        ],
      },
      {
        id: 'overlinked', title: 'No payment is linked for more than its amount', fixable: false,
        issues: overLinked.rows.map((r) => ({ label: `Receipt ${r.number}`, detail: `Amount ${Number(r.amount)}, linked ${Number(r.linked)}` })),
      },
    ];
    return { ok: checks.every((c) => !c.issues.length), checks };
  }

  /** Repairs what can be repaired safely: derived figures are recomputed from the entries behind them. */
  async fix(firmId: string) {
    await this.db.transaction().execute(async (trx) => {
      await sql`update items i set stock_qty = coalesce((select sum(m.qty_change) from stock_movements m where m.item_id = i.id), 0)
                 where i.firm_id = ${firmId} and i.type = 'product'`.execute(trx);
      await sql`update invoices i set received = coalesce((select sum(ip.amount) from invoice_payments ip where ip.invoice_id = i.id), 0)
                 where i.firm_id = ${firmId} and i.deleted_at is null`.execute(trx);
      await sql`delete from payment_allocations a using payments p, invoices i
                 where a.firm_id = ${firmId} and p.id = a.payment_id and i.id = a.invoice_id
                   and (p.deleted_at is not null or i.deleted_at is not null)`.execute(trx);
    });
    return this.verify(firmId);
  }

  // ---------------------------------------------------------------- close books

  /** Locks everything dated on or before [date]; null re-opens the books. */
  async closeBooks(firmId: string, date: string | null) {
    await this.db.updateTable('firms').set({ books_lock_date: date, updated_at: new Date() }).where('id', '=', firmId).execute();
    return { booksLockDate: date };
  }

  /**
   * Starts a new company for the next year from this one's closing position: party balances, stock,
   * bank and cash balances, outstanding loans and own ledger accounts become opening balances.
   * Masters and settings are copied; transactions stay behind in this company.
   */
  async startNewYear(user: JwtPayload, dto: NewYearDto) {
    const from = user.firmId;
    const start = dto.startDate;
    const firmId = await this.db.transaction().execute(async (trx) => {
      const old = await trx.selectFrom('firms').selectAll().where('id', '=', from).executeTakeFirstOrThrow();
      const firm = await trx
        .insertInto('firms')
        .values({
          name: dto.name, phone: old.phone, gstin: old.gstin, email: old.email, books_start_date: start, business_type: old.business_type,
          business_category: old.business_category, state_code: old.state_code, pincode: old.pincode, address: old.address,
          settings: JSON.stringify(old.settings),
        })
        .returning('id')
        .executeTakeFirstOrThrow();
      const to = firm.id;
      const file = async (fileId: string | null) => {
        if (!fileId) return null;
        const row = await sql<{ id: string }>`
          insert into files (firm_id, name, mime_type, size, data) select ${to}, name, mime_type, size, data from files where id = ${fileId} returning id`.execute(trx);
        return row.rows[0]?.id ?? null;
      };
      await trx.updateTable('firms').set({ logo_file_id: await file(old.logo_file_id), signature_file_id: await file(old.signature_file_id) }).where('id', '=', to).execute();

      await sql`insert into firm_members (firm_id, user_id, role) select ${to}, user_id, role from firm_members where firm_id = ${from}`.execute(trx);
      await sql`insert into units (firm_id, name, short_name) select ${to}, name, short_name from units where firm_id = ${from}`.execute(trx);
      await sql`insert into expense_categories (firm_id, name) select ${to}, name from expense_categories where firm_id = ${from}`.execute(trx);
      await sql`insert into expense_item_defs (firm_id, name, price, hsn_code, gst_rate)
                select ${to}, name, price, hsn_code, gst_rate from expense_item_defs where firm_id = ${from} and deleted_at is null`.execute(trx);
      await sql`insert into currencies (firm_id, code, symbol, rate) select ${to}, code, symbol, rate from currencies where firm_id = ${from}`.execute(trx);

      await sql`insert into party_groups (firm_id, name) select ${to}, name from party_groups where firm_id = ${from}`.execute(trx);
      // Parties: what they owe (or are owed) today becomes the opening balance, and their loyalty points carry over.
      await sql`insert into parties (firm_id, name, phone, gstin, gst_type, state_code, email, billing_address, shipping_address, opening_balance,
                                     opening_balance_date, credit_limit, additional_fields, assigned_user_id, currency_code, group_id, loyalty_opening)
                select ${to}, name, phone, gstin, gst_type, state_code, email, billing_address, shipping_address,
                       ${partyBalanceSql(sql.ref('parties.id'), sql.ref('parties.opening_balance'))}, ${start}::date, credit_limit, additional_fields,
                       assigned_user_id, currency_code,
                       (select n.id from party_groups n join party_groups o on lower(o.name) = lower(n.name) where o.id = parties.group_id and n.firm_id = ${to}),
                       parties.loyalty_opening + coalesce((select sum(i.loyalty_earned - i.loyalty_redeemed) from invoices i
                                                            where i.party_id = parties.id and i.type = 'sale' and i.deleted_at is null), 0)
                  from parties where firm_id = ${from} and deleted_at is null`.execute(trx);

      const godownIds = new Map<string, string>();
      for (const g of await trx.selectFrom('godowns').select(['id', 'name', 'address']).where('firm_id', '=', from).where('deleted_at', 'is', null).execute()) {
        godownIds.set(g.id, (await trx.insertInto('godowns').values({ firm_id: to, name: g.name, address: g.address }).returning('id').executeTakeFirstOrThrow()).id);
      }

      // Items: stock in hand becomes opening stock, valued at the purchase price.
      const categories = await trx.selectFrom('categories').select(['id', 'name']).where('firm_id', '=', from).execute();
      const categoryIds = new Map<string, string>();
      for (const c of categories) {
        categoryIds.set(c.id, (await trx.insertInto('categories').values({ firm_id: to, name: c.name }).returning('id').executeTakeFirstOrThrow()).id);
      }
      const items = await trx.selectFrom('items').selectAll().where('firm_id', '=', from).where('deleted_at', 'is', null).execute();
      for (const i of items) {
        const qty = i.type === 'product' ? Number(i.stock_qty) : 0;
        const created = await trx
          .insertInto('items')
          .values({
            firm_id: to, type: i.type, name: i.name, hsn_code: i.hsn_code, unit: i.unit, category_id: i.category_id ? (categoryIds.get(i.category_id) ?? null) : null,
            item_code: i.item_code, sale_price: i.sale_price, sale_price_includes_tax: i.sale_price_includes_tax, sale_discount: i.sale_discount,
            sale_discount_type: i.sale_discount_type, wholesale_price: i.wholesale_price, wholesale_min_qty: i.wholesale_min_qty,
            purchase_price: i.purchase_price, purchase_price_includes_tax: i.purchase_price_includes_tax, gst_rate: i.gst_rate, opening_qty: qty,
            opening_price: i.purchase_price, opening_date: start, min_stock: i.min_stock, location: i.location, stock_qty: qty,
            image_file_id: await file(i.image_file_id), service_reminder_days: i.service_reminder_days, cess_rate: i.cess_rate, mrp: i.mrp,
          })
          .returning('id')
          .executeTakeFirstOrThrow();
        if (i.type !== 'product') continue;
        // Opening stock is brought in store by store and batch by batch, so each keeps what it holds.
        const held = await trx
          .selectFrom('stock_movements')
          .select(['godown_id', 'batch_no', sql<string | null>`max(expiry_date)`.as('expiry_date'), sql<string>`sum(qty_change)`.as('qty')])
          .where('item_id', '=', i.id)
          .groupBy(['godown_id', 'batch_no'])
          .having(sql`sum(qty_change)`, '<>', 0)
          .execute();
        for (const h of held) {
          await trx
            .insertInto('stock_movements')
            .values({
              firm_id: to, item_id: created.id, type: 'opening', qty_change: h.qty, price_per_unit: i.purchase_price, movement_date: start,
              godown_id: h.godown_id ? (godownIds.get(h.godown_id) ?? null) : null, batch_no: h.batch_no, expiry_date: h.expiry_date,
            })
            .execute();
        }
        // The item's own "opening quantity" is the part in the main store without a batch.
        const main = held.find((h) => h.godown_id === null && h.batch_no === null);
        await trx.updateTable('items').set({ opening_qty: main ? main.qty : 0 }).where('id', '=', created.id).execute();
      }

      // Loans still outstanding. In the new books a loan's opening balance counts as money received in
      // cash, so the cash carried forward below is reduced by the same amount.
      const loans = await sql<{ name: string; lender: string | null; account_number: string | null; interest_rate: string | null; term_months: number | null; description: string | null; balance: string }>`
        select l.name, l.lender, l.account_number, l.interest_rate, l.term_months, l.description,
               l.opening_balance + coalesce((select sum(case when t.kind = 'payment' then -t.principal else t.principal end)
                                               from loan_transactions t where t.loan_id = l.id and t.deleted_at is null), 0) as balance
          from loan_accounts l where l.firm_id = ${from} and l.deleted_at is null`.execute(trx);
      let loanCash = 0;
      for (const l of loans.rows) {
        if (Number(l.balance) <= 0) continue;
        loanCash += Number(l.balance);
        await trx
          .insertInto('loan_accounts')
          .values({
            firm_id: to, name: l.name, lender: l.lender, account_number: l.account_number, opening_balance: l.balance, balance_date: start,
            bank_account_id: null, interest_rate: l.interest_rate, term_months: l.term_months, description: l.description,
          })
          .execute();
      }

      // Bank accounts open with today's balance; cash in hand is brought in as an adjustment.
      await sql`insert into bank_accounts (firm_id, name, opening_balance, opening_date, account_number, ifsc, bank_name, holder_name, upi_id)
                select ${to}, b.name,
                       b.opening_balance + coalesce((select sum(f.amount) from money_flows f where f.bank_account_id = b.id and f.account = 'bank'), 0),
                       ${start}::date, b.account_number, b.ifsc, b.bank_name, b.holder_name, b.upi_id
                  from bank_accounts b where b.firm_id = ${from} and b.deleted_at is null`.execute(trx);
      const cash = await trx.selectFrom('money_flows').select(sql<string>`coalesce(sum(amount), 0)`.as('total')).where('firm_id', '=', from).where('account', '=', 'cash').executeTakeFirstOrThrow();
      const openingCash = r2(Number(cash.total) - loanCash);
      if (openingCash !== 0) {
        await trx
          .insertInto('fund_adjustments')
          .values({ firm_id: to, kind: openingCash > 0 ? 'cash_add' : 'cash_reduce', amount: Math.abs(openingCash), adjustment_date: start, description: 'Opening cash in hand' })
          .execute();
      }

      await this.carryLedgerAccounts(trx, from, to, start);
      return to;
    });
    return { id: firmId, name: dto.name };
  }

  /** Own ledger accounts; asset, liability and equity balances are carried through one opening journal entry. */
  private async carryLedgerAccounts(trx: Transaction<Database>, from: string, to: string, start: string) {
    const accounts = await sql<{ id: string; name: string; type: 'asset' | 'liability' | 'income' | 'expense' | 'equity'; balance: string }>`
      select a.id, a.name, a.type,
             coalesce((select sum(jl.debit - jl.credit) from journal_lines jl join journal_entries e on e.id = jl.entry_id
                        where jl.ledger_account_id = a.id and e.deleted_at is null), 0) as balance
        from ledger_accounts a where a.firm_id = ${from} and a.deleted_at is null`.execute(trx);
    const lines: Array<{ ledger_account_id: string; debit: number; credit: number }> = [];
    for (const a of accounts.rows) {
      const created = await trx.insertInto('ledger_accounts').values({ firm_id: to, name: a.name, type: a.type }).returning('id').executeTakeFirstOrThrow();
      const balance = Number(a.balance);
      // Income and expense accounts start each year at zero.
      if (balance !== 0 && a.type !== 'income' && a.type !== 'expense') {
        lines.push({ ledger_account_id: created.id, debit: balance > 0 ? balance : 0, credit: balance < 0 ? -balance : 0 });
      }
    }
    if (!lines.length) return;
    const difference = r2(lines.reduce((s, l) => s + l.debit - l.credit, 0));
    if (difference !== 0) {
      const name = accounts.rows.some((a) => a.name.toLowerCase() === 'opening balances') ? `Opening balances ${start}` : 'Opening balances';
      const equity = await trx.insertInto('ledger_accounts').values({ firm_id: to, name, type: 'equity' }).returning('id').executeTakeFirstOrThrow();
      lines.push({ ledger_account_id: equity.id, debit: difference < 0 ? -difference : 0, credit: difference > 0 ? difference : 0 });
    }
    const entry = await trx
      .insertInto('journal_entries')
      .values({ firm_id: to, number: '1', entry_date: start, description: 'Opening balances brought forward' })
      .returning('id')
      .executeTakeFirstOrThrow();
    await trx.insertInto('journal_lines').values(lines.map((l, i) => ({ firm_id: to, entry_id: entry.id, money_account: null, bank_account_id: null, sort_order: i, ...l }))).execute();
  }

  // ---------------------------------------------------------------- backup and restore

  backup(firmId: string) {
    return exportFirm(this.db, firmId);
  }

  /** Restores a backup as a new company owned by this login. */
  async restore(user: JwtPayload, backup: Record<string, unknown>, name?: string) {
    const firmId = await this.db.transaction().execute(async (trx) => {
      const id = await restoreFirm(trx, backup, name);
      await trx.insertInto('firm_members').values({ firm_id: id, user_id: user.sub, role: 'owner' }).execute();
      return id;
    });
    const firm = await this.db.selectFrom('firms').select(['id', 'name']).where('id', '=', firmId).executeTakeFirstOrThrow();
    return { id: firm.id, name: firm.name };
  }
}
