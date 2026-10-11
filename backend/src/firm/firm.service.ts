import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Selectable, sql } from 'kysely';
import { assertOwnFile } from '../common/own-file';
import type { JwtPayload } from '../auth/jwt.strategy';
import { Scope, scopeOf } from '../auth/scope';
import { Db, KYSELY } from '../database/database.module';
import { FirmsTable } from '../database/schema';
import { UpdateFirmDto } from './firm.dto';
import { FirmSettings, withDefaults } from './firm-settings';

const toApi = (f: Selectable<FirmsTable>) => ({
  id: f.id,
  name: f.name,
  phone: f.phone,
  gstin: f.gstin,
  email: f.email,
  booksStartDate: f.books_start_date,
  businessType: f.business_type,
  businessCategory: f.business_category,
  stateCode: f.state_code,
  pincode: f.pincode,
  address: f.address,
  logoFileId: f.logo_file_id,
  signatureFileId: f.signature_file_id,
  booksLockDate: f.books_lock_date,
  settings: withDefaults(f.settings),
});

@Injectable()
export class FirmService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  async get(firmId: string) {
    const firm = await this.db.selectFrom('firms').selectAll().where('id', '=', firmId).executeTakeFirst();
    if (!firm) throw new NotFoundException();
    return toApi(firm);
  }

  async settings(firmId: string): Promise<FirmSettings> {
    return (await this.get(firmId)).settings;
  }

  /** Whose data [user] may see: salesmen are limited to their own unless the business allows more. */
  async scope(user: JwtPayload): Promise<Scope> {
    return user.role === 'salesman' ? scopeOf(user, await this.settings(user.firmId)) : {};
  }

  async update(firmId: string, dto: UpdateFirmDto) {
    await assertOwnFile(this.db, firmId, dto.logoFileId);
    await assertOwnFile(this.db, firmId, dto.signatureFileId);
    const firm = await this.db
      .updateTable('firms')
      .set({
        name: dto.name?.trim(),
        phone: dto.phone,
        gstin: dto.gstin,
        email: dto.email,
        books_start_date: dto.booksStartDate,
        business_type: dto.businessType,
        business_category: dto.businessCategory,
        state_code: dto.stateCode,
        pincode: dto.pincode,
        address: dto.address,
        logo_file_id: dto.logoFileId,
        signature_file_id: dto.signatureFileId,
        // Merge: only the keys sent change (undefined keys are dropped by JSON.stringify).
        settings: dto.settings ? sql`settings || ${JSON.stringify(dto.settings)}::jsonb` : undefined,
        updated_at: new Date(),
      })
      .where('id', '=', firmId)
      .returningAll()
      .executeTakeFirstOrThrow();
    return toApi(firm);
  }
}
