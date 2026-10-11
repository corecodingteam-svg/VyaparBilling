import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { sql, Transaction } from 'kysely';
import { resolveBankAccount } from '../common/bank-account';
import { assertBooksOpen } from '../common/books-lock';
import { num } from '../common/numbers';
import { r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { Database } from '../database/schema';
import { CurrencyDto, LedgerAccountDto, SaveJournalDto } from './accounting.dto';

const isUniqueViolation = (e: unknown) => (e as { code?: string })?.code === '23505';

@Injectable()
export class AccountingService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  // ---------------------------------------------------------------- ledger accounts

  /** Own ledger accounts with their balance (debits − credits). */
  async ledgerAccounts(firmId: string) {
    const rows = await this.db
      .selectFrom('ledger_accounts as a')
      .select(['a.id', 'a.name', 'a.type'])
      .select(
        sql<string>`coalesce((select sum(jl.debit - jl.credit) from journal_lines jl join journal_entries e on e.id = jl.entry_id
                               where jl.ledger_account_id = a.id and e.deleted_at is null), 0)`.as('balance'),
      )
      .where('a.firm_id', '=', firmId)
      .where('a.deleted_at', 'is', null)
      .orderBy(sql`lower(a.name)`)
      .execute();
    return rows.map((a) => ({ id: a.id, name: a.name, type: a.type, balance: Number(a.balance) }));
  }

  async saveLedgerAccount(firmId: string, dto: LedgerAccountDto, id?: string) {
    try {
      if (id) {
        const res = await this.db.updateTable('ledger_accounts').set({ name: dto.name, type: dto.type }).where('id', '=', id).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
        if (!res.numUpdatedRows) throw new NotFoundException({ code: 'ACCOUNT_NOT_FOUND', message: 'Account not found.' });
      } else {
        await this.db.insertInto('ledger_accounts').values({ firm_id: firmId, name: dto.name, type: dto.type }).execute();
      }
    } catch (e) {
      if (isUniqueViolation(e)) throw new ConflictException({ code: 'ACCOUNT_EXISTS', message: 'An account with this name already exists.' });
      throw e;
    }
    return this.ledgerAccounts(firmId);
  }

  async deleteLedgerAccount(firmId: string, id: string) {
    const used = await this.db
      .selectFrom('journal_lines as jl')
      .innerJoin('journal_entries as e', 'e.id', 'jl.entry_id')
      .select('jl.id')
      .where('jl.ledger_account_id', '=', id)
      .where('e.deleted_at', 'is', null)
      .executeTakeFirst();
    if (used) throw new ConflictException({ code: 'ACCOUNT_IN_USE', message: 'This account has journal entries. Delete them first.' });
    const res = await this.db.updateTable('ledger_accounts').set({ deleted_at: new Date() }).where('id', '=', id).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
    if (!res.numUpdatedRows) throw new NotFoundException({ code: 'ACCOUNT_NOT_FOUND', message: 'Account not found.' });
  }

  // ---------------------------------------------------------------- journal entries

  async journals(firmId: string, from?: string, to?: string) {
    let q = this.db
      .selectFrom('journal_entries as e')
      .select(['e.id', 'e.number', 'e.entry_date', 'e.description'])
      .select(sql<string>`(select coalesce(sum(jl.debit), 0) from journal_lines jl where jl.entry_id = e.id)`.as('amount'))
      .where('e.firm_id', '=', firmId)
      .where('e.deleted_at', 'is', null);
    if (from) q = q.where('e.entry_date', '>=', from);
    if (to) q = q.where('e.entry_date', '<=', to);
    const rows = await q.orderBy('e.entry_date', 'desc').orderBy('e.created_at', 'desc').execute();
    return rows.map((e) => ({ id: e.id, number: e.number, date: e.entry_date, description: e.description, amount: Number(e.amount) }));
  }

  async nextJournalNumber(firmId: string) {
    const row = await this.db
      .selectFrom('journal_entries')
      .select(sql<string>`coalesce(max(number::bigint), 0) + 1`.as('next'))
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .where(sql<boolean>`number ~ '^[0-9]{1,15}$'`)
      .executeTakeFirstOrThrow();
    return { number: String(row.next) };
  }

  async journal(firmId: string, id: string) {
    const e = await this.db.selectFrom('journal_entries').selectAll().where('id', '=', id).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
    if (!e) throw new NotFoundException({ code: 'JOURNAL_NOT_FOUND', message: 'Journal entry not found.' });
    const lines = await this.db
      .selectFrom('journal_lines as jl')
      .leftJoin('ledger_accounts as a', 'a.id', 'jl.ledger_account_id')
      .leftJoin('bank_accounts as b', 'b.id', 'jl.bank_account_id')
      .select(['jl.ledger_account_id', 'jl.money_account', 'jl.bank_account_id', 'jl.debit', 'jl.credit', 'a.name as account_name', 'b.name as bank_name'])
      .where('jl.entry_id', '=', id)
      .orderBy('jl.sort_order')
      .execute();
    return {
      id: e.id,
      number: e.number,
      date: e.entry_date,
      description: e.description,
      amount: r2(lines.reduce((s, l) => s + Number(l.debit), 0)),
      lines: lines.map((l) => ({
        ledgerAccountId: l.ledger_account_id,
        moneyAccount: l.money_account,
        bankAccountId: l.bank_account_id,
        accountName: l.account_name ?? l.bank_name ?? 'Cash',
        debit: num(l.debit),
        credit: num(l.credit),
      })),
    };
  }

  async createJournal(firmId: string, dto: SaveJournalDto) {
    await assertBooksOpen(this.db, firmId, dto.date);
    await this.assertNumberFree(firmId, dto.number);
    const id = await this.db.transaction().execute(async (trx) => {
      const row = await trx
        .insertInto('journal_entries')
        .values({ firm_id: firmId, number: dto.number, entry_date: dto.date, description: dto.description ?? null })
        .returning('id')
        .executeTakeFirstOrThrow();
      await this.writeLines(trx, firmId, row.id, dto);
      return row.id;
    });
    return this.journal(firmId, id);
  }

  async updateJournal(firmId: string, id: string, dto: SaveJournalDto) {
    const current = await this.journal(firmId, id);
    await assertBooksOpen(this.db, firmId, current.date, dto.date);
    await this.assertNumberFree(firmId, dto.number, id);
    await this.db.transaction().execute(async (trx) => {
      await trx.updateTable('journal_entries').set({ number: dto.number, entry_date: dto.date, description: dto.description ?? null }).where('id', '=', id).execute();
      await trx.deleteFrom('journal_lines').where('entry_id', '=', id).execute();
      await this.writeLines(trx, firmId, id, dto);
    });
    return this.journal(firmId, id);
  }

  async deleteJournal(firmId: string, id: string) {
    await assertBooksOpen(this.db, firmId, (await this.journal(firmId, id)).date);
    await this.db.updateTable('journal_entries').set({ deleted_at: new Date() }).where('id', '=', id).execute();
  }

  private async assertNumberFree(firmId: string, number: string, exceptId?: string) {
    const dup = await this.db
      .selectFrom('journal_entries')
      .select('id')
      .where('firm_id', '=', firmId)
      .where('number', '=', number)
      .where('deleted_at', 'is', null)
      .$if(!!exceptId, (q) => q.where('id', '!=', exceptId!))
      .executeTakeFirst();
    if (dup) throw new ConflictException({ code: 'NUMBER_TAKEN', message: `Journal number ${number} is already used.` });
  }

  /** Every line sits on exactly one account and one side, and the two sides must be equal. */
  private async writeLines(trx: Transaction<Database>, firmId: string, entryId: string, dto: SaveJournalDto) {
    const rows = [];
    for (const [i, l] of dto.lines.entries()) {
      const debit = l.debit ?? 0;
      const credit = l.credit ?? 0;
      if ((debit > 0) === (credit > 0)) {
        throw new BadRequestException({ code: 'BAD_LINE', message: `Line ${i + 1}: enter either a debit or a credit amount.` });
      }
      let ledgerId: string | null = null;
      let bankId: string | null = null;
      if (l.ledgerAccountId) {
        const account = await trx.selectFrom('ledger_accounts').select('id').where('id', '=', l.ledgerAccountId).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
        if (!account) throw new BadRequestException({ code: 'ACCOUNT_NOT_FOUND', message: `Line ${i + 1}: the account no longer exists.` });
        ledgerId = account.id;
      } else if (l.moneyAccount === 'bank') {
        bankId = await resolveBankAccount(trx, firmId, 'bank', l.bankAccountId);
        if (!bankId) throw new BadRequestException({ code: 'BANK_ACCOUNT_REQUIRED', message: `Line ${i + 1}: select a bank account.` });
      } else if (l.moneyAccount !== 'cash') {
        throw new BadRequestException({ code: 'ACCOUNT_REQUIRED', message: `Line ${i + 1}: select an account.` });
      }
      rows.push({
        firm_id: firmId, entry_id: entryId, ledger_account_id: ledgerId, money_account: ledgerId ? null : l.moneyAccount!, bank_account_id: bankId,
        debit, credit, sort_order: i,
      });
    }
    const debits = r2(rows.reduce((s, r) => s + r.debit, 0));
    const credits = r2(rows.reduce((s, r) => s + r.credit, 0));
    if (debits !== credits) {
      throw new BadRequestException({ code: 'UNBALANCED', message: `Debits (${debits}) and credits (${credits}) must be equal.` });
    }
    await trx.insertInto('journal_lines').values(rows).execute();
  }

  // ---------------------------------------------------------------- currencies

  async currencies(firmId: string) {
    const rows = await this.db.selectFrom('currencies').selectAll().where('firm_id', '=', firmId).orderBy('code').execute();
    return rows.map((c) => ({ id: c.id, code: c.code, symbol: c.symbol, rate: Number(c.rate) }));
  }

  /** Adds the currency or updates its symbol and rate. */
  async saveCurrency(firmId: string, dto: CurrencyDto) {
    await this.db
      .insertInto('currencies')
      .values({ firm_id: firmId, code: dto.code, symbol: dto.symbol, rate: dto.rate })
      .onConflict((oc) => oc.columns(['firm_id', 'code']).doUpdateSet({ symbol: dto.symbol, rate: dto.rate, updated_at: new Date() }))
      .execute();
    return this.currencies(firmId);
  }

  async deleteCurrency(firmId: string, id: string) {
    const res = await this.db.deleteFrom('currencies').where('id', '=', id).where('firm_id', '=', firmId).executeTakeFirst();
    if (!res.numDeletedRows) throw new NotFoundException({ code: 'CURRENCY_NOT_FOUND', message: 'Currency not found.' });
  }
}
