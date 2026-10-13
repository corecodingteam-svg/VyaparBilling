import {
  BadRequestException, Body, Controller, Delete, Get, HttpCode, Inject, Injectable, Module, NotFoundException, Param, ParseUUIDPipe, Post, Put, Query, UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsDateString, IsNumber, IsOptional, IsPositive, IsString, IsUUID, Max, MaxLength, Min, ValidateNested } from 'class-validator';
import { sql, Transaction } from 'kysely';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { assertBooksOpen } from '../common/books-lock';
import { r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { Database } from '../database/schema';
import { FirmService } from '../firm/firm.service';

const n = (v: unknown) => Number(v ?? 0);
const r3 = (v: number) => Math.round((v + Number.EPSILON) * 1000) / 1000;

class BomLineDto {
  @IsUUID() componentId: string;
  @IsNumber({ maxDecimalPlaces: 3 }) @IsPositive() @Max(1e9) quantity: number;
}

class SaveBomDto {
  @IsArray() @ArrayMaxSize(100) @ValidateNested({ each: true }) @Type(() => BomLineDto) lines: BomLineDto[];
}

class ManufactureDto {
  @IsUUID() itemId: string;
  @IsNumber({ maxDecimalPlaces: 3 }) @IsPositive() @Max(1e9) quantity: number;
  @IsDateString() entryDate: string;
  @IsOptional() @IsUUID() godownId?: string | null;
  /** Labour, power and other costs of this run, added to the cost of the components. */
  @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(1e11) extraCost?: number;
  @IsOptional() @IsString() @MaxLength(500) description?: string | null;
}

@Injectable()
export class ManufacturingService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly firms: FirmService,
  ) {}

  private async product(db: Db | Transaction<Database>, firmId: string, id: string) {
    const item = await db.selectFrom('items').select(['id', 'name', 'type', 'unit', 'purchase_price', 'stock_qty']).where('id', '=', id).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
    if (!item) throw new NotFoundException({ code: 'ITEM_NOT_FOUND', message: 'Item not found.' });
    if (item.type !== 'product') throw new BadRequestException({ code: 'NOT_A_PRODUCT', message: `${item.name} is a service; only products can be made or used up.` });
    return item;
  }

  /** The components of an item with what one unit costs to make from them at today's purchase prices. */
  async bom(firmId: string, itemId: string) {
    await this.product(this.db, firmId, itemId);
    const rows = await this.db
      .selectFrom('bom_lines as b').innerJoin('items as c', 'c.id', 'b.component_id')
      .select(['b.component_id', 'b.quantity', 'c.name', 'c.unit', 'c.purchase_price', 'c.stock_qty'])
      .where('b.item_id', '=', itemId).where('b.firm_id', '=', firmId).orderBy('b.sort_order').execute();
    const lines = rows.map((r) => ({ componentId: r.component_id, name: r.name, unit: r.unit, quantity: n(r.quantity), unitCost: n(r.purchase_price), inStock: n(r.stock_qty) }));
    return { lines, costPerUnit: r2(lines.reduce((s, l) => s + l.quantity * l.unitCost, 0)) };
  }

  /** Replaces the item's bill of materials. A component may not, directly or through others, need the item itself. */
  async saveBom(firmId: string, itemId: string, dto: SaveBomDto) {
    await this.product(this.db, firmId, itemId);
    const ids = dto.lines.map((l) => l.componentId);
    if (new Set(ids).size !== ids.length) throw new BadRequestException({ code: 'DUPLICATE_COMPONENT', message: 'A component is listed more than once.' });
    for (const id of ids) {
      if (id === itemId) throw new BadRequestException({ code: 'SELF_COMPONENT', message: 'An item cannot be made from itself.' });
      await this.product(this.db, firmId, id);
    }
    // Walk down from each component; reaching the item again would make a loop (A needs B needs A).
    const all = await this.db.selectFrom('bom_lines').select(['item_id', 'component_id']).where('firm_id', '=', firmId).where('item_id', '!=', itemId).execute();
    const children = new Map<string, string[]>();
    for (const b of all) children.set(b.item_id, [...(children.get(b.item_id) ?? []), b.component_id]);
    const seen = new Set<string>();
    const stack = [...ids];
    while (stack.length) {
      const id = stack.pop()!;
      if (id === itemId) throw new BadRequestException({ code: 'BOM_LOOP', message: 'That would make the item need itself: one of its components is made from it.' });
      if (seen.has(id)) continue;
      seen.add(id);
      stack.push(...(children.get(id) ?? []));
    }
    await this.db.transaction().execute(async (trx) => {
      await trx.deleteFrom('bom_lines').where('item_id', '=', itemId).where('firm_id', '=', firmId).execute();
      if (dto.lines.length) {
        await trx.insertInto('bom_lines').values(dto.lines.map((l, i) => ({ firm_id: firmId, item_id: itemId, component_id: l.componentId, quantity: l.quantity, sort_order: i }))).execute();
      }
    });
    return this.bom(firmId, itemId);
  }

  /** What making [quantity] units needs, against what is in stock. */
  async requirements(firmId: string, itemId: string, quantity: number) {
    const { lines } = await this.bom(firmId, itemId);
    const need = lines.map((l) => ({ ...l, needed: r3(l.quantity * quantity), short: Math.max(0, r3(l.quantity * quantity - l.inStock)) }));
    return { lines: need, canMake: need.every((l) => l.short === 0) };
  }

  private view(e: { id: string; number: string; item_id: string; quantity: unknown; entry_date: string; component_cost: unknown; extra_cost: unknown; description: string | null; name: string; unit: string | null; godown_id: string | null }) {
    const cost = r2(n(e.component_cost) + n(e.extra_cost));
    return {
      id: e.id, number: e.number, itemId: e.item_id, itemName: e.name, unit: e.unit, quantity: n(e.quantity), date: e.entry_date, godownId: e.godown_id,
      componentCost: n(e.component_cost), extraCost: n(e.extra_cost), totalCost: cost, costPerUnit: n(e.quantity) ? r2(cost / n(e.quantity)) : 0, description: e.description,
    };
  }

  async list(firmId: string, from?: string, to?: string) {
    const rows = await this.db
      .selectFrom('manufacture_entries as e').innerJoin('items as i', 'i.id', 'e.item_id')
      .select(['e.id', 'e.number', 'e.item_id', 'e.quantity', 'e.entry_date', 'e.component_cost', 'e.extra_cost', 'e.description', 'e.godown_id', 'i.name', 'i.unit'])
      .where('e.firm_id', '=', firmId).where('e.deleted_at', 'is', null)
      .$if(!!from, (q) => q.where('e.entry_date', '>=', from!)).$if(!!to, (q) => q.where('e.entry_date', '<=', to!))
      .orderBy('e.entry_date', 'desc').orderBy('e.created_at', 'desc').execute();
    return rows.map((r) => this.view(r));
  }

  async get(firmId: string, id: string) {
    const e = (await this.list(firmId)).find((x) => x.id === id);
    if (!e) throw new NotFoundException({ code: 'ENTRY_NOT_FOUND', message: 'Production entry not found.' });
    const used = await this.db
      .selectFrom('stock_movements as m').innerJoin('items as c', 'c.id', 'm.item_id')
      .select(['c.name', 'c.unit', 'm.qty_change', 'm.price_per_unit']).where('m.manufacture_id', '=', id).where('m.type', '=', 'manufacture_out').execute();
    return { ...e, components: used.map((u) => ({ name: u.name, unit: u.unit, quantity: -n(u.qty_change), unitCost: n(u.price_per_unit) })) };
  }

  async nextNumber(firmId: string) {
    const r = await this.db.selectFrom('manufacture_entries').select(sql<string>`coalesce(max(case when number ~ '^[0-9]{1,15}$' then number::bigint end), 0) + 1`.as('next')).where('firm_id', '=', firmId).executeTakeFirstOrThrow();
    return { number: String(r.next) };
  }

  /** Makes [quantity] units: uses up the components and adds the finished goods, at what they cost to make. */
  async make(firmId: string, userId: string, dto: ManufactureDto) {
    await assertBooksOpen(this.db, firmId, dto.entryDate);
    const settings = await this.firms.settings(firmId);
    const id = await this.db.transaction().execute(async (trx) => {
      const item = await this.product(trx, firmId, dto.itemId);
      const rows = await trx
        .selectFrom('bom_lines as b').innerJoin('items as c', 'c.id', 'b.component_id')
        .select(['b.component_id', 'b.quantity', 'c.name', 'c.purchase_price', 'c.stock_qty'])
        .where('b.item_id', '=', dto.itemId).where('b.firm_id', '=', firmId).orderBy('b.sort_order').forUpdate().execute();
      if (!rows.length) throw new BadRequestException({ code: 'NO_BOM', message: `${item.name} has no bill of materials yet. Add its components first.` });
      const used = rows.map((r) => ({ id: r.component_id, name: r.name, qty: r3(n(r.quantity) * dto.quantity), cost: n(r.purchase_price), stock: n(r.stock_qty) }));
      const short = used.filter((u) => u.stock < u.qty);
      if (short.length && settings.blockNegativeStock) {
        throw new BadRequestException({
          code: 'NOT_ENOUGH_STOCK',
          message: `Not enough stock: ${short.map((u) => `${u.name} (need ${u.qty}, have ${u.stock})`).join(', ')}.`,
        });
      }
      const componentCost = r2(used.reduce((s, u) => s + u.qty * u.cost, 0));
      const extra = dto.extraCost ?? 0;
      const { number } = await this.nextNumberIn(trx, firmId);
      const entry = await trx
        .insertInto('manufacture_entries')
        .values({ firm_id: firmId, number, item_id: dto.itemId, quantity: dto.quantity, entry_date: dto.entryDate, godown_id: dto.godownId ?? null, component_cost: componentCost, extra_cost: extra, description: dto.description ?? null, created_by: userId })
        .returning('id').executeTakeFirstOrThrow();
      const move = (itemId: string, type: 'manufacture_in' | 'manufacture_out', qty: number, price: number) =>
        trx.insertInto('stock_movements').values({
          firm_id: firmId, item_id: itemId, type, qty_change: type === 'manufacture_in' ? qty : -qty, price_per_unit: price, movement_date: dto.entryDate,
          godown_id: dto.godownId ?? null, manufacture_id: entry.id, notes: `Production ${number}`,
        }).execute();
      for (const u of used) {
        await move(u.id, 'manufacture_out', u.qty, u.cost);
        await trx.updateTable('items').set({ stock_qty: sql`stock_qty - ${u.qty}`, updated_at: new Date() }).where('id', '=', u.id).execute();
      }
      await move(dto.itemId, 'manufacture_in', dto.quantity, r2((componentCost + extra) / dto.quantity));
      await trx.updateTable('items').set({ stock_qty: sql`stock_qty + ${dto.quantity}`, updated_at: new Date() }).where('id', '=', dto.itemId).execute();
      return entry.id;
    });
    return this.get(firmId, id);
  }

  private async nextNumberIn(trx: Transaction<Database>, firmId: string) {
    const r = await trx.selectFrom('manufacture_entries').select(sql<string>`coalesce(max(case when number ~ '^[0-9]{1,15}$' then number::bigint end), 0) + 1`.as('next')).where('firm_id', '=', firmId).executeTakeFirstOrThrow();
    return { number: String(r.next) };
  }

  /** Undoes a production entry: the components come back and the finished goods go. */
  async remove(firmId: string, id: string) {
    const entry = await this.get(firmId, id);
    await assertBooksOpen(this.db, firmId, entry.date);
    await this.db.transaction().execute(async (trx) => {
      const item = await this.product(trx, firmId, entry.itemId);
      if (n(item.stock_qty) < entry.quantity) {
        throw new BadRequestException({ code: 'ALREADY_SOLD', message: `Only ${n(item.stock_qty)} ${item.name} is in stock, so ${entry.quantity} cannot be taken back out. Some of it has been sold or used.` });
      }
      const moves = await trx.selectFrom('stock_movements').select(['item_id', 'qty_change']).where('manufacture_id', '=', id).execute();
      for (const m of moves) await trx.updateTable('items').set({ stock_qty: sql`stock_qty - ${m.qty_change}`, updated_at: new Date() }).where('id', '=', m.item_id).execute();
      await trx.deleteFrom('stock_movements').where('manufacture_id', '=', id).execute();
      await trx.updateTable('manufacture_entries').set({ deleted_at: new Date() }).where('id', '=', id).execute();
    });
  }
}

@ApiTags('manufacturing')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Roles(...STAFF)
@Controller('manufacturing')
export class ManufacturingController {
  constructor(private readonly m: ManufacturingService) {}

  @Get('bom/:itemId')
  bom(@CurrentUser() u: JwtPayload, @Param('itemId', ParseUUIDPipe) id: string) {
    return this.m.bom(u.firmId, id);
  }

  @Put('bom/:itemId')
  saveBom(@CurrentUser() u: JwtPayload, @Param('itemId', ParseUUIDPipe) id: string, @Body() dto: SaveBomDto) {
    return this.m.saveBom(u.firmId, id, dto);
  }

  @Get('requirements')
  requirements(@CurrentUser() u: JwtPayload, @Query('itemId', ParseUUIDPipe) itemId: string, @Query('quantity') quantity: string) {
    const q = Number(quantity);
    if (!(q > 0)) throw new BadRequestException({ code: 'BAD_QUANTITY', message: 'Give how many to make.' });
    return this.m.requirements(u.firmId, itemId, q);
  }

  @Get('next-number')
  nextNumber(@CurrentUser() u: JwtPayload) {
    return this.m.nextNumber(u.firmId);
  }

  @Get('entries')
  list(@CurrentUser() u: JwtPayload, @Query('from') from?: string, @Query('to') to?: string) {
    return this.m.list(u.firmId, from, to);
  }

  @Get('entries/:id')
  get(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.m.get(u.firmId, id);
  }

  @Post('entries')
  make(@CurrentUser() u: JwtPayload, @Body() dto: ManufactureDto) {
    return this.m.make(u.firmId, u.sub, dto);
  }

  @Delete('entries/:id')
  @HttpCode(204)
  remove(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.m.remove(u.firmId, id);
  }
}

@Module({ controllers: [ManufacturingController], providers: [ManufacturingService] })
export class ManufacturingModule {}
