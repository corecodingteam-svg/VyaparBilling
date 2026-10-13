import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Selectable, sql, Transaction } from 'kysely';
import { resolveBankAccount } from '../common/bank-account';
import { assertBooksOpen } from '../common/books-lock';
import { num } from '../common/numbers';
import { r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { Database, ExpensesTable, PaymentMode } from '../database/schema';
import { ExpenseCategoryDto, ExpenseItemDefDto, ExpenseLineDto, SaveExpenseDto } from './expense.dto';

const isUniqueViolation = (e: unknown) => (e as { code?: string })?.code === '23505';

/** One expense line: GST is either added on top of the price or already inside it. */
export const computeExpenseLine = (l: ExpenseLineDto, inclusive: boolean) => {
  const gross = r2(l.quantity * l.price);
  const rate = l.gstRate ?? 0;
  const taxable = inclusive ? r2(gross / (1 + rate / 100)) : gross;
  const tax = inclusive ? r2(gross - taxable) : r2((taxable * rate) / 100);
  return { gstRate: rate, taxable, tax, amount: r2(taxable + tax) };
};

type ExpenseRow = Selectable<ExpensesTable> & { category_name: string; payment_modes: string | null };

const summary = (e: ExpenseRow) => ({
  id: e.id,
  categoryId: e.category_id,
  categoryName: e.category_name,
  number: e.number,
  expenseDate: e.expense_date,
  total: num(e.total),
  taxAmount: num(e.tax_amount),
  paymentMode: e.payment_mode,
  /** e.g. "Cash + UPI" when paid in parts. */
  paymentLabel: e.payment_modes ?? e.payment_mode,
  bankAccountId: e.bank_account_id,
  supplierState: e.supplier_state,
  supplierGstin: e.supplier_gstin,
});

@Injectable()
export class ExpensesService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  // ---------------------------------------------------------------- categories

  /** Categories with the total spent in each. */
  async categories(firmId: string) {
    const rows = await this.db
      .selectFrom('expense_categories as c')
      .leftJoin('expenses as e', (j) => j.onRef('e.category_id', '=', 'c.id').on('e.deleted_at', 'is', null))
      .select(['c.id', 'c.name', sql<string>`coalesce(sum(e.total), 0)`.as('total')])
      .where('c.firm_id', '=', firmId)
      .groupBy(['c.id', 'c.name'])
      .orderBy(sql`lower(c.name)`)
      .execute();
    return rows.map((r) => ({ id: r.id, name: r.name, total: Number(r.total) }));
  }

  async createCategory(firmId: string, dto: ExpenseCategoryDto) {
    try {
      const row = await this.db.insertInto('expense_categories').values({ firm_id: firmId, name: dto.name }).returning(['id', 'name']).executeTakeFirstOrThrow();
      return { ...row, total: 0 };
    } catch (e) {
      if (isUniqueViolation(e)) throw new ConflictException({ code: 'CATEGORY_EXISTS', message: 'This expense category already exists.' });
      throw e;
    }
  }

  async renameCategory(firmId: string, id: string, dto: ExpenseCategoryDto) {
    try {
      const row = await this.db.updateTable('expense_categories').set({ name: dto.name }).where('id', '=', id).where('firm_id', '=', firmId).returning(['id', 'name']).executeTakeFirst();
      if (!row) throw new NotFoundException();
      return row;
    } catch (e) {
      if (isUniqueViolation(e)) throw new ConflictException({ code: 'CATEGORY_EXISTS', message: 'This expense category already exists.' });
      throw e;
    }
  }

  async deleteCategory(firmId: string, id: string) {
    const cat = await this.db.selectFrom('expense_categories').select('id').where('id', '=', id).where('firm_id', '=', firmId).executeTakeFirst();
    if (!cat) throw new NotFoundException();
    const used = await this.db.selectFrom('expenses').select('id').where('category_id', '=', id).where('deleted_at', 'is', null).executeTakeFirst();
    if (used) throw new ConflictException({ code: 'CATEGORY_IN_USE', message: 'This category has expenses. Delete them first.' });
    // Soft-deleted expenses still reference the category; remove them for good along with it.
    await this.db.transaction().execute(async (trx) => {
      await trx.deleteFrom('expenses').where('category_id', '=', id).execute();
      await trx.deleteFrom('expense_categories').where('id', '=', id).execute();
    });
  }

  // ---------------------------------------------------------------- expenses

  private base(firmId: string) {
    return this.db
      .selectFrom('expenses')
      .innerJoin('expense_categories', 'expense_categories.id', 'expenses.category_id')
      .selectAll('expenses')
      .select('expense_categories.name as category_name')
      .select(
        sql<string | null>`(select string_agg(case m.payment_mode when 'upi' then 'UPI' else initcap(m.payment_mode) end, ' + ' order by m.first) from (
          select ep.payment_mode, min(ep.sort_order) as first from expense_payments ep where ep.expense_id = expenses.id group by ep.payment_mode) m)`.as(
          'payment_modes',
        ),
      )
      .where('expenses.firm_id', '=', firmId)
      .where('expenses.deleted_at', 'is', null);
  }

  async list(firmId: string, opts: { categoryId?: string; from?: string; to?: string }) {
    let q = this.base(firmId);
    if (opts.categoryId) q = q.where('expenses.category_id', '=', opts.categoryId);
    if (opts.from) q = q.where('expenses.expense_date', '>=', opts.from);
    if (opts.to) q = q.where('expenses.expense_date', '<=', opts.to);
    const rows = await q.orderBy('expenses.expense_date', 'desc').orderBy('expenses.created_at', 'desc').execute();
    return rows.map(summary);
  }

  async get(firmId: string, id: string) {
    const e = await this.base(firmId).where('expenses.id', '=', id).executeTakeFirst();
    if (!e) throw new NotFoundException({ code: 'EXPENSE_NOT_FOUND', message: 'Expense not found.' });
    const lines = await this.db.selectFrom('expense_items').selectAll().where('expense_id', '=', id).orderBy('sort_order').execute();
    const parts = await this.db.selectFrom('expense_payments').selectAll().where('expense_id', '=', id).orderBy('sort_order').execute();
    return {
      ...summary(e),
      payments: parts.map((p) => ({ mode: p.payment_mode, bankAccountId: p.bank_account_id, amount: num(p.amount) })),
      subtotal: num(e.subtotal),
      taxableAmount: num(e.taxable_amount),
      pricesIncludeTax: e.prices_include_tax,
      roundOff: num(e.round_off),
      description: e.description,
      lines: lines.map((l) => ({
        name: l.name, quantity: num(l.quantity), price: num(l.price), gstRate: num(l.gst_rate), taxableValue: num(l.taxable_value), tax: num(l.tax),
        amount: num(l.amount),
      })),
    };
  }

  async create(firmId: string, dto: SaveExpenseDto) {
    await assertBooksOpen(this.db, firmId, dto.expenseDate);
    const id = await this.db.transaction().execute(async (trx) => {
      const { parts, ...header } = await this.header(trx, firmId, dto);
      const row = await trx.insertInto('expenses').values({ firm_id: firmId, ...header }).returning('id').executeTakeFirstOrThrow();
      await this.writeLines(trx, row.id, dto);
      await this.writeParts(trx, firmId, row.id, parts);
      return row.id;
    });
    return this.get(firmId, id);
  }

  async update(firmId: string, id: string, dto: SaveExpenseDto) {
    await assertBooksOpen(this.db, firmId, (await this.get(firmId, id)).expenseDate, dto.expenseDate);
    await this.db.transaction().execute(async (trx) => {
      const { parts, ...header } = await this.header(trx, firmId, dto);
      await trx.updateTable('expenses').set({ ...header, updated_at: new Date() }).where('id', '=', id).execute();
      await trx.deleteFrom('expense_items').where('expense_id', '=', id).execute();
      await this.writeLines(trx, id, dto);
      await trx.deleteFrom('expense_payments').where('expense_id', '=', id).execute();
      await this.writeParts(trx, firmId, id, parts);
    });
    return this.get(firmId, id);
  }

  async remove(firmId: string, id: string) {
    await assertBooksOpen(this.db, firmId, (await this.get(firmId, id)).expenseDate);
    await this.db.transaction().execute(async (trx) => {
      await trx.deleteFrom('attachments').where('owner_type', '=', 'expense').where('owner_id', '=', id).execute();
      await trx.updateTable('expenses').set({ deleted_at: new Date() }).where('id', '=', id).execute();
    });
  }

  // ---------------------------------------------------------------- expense items

  /** Reusable expense items with how much has been spent on each (matched by name). */
  async itemDefs(firmId: string) {
    const rows = await this.db
      .selectFrom('expense_item_defs as d')
      .selectAll('d')
      .select(
        sql<string>`coalesce((select sum(ei.amount) from expense_items ei join expenses e on e.id = ei.expense_id
                               where e.firm_id = d.firm_id and e.deleted_at is null and lower(ei.name) = lower(d.name)), 0)`.as('total'),
      )
      .where('d.firm_id', '=', firmId)
      .where('d.deleted_at', 'is', null)
      .orderBy(sql`lower(d.name)`)
      .execute();
    return rows.map((d) => ({ id: d.id, name: d.name, price: num(d.price), hsnCode: d.hsn_code, gstRate: num(d.gst_rate), total: Number(d.total) }));
  }

  async saveItemDef(firmId: string, dto: ExpenseItemDefDto, id?: string) {
    const values = { name: dto.name, price: dto.price ?? 0, hsn_code: dto.hsnCode ?? null, gst_rate: dto.gstRate ?? null };
    try {
      if (id) {
        const res = await this.db.updateTable('expense_item_defs').set(values).where('id', '=', id).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
        if (!res.numUpdatedRows) throw new NotFoundException({ code: 'EXPENSE_ITEM_NOT_FOUND', message: 'Expense item not found.' });
      } else {
        await this.db.insertInto('expense_item_defs').values({ firm_id: firmId, ...values }).execute();
      }
    } catch (e) {
      if (isUniqueViolation(e)) throw new ConflictException({ code: 'EXPENSE_ITEM_EXISTS', message: 'An expense item with this name already exists.' });
      throw e;
    }
    return this.itemDefs(firmId);
  }

  async deleteItemDef(firmId: string, id: string) {
    const res = await this.db.updateTable('expense_item_defs').set({ deleted_at: new Date() }).where('id', '=', id).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
    if (!res.numUpdatedRows) throw new NotFoundException({ code: 'EXPENSE_ITEM_NOT_FOUND', message: 'Expense item not found.' });
  }

  /** Validates the category and computes totals server-side. */
  private async header(trx: Transaction<Database>, firmId: string, dto: SaveExpenseDto) {
    const cat = await trx.selectFrom('expense_categories').select('id').where('id', '=', dto.categoryId).where('firm_id', '=', firmId).executeTakeFirst();
    if (!cat) throw new BadRequestException({ code: 'CATEGORY_NOT_FOUND', message: 'Selected expense category no longer exists.' });
    const lines = dto.lines.map((l) => computeExpenseLine(l, dto.pricesIncludeTax ?? false));
    const subtotal = r2(lines.reduce((s, l) => s + l.amount, 0));
    const total = dto.roundOff ? Math.round(subtotal) : subtotal;
    // How it was paid: one mode, or several parts that add up to the total.
    const given = dto.payments?.filter((p) => p.amount > 0) ?? [];
    const raw = given.length ? given : [{ mode: dto.paymentMode ?? ('cash' as const), bankAccountId: dto.bankAccountId ?? null, amount: total }];
    if (r2(raw.reduce((s, p) => s + p.amount, 0)) !== total) {
      throw new BadRequestException({ code: 'SPLIT_MISMATCH', message: `The payment types must add up to the total of ${total}.` });
    }
    const parts = [];
    for (const p of raw) parts.push({ mode: p.mode, amount: p.amount, bankAccountId: await resolveBankAccount(trx, firmId, p.mode, p.bankAccountId) });
    return {
      parts,
      category_id: dto.categoryId,
      number: dto.number ?? null,
      expense_date: dto.expenseDate,
      prices_include_tax: dto.pricesIncludeTax ?? false,
      taxable_amount: r2(lines.reduce((s, l) => s + l.taxable, 0)),
      tax_amount: r2(lines.reduce((s, l) => s + l.tax, 0)),
      subtotal,
      round_off: r2(total - subtotal),
      total,
      // The first part, for lists; the full split lives in expense_payments.
      payment_mode: parts[0].mode,
      bank_account_id: parts[0].bankAccountId,
      description: dto.description ?? null,
      supplier_state: dto.supplierState ?? null,
      supplier_gstin: dto.supplierGstin?.toUpperCase() ?? null,
    };
  }

  private async writeParts(
    trx: Transaction<Database>,
    firmId: string,
    expenseId: string,
    parts: Array<{ mode: PaymentMode; bankAccountId: string | null; amount: number }>,
  ) {
    const rows = parts.filter((p) => p.amount > 0);
    if (!rows.length) return; // an expense of zero moves no money
    await trx
      .insertInto('expense_payments')
      .values(rows.map((p, i) => ({ firm_id: firmId, expense_id: expenseId, payment_mode: p.mode, bank_account_id: p.bankAccountId, amount: p.amount, sort_order: i })))
      .execute();
  }

  private async writeLines(trx: Transaction<Database>, expenseId: string, dto: SaveExpenseDto) {
    await trx
      .insertInto('expense_items')
      .values(
        dto.lines.map((l, i) => {
          const c = computeExpenseLine(l, dto.pricesIncludeTax ?? false);
          return { expense_id: expenseId, name: l.name, quantity: l.quantity, price: l.price, gst_rate: c.gstRate, taxable_value: c.taxable, tax: c.tax, amount: c.amount, sort_order: i };
        }),
      )
      .execute();
  }
}
