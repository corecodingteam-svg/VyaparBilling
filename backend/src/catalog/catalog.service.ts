import { ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { sql } from 'kysely';
import { Db, KYSELY } from '../database/database.module';
import { CategoryDto, UnitDto } from './catalog.dto';

const isUniqueViolation = (e: unknown) => (e as { code?: string })?.code === '23505';

/** Item categories and units of measure. */
@Injectable()
export class CatalogService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  async categories(firmId: string) {
    const rows = await this.db
      .selectFrom('categories')
      .leftJoin('items', (j) => j.onRef('items.category_id', '=', 'categories.id').on('items.deleted_at', 'is', null))
      .select(['categories.id', 'categories.name', (eb) => eb.fn.count<string>('items.id').as('item_count')])
      .where('categories.firm_id', '=', firmId)
      .groupBy(['categories.id', 'categories.name'])
      .orderBy(sql`lower(categories.name)`)
      .execute();
    return rows.map((r) => ({ id: r.id, name: r.name, itemCount: Number(r.item_count) }));
  }

  async createCategory(firmId: string, dto: CategoryDto) {
    try {
      const row = await this.db.insertInto('categories').values({ firm_id: firmId, name: dto.name }).returning(['id', 'name']).executeTakeFirstOrThrow();
      return { ...row, itemCount: 0 };
    } catch (e) {
      if (isUniqueViolation(e)) throw new ConflictException({ code: 'CATEGORY_EXISTS', message: 'This category already exists.' });
      throw e;
    }
  }

  async renameCategory(firmId: string, id: string, dto: CategoryDto) {
    try {
      const row = await this.db.updateTable('categories').set({ name: dto.name }).where('id', '=', id).where('firm_id', '=', firmId).returning(['id', 'name']).executeTakeFirst();
      if (!row) throw new NotFoundException();
      return row;
    } catch (e) {
      if (isUniqueViolation(e)) throw new ConflictException({ code: 'CATEGORY_EXISTS', message: 'This category already exists.' });
      throw e;
    }
  }

  /** Items in a deleted category become uncategorised (FK is ON DELETE SET NULL). */
  async deleteCategory(firmId: string, id: string) {
    const res = await this.db.deleteFrom('categories').where('id', '=', id).where('firm_id', '=', firmId).executeTakeFirst();
    if (!res.numDeletedRows) throw new NotFoundException();
  }

  async units(firmId: string) {
    const rows = await this.db
      .selectFrom('units')
      .select(['id', 'name', 'short_name'])
      .where('firm_id', '=', firmId)
      .orderBy(sql`lower(name)`)
      .execute();
    return rows.map((r) => ({ id: r.id, name: r.name, shortName: r.short_name }));
  }

  async createUnit(firmId: string, dto: UnitDto) {
    try {
      const r = await this.db.insertInto('units').values({ firm_id: firmId, name: dto.name, short_name: dto.shortName }).returning(['id', 'name', 'short_name']).executeTakeFirstOrThrow();
      return { id: r.id, name: r.name, shortName: r.short_name };
    } catch (e) {
      if (isUniqueViolation(e)) throw new ConflictException({ code: 'UNIT_EXISTS', message: 'A unit with this short name already exists.' });
      throw e;
    }
  }

  async deleteUnit(firmId: string, id: string) {
    const unit = await this.db.selectFrom('units').select('short_name').where('id', '=', id).where('firm_id', '=', firmId).executeTakeFirst();
    if (!unit) throw new NotFoundException();
    const inUse = await this.db.selectFrom('items').select('id').where('firm_id', '=', firmId).where('deleted_at', 'is', null).where('unit', '=', unit.short_name).executeTakeFirst();
    if (inUse) throw new ConflictException({ code: 'UNIT_IN_USE', message: 'This unit is used by items and cannot be deleted.' });
    await this.db.deleteFrom('units').where('id', '=', id).execute();
  }
}
