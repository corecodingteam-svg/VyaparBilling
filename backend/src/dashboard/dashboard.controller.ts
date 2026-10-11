import { Controller, Get, Inject, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { sql } from 'kysely';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { partyBalanceSql } from '../common/party-balance';
import { today } from '../common/numbers';
import { Db, KYSELY } from '../database/database.module';
import { FirmService } from '../firm/firm.service';

@ApiTags('dashboard')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('dashboard')
export class DashboardController {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly firm: FirmService,
  ) {}

  /** Receivable/payable from party balances, low-stock count and daily sales for [from, to] (default: this month). */
  @Get()
  async summary(@CurrentUser() u: JwtPayload, @Query('from') from?: string, @Query('to') to?: string) {
    const start = from ?? today().slice(0, 8) + '01';
    const end = to ?? today();
    const own = (await this.firm.scope(u)).ownerUserId;

    const balances = this.db
      .selectFrom('parties')
      .select(partyBalanceSql(sql.ref('parties.id'), sql.ref('parties.opening_balance')).as('balance'))
      .where('firm_id', '=', u.firmId)
      .where('deleted_at', 'is', null)
      .$if(!!own, (q) => q.where('assigned_user_id', '=', own!))
      .as('b');
    const r = await this.db
      .selectFrom(balances)
      .select([
        sql<string>`coalesce(sum(balance) filter (where balance > 0), 0)`.as('receivable'),
        sql<string>`count(*) filter (where balance > 0)`.as('receivable_parties'),
        sql<string>`coalesce(-sum(balance) filter (where balance < 0), 0)`.as('payable'),
        sql<string>`count(*) filter (where balance < 0)`.as('payable_parties'),
      ])
      .executeTakeFirstOrThrow();

    const lowStock = await this.db
      .selectFrom('items')
      .select(sql<string>`count(*)`.as('n'))
      .where('firm_id', '=', u.firmId)
      .where('deleted_at', 'is', null)
      .where('type', '=', 'product')
      .where(sql<boolean>`min_stock is not null and stock_qty <= min_stock`)
      .executeTakeFirstOrThrow();

    const daily = await this.db
      .selectFrom('invoices')
      .select(['invoice_date as date', sql<string>`sum(total)`.as('amount')])
      .where('firm_id', '=', u.firmId)
      .where('type', '=', 'sale')
      .where('deleted_at', 'is', null)
      .where('invoice_date', '>=', start)
      .where('invoice_date', '<=', end)
      .$if(!!own, (q) => q.where('created_by', '=', own!))
      .groupBy('invoice_date')
      .orderBy('invoice_date')
      .execute();

    const money = await this.db
      .selectFrom('money_flows')
      .select([
        sql<string>`coalesce(sum(amount) filter (where account = 'cash'), 0)`.as('cash'),
        sql<string>`coalesce(sum(amount) filter (where account = 'bank'), 0)`.as('bank_flows'),
      ])
      .where('firm_id', '=', u.firmId)
      .executeTakeFirstOrThrow();
    const opening = await this.db
      .selectFrom('bank_accounts')
      .select(sql<string>`coalesce(sum(opening_balance), 0)`.as('total'))
      .where('firm_id', '=', u.firmId)
      .where('deleted_at', 'is', null)
      .executeTakeFirstOrThrow();

    // Salesmen do not see the business's cash and bank position.
    const staff = u.role !== 'salesman';
    return {
      cashInHand: staff ? Number(money.cash) : 0,
      bankBalance: staff ? Number(opening.total) + Number(money.bank_flows) : 0,
      receivable: Number(r.receivable),
      receivableParties: Number(r.receivable_parties),
      payable: Number(r.payable),
      payableParties: Number(r.payable_parties),
      lowStockItems: Number(lowStock.n),
      sales: {
        from: start,
        to: end,
        total: daily.reduce((s, d) => s + Number(d.amount), 0),
        daily: daily.map((d) => ({ date: d.date, amount: Number(d.amount) })),
      },
    };
  }
}
