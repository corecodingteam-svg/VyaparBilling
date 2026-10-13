import { BadRequestException } from '@nestjs/common';
import type { Credentials } from '../integrations/integrations.service';

/** What a provider returned for one message. */
export interface Sent {
  id: string | null;
}

/** Digits only, with India's 91 added to a bare 10-digit number. */
export function normalizePhone(phone: string): string {
  const digits = phone.replace(/\D/g, '').replace(/^0+/, '');
  return digits.length === 10 ? `91${digits}` : digits;
}

export const render = (template: string, vars: Record<string, string>) => template.replace(/\{(\w+)\}/g, (m, k) => vars[k] ?? m).replace(/\s+/g, ' ').trim();

async function call(url: string, init: RequestInit, what: string) {
  let res: Response;
  try {
    res = await fetch(url, { ...init, signal: AbortSignal.timeout(20_000) });
  } catch (e) {
    throw new BadRequestException({ code: 'PROVIDER_UNREACHABLE', message: `Could not reach ${what}: ${(e as Error).message}` });
  }
  const text = await res.text();
  let json: any = {};
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    /* not JSON */
  }
  if (!res.ok) {
    const detail = json?.error?.message ?? json?.message ?? json?.error ?? text.slice(0, 200);
    throw new BadRequestException({ code: 'PROVIDER_ERROR', message: `${what} refused the message: ${typeof detail === 'string' ? detail : JSON.stringify(detail)}` });
  }
  return json;
}

/**
 * WhatsApp Cloud API. With a template name the message is a template message (allowed to anyone);
 * without one it is plain text, which WhatsApp only delivers inside the 24 hours after the customer last wrote.
 */
export async function sendWhatsApp(c: Credentials, to: string, opts: { template?: string; params?: string[]; text: string }): Promise<Sent> {
  const base = (c.config.apiBase || 'https://graph.facebook.com/v20.0').replace(/\/$/, '');
  const body = opts.template
    ? {
        messaging_product: 'whatsapp',
        to,
        type: 'template',
        template: {
          name: opts.template,
          language: { code: c.config.language || 'en' },
          components: opts.params?.length ? [{ type: 'body', parameters: opts.params.map((text) => ({ type: 'text', text })) }] : [],
        },
      }
    : { messaging_product: 'whatsapp', to, type: 'text', text: { body: opts.text, preview_url: true } };
  const json = await call(
    `${base}/${c.config.phoneNumberId}/messages`,
    { method: 'POST', headers: { Authorization: `Bearer ${c.secrets.accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) },
    'WhatsApp',
  );
  return { id: json?.messages?.[0]?.id ?? null };
}

/** Twilio (any text) or MSG91 (a DLT-approved flow template whose variables are var1, var2, …). */
export async function sendSms(c: Credentials, to: string, opts: { text: string; params?: string[] }): Promise<Sent> {
  if (c.config.gateway === 'msg91') {
    if (!c.config.msg91TemplateId) throw new BadRequestException({ code: 'MISSING_FIELDS', message: 'MSG91 needs a flow template ID.' });
    const base = (c.config.apiBase || 'https://control.msg91.com').replace(/\/$/, '');
    const recipient: Record<string, string> = { mobiles: to };
    (opts.params ?? [opts.text]).forEach((v, i) => (recipient[`var${i + 1}`] = v));
    const json = await call(
      `${base}/api/v5/flow/`,
      { method: 'POST', headers: { authkey: c.secrets.authToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ template_id: c.config.msg91TemplateId, recipients: [recipient] }) },
      'MSG91',
    );
    return { id: json?.request_id ?? json?.message ?? null };
  }
  if (!c.config.accountSid || !c.config.from) throw new BadRequestException({ code: 'MISSING_FIELDS', message: 'Twilio needs an account SID and a sender.' });
  const base = (c.config.apiBase || 'https://api.twilio.com').replace(/\/$/, '');
  const form = new URLSearchParams({ To: `+${to}`, Body: opts.text });
  form.set(c.config.from.startsWith('MG') ? 'MessagingServiceSid' : 'From', c.config.from);
  const json = await call(
    `${base}/2010-04-01/Accounts/${c.config.accountSid}/Messages.json`,
    {
      method: 'POST',
      headers: { Authorization: `Basic ${Buffer.from(`${c.config.accountSid}:${c.secrets.authToken}`).toString('base64')}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form.toString(),
    },
    'Twilio',
  );
  return { id: json?.sid ?? null };
}
