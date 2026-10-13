import {
  BadRequestException, Body, ConflictException, Controller, Get, Header, HttpCode, Inject, Injectable, Module, NotFoundException, Param, Post, Put, Query, Req, Res, UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsInt, IsNumber, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min, MinLength, ValidateNested } from 'class-validator';
import { sql } from 'kysely';
import type { Request, Response } from 'express';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { ADMINS, Roles, STAFF } from '../auth/roles';
import { today } from '../common/numbers';
import { r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { FirmService } from '../firm/firm.service';
import { InvoicesModule } from '../invoices/invoices.module';
import { InvoicesService } from '../invoices/invoices.service';
import { PartiesModule } from '../parties/parties.module';
import { PartiesService } from '../parties/parties.service';
import { storeHtml, storeScript } from './store-page';

const n = (v: unknown) => Number(v ?? 0);
const digits = (s: string) => s.replace(/\D/g, '').replace(/^0+/, '').replace(/^91(?=\d{10}$)/, '');

class OrderLineDto {
  @IsUUID() itemId: string;
  @IsNumber({ maxDecimalPlaces: 3 }) @Min(0.001) @Max(999) quantity: number;
}

class OrderDto {
  @IsString() @MinLength(1) @MaxLength(100) name: string;
  @IsString() @Matches(/^[+\d\s()-]{8,20}$/, { message: 'Enter a valid mobile number.' }) phone: string;
  @IsOptional() @IsString() @MaxLength(300) address?: string;
  @IsOptional() @IsString() @MaxLength(300) note?: string;
  /** A field real visitors never see; bots fill it in. */
  @IsOptional() @IsString() website?: string;
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(50) @ValidateNested({ each: true }) @Type(() => OrderLineDto) lines: OrderLineDto[];
}

class StoreSettingsDto {
  @IsOptional() @Matches(/^[a-z0-9][a-z0-9-]{2,39}$/, { message: 'The shop address uses 3–40 lowercase letters, digits and dashes.' }) slug?: string;
  @IsOptional() @IsBoolean() enabled?: boolean;
  @IsOptional() @IsString() @MaxLength(120) tagline?: string;
  @IsOptional() @IsString() @MaxLength(200) note?: string;
}

class StoreItemsDto {
  @IsArray() @ArrayMaxSize(1000) @IsUUID('all', { each: true }) itemIds: string[];
  @IsBoolean() inStore: boolean;
}

class OrderStatusDto {
  @Matches(/^(accepted|rejected)$/) status: 'accepted' | 'rejected';
}

@Injectable()
export class StoreService {
  /** Orders per address in the last hour, to keep a script from flooding a shop. */
  private readonly hits = new Map<string, number[]>();

  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly firms: FirmService,
    private readonly invoices: InvoicesService,
    private readonly parties: PartiesService,
  ) {}

  /** The shop of a slug, only when its owner has switched it on. */
  private async shop(slug: string) {
    const firm = await this.db.selectFrom('firms').select(['id', 'name', 'phone', 'address', 'city', 'state_code', 'store_slug']).where('store_slug', '=', slug).executeTakeFirst();
    const settings = firm ? await this.firms.settings(firm.id) : null;
    if (!firm || !settings?.storeEnabled) throw new NotFoundException({ code: 'NO_SHOP', message: 'This shop is not open.' });
    return { firm, settings };
  }

  /** The inclusive selling price: the shop always shows what the customer pays, GST included. */
  private price(i: { sale_price: unknown; sale_price_includes_tax: boolean; gst_rate: unknown }) {
    return r2(i.sale_price_includes_tax ? n(i.sale_price) : n(i.sale_price) * (1 + n(i.gst_rate) / 100));
  }

  async data(slug: string) {
    const { firm, settings } = await this.shop(slug);
    const items = await this.db
      .selectFrom('items').select(['id', 'name', 'unit', 'sale_price', 'sale_price_includes_tax', 'gst_rate', 'type', 'stock_qty', 'image_file_id'])
      .where('firm_id', '=', firm.id).where('in_store', '=', true).where('deleted_at', 'is', null).orderBy('name').execute();
    return {
      name: firm.name, phone: firm.phone, address: [firm.address, firm.city].filter(Boolean).join(', ') || null, tagline: settings.storeTagline, note: settings.storeNote,
      items: items.map((i) => ({
        id: i.id, name: i.name, unit: i.unit, price: this.price(i), image: i.image_file_id,
        soldOut: settings.stockMaintenance && i.type === 'product' && n(i.stock_qty) <= 0,
      })),
    };
  }

  async image(slug: string, fileId: string) {
    const { firm } = await this.shop(slug);
    const f = await this.db
      .selectFrom('files as f').innerJoin('items as i', 'i.image_file_id', 'f.id')
      .select(['f.mime_type', 'f.data']).where('f.id', '=', fileId).where('i.firm_id', '=', firm.id).where('i.in_store', '=', true).where('i.deleted_at', 'is', null).executeTakeFirst();
    if (!f || !/^image\/(png|jpeg|webp|gif)$/.test(f.mime_type)) throw new NotFoundException();
    return f;
  }

  private throttle(ip: string) {
    const now = Date.now();
    const recent = (this.hits.get(ip) ?? []).filter((t) => now - t < 3600_000);
    if (recent.length >= 5) throw new BadRequestException({ code: 'TOO_MANY', message: 'Too many orders from this connection. Please try again later.' });
    this.hits.set(ip, [...recent, now]);
    if (this.hits.size > 5000) for (const [k, v] of this.hits) if (v.every((t) => now - t >= 3600_000)) this.hits.delete(k);
  }

  /** A customer's order becomes a sale order for their party (found by phone, or made) that the business then accepts or rejects. */
  async order(slug: string, dto: OrderDto, ip: string) {
    const { firm, settings } = await this.shop(slug);
    // Bots fill in the hidden field; they are told it worked so they do not retry.
    if (dto.website) return { number: '0' };
    this.throttle(ip);
    const phone = digits(dto.phone);
    if (phone.length < 8) throw new BadRequestException({ code: 'BAD_PHONE', message: 'Enter a valid mobile number.' });
    const dayAgo = new Date(Date.now() - 86400_000);
    const recent = await this.db.selectFrom('store_orders').select((e) => e.fn.countAll<string>().as('c')).where('firm_id', '=', firm.id).where('phone', '=', phone).where('created_at', '>', dayAgo).executeTakeFirstOrThrow();
    if (n(recent.c) >= 5) throw new BadRequestException({ code: 'TOO_MANY', message: 'This number has already sent several orders today. Please call the shop.' });

    const ids = [...new Set(dto.lines.map((l) => l.itemId))];
    const items = await this.db
      .selectFrom('items').selectAll().where('firm_id', '=', firm.id).where('in_store', '=', true).where('deleted_at', 'is', null).where('id', 'in', ids).execute();
    const lines = dto.lines.map((l) => {
      const item = items.find((i) => i.id === l.itemId);
      if (!item) throw new BadRequestException({ code: 'ITEM_UNAVAILABLE', message: 'One of the products is no longer sold here. Please refresh the page.' });
      if (settings.stockMaintenance && item.type === 'product' && n(item.stock_qty) < l.quantity) {
        throw new BadRequestException({ code: 'NO_STOCK', message: `Only ${n(item.stock_qty)} of ${item.name} left.` });
      }
      // The price is ours, never the customer's.
      return { itemId: item.id, name: item.name, quantity: l.quantity, unit: item.unit, price: this.price(item), gstRate: item.gst_rate === null ? null : n(item.gst_rate), hsnCode: item.hsn_code };
    });

    // A returning customer is found by the last ten digits of their phone, however it was typed.
    let party = (
      await sql<{ id: string; name: string }>`
        select id, name from parties where firm_id = ${firm.id} and deleted_at is null
           and right(regexp_replace(coalesce(phone, ''), '\\D', '', 'g'), 10) = ${phone.slice(-10)} limit 1`.execute(this.db)
    ).rows[0];
    if (!party) {
      const name = dto.name.trim();
      const clash = await sql<{ id: string }>`select id from parties where firm_id = ${firm.id} and deleted_at is null and lower(name) = ${name.toLowerCase()} limit 1`.execute(this.db);
      const created = await this.parties.create(firm.id, { name: clash.rows.length ? `${name} (${phone.slice(-4)})` : name, phone: dto.phone.trim().slice(0, 20), billingAddress: dto.address ?? null, stateCode: firm.state_code ?? undefined } as never);
      party = { id: (created as { id: string }).id, name: (created as { name: string }).name };
    }
    const { number } = await this.invoices.nextNumber(firm.id, 'sale_order');
    const order = await this.invoices.create(firm.id, {
      type: 'sale_order', number, invoiceDate: today(), isCash: false, partyId: party.id, partyName: party.name, phone: dto.phone.trim(), billingAddress: dto.address ?? null,
      stateOfSupply: firm.state_code ?? null, pricesIncludeTax: true, roundOff: true, description: `Online order${dto.note ? `: ${dto.note}` : ''}`, lines,
    } as never);
    await this.db.insertInto('store_orders').values({ firm_id: firm.id, invoice_id: (order as { id: string }).id, customer_name: dto.name.trim(), phone, address: dto.address ?? null, note: dto.note ?? null }).execute();
    return { number, total: (order as { total: number }).total };
  }

  // ---------------------------------------------------------------- the owner's side

  async settings(firmId: string) {
    const firm = await this.db.selectFrom('firms').select('store_slug').where('id', '=', firmId).executeTakeFirstOrThrow();
    const s = await this.firms.settings(firmId);
    const items = await this.db.selectFrom('items').select(['id', 'name', 'sale_price', 'in_store', 'type', 'stock_qty']).where('firm_id', '=', firmId).where('deleted_at', 'is', null).orderBy('name').execute();
    return {
      slug: firm.store_slug, enabled: s.storeEnabled, tagline: s.storeTagline, note: s.storeNote, path: firm.store_slug ? `/store/${firm.store_slug}` : null,
      items: items.map((i) => ({ id: i.id, name: i.name, price: n(i.sale_price), inStore: i.in_store, stock: i.type === 'product' ? n(i.stock_qty) : null })),
    };
  }

  async saveSettings(firmId: string, dto: StoreSettingsDto) {
    if (dto.slug) {
      const taken = await this.db.selectFrom('firms').select('id').where('store_slug', '=', dto.slug).where('id', '!=', firmId).executeTakeFirst();
      if (taken) throw new ConflictException({ code: 'SLUG_TAKEN', message: 'That shop address is taken. Try another.' });
      await this.db.updateTable('firms').set({ store_slug: dto.slug }).where('id', '=', firmId).execute();
    }
    const current = await this.db.selectFrom('firms').select(['store_slug', 'settings']).where('id', '=', firmId).executeTakeFirstOrThrow();
    if (dto.enabled && !current.store_slug && !dto.slug) throw new BadRequestException({ code: 'NO_SLUG', message: 'Choose the shop address first.' });
    const merged = { ...(current.settings as Record<string, unknown>), ...(dto.enabled !== undefined ? { storeEnabled: dto.enabled } : {}), ...(dto.tagline !== undefined ? { storeTagline: dto.tagline } : {}), ...(dto.note !== undefined ? { storeNote: dto.note } : {}) };
    await this.db.updateTable('firms').set({ settings: JSON.stringify(merged), updated_at: new Date() }).where('id', '=', firmId).execute();
    return this.settings(firmId);
  }

  async setItems(firmId: string, dto: StoreItemsDto) {
    if (dto.itemIds.length) await this.db.updateTable('items').set({ in_store: dto.inStore }).where('firm_id', '=', firmId).where('id', 'in', dto.itemIds).execute();
    return this.settings(firmId);
  }

  async orders(firmId: string) {
    const rows = await this.db
      .selectFrom('store_orders as o').leftJoin('invoices as i', 'i.id', 'o.invoice_id')
      .select(['o.id', 'o.customer_name', 'o.phone', 'o.address', 'o.note', 'o.status', 'o.created_at', 'o.invoice_id', 'i.number', 'i.total', 'i.deleted_at'])
      .where('o.firm_id', '=', firmId).orderBy('o.created_at', 'desc').limit(200).execute();
    return rows.map((r) => ({ id: r.id, customer: r.customer_name, phone: r.phone, address: r.address, note: r.note, status: r.status, createdAt: r.created_at, invoiceId: r.invoice_id, number: r.number, total: n(r.total), removed: r.deleted_at !== null }));
  }

  async setStatus(firmId: string, id: string, status: 'accepted' | 'rejected') {
    const res = await this.db.updateTable('store_orders').set({ status }).where('id', '=', id).where('firm_id', '=', firmId).executeTakeFirst();
    if (!res.numUpdatedRows) throw new NotFoundException({ code: 'ORDER_NOT_FOUND', message: 'Order not found.' });
    return this.orders(firmId);
  }
}

/** What anyone on the internet can reach: the shop page, its data, pictures and the order form. */
@ApiTags('store')
@Controller('store')
export class PublicStoreController {
  constructor(private readonly store: StoreService) {}

  @Get('_assets/store.js')
  @Header('content-type', 'application/javascript; charset=utf-8')
  @Header('cache-control', 'public, max-age=300')
  script() {
    return storeScript;
  }

  @Get(':slug')
  @Header('content-type', 'text/html; charset=utf-8')
  async page(@Param('slug') slug: string) {
    await this.store.data(slug);
    return storeHtml(slug);
  }

  @Get(':slug/data')
  data(@Param('slug') slug: string) {
    return this.store.data(slug);
  }

  @Get(':slug/image/:fileId')
  async image(@Param('slug') slug: string, @Param('fileId') fileId: string, @Res() res: Response) {
    if (!/^[0-9a-f-]{36}$/.test(fileId)) throw new NotFoundException();
    const f = await this.store.image(slug, fileId);
    res.set({ 'content-type': f.mime_type, 'cache-control': 'public, max-age=3600', 'x-content-type-options': 'nosniff' }).send(f.data);
  }

  @Post(':slug/orders')
  @HttpCode(200)
  order(@Param('slug') slug: string, @Body() dto: OrderDto, @Req() req: Request) {
    return this.store.order(slug, dto, req.ip ?? 'unknown');
  }
}

@ApiTags('store-admin')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('store-admin')
export class StoreAdminController {
  constructor(private readonly store: StoreService) {}

  @Get()
  @Roles(...STAFF)
  settings(@CurrentUser() u: JwtPayload) {
    return this.store.settings(u.firmId);
  }

  @Put()
  @Roles(...ADMINS)
  save(@CurrentUser() u: JwtPayload, @Body() dto: StoreSettingsDto) {
    return this.store.saveSettings(u.firmId, dto);
  }

  @Put('items')
  @Roles(...ADMINS)
  items(@CurrentUser() u: JwtPayload, @Body() dto: StoreItemsDto) {
    return this.store.setItems(u.firmId, dto);
  }

  @Get('orders')
  @Roles(...STAFF)
  orders(@CurrentUser() u: JwtPayload) {
    return this.store.orders(u.firmId);
  }

  @Put('orders/:id')
  @Roles(...STAFF)
  status(@CurrentUser() u: JwtPayload, @Param('id') id: string, @Body() dto: OrderStatusDto) {
    return this.store.setStatus(u.firmId, id, dto.status);
  }
}

void IsInt;
void Query;

@Module({ imports: [InvoicesModule, PartiesModule], controllers: [PublicStoreController, StoreAdminController], providers: [StoreService] })
export class StoreModule {}
