import * as crypto from 'crypto';
import {
  BadRequestException, Body, Controller, Get, Headers, HttpCode, Inject, Injectable, Logger, Module, NotFoundException, Param, ParseUUIDPipe, Post, Req, UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { today } from '../common/numbers';
import { r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import { FirmService } from '../firm/firm.service';
import { IntegrationsService } from '../integrations/integrations.service';
import { MessagingService } from '../messaging/messaging.service';
import { PaymentsModule } from '../payments/payments.module';
import { PaymentsService } from '../payments/payments.service';
import { cancelPaymentLink, createPaymentLink, fetchPaymentLink, verifyWebhook } from './razorpay';

const view = (l: any) => ({
  id: l.id, invoiceId: l.invoice_id, url: l.short_url, amount: Number(l.amount), status: l.status, paymentId: l.payment_id, createdAt: l.created_at, paidAt: l.paid_at,
});

@Injectable()
export class OnlinePaymentsService {
  private readonly log = new Logger('OnlinePayments');

  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly integrations: IntegrationsService,
    private readonly payments: PaymentsService,
    private readonly messaging: MessagingService,
    private readonly firms: FirmService,
  ) {}

  async forInvoice(firmId: string, invoiceId: string) {
    const rows = await this.db.selectFrom('payment_links').selectAll().where('firm_id', '=', firmId).where('invoice_id', '=', invoiceId).orderBy('created_at', 'desc').execute();
    return rows.map(view);
  }

  /** A pay-online link for what is still unpaid on a sale invoice. */
  async createLink(firmId: string, userId: string, invoiceId: string) {
    const creds = await this.integrations.credentials(firmId, 'razorpay');
    if (!creds) throw new BadRequestException({ code: 'NOT_CONNECTED', message: 'Online payments are not set up. Add Razorpay under Settings → Integrations.' });
    const inv = await this.db.selectFrom('invoices').selectAll().where('id', '=', invoiceId).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst();
    if (!inv || inv.type !== 'sale') throw new NotFoundException({ code: 'INVOICE_NOT_FOUND', message: 'Sale invoice not found.' });
    if (!inv.party_id) throw new BadRequestException({ code: 'NO_PARTY', message: 'Online payment needs a customer on the invoice, so the money can be recorded against them.' });
    if (inv.currency_code) throw new BadRequestException({ code: 'FOREIGN_CURRENCY', message: 'Online payment links are in rupees only.' });
    const linked = await this.db.selectFrom('payment_allocations').select((e) => e.fn.sum<string>('amount').as('s')).where('invoice_id', '=', invoiceId).executeTakeFirst();
    const due = r2(Number(inv.total) - Number(inv.received) - Number(linked?.s ?? 0) - Number(inv.tds_amount) - Number(inv.loyalty_amount));
    if (due <= 0) throw new BadRequestException({ code: 'NOTHING_DUE', message: 'This invoice is already paid.' });
    // One open link per invoice: reuse it when the amount still matches, otherwise retire it.
    for (const open of await this.db.selectFrom('payment_links').selectAll().where('invoice_id', '=', invoiceId).where('status', '=', 'created').execute()) {
      if (Number(open.amount) === due) return view(open);
      await cancelPaymentLink(creds, open.provider_link_id).catch(() => undefined);
      await this.db.updateTable('payment_links').set({ status: 'cancelled' }).where('id', '=', open.id).execute();
    }
    const firm = await this.db.selectFrom('firms').select('name').where('id', '=', firmId).executeTakeFirstOrThrow();
    const ref = crypto.randomUUID();
    const link = await createPaymentLink(creds, {
      amount: due, description: `Invoice ${inv.number} — ${firm.name}`, customer: { name: inv.party_name, contact: inv.phone }, referenceId: ref,
      callbackUrl: process.env.APP_URL || undefined,
    });
    const row = await this.db
      .insertInto('payment_links')
      .values({ firm_id: firmId, invoice_id: invoiceId, provider: 'razorpay', provider_link_id: link.id, short_url: link.shortUrl, amount: String(due), created_by: userId, note: ref })
      .returningAll().executeTakeFirstOrThrow();
    return view(row);
  }

  /** Asks Razorpay whether a link has been paid (for when a webhook did not arrive). */
  async refresh(firmId: string, linkId: string) {
    const l = await this.db.selectFrom('payment_links').selectAll().where('id', '=', linkId).where('firm_id', '=', firmId).executeTakeFirst();
    if (!l) throw new NotFoundException({ code: 'LINK_NOT_FOUND', message: 'Payment link not found.' });
    const creds = await this.integrations.credentials(firmId, 'razorpay');
    if (creds && l.status === 'created') {
      const r = await fetchPaymentLink(creds, l.provider_link_id);
      if (r.status === 'paid') await this.markPaid(firmId, l.provider_link_id, r.paymentId, creds.config.bankAccountId);
      else if (r.status === 'cancelled' || r.status === 'expired') await this.db.updateTable('payment_links').set({ status: r.status }).where('id', '=', l.id).execute();
    }
    return view(await this.db.selectFrom('payment_links').selectAll().where('id', '=', linkId).executeTakeFirstOrThrow());
  }

  /** Called with the raw body Razorpay sent; the signature proves it came from them. */
  async webhook(firmId: string, raw: Buffer | undefined, signature: string | undefined) {
    const creds = await this.integrations.credentials(firmId, 'razorpay');
    if (!creds || !raw || !verifyWebhook(raw, signature, creds.secrets.webhookSecret ?? '')) {
      throw new BadRequestException({ code: 'BAD_SIGNATURE', message: 'Signature does not match.' });
    }
    const event = JSON.parse(raw.toString());
    const entity = event?.payload?.payment_link?.entity;
    if (event.event === 'payment_link.paid' && entity?.id) {
      await this.markPaid(firmId, entity.id, event.payload?.payment?.entity?.id ?? null, creds.config.bankAccountId);
    } else if ((event.event === 'payment_link.cancelled' || event.event === 'payment_link.expired') && entity?.id) {
      await this.db.updateTable('payment_links').set({ status: event.event === 'payment_link.expired' ? 'expired' : 'cancelled' })
        .where('provider_link_id', '=', entity.id).where('firm_id', '=', firmId).where('status', '=', 'created').execute();
    }
    return { ok: true };
  }

  /** Records the money as a Payment-In against the invoice, once, however many times Razorpay tells us. */
  private async markPaid(firmId: string, providerLinkId: string, providerPaymentId: string | null, bankAccountId?: string) {
    // The conditional update is the lock: only one caller moves the link out of "created".
    const claimed = await this.db
      .updateTable('payment_links').set({ status: 'paid', paid_at: new Date(), provider_payment_id: providerPaymentId })
      .where('provider_link_id', '=', providerLinkId).where('firm_id', '=', firmId).where('status', '=', 'created').returningAll().executeTakeFirst();
    if (!claimed) return;
    try {
      const inv = await this.db.selectFrom('invoices').select(['party_id', 'number']).where('id', '=', claimed.invoice_id).executeTakeFirstOrThrow();
      const { number } = await this.payments.nextNumber(firmId, 'in');
      const bank = bankAccountId
        ? await this.db.selectFrom('bank_accounts').select('id').where('id', '=', bankAccountId).where('firm_id', '=', firmId).where('deleted_at', 'is', null).executeTakeFirst()
        : undefined;
      const created = await this.payments.create(firmId, {
        type: 'in', number, partyId: inv.party_id!, paymentDate: today(), amount: Number(claimed.amount), paymentMode: 'upi', bankAccountId: bank?.id ?? null,
        allocations: [{ invoiceId: claimed.invoice_id, amount: Number(claimed.amount) }],
        description: `Paid online against invoice ${inv.number}${providerPaymentId ? ` (Razorpay ${providerPaymentId})` : ''}`,
      } as any);
      await this.db.updateTable('payment_links').set({ payment_id: created.id }).where('id', '=', claimed.id).execute();
      void this.messaging.autoSend(firmId, null, 'payment', created.id);
    } catch (e) {
      // Put the link back so the next webhook or a manual refresh can try again.
      await this.db.updateTable('payment_links').set({ status: 'created', paid_at: null, provider_payment_id: null }).where('id', '=', claimed.id).execute();
      this.log.error(`Could not record online payment for link ${providerLinkId}: ${(e as Error).message}`);
      throw e;
    }
  }

  /** The address to give Razorpay as the webhook for this company. */
  webhookUrl(firmId: string) {
    const base = (process.env.PUBLIC_API_URL ?? '').replace(/\/$/, '');
    return `${base}/api/v1/webhooks/razorpay/${firmId}`;
  }
}
void Get;

@ApiTags('online-payments')
@Controller()
export class OnlinePaymentsController {
  constructor(private readonly online: OnlinePaymentsService) {}

  @Get('online-payments/webhook-url')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...STAFF)
  webhookUrl(@CurrentUser() u: JwtPayload) {
    return { url: this.online.webhookUrl(u.firmId) };
  }

  @Get('online-payments/invoices/:id')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  forInvoice(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.online.forInvoice(u.firmId, id);
  }

  @Post('online-payments/invoices/:id/link')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...STAFF)
  link(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.online.createLink(u.firmId, u.sub, id);
  }

  @Post('online-payments/links/:id/refresh')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...STAFF)
  refresh(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.online.refresh(u.firmId, id);
  }

  /** Called by Razorpay's servers: no login, the signature is the proof. */
  @Post('webhooks/razorpay/:firmId')
  @HttpCode(200)
  webhook(@Param('firmId', ParseUUIDPipe) firmId: string, @Req() req: Request & { rawBody?: Buffer }, @Headers('x-razorpay-signature') sig: string | undefined, @Body() _body: unknown) {
    return this.online.webhook(firmId, req.rawBody, sig);
  }
}

@Module({ imports: [PaymentsModule], controllers: [OnlinePaymentsController], providers: [OnlinePaymentsService], exports: [OnlinePaymentsService] })
export class OnlinePaymentsModule {}
