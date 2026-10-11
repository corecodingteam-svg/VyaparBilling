import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Selectable, sql } from 'kysely';
import { assertOwnFile } from '../common/own-file';
import { num, today } from '../common/numbers';
import { Db, KYSELY } from '../database/database.module';
import { ItemsTable } from '../database/schema';
import { AdjustStockDto, BulkItemChangeDto, CreateItemDto, ImportItemDto, UpdateItemDto } from './item.dto';

type ItemRow = Selectable<ItemsTable> & { category_name: string | null };

const toApi = (i: ItemRow) => ({
  id: i.id,
  type: i.type,
  name: i.name,
  hsnCode: i.hsn_code,
  unit: i.unit,
  categoryId: i.category_id,
  categoryName: i.category_name,
  itemCode: i.item_code,
  salePrice: num(i.sale_price),
  salePriceIncludesTax: i.sale_price_includes_tax,
  saleDiscount: num(i.sale_discount),
  saleDiscountType: i.sale_discount_type,
  wholesalePrice: num(i.wholesale_price),
  wholesaleMinQty: num(i.wholesale_min_qty),
  purchasePrice: num(i.purchase_price),
  purchasePriceIncludesTax: i.purchase_price_includes_tax,
  gstRate: num(i.gst_rate),
  openingQty: num(i.opening_qty),
  openingPrice: num(i.opening_price),
  openingDate: i.opening_date,
  minStock: num(i.min_stock),
  location: i.location,
  imageFileId: i.image_file_id,
  cessRate: num(i.cess_rate),
  mrp: num(i.mrp),
  serviceReminderDays: i.service_reminder_days,
  stockQty: num(i.stock_qty),
  stockValue: Math.round(Number(i.stock_qty) * Number(i.purchase_price) * 100) / 100,
  lowStock: i.type === 'product' && i.min_stock !== null && Number(i.stock_qty) <= Number(i.min_stock),
});

@Injectable()
export class ItemsService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  private base(firmId: string) {
    return this.db
      .selectFrom('items')
      .leftJoin('categories', 'categories.id', 'items.category_id')
      .selectAll('items')
      .select('categories.name as category_name')
      .where('items.firm_id', '=', firmId)
      .where('items.deleted_at', 'is', null);
  }

  async list(firmId: string, opts: { type?: string; search?: string; categoryId?: string }) {
    let q = this.base(firmId);
    if (opts.type === 'product' || opts.type === 'service') q = q.where('items.type', '=', opts.type);
    if (opts.categoryId) q = q.where('items.category_id', '=', opts.categoryId);
    if (opts.search?.trim()) {
      const term = `%${opts.search.trim()}%`;
      q = q.where((eb) => eb.or([eb('items.name', 'ilike', term), eb('items.item_code', 'ilike', term)]));
    }
    return (await q.orderBy(sql`lower(items.name)`).execute()).map(toApi);
  }

  async get(firmId: string, id: string) {
    return toApi(await this.find(firmId, id));
  }

  async movements(firmId: string, id: string) {
    await this.find(firmId, id);
    const rows = await this.db
      .selectFrom('stock_movements as m')
      .leftJoin('invoices as i', 'i.id', 'm.invoice_id')
      .selectAll('m')
      .select(['i.number as ref_number', 'i.party_name'])
      .where('m.item_id', '=', id)
      .orderBy('m.movement_date', 'desc')
      .orderBy(sql`m.type = 'opening'`) // opening stock sorts below other movements on the same day
      .orderBy('m.created_at', 'desc')
      .execute();
    return rows.map((m) => ({
      id: m.id,
      type: m.type,
      invoiceId: m.invoice_id,
      reference: m.ref_number,
      partyName: m.party_name,
      quantity: num(m.qty_change),
      pricePerUnit: num(m.price_per_unit),
      date: m.movement_date,
      notes: m.notes,
    }));
  }

  async create(firmId: string, dto: CreateItemDto) {
    await this.assertCodeFree(firmId, dto.itemCode);
    await assertOwnFile(this.db, firmId, dto.imageFileId);
    const isProduct = (dto.type ?? 'product') === 'product';
    const openingQty = isProduct ? (dto.openingQty ?? 0) : 0;
    const openingDate = dto.openingDate ?? today();

    const id = await this.db.transaction().execute(async (trx) => {
      const item = await trx
        .insertInto('items')
        .values({
          firm_id: firmId,
          ...this.columns(dto),
          name: dto.name,
          opening_qty: openingQty,
          opening_date: openingDate,
          stock_qty: openingQty,
        })
        .returning('id')
        .executeTakeFirstOrThrow();
      if (openingQty !== 0) {
        await trx
          .insertInto('stock_movements')
          .values({
            firm_id: firmId, item_id: item.id, type: 'opening', qty_change: openingQty,
            price_per_unit: dto.openingPrice ?? null, movement_date: openingDate,
          })
          .execute();
      }
      return item.id;
    });
    return this.get(firmId, id);
  }

  async update(firmId: string, id: string, dto: UpdateItemDto) {
    const current = await this.find(firmId, id);
    if (dto.itemCode !== undefined) await this.assertCodeFree(firmId, dto.itemCode, id);
    await assertOwnFile(this.db, firmId, dto.imageFileId);
    const isProduct = (dto.type ?? current.type) === 'product';

    await this.db.transaction().execute(async (trx) => {
      const newOpening = isProduct ? (dto.openingQty ?? Number(current.opening_qty)) : 0;
      const delta = newOpening - Number(current.opening_qty);
      const openingDate = dto.openingDate ?? current.opening_date;

      await trx
        .updateTable('items')
        .set({
          ...this.columns(dto),
          name: dto.name,
          opening_qty: newOpening,
          opening_date: openingDate,
          stock_qty: sql`stock_qty + ${delta}`,
          updated_at: new Date(),
        })
        .where('id', '=', id)
        .execute();

      // Keep the single "opening" movement in sync with the item's opening stock.
      // (Opening stock carried into other stores or batches by a year-end is separate and left alone.)
      await trx.deleteFrom('stock_movements').where('item_id', '=', id).where('type', '=', 'opening').where('godown_id', 'is', null).where('batch_no', 'is', null).execute();
      if (newOpening !== 0) {
        await trx
          .insertInto('stock_movements')
          .values({
            firm_id: firmId, item_id: id, type: 'opening', qty_change: newOpening,
            price_per_unit: dto.openingPrice !== undefined ? dto.openingPrice : current.opening_price,
            movement_date: openingDate,
          })
          .execute();
      }
    });
    return this.get(firmId, id);
  }

  /**
   * Creates many items. Rows are independent: a bad row (duplicate name or code) is reported with
   * its position and the rest are still imported. Categories are matched by name and created if new.
   */
  async import(firmId: string, rows: ImportItemDto[]) {
    const categories = new Map(
      (await this.db.selectFrom('categories').select(['id', 'name']).where('firm_id', '=', firmId).execute()).map((c) => [c.name.toLowerCase(), c.id]),
    );
    const existing = new Set(
      (await this.db.selectFrom('items').select('name').where('firm_id', '=', firmId).where('deleted_at', 'is', null).execute()).map((i) => i.name.toLowerCase()),
    );
    const errors: Array<{ row: number; name: string; message: string }> = [];
    let created = 0;
    for (const [index, row] of rows.entries()) {
      const { categoryName, ...item } = row;
      try {
        if (existing.has(item.name.toLowerCase())) throw new ConflictException({ message: 'An item with this name already exists.' });
        if (categoryName) {
          const key = categoryName.toLowerCase();
          if (!categories.has(key)) {
            const cat = await this.db.insertInto('categories').values({ firm_id: firmId, name: categoryName }).returning('id').executeTakeFirstOrThrow();
            categories.set(key, cat.id);
          }
          item.categoryId = categories.get(key);
        }
        await this.create(firmId, item);
        existing.add(item.name.toLowerCase());
        created++;
      } catch (e) {
        const res = (e as { getResponse?: () => unknown }).getResponse?.() as { message?: string } | undefined;
        errors.push({ row: index + 1, name: item.name, message: res?.message ?? 'Could not import this row.' });
      }
    }
    return { created, errors };
  }

  /** Applies price / tax / minimum-stock changes to many items in one transaction. */
  async bulkUpdate(firmId: string, changes: BulkItemChangeDto[]) {
    const ids = changes.map((c) => c.id);
    const found = await this.db.selectFrom('items').select('id').where('firm_id', '=', firmId).where('deleted_at', 'is', null).where('id', 'in', ids).execute();
    if (found.length !== new Set(ids).size) throw new BadRequestException({ code: 'ITEM_NOT_FOUND', message: 'One of the items no longer exists.' });
    await this.db.transaction().execute(async (trx) => {
      for (const c of changes) {
        await trx
          .updateTable('items')
          .set({ sale_price: c.salePrice, purchase_price: c.purchasePrice, gst_rate: c.gstRate, min_stock: c.minStock, updated_at: new Date() })
          .where('id', '=', c.id)
          .execute();
      }
    });
    return { updated: changes.length };
  }

  async adjust(firmId: string, id: string, dto: AdjustStockDto) {
    const item = await this.find(firmId, id);
    if (item.type !== 'product') {
      throw new BadRequestException({ code: 'NOT_A_PRODUCT', message: 'Stock can only be adjusted for products.' });
    }
    const change = dto.type === 'add' ? dto.quantity : -dto.quantity;
    await this.db.transaction().execute(async (trx) => {
      await trx
        .insertInto('stock_movements')
        .values({
          firm_id: firmId, item_id: id, type: dto.type, qty_change: change,
          price_per_unit: dto.pricePerUnit ?? null, movement_date: dto.date, notes: dto.notes ?? null,
          godown_id: dto.godownId ?? null, batch_no: dto.batchNo ?? null, expiry_date: dto.expiryDate ?? null,
        })
        .execute();
      await trx.updateTable('items').set({ stock_qty: sql`stock_qty + ${change}`, updated_at: new Date() }).where('id', '=', id).execute();
    });
    return this.get(firmId, id);
  }

  async remove(firmId: string, id: string) {
    await this.find(firmId, id);
    await this.db.updateTable('items').set({ deleted_at: new Date() }).where('id', '=', id).execute();
  }

  /** Stock of the item per batch (and store), from its movements. Batches with nothing left are left out. */
  async batches(firmId: string, id: string, godownId?: string | null) {
    await this.find(firmId, id);
    let q = this.db
      .selectFrom('stock_movements as m')
      .select(['m.batch_no', sql<string | null>`max(m.expiry_date)`.as('expiry_date'), sql<string>`sum(m.qty_change)`.as('qty')])
      .select(
        sql<string | null>`(select max(ii.mrp) from invoice_items ii join invoices i on i.id = ii.invoice_id
                             where ii.item_id = ${id} and ii.batch_no = m.batch_no and i.deleted_at is null)`.as('mrp'),
      )
      .where('m.item_id', '=', id)
      .where('m.batch_no', 'is not', null);
    if (godownId !== undefined) q = godownId === null ? q.where('m.godown_id', 'is', null) : q.where('m.godown_id', '=', godownId);
    const rows = await q.groupBy('m.batch_no').having(sql`sum(m.qty_change)`, '>', 0).orderBy(sql`max(m.expiry_date) nulls last`).execute();
    return rows.map((b) => ({ batchNo: b.batch_no!, expiryDate: b.expiry_date, mrp: num(b.mrp), quantity: Number(b.qty) }));
  }

  /** Serial numbers of the item that are in stock: bought (or returned by a customer) and not sold since. */
  async serials(firmId: string, id: string) {
    await this.find(firmId, id);
    const lines = await this.db
      .selectFrom('invoice_items as ii')
      .innerJoin('invoices as i', 'i.id', 'ii.invoice_id')
      .select(['ii.serial_nos', 'i.type'])
      .where('i.firm_id', '=', firmId)
      .where('i.deleted_at', 'is', null)
      .where('i.type', 'in', ['sale', 'purchase', 'credit_note', 'debit_note'])
      .where('ii.item_id', '=', id)
      .where('ii.serial_nos', 'is not', null)
      .execute();
    const net = new Map<string, number>();
    for (const l of lines) {
      const sign = l.type === 'purchase' || l.type === 'credit_note' ? 1 : -1;
      for (const serial of (l.serial_nos ?? '').split(',').map((v) => v.trim()).filter(Boolean)) net.set(serial, (net.get(serial) ?? 0) + sign);
    }
    return [...net.entries()].filter(([, n]) => n > 0).map(([serial]) => serial).sort();
  }

  /** The item's stock in each store that has any. */
  async stockByGodown(firmId: string, id: string) {
    await this.find(firmId, id);
    const rows = await this.db
      .selectFrom('stock_movements as m')
      .leftJoin('godowns as g', 'g.id', 'm.godown_id')
      .select(['m.godown_id', sql<string>`coalesce(g.name, 'Main Store')`.as('name'), sql<string>`sum(m.qty_change)`.as('qty')])
      .where('m.item_id', '=', id)
      .groupBy(['m.godown_id', 'g.name'])
      .execute();
    return rows.map((r) => ({ godownId: r.godown_id, name: r.name, quantity: Number(r.qty) })).filter((r) => r.quantity !== 0);
  }

  private columns(dto: UpdateItemDto) {
    return {
      type: dto.type,
      hsn_code: dto.hsnCode,
      unit: dto.unit,
      category_id: dto.categoryId,
      item_code: dto.itemCode,
      sale_price: dto.salePrice,
      sale_price_includes_tax: dto.salePriceIncludesTax,
      sale_discount: dto.saleDiscount,
      sale_discount_type: dto.saleDiscountType,
      wholesale_price: dto.wholesalePrice,
      wholesale_min_qty: dto.wholesaleMinQty,
      purchase_price: dto.purchasePrice,
      purchase_price_includes_tax: dto.purchasePriceIncludesTax,
      gst_rate: dto.gstRate,
      opening_price: dto.openingPrice,
      min_stock: dto.minStock,
      location: dto.location,
      image_file_id: dto.imageFileId,
      cess_rate: dto.cessRate,
      mrp: dto.mrp,
      service_reminder_days: dto.serviceReminderDays,
    };
  }

  private async find(firmId: string, id: string): Promise<ItemRow> {
    const item = await this.base(firmId).where('items.id', '=', id).executeTakeFirst();
    if (!item) throw new NotFoundException({ code: 'ITEM_NOT_FOUND', message: 'Item not found.' });
    return item;
  }

  private async assertCodeFree(firmId: string, code: string | null | undefined, exceptId?: string) {
    if (!code) return;
    let q = this.db
      .selectFrom('items')
      .select('id')
      .where('firm_id', '=', firmId)
      .where('deleted_at', 'is', null)
      .where('item_code', '=', code);
    if (exceptId) q = q.where('id', '!=', exceptId);
    if (await q.executeTakeFirst()) {
      throw new ConflictException({ code: 'ITEM_CODE_EXISTS', message: 'Another item already uses this item code.' });
    }
  }
}
