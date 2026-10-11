import {
  BadRequestException, Body, ConflictException, Controller, Delete, Get, HttpCode, Inject, Injectable, Module, NotFoundException, Param, ParseUUIDPipe,
  Post, Put, UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsDateString, IsNumber, IsOptional, IsPositive, IsString, IsUUID, Max, MaxLength, MinLength, ValidateIf } from 'class-validator';
import { sql } from 'kysely';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { assertBooksOpen } from '../common/books-lock';
import { r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { emptyToNull } from '../firm/firm.dto';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class GodownDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(1) @MaxLength(60)
  name: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(300)
  address?: string | null;
}

export class StockTransferDto {
  @ApiProperty() @IsUUID()
  itemId: string;

  @ApiPropertyOptional({ description: 'null = main store' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  fromGodownId?: string | null;

  @ApiPropertyOptional({ description: 'null = main store' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  toGodownId?: string | null;

  @ApiProperty() @IsNumber({ maxDecimalPlaces: 3 }) @IsPositive() @Max(1e9)
  quantity: number;

  @ApiProperty() @IsDateString()
  date: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(40)
  batchNo?: string | null;
}

@Injectable()
export class GodownsService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  /** The main store first, then every godown, each with how many items it holds and their value at purchase price. */
  async list(firmId: string) {
    const godowns = await this.db.selectFrom('godowns').select(['id', 'name', 'address']).where('firm_id', '=', firmId).where('deleted_at', 'is', null).orderBy(sql`lower(name)`).execute();
    const stock = await sql<{ godown_id: string | null; items: string; value: string }>`
      select q.godown_id, count(*) filter (where q.qty <> 0) as items, coalesce(sum(q.qty * i.purchase_price), 0) as value
        from (select m.godown_id, m.item_id, sum(m.qty_change) as qty from stock_movements m where m.firm_id = ${firmId} group by m.godown_id, m.item_id) q
        join items i on i.id = q.item_id and i.deleted_at is null and i.type = 'product'
       group by q.godown_id`.execute(this.db);
    const of = (id: string | null) => stock.rows.find((r) => r.godown_id === id);
    return [
      { id: null as string | null, name: 'Main Store', address: null as string | null, itemCount: Number(of(null)?.items ?? 0), stockValue: r2(Number(of(null)?.value ?? 0)) },
      ...godowns.map((g) => ({ id: g.id as string | null, name: g.name, address: g.address, itemCount: Number(of(g.id)?.items ?? 0), stockValue: r2(Number(of(g.id)?.value ?? 0)) })),
    ];
  }

  /** What one store holds. [id] null = the main store. */
  async stock(firmId: string, id: string | null) {
    if (id) await this.find(firmId, id);
    const rows = await sql<{ id: string; name: string; unit: string | null; qty: string; purchase_price: string }>`
      select i.id, i.name, i.unit, sum(m.qty_change) as qty, i.purchase_price
        from stock_movements m join items i on i.id = m.item_id
       where m.firm_id = ${firmId} and i.deleted_at is null and i.type = 'product'
         and ${id === null ? sql`m.godown_id is null` : sql`m.godown_id = ${id}`}
       group by i.id having sum(m.qty_change) <> 0 order by lower(i.name)`.execute(this.db);
    return rows.rows.map((r) => ({ itemId: r.id, name: r.name, unit: r.unit, quantity: Number(r.qty), value: r2(Number(r.qty) * Number(r.purchase_price)) }));
  }

  private async find(firmId: string, id: string) {
    const g = await this.db.selectFrom('godowns').select(['id', 'name']).where('id', '=', id).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
    if (!g) throw new NotFoundException({ code: 'GODOWN_NOT_FOUND', message: 'Godown not found.' });
    return g;
  }

  async save(firmId: string, dto: GodownDto, id?: string) {
    if (dto.name.toLowerCase() === 'main store') throw new ConflictException({ code: 'GODOWN_EXISTS', message: 'The main store already exists.' });
    try {
      if (id) {
        await this.find(firmId, id);
        await this.db.updateTable('godowns').set({ name: dto.name, address: dto.address ?? null }).where('id', '=', id).execute();
      } else {
        await this.db.insertInto('godowns').values({ firm_id: firmId, name: dto.name, address: dto.address ?? null }).execute();
      }
    } catch (e) {
      if ((e as { code?: string })?.code === '23505') throw new ConflictException({ code: 'GODOWN_EXISTS', message: 'A godown with this name already exists.' });
      throw e;
    }
    return this.list(firmId);
  }

  async remove(firmId: string, id: string) {
    await this.find(firmId, id);
    if ((await this.stock(firmId, id)).length) {
      throw new ConflictException({ code: 'GODOWN_HAS_STOCK', message: 'This godown still holds stock. Transfer it out first.' });
    }
    await this.db.updateTable('godowns').set({ deleted_at: new Date() }).where('id', '=', id).execute();
  }

  /** Moves stock from one store to another: one movement out, one in. The item's total stock is unchanged. */
  async transfer(firmId: string, dto: StockTransferDto) {
    const from = dto.fromGodownId ?? null;
    const to = dto.toGodownId ?? null;
    if (from === to) throw new BadRequestException({ code: 'SAME_GODOWN', message: 'Choose two different stores.' });
    await assertBooksOpen(this.db, firmId, dto.date);
    const names = { from: from ? (await this.find(firmId, from)).name : 'Main Store', to: to ? (await this.find(firmId, to)).name : 'Main Store' };
    const item = await this.db.selectFrom('items').select(['id', 'name', 'type']).where('id', '=', dto.itemId).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
    if (!item || item.type !== 'product') throw new BadRequestException({ code: 'ITEM_NOT_FOUND', message: 'Select a product to transfer.' });

    const held = await this.db
      .selectFrom('stock_movements')
      .select(sql<string>`coalesce(sum(qty_change), 0)`.as('qty'))
      .where('item_id', '=', dto.itemId)
      .where((eb) => (from === null ? eb('godown_id', 'is', null) : eb('godown_id', '=', from)))
      .$if(!!dto.batchNo, (q) => q.where('batch_no', '=', dto.batchNo!))
      .executeTakeFirstOrThrow();
    if (Number(held.qty) < dto.quantity) {
      throw new BadRequestException({
        code: 'INSUFFICIENT_STOCK',
        message: `${names.from} has only ${Number(held.qty)} of ${item.name}${dto.batchNo ? ` in batch ${dto.batchNo}` : ''}.`,
      });
    }
    const common = { firm_id: firmId, item_id: dto.itemId, type: 'transfer' as const, movement_date: dto.date, batch_no: dto.batchNo ?? null };
    await this.db
      .insertInto('stock_movements')
      .values([
        { ...common, godown_id: from, qty_change: -dto.quantity, notes: `Transfer to ${names.to}` },
        { ...common, godown_id: to, qty_change: dto.quantity, notes: `Transfer from ${names.from}` },
      ])
      .execute();
    return this.list(firmId);
  }
}

@ApiTags('godowns')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('godowns')
export class GodownsController {
  constructor(private readonly godowns: GodownsService) {}

  /** Readable by everyone: documents pick the store their stock moves through. */
  @Get()
  list(@CurrentUser() u: JwtPayload) {
    return this.godowns.list(u.firmId);
  }

  @Get('main/stock')
  mainStock(@CurrentUser() u: JwtPayload) {
    return this.godowns.stock(u.firmId, null);
  }

  @Get(':id/stock')
  stock(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.godowns.stock(u.firmId, id);
  }

  @Post()
  @Roles(...STAFF)
  create(@CurrentUser() u: JwtPayload, @Body() dto: GodownDto) {
    return this.godowns.save(u.firmId, dto);
  }

  @Post('transfer')
  @HttpCode(200)
  @Roles(...STAFF)
  transfer(@CurrentUser() u: JwtPayload, @Body() dto: StockTransferDto) {
    return this.godowns.transfer(u.firmId, dto);
  }

  @Put(':id')
  @Roles(...STAFF)
  update(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: GodownDto) {
    return this.godowns.save(u.firmId, dto, id);
  }

  @Delete(':id')
  @HttpCode(204)
  @Roles(...STAFF)
  remove(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.godowns.remove(u.firmId, id);
  }
}

@Module({ controllers: [GodownsController], providers: [GodownsService] })
export class GodownsModule {}
