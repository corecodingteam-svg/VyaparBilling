import { BadRequestException, Inject, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { sql } from 'kysely';
import { Scope } from '../auth/scope';
import { r2 } from '../common/party-balance';
import { Db, KYSELY } from '../database/database.module';
import type { MessageLogTable } from '../database/schema';
import { FirmService } from '../firm/firm.service';
import { IntegrationsService } from '../integrations/integrations.service';
import { normalizePhone, render, Sent, sendSms, sendWhatsApp } from './clients';

export type Channel = 'whatsapp' | 'sms';
type Kind = MessageLogTable['kind'];

interface Outgoing {
  channel: Channel;
  kind: Kind;
  to: string;
  /** The plain text (SMS, and WhatsApp without an approved template). */
  text: string;
  /** Values for the approved template's variables, in order. */
  params?: string[];
  partyId?: string | null;
  refId?: string | null;
}

@Injectable()
export class MessagingService {
  private readonly log = new Logger('Messaging');

  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly firms: FirmService,
    private readonly integrations: IntegrationsService,
  ) {}

  /** Sends one message and records the outcome. A provider failure is logged and then rethrown. */
  async send(firmId: string, userId: string | null, m: Outgoing): Promise<Sent> {
    const to = normalizePhone(m.to);
    if (to.length < 10) throw new BadRequestException({ code: 'NO_PHONE', message: 'This customer has no valid phone number.' });
    const creds = await this.integrations.credentials(firmId, m.channel);
    if (!creds) {
      throw new BadRequestException({ code: 'NOT_CONNECTED', message: `${m.channel === 'sms' ? 'SMS' : 'WhatsApp'} is not set up. Add it under Settings → Integrations.` });
    }
    const templates: Record<Kind, string | undefined> = {
      invoice: creds.config.invoiceTemplate, payment: creds.config.paymentTemplate, reminder: creds.config.reminderTemplate,
      marketing: creds.config.marketingTemplate, test: undefined, other: undefined,
    };
    let sent: Sent | undefined;
    let error: string | null = null;
    try {
      sent = m.channel === 'whatsapp'
        ? await sendWhatsApp(creds, to, { template: templates[m.kind], params: m.params, text: m.text })
        : await sendSms(creds, to, { text: m.text, params: m.params });
    } catch (e) {
      error = ((e as any)?.response?.message ?? (e as Error).message) as string;
    }
    await this.db
      .insertInto('message_log')
      .values({
        firm_id: firmId, channel: m.channel, kind: m.kind, party_id: m.partyId ?? null, ref_id: m.refId ?? null, to_phone: to, body: m.text,
        status: error ? 'failed' : 'sent', provider_id: sent?.id ?? null, error, created_by: userId,
      })
      .execute();
    if (error) throw new BadRequestException({ code: 'SEND_FAILED', message: error });
    return sent!;
  }

  /** The wording variables of a sale invoice. */
  private async invoiceVars(firmId: string, id: string, scope: Scope = {}) {
    const q = this.db
      .selectFrom('invoices as i')
      .leftJoin('parties as p', 'p.id', 'i.party_id')
      .select(['i.id', 'i.party_id', 'i.number', 'i.total', 'i.received', 'i.party_name', 'i.phone', 'i.type', 'p.phone as party_phone'])
      .where('i.id', '=', id)
      .where('i.firm_id', '=', firmId)
      .where('i.deleted_at', 'is', null)
      .$if(!!scope.ownerUserId, (b) => b.where((e) => e.or([e('i.created_by', '=', scope.ownerUserId!), e('p.assigned_user_id', '=', scope.ownerUserId!)])));
    const inv = await q.executeTakeFirst();
    if (!inv) throw new NotFoundException({ code: 'INVOICE_NOT_FOUND', message: 'Invoice not found.' });
    const link = await this.db
      .selectFrom('payment_links').select('short_url').where('invoice_id', '=', id).where('status', '=', 'created').orderBy('created_at', 'desc').executeTakeFirst();
    const firm = await this.db.selectFrom('firms').select('name').where('id', '=', firmId).executeTakeFirstOrThrow();
    return {
      inv,
      phone: inv.phone ?? inv.party_phone,
      vars: {
        customer: inv.party_name ?? 'Customer', number: inv.number, amount: String(r2(Number(inv.total))), business: firm.name,
        balance: String(r2(Number(inv.total) - Number(inv.received))), link: link?.short_url ?? '',
      } as Record<string, string>,
    };
  }

  async sendInvoice(firmId: string, userId: string | null, id: string, channel: Channel, scope: Scope = {}, phoneOverride?: string) {
    const { inv, phone, vars } = await this.invoiceVars(firmId, id, scope);
    const settings = await this.firms.settings(firmId);
    return this.send(firmId, userId, {
      channel, kind: 'invoice', to: phoneOverride || phone || '', text: render(settings.invoiceMessage, vars),
      params: [vars.customer, vars.number, vars.amount, vars.balance, vars.business], partyId: inv.party_id, refId: id,
    });
  }

  async sendPayment(firmId: string, userId: string | null, id: string, channel: Channel, scope: Scope = {}, phoneOverride?: string) {
    const pay = await this.db
      .selectFrom('payments as p')
      .innerJoin('parties as pa', 'pa.id', 'p.party_id')
      .select(['p.id', 'p.party_id', 'p.number', 'p.amount', 'pa.name', 'pa.phone', 'pa.assigned_user_id'])
      .where('p.id', '=', id)
      .where('p.firm_id', '=', firmId)
      .where('p.deleted_at', 'is', null)
      .executeTakeFirst();
    if (!pay || (scope.ownerUserId && pay.assigned_user_id !== scope.ownerUserId)) throw new NotFoundException({ code: 'PAYMENT_NOT_FOUND', message: 'Payment not found.' });
    const firm = await this.db.selectFrom('firms').select('name').where('id', '=', firmId).executeTakeFirstOrThrow();
    const vars = { customer: pay.name, number: pay.number, amount: String(r2(Number(pay.amount))), business: firm.name, balance: '', link: '' };
    const settings = await this.firms.settings(firmId);
    return this.send(firmId, userId, {
      channel, kind: 'payment', to: phoneOverride || pay.phone || '', text: render(settings.paymentMessage, vars),
      params: [vars.customer, vars.number, vars.amount, vars.business], partyId: pay.party_id, refId: id,
    });
  }

  /** A reminder to one customer for what they owe. */
  async sendReminder(firmId: string, userId: string | null, partyId: string, amount: number, channel: Channel, phoneOverride?: string) {
    const p = await this.db.selectFrom('parties').select(['id', 'name', 'phone']).where('id', '=', partyId).where('firm_id', '=', firmId).executeTakeFirst();
    if (!p) throw new NotFoundException({ code: 'PARTY_NOT_FOUND', message: 'Party not found.' });
    const firm = await this.db.selectFrom('firms').select('name').where('id', '=', firmId).executeTakeFirstOrThrow();
    const settings = await this.firms.settings(firmId);
    const vars = { customer: p.name, amount: String(r2(amount)), business: firm.name, link: '', number: '', balance: '' };
    return this.send(firmId, userId, {
      channel, kind: 'reminder', to: phoneOverride || p.phone || '', text: render(settings.reminderMessage, vars), params: [vars.customer, vars.amount, vars.business], partyId, refId: null,
    });
  }

  /** The same message to many parties (all with a phone, optionally one group). One failure does not stop the rest. */
  async marketing(firmId: string, userId: string | null, channel: Channel, text: string, opts: { partyIds?: string[]; groupId?: string }) {
    const rows = await this.db
      .selectFrom('parties').select(['id', 'name', 'phone']).where('firm_id', '=', firmId).where('deleted_at', 'is', null).where('phone', 'is not', null)
      .$if(!!opts.partyIds?.length, (q) => q.where('id', 'in', opts.partyIds!))
      .$if(!!opts.groupId, (q) => q.where('group_id', '=', opts.groupId!))
      .limit(500).execute();
    const firm = await this.db.selectFrom('firms').select('name').where('id', '=', firmId).executeTakeFirstOrThrow();
    let sent = 0;
    const failed: { name: string; error: string }[] = [];
    for (const p of rows) {
      const vars = { customer: p.name, business: firm.name };
      try {
        await this.send(firmId, userId, { channel, kind: 'marketing', to: p.phone!, text: render(text, vars), params: [p.name], partyId: p.id });
        sent++;
      } catch (e) {
        failed.push({ name: p.name, error: ((e as any)?.response?.message ?? (e as Error).message) as string });
      }
    }
    return { recipients: rows.length, sent, failed };
  }

  async test(firmId: string, userId: string | null, channel: Channel, to: string) {
    await this.send(firmId, userId, { channel, kind: 'test', to, text: 'Test message from your billing app.', params: [] });
    return { ok: true };
  }

  async history(firmId: string, limit = 100) {
    const rows = await this.db
      .selectFrom('message_log as m').leftJoin('parties as p', 'p.id', 'm.party_id')
      .select(['m.id', 'm.channel', 'm.kind', 'm.to_phone', 'm.body', 'm.status', 'm.error', 'm.created_at', 'p.name as party_name'])
      .where('m.firm_id', '=', firmId).orderBy('m.created_at', 'desc').limit(limit).execute();
    return rows.map((r) => ({
      id: r.id, channel: r.channel, kind: r.kind, to: r.to_phone, body: r.body, status: r.status, error: r.error, createdAt: r.created_at, partyName: r.party_name,
    }));
  }

  /** Sends a new document automatically when the company asked for it; never fails the caller. */
  async autoSend(firmId: string, userId: string | null, what: 'invoice' | 'payment', id: string) {
    try {
      const s = await this.firms.settings(firmId);
      const channel = what === 'invoice' ? s.autoSendInvoices : s.autoSendPayments;
      if (channel === 'off') return;
      if (what === 'invoice') {
        const t = await this.db.selectFrom('invoices').select('type').where('id', '=', id).executeTakeFirst();
        if (t?.type !== 'sale') return;
        await this.sendInvoice(firmId, userId, id, channel);
      } else {
        const t = await this.db.selectFrom('payments').select('type').where('id', '=', id).executeTakeFirst();
        if (t?.type !== 'in') return;
        await this.sendPayment(firmId, userId, id, channel);
      }
    } catch (e) {
      this.log.warn(`Automatic ${what} message failed: ${(e as Error).message}`);
    }
  }
}
void sql;
