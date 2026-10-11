import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Selectable, sql } from 'kysely';
import { resolveBankAccount } from '../common/bank-account';
import { assertBooksOpen } from '../common/books-lock';
import { num } from '../common/numbers';
import { Db, KYSELY } from '../database/database.module';
import { BankAccountsTable, MoneyFlowsView } from '../database/schema';
import { CreateAdjustmentDto, CreateBankAccountDto, UpdateBankAccountDto } from './cash-bank.dto';

type AccountRow = Selectable<BankAccountsTable> & { balance: string };

const accountApi = (a: AccountRow) => ({
  id: a.id,
  name: a.name,
  openingBalance: num(a.opening_balance),
  openingDate: a.opening_date,
  accountNumber: a.account_number,
  ifsc: a.ifsc,
  bankName: a.bank_name,
  holderName: a.holder_name,
  upiId: a.upi_id,
  balance: num(a.balance),
});

const flowApi = (f: Selectable<MoneyFlowsView>) => ({
  source: f.source, // sale | purchase | credit_note | debit_note | payment_in | payment_out | expense | adjustment
  id: f.source_id,
  type: f.label,
  name: f.name ?? '',
  number: f.ref_number,
  date: f.flow_date,
  amount: Number(f.amount), // signed: + money in, − money out
  paymentMode: f.payment_mode,
  bankAccountId: f.bank_account_id,
});

/** Where the payment parts of each kind of transaction live, keyed by the money_flows source. */
const CHEQUE_PARTS = {
  sale: ['invoice_payments', 'invoice_id'],
  purchase: ['invoice_payments', 'invoice_id'],
  credit_note: ['invoice_payments', 'invoice_id'],
  debit_note: ['invoice_payments', 'invoice_id'],
  payment_in: ['payment_parts', 'payment_id'],
  payment_out: ['payment_parts', 'payment_id'],
  expense: ['expense_payments', 'expense_id'],
} as const;

@Injectable()
export class CashBankService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  // ---------------------------------------------------------------- bank accounts

  /** Balance = opening balance + every flow through the account. */
  private accounts(firmId: string) {
    return this.db
      .selectFrom('bank_accounts as b')
      .selectAll('b')
      .select(
        sql<string>`b.opening_balance + coalesce((select sum(f.amount) from money_flows f where f.bank_account_id = b.id), 0)`.as('balance'),
      )
      .where('b.firm_id', '=', firmId)
      .where('b.deleted_at', 'is', null);
  }

  async listAccounts(firmId: string) {
    return (await this.accounts(firmId).orderBy(sql`lower(b.name)`).execute()).map(accountApi);
  }

  async getAccount(firmId: string, id: string) {
    const a = await this.accounts(firmId).where('b.id', '=', id).executeTakeFirst();
    if (!a) throw new NotFoundException({ code: 'BANK_ACCOUNT_NOT_FOUND', message: 'Bank account not found.' });
    return accountApi(a);
  }

  /** Newest first; the opening balance is the last row. */
  async accountTransactions(firmId: string, id: string) {
    const account = await this.getAccount(firmId, id);
    const flows = await this.db
      .selectFrom('money_flows')
      .selectAll()
      .where('firm_id', '=', firmId)
      .where('bank_account_id', '=', id)
      .orderBy('flow_date', 'desc')
      .orderBy('created_at', 'desc')
      .execute();
    const rows = flows.map(flowApi);
    if (account.openingBalance !== 0) {
      rows.push({
        source: 'opening' as never, id: account.id, type: 'Opening Balance', name: 'Opening Balance', number: null,
        date: account.openingDate, amount: account.openingBalance!, paymentMode: 'bank', bankAccountId: account.id,
      });
    }
    return rows;
  }

  async createAccount(firmId: string, dto: CreateBankAccountDto) {
    await this.assertNameFree(firmId, dto.name);
    const row = await this.db.insertInto('bank_accounts').values({ firm_id: firmId, name: dto.name, ...this.columns(dto) }).returning('id').executeTakeFirstOrThrow();
    return this.getAccount(firmId, row.id);
  }

  async updateAccount(firmId: string, id: string, dto: UpdateBankAccountDto) {
    await this.getAccount(firmId, id);
    if (dto.name !== undefined) await this.assertNameFree(firmId, dto.name, id);
    await this.db.updateTable('bank_accounts').set({ name: dto.name, ...this.columns(dto), updated_at: new Date() }).where('id', '=', id).execute();
    return this.getAccount(firmId, id);
  }

  async deleteAccount(firmId: string, id: string) {
    await this.getAccount(firmId, id);
    const used = await this.db.selectFrom('money_flows').select('source_id').where('bank_account_id', '=', id).executeTakeFirst();
    if (used) throw new ConflictException({ code: 'BANK_ACCOUNT_IN_USE', message: 'This account has transactions and cannot be deleted.' });
    await this.db.updateTable('bank_accounts').set({ deleted_at: new Date() }).where('id', '=', id).execute();
  }

  private columns(dto: UpdateBankAccountDto) {
    return {
      opening_balance: dto.openingBalance,
      opening_date: dto.openingDate,
      account_number: dto.accountNumber,
      ifsc: dto.ifsc,
      bank_name: dto.bankName,
      holder_name: dto.holderName,
      upi_id: dto.upiId,
    };
  }

  private async assertNameFree(firmId: string, name: string, exceptId?: string) {
    const dup = await this.db
      .selectFrom('bank_accounts')
      .select('id')
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .where(sql`lower(name)`, '=', name.toLowerCase())
      .$if(!!exceptId, (q) => q.where('id', '!=', exceptId!))
      .executeTakeFirst();
    if (dup) throw new ConflictException({ code: 'BANK_ACCOUNT_EXISTS', message: 'A bank account with this name already exists.' });
  }

  // ---------------------------------------------------------------- cash in hand

  async cash(firmId: string) {
    const flows = await this.db
      .selectFrom('money_flows')
      .selectAll()
      .where('firm_id', '=', firmId)
      .where('account', '=', 'cash')
      .orderBy('flow_date', 'desc')
      .orderBy('created_at', 'desc')
      .execute();
    const transactions = flows.map(flowApi);
    return { balance: Math.round(transactions.reduce((s, t) => s + t.amount, 0) * 100) / 100, transactions };
  }

  // ---------------------------------------------------------------- adjustments & transfers

  /** Checks which accounts a kind of adjustment needs and returns the columns to store. */
  private async adjustmentColumns(firmId: string, dto: CreateAdjustmentDto) {
    const needsBank = !dto.kind.startsWith('cash_') || dto.kind === 'cash_to_bank';
    const isTransfer = dto.kind === 'bank_to_bank';
    if (needsBank && !dto.bankAccountId) throw new BadRequestException({ code: 'BANK_ACCOUNT_REQUIRED', message: 'Select a bank account.' });
    if (isTransfer && !dto.toBankAccountId) throw new BadRequestException({ code: 'BANK_ACCOUNT_REQUIRED', message: 'Select the account to transfer to.' });
    if (isTransfer && dto.toBankAccountId === dto.bankAccountId) {
      throw new BadRequestException({ code: 'SAME_ACCOUNT', message: 'Choose two different accounts.' });
    }
    return {
      kind: dto.kind,
      bank_account_id: needsBank ? await resolveBankAccount(this.db, firmId, 'bank', dto.bankAccountId) : null,
      to_bank_account_id: isTransfer ? await resolveBankAccount(this.db, firmId, 'bank', dto.toBankAccountId) : null,
      amount: dto.amount,
      adjustment_date: dto.date,
      description: dto.description ?? null,
    };
  }

  async getAdjustment(firmId: string, id: string) {
    const a = await this.db.selectFrom('fund_adjustments').selectAll().where('id', '=', id).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
    if (!a) throw new NotFoundException({ code: 'ADJUSTMENT_NOT_FOUND', message: 'Adjustment not found.' });
    return {
      id: a.id, kind: a.kind, bankAccountId: a.bank_account_id, toBankAccountId: a.to_bank_account_id, amount: num(a.amount),
      date: a.adjustment_date, description: a.description,
    };
  }

  async createAdjustment(firmId: string, dto: CreateAdjustmentDto) {
    await assertBooksOpen(this.db, firmId, dto.date);
    const row = await this.db
      .insertInto('fund_adjustments')
      .values({ firm_id: firmId, ...(await this.adjustmentColumns(firmId, dto)) })
      .returning('id')
      .executeTakeFirstOrThrow();
    return { id: row.id };
  }

  async updateAdjustment(firmId: string, id: string, dto: CreateAdjustmentDto) {
    const current = await this.getAdjustment(firmId, id);
    await assertBooksOpen(this.db, firmId, current.date, dto.date);
    await this.db.updateTable('fund_adjustments').set(await this.adjustmentColumns(firmId, dto)).where('id', '=', id).execute();
    return this.getAdjustment(firmId, id);
  }

  async deleteAdjustment(firmId: string, id: string) {
    await assertBooksOpen(this.db, firmId, (await this.getAdjustment(firmId, id)).date);
    const res = await this.db
      .updateTable('fund_adjustments')
      .set({ deleted_at: new Date() })
      .where('id', '=', id)
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .executeTakeFirst();
    if (!res.numUpdatedRows) throw new NotFoundException({ code: 'ADJUSTMENT_NOT_FOUND', message: 'Adjustment not found.' });
  }

  // ---------------------------------------------------------------- cheques

  /** Every cheque payment: open until deposited into (or paid from) a bank account. */
  async cheques(firmId: string) {
    const flows = await this.db
      .selectFrom('money_flows')
      .selectAll()
      .where('firm_id', '=', firmId)
      .where('payment_mode', '=', 'cheque')
      .where('source', '!=', 'adjustment')
      .orderBy('flow_date', 'desc')
      .orderBy('created_at', 'desc')
      .execute();
    return flows.map((f) => ({ ...flowApi(f), status: f.bank_account_id ? 'closed' : 'open' }));
  }

  /** Marks a cheque as deposited/withdrawn through [bankAccountId]; null re-opens it. */
  async setChequeAccount(firmId: string, source: string, id: string, bankAccountId: string | null) {
    const parts = CHEQUE_PARTS[source as keyof typeof CHEQUE_PARTS];
    if (!parts) throw new BadRequestException({ code: 'BAD_SOURCE', message: 'Unknown cheque transaction type.' });
    const account = bankAccountId ? await resolveBankAccount(this.db, firmId, 'cheque', bankAccountId) : null;
    // The cheque is one of the transaction's payment parts.
    const [table, owner] = parts;
    const res = await sql`update ${sql.table(table)} set bank_account_id = ${account}
                           where ${sql.ref(owner)} = ${id} and firm_id = ${firmId} and payment_mode = 'cheque'`.execute(this.db);
    if (!res.numAffectedRows) throw new NotFoundException({ code: 'CHEQUE_NOT_FOUND', message: 'Cheque transaction not found.' });
    // Payments and expenses also keep their first part on their own row, for lists.
    if (table === 'payment_parts') {
      await this.db.updateTable('payments').set({ bank_account_id: account }).where('id', '=', id).where('firm_id', '=', firmId).where('payment_mode', '=', 'cheque').execute();
    } else if (table === 'expense_payments') {
      await this.db.updateTable('expenses').set({ bank_account_id: account }).where('id', '=', id).where('firm_id', '=', firmId).where('payment_mode', '=', 'cheque').execute();
    }
  }
}
