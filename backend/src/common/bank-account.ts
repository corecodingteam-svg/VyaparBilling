import { BadRequestException } from '@nestjs/common';
import { Kysely, Transaction } from 'kysely';
import { Database } from '../database/schema';

/**
 * The bank account a transaction's money moves through. Cash never has one; bank/UPI/card may name
 * one; a cheque gets one only once it is deposited. Returns the validated id or null.
 */
export async function resolveBankAccount(
  db: Kysely<Database> | Transaction<Database>,
  firmId: string,
  paymentMode: string | undefined,
  bankAccountId: string | null | undefined,
): Promise<string | null> {
  if (!bankAccountId || (paymentMode ?? 'cash') === 'cash') return null;
  const account = await db
    .selectFrom('bank_accounts')
    .select('id')
    .where('id', '=', bankAccountId)
    .where('firm_id', '=', firmId)
    .where('deleted_at', 'is', null)
    .executeTakeFirst();
  if (!account) throw new BadRequestException({ code: 'BANK_ACCOUNT_NOT_FOUND', message: 'Selected bank account no longer exists.' });
  return account.id;
}
