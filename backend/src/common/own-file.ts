import { BadRequestException } from '@nestjs/common';
import { Kysely, Transaction } from 'kysely';
import { Database } from '../database/schema';

/** A file id sent by the client must be a file this company uploaded. */
export async function assertOwnFile(db: Kysely<Database> | Transaction<Database>, firmId: string, fileId: string | null | undefined) {
  if (!fileId) return;
  const file = await db.selectFrom('files').select('id').where('id', '=', fileId).where('firm_id', '=', firmId).executeTakeFirst();
  if (!file) throw new BadRequestException({ code: 'FILE_NOT_FOUND', message: 'The uploaded file could not be found. Upload it again.' });
}
