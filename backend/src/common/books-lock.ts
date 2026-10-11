import { BadRequestException } from '@nestjs/common';
import { Kysely, Transaction } from 'kysely';
import { Database } from '../database/schema';

/**
 * Refuses to touch the books on or before the company's lock date ("close books").
 * Pass every date involved: for an edit, both the old and the new date.
 */
export async function assertBooksOpen(db: Kysely<Database> | Transaction<Database>, firmId: string, ...dates: Array<string | null | undefined>) {
  const firm = await db.selectFrom('firms').select('books_lock_date').where('id', '=', firmId).executeTakeFirstOrThrow();
  const lock = firm.books_lock_date;
  if (!lock) return;
  if (dates.some((d) => d && d <= lock)) {
    throw new BadRequestException({
      code: 'BOOKS_LOCKED',
      message: `Books are closed up to ${lock.split('-').reverse().join('/')}. Transactions on or before that date cannot be added or changed.`,
    });
  }
}
