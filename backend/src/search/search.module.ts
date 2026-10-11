import { Controller, Get, Inject, Module, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { INVOICE_TYPES, INVOICE_TYPE_NAMES } from '../common/invoice-types';
import { num } from '../common/numbers';
import { Db, KYSELY } from '../database/database.module';
import { FirmService } from '../firm/firm.service';

/** Salesmen only see the sale side. */
const PURCHASE_SIDE = ['purchase', 'purchase_order', 'debit_note'];

@ApiTags('search')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('search')
export class SearchController {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly firm: FirmService,
  ) {}

  /** Quick search across parties, items and documents. */
  @Get()
  async search(@CurrentUser() u: JwtPayload, @Query('q') q?: string) {
    const text = (q ?? '').trim();
    if (text.length < 2) return { parties: [], items: [], invoices: [] };
    // Escape LIKE wildcards so the text is matched literally.
    const term = `%${text.replace(/[\\%_]/g, '\\$&')}%`;
    const own = (await this.firm.scope(u)).ownerUserId;
    const [parties, items, invoices] = await Promise.all([
      this.db
        .selectFrom('parties')
        .select(['id', 'name', 'phone'])
        .where('firm_id', '=', u.firmId)
        .where('deleted_at', 'is', null)
        .where((eb) => eb.or([eb('name', 'ilike', term), eb('phone', 'ilike', term), eb('gstin', 'ilike', term)]))
        .$if(!!own, (q) => q.where('assigned_user_id', '=', own!))
        .orderBy('name')
        .limit(8)
        .execute(),
      this.db
        .selectFrom('items')
        .select(['id', 'name', 'item_code', 'sale_price', 'stock_qty', 'type'])
        .where('firm_id', '=', u.firmId)
        .where('deleted_at', 'is', null)
        .where((eb) => eb.or([eb('name', 'ilike', term), eb('item_code', 'ilike', term), eb('hsn_code', 'ilike', term)]))
        .orderBy('name')
        .limit(8)
        .execute(),
      this.db
        .selectFrom('invoices')
        .select(['id', 'type', 'number', 'party_name', 'invoice_date', 'total'])
        .where('firm_id', '=', u.firmId)
        .where('deleted_at', 'is', null)
        .where('type', 'in', INVOICE_TYPE_NAMES.filter((t) => u.role !== 'salesman' || !PURCHASE_SIDE.includes(t)))
        .where((eb) => eb.or([eb('number', 'ilike', term), eb('party_name', 'ilike', term), eb('phone', 'ilike', term)]))
        .$if(!!own, (q) =>
          q.where((eb) =>
            eb.or([eb('created_by', '=', own!), eb('party_id', 'in', eb.selectFrom('parties').select('parties.id').where('parties.assigned_user_id', '=', own!))]),
          ),
        )
        .orderBy('invoice_date', 'desc')
        .limit(10)
        .execute(),
    ]);
    return {
      parties: parties.map((p) => ({ id: p.id, name: p.name, phone: p.phone })),
      items: items.map((i) => ({ id: i.id, name: i.name, itemCode: i.item_code, salePrice: num(i.sale_price), stockQty: i.type === 'product' ? num(i.stock_qty) : null })),
      invoices: invoices.map((i) => ({
        id: i.id, type: i.type, typeLabel: INVOICE_TYPES[i.type].label, number: i.number, partyName: i.party_name, date: i.invoice_date, total: num(i.total),
      })),
    };
  }
}

@Module({ controllers: [SearchController] })
export class SearchModule {}
