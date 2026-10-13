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
    if (text.length < 2) return { parties: [], items: [], invoices: [], payments: [], expenses: [] };
    // Escape LIKE wildcards so the text is matched literally.
    const term = `%${text.replace(/[\\%_]/g, '\\$&')}%`;
    const own = (await this.firm.scope(u)).ownerUserId;
    const staff = u.role !== 'salesman';
    const [parties, items, invoices, payments, expenses] = await Promise.all([
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
      this.db
        .selectFrom('payments as p')
        .innerJoin('parties as pa', 'pa.id', 'p.party_id')
        .select(['p.id', 'p.type', 'p.number', 'p.payment_date', 'p.amount', 'pa.name'])
        .where('p.firm_id', '=', u.firmId)
        .where('p.deleted_at', 'is', null)
        .$if(!staff, (q) => q.where('p.type', '=', 'in'))
        .where((eb) => eb.or([eb('p.number', 'ilike', term), eb('pa.name', 'ilike', term), eb('p.description', 'ilike', term)]))
        .$if(!!own, (q) => q.where((eb) => eb.or([eb('p.created_by', '=', own!), eb('pa.assigned_user_id', '=', own!)])))
        .orderBy('p.payment_date', 'desc')
        .limit(8)
        .execute(),
      // Expenses are part of the books salesmen do not see.
      staff
        ? this.db
            .selectFrom('expenses as e')
            .innerJoin('expense_categories as c', 'c.id', 'e.category_id')
            .select(['e.id', 'e.number', 'e.expense_date', 'e.total', 'e.description', 'c.name'])
            .where('e.firm_id', '=', u.firmId)
            .where('e.deleted_at', 'is', null)
            .where((eb) => eb.or([eb('e.number', 'ilike', term), eb('c.name', 'ilike', term), eb('e.description', 'ilike', term)]))
            .orderBy('e.expense_date', 'desc')
            .limit(8)
            .execute()
        : Promise.resolve([]),
    ]);
    return {
      parties: parties.map((p) => ({ id: p.id, name: p.name, phone: p.phone })),
      items: items.map((i) => ({ id: i.id, name: i.name, itemCode: i.item_code, salePrice: num(i.sale_price), stockQty: i.type === 'product' ? num(i.stock_qty) : null })),
      invoices: invoices.map((i) => ({
        id: i.id, type: i.type, typeLabel: INVOICE_TYPES[i.type].label, number: i.number, partyName: i.party_name, date: i.invoice_date, total: num(i.total),
      })),
      payments: payments.map((p) => ({ id: p.id, type: p.type, number: p.number, partyName: p.name, date: p.payment_date, amount: num(p.amount) })),
      expenses: expenses.map((e) => ({ id: e.id, number: e.number, category: e.name, date: e.expense_date, total: num(e.total), description: e.description })),
    };
  }
}

@Module({ controllers: [SearchController] })
export class SearchModule {}
