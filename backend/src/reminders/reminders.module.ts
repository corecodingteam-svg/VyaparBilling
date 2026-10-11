import { Controller, Delete, Get, HttpCode, Inject, Injectable, Module, NotFoundException, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { sql } from 'kysely';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Scope } from '../auth/scope';
import { today } from '../common/numbers';
import { partyBalanceSql, r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { FirmService } from '../firm/firm.service';

const daysBetween = (from: string, to: string) => Math.round((Date.parse(to) - Date.parse(from)) / 86400000);
const addDays = (date: string, days: number) => new Date(Date.parse(date) + days * 86400000).toISOString().slice(0, 10);

@Injectable()
export class RemindersService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly firms: FirmService,
  ) {}

  /**
   * Customers to chase: those who still owe money and have a sale invoice past its due date.
   * An invoice without a due date falls due the configured number of days after its date.
   */
  async payments(firmId: string, scope: Scope = {}) {
    const settings = await this.firms.settings(firmId);
    const graceDays = settings.paymentReminderDays ?? 0;
    const rows = await this.db
      .selectFrom('invoices as i')
      .innerJoin('parties as p', 'p.id', 'i.party_id')
      .select(['p.id', 'p.name', 'p.phone', 'i.number', 'i.invoice_date', 'i.due_date', 'i.total', 'i.received', 'i.tds_amount', 'i.loyalty_amount'])
      .select(sql<string>`coalesce((select sum(a.amount) from payment_allocations a where a.invoice_id = i.id), 0)`.as('linked'))
      .select(partyBalanceSql(sql.ref('p.id'), sql.ref('p.opening_balance')).as('balance'))
      .where('i.firm_id', '=', firmId)
      .where('i.type', '=', 'sale')
      .where('i.deleted_at', 'is', null)
      .where('p.deleted_at', 'is', null)
      .$if(!!scope.ownerUserId, (q) => q.where('p.assigned_user_id', '=', scope.ownerUserId!))
      .orderBy('i.invoice_date')
      .execute();
    const now = today();
    const byParty = new Map<string, { partyId: string; name: string; phone: string | null; balance: number; overdueAmount: number; invoices: number; oldestDue: string; daysOverdue: number }>();
    for (const r of rows) {
      const due = r2(Number(r.total) - Number(r.received) - Number(r.linked) - Number(r.tds_amount) - Number(r.loyalty_amount));
      const dueDate = r.due_date ?? addDays(r.invoice_date, graceDays);
      if (due <= 0 || Number(r.balance) <= 0 || dueDate >= now) continue;
      const entry = byParty.get(r.id) ?? {
        partyId: r.id, name: r.name, phone: r.phone, balance: Number(r.balance), overdueAmount: 0, invoices: 0, oldestDue: dueDate, daysOverdue: daysBetween(dueDate, now),
      };
      entry.overdueAmount = r2(entry.overdueAmount + due);
      entry.invoices += 1;
      byParty.set(r.id, entry);
    }
    // Never ask for more than the party owes overall (advance payments may not be linked to invoices).
    return [...byParty.values()]
      .map((e) => ({ ...e, overdueAmount: Math.min(e.overdueAmount, e.balance) }))
      .sort((a, b) => b.daysOverdue - a.daysOverdue);
  }

  /** Services sold whose next visit is due within 30 days or already overdue, and not yet marked done. */
  async services(firmId: string, scope: Scope = {}) {
    const rows = await this.db
      .selectFrom('invoice_items as ii')
      .innerJoin('invoices as i', 'i.id', 'ii.invoice_id')
      .innerJoin('items as it', 'it.id', 'ii.item_id')
      .leftJoin('parties as p', 'p.id', 'i.party_id')
      .leftJoin('service_reminders_done as d', 'd.invoice_item_id', 'ii.id')
      .select(['ii.id', 'ii.name', 'i.id as invoice_id', 'i.number', 'i.invoice_date', 'i.party_name', 'i.phone', 'p.phone as party_phone', 'it.service_reminder_days'])
      .where('i.firm_id', '=', firmId)
      .where('i.type', '=', 'sale')
      .where('i.deleted_at', 'is', null)
      .where('it.service_reminder_days', 'is not', null)
      .where('d.invoice_item_id', 'is', null)
      .$if(!!scope.ownerUserId, (q) => q.where((eb) => eb.or([eb('i.created_by', '=', scope.ownerUserId!), eb('p.assigned_user_id', '=', scope.ownerUserId!)])))
      .execute();
    const now = today();
    return rows
      .map((r) => {
        const dueDate = addDays(r.invoice_date, r.service_reminder_days!);
        return {
          id: r.id, itemName: r.name, invoiceId: r.invoice_id, invoiceNumber: r.number, soldOn: r.invoice_date, partyName: r.party_name,
          phone: r.phone ?? r.party_phone, dueDate, daysLeft: daysBetween(now, dueDate),
        };
      })
      .filter((r) => r.daysLeft <= 30)
      .sort((a, b) => a.daysLeft - b.daysLeft);
  }

  async markServiceDone(firmId: string, invoiceItemId: string) {
    const line = await this.db
      .selectFrom('invoice_items as ii')
      .innerJoin('invoices as i', 'i.id', 'ii.invoice_id')
      .select('ii.id')
      .where('ii.id', '=', invoiceItemId)
      .where('i.firm_id', '=', firmId)
      .executeTakeFirst();
    if (!line) throw new NotFoundException({ code: 'REMINDER_NOT_FOUND', message: 'Reminder not found.' });
    await this.db.insertInto('service_reminders_done').values({ invoice_item_id: invoiceItemId, firm_id: firmId }).onConflict((oc) => oc.doNothing()).execute();
  }

  async reopenService(firmId: string, invoiceItemId: string) {
    await this.db.deleteFrom('service_reminders_done').where('invoice_item_id', '=', invoiceItemId).where('firm_id', '=', firmId).execute();
  }
}

@ApiTags('reminders')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('reminders')
export class RemindersController {
  constructor(
    private readonly reminders: RemindersService,
    private readonly firm: FirmService,
  ) {}

  @Get('payments')
  async payments(@CurrentUser() u: JwtPayload) {
    return this.reminders.payments(u.firmId, await this.firm.scope(u));
  }

  @Get('services')
  async services(@CurrentUser() u: JwtPayload) {
    return this.reminders.services(u.firmId, await this.firm.scope(u));
  }

  @Post('services/:id/done')
  @HttpCode(204)
  markDone(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.reminders.markServiceDone(u.firmId, id);
  }

  @Delete('services/:id/done')
  @HttpCode(204)
  reopen(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.reminders.reopenService(u.firmId, id);
  }
}

@Module({ controllers: [RemindersController], providers: [RemindersService] })
export class RemindersModule {}
