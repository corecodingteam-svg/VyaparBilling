import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Selectable, sql } from 'kysely';
import { resolveBankAccount } from '../common/bank-account';
import { assertBooksOpen } from '../common/books-lock';
import { num } from '../common/numbers';
import { r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { LoanAccountsTable } from '../database/schema';
import { CreateLoanDto, CreateLoanTransactionDto, UpdateLoanDto } from './loan.dto';

type LoanRow = Selectable<LoanAccountsTable> & { balance: string };

const KIND_LABEL = { payment: 'Loan Payment', increase: 'Loan Increased', charge: 'Charges' } as const;

const toApi = (l: LoanRow) => ({
  id: l.id,
  name: l.name,
  lender: l.lender,
  accountNumber: l.account_number,
  openingBalance: num(l.opening_balance),
  balanceDate: l.balance_date,
  bankAccountId: l.bank_account_id,
  interestRate: num(l.interest_rate),
  termMonths: l.term_months,
  description: l.description,
  balance: num(l.balance),
});

@Injectable()
export class LoansService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  /** Outstanding = opening + further borrowing + charges − principal repaid. */
  private base(firmId: string) {
    return this.db
      .selectFrom('loan_accounts as l')
      .selectAll('l')
      .select(
        sql<string>`l.opening_balance + coalesce((
          select sum(case when t.kind = 'payment' then -t.principal else t.principal end)
            from loan_transactions t where t.loan_id = l.id and t.deleted_at is null), 0)`.as('balance'),
      )
      .where('l.firm_id', '=', firmId)
      .where('l.deleted_at', 'is', null);
  }

  async list(firmId: string) {
    return (await this.base(firmId).orderBy(sql`lower(l.name)`).execute()).map(toApi);
  }

  async get(firmId: string, id: string) {
    const loan = await this.base(firmId).where('l.id', '=', id).executeTakeFirst();
    if (!loan) throw new NotFoundException({ code: 'LOAN_NOT_FOUND', message: 'Loan account not found.' });
    return toApi(loan);
  }

  /** Newest first, each with the loan balance after it; the opening balance is the last row. */
  async transactions(firmId: string, id: string) {
    const loan = await this.get(firmId, id);
    const txns = await this.db
      .selectFrom('loan_transactions')
      .selectAll()
      .where('loan_id', '=', id)
      .where('deleted_at', 'is', null)
      .orderBy('txn_date')
      .orderBy('created_at')
      .execute();
    let running = loan.openingBalance ?? 0;
    const rows = txns.map((t) => {
      const principal = Number(t.principal);
      running = r2(running + (t.kind === 'payment' ? -principal : principal));
      return {
        id: t.id as string | null,
        kind: t.kind as string,
        type: KIND_LABEL[t.kind] as string,
        date: t.txn_date,
        principal,
        interest: Number(t.interest),
        total: r2(principal + Number(t.interest)),
        balance: running,
        bankAccountId: t.bank_account_id,
        description: t.description,
      };
    });
    rows.reverse();
    rows.push({
      id: null, kind: 'opening', type: 'Opening Loan', date: loan.balanceDate, principal: loan.openingBalance ?? 0, interest: 0,
      total: loan.openingBalance ?? 0, balance: loan.openingBalance ?? 0, bankAccountId: loan.bankAccountId, description: null,
    });
    return rows;
  }

  async create(firmId: string, dto: CreateLoanDto) {
    await this.assertNameFree(firmId, dto.name);
    const row = await this.db
      .insertInto('loan_accounts')
      .values({ firm_id: firmId, name: dto.name, ...(await this.columns(firmId, dto)) })
      .returning('id')
      .executeTakeFirstOrThrow();
    return this.get(firmId, row.id);
  }

  async update(firmId: string, id: string, dto: UpdateLoanDto) {
    await this.get(firmId, id);
    if (dto.name !== undefined) await this.assertNameFree(firmId, dto.name, id);
    await this.db.updateTable('loan_accounts').set({ name: dto.name, ...(await this.columns(firmId, dto)), updated_at: new Date() }).where('id', '=', id).execute();
    return this.get(firmId, id);
  }

  async remove(firmId: string, id: string) {
    await this.get(firmId, id);
    const used = await this.db.selectFrom('loan_transactions').select('id').where('loan_id', '=', id).where('deleted_at', 'is', null).executeTakeFirst();
    if (used) throw new ConflictException({ code: 'LOAN_IN_USE', message: 'This loan has transactions. Delete them first.' });
    await this.db.updateTable('loan_accounts').set({ deleted_at: new Date() }).where('id', '=', id).execute();
  }

  /**
   * Columns for a loan entry. [outstanding] is the loan balance without this entry, so an edited
   * repayment is checked against what would be owed without it.
   */
  private async txnColumns(firmId: string, outstanding: number, dto: CreateLoanTransactionDto) {
    const interest = dto.kind === 'payment' ? (dto.interest ?? 0) : 0;
    if (dto.principal + interest <= 0) throw new BadRequestException({ code: 'AMOUNT_REQUIRED', message: 'Enter an amount greater than 0.' });
    if (dto.kind === 'payment' && dto.principal > outstanding) {
      throw new BadRequestException({ code: 'OVERPAYMENT', message: 'Principal is more than the outstanding loan balance.' });
    }
    return {
      kind: dto.kind,
      principal: dto.principal,
      interest,
      txn_date: dto.date,
      // Charges are added to the loan itself; no cash or bank is involved.
      bank_account_id: dto.kind === 'charge' ? null : await resolveBankAccount(this.db, firmId, 'bank', dto.bankAccountId),
      description: dto.description ?? null,
    };
  }

  async addTransaction(firmId: string, loanId: string, dto: CreateLoanTransactionDto) {
    const loan = await this.get(firmId, loanId);
    await assertBooksOpen(this.db, firmId, dto.date);
    const row = await this.db
      .insertInto('loan_transactions')
      .values({ firm_id: firmId, loan_id: loanId, ...(await this.txnColumns(firmId, loan.balance ?? 0, dto)) })
      .returning('id')
      .executeTakeFirstOrThrow();
    return { id: row.id };
  }

  private async getTransaction(firmId: string, id: string) {
    const t = await this.db.selectFrom('loan_transactions').selectAll().where('id', '=', id).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
    if (!t) throw new NotFoundException({ code: 'LOAN_TXN_NOT_FOUND', message: 'Loan transaction not found.' });
    return t;
  }

  async updateTransaction(firmId: string, id: string, dto: CreateLoanTransactionDto) {
    const t = await this.getTransaction(firmId, id);
    await assertBooksOpen(this.db, firmId, t.txn_date, dto.date);
    const loan = await this.get(firmId, t.loan_id);
    const effect = t.kind === 'payment' ? -Number(t.principal) : Number(t.principal);
    await this.db.updateTable('loan_transactions').set(await this.txnColumns(firmId, r2((loan.balance ?? 0) - effect), dto)).where('id', '=', id).execute();
    return { id };
  }

  async removeTransaction(firmId: string, id: string) {
    await assertBooksOpen(this.db, firmId, (await this.getTransaction(firmId, id)).txn_date);
    const res = await this.db
      .updateTable('loan_transactions')
      .set({ deleted_at: new Date() })
      .where('id', '=', id)
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .executeTakeFirst();
    if (!res.numUpdatedRows) throw new NotFoundException({ code: 'LOAN_TXN_NOT_FOUND', message: 'Loan transaction not found.' });
  }

  private async columns(firmId: string, dto: UpdateLoanDto) {
    return {
      lender: dto.lender,
      account_number: dto.accountNumber,
      opening_balance: dto.openingBalance,
      balance_date: dto.balanceDate,
      bank_account_id: dto.bankAccountId === undefined ? undefined : await resolveBankAccount(this.db, firmId, 'bank', dto.bankAccountId),
      interest_rate: dto.interestRate,
      term_months: dto.termMonths,
      description: dto.description,
    };
  }

  private async assertNameFree(firmId: string, name: string, exceptId?: string) {
    const dup = await this.db
      .selectFrom('loan_accounts')
      .select('id')
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .where(sql`lower(name)`, '=', name.toLowerCase())
      .$if(!!exceptId, (q) => q.where('id', '!=', exceptId!))
      .executeTakeFirst();
    if (dup) throw new ConflictException({ code: 'LOAN_EXISTS', message: 'A loan account with this name already exists.' });
  }
}
