import * as crypto from 'crypto';
import { BadRequestException } from '@nestjs/common';
import type { Credentials } from '../integrations/integrations.service';

const base = (c: Credentials) => (c.config.apiBase || 'https://api.razorpay.com').replace(/\/$/, '');
const auth = (c: Credentials) => `Basic ${Buffer.from(`${c.config.keyId}:${c.secrets.keySecret}`).toString('base64')}`;

async function call(c: Credentials, method: string, path: string, body?: unknown) {
  let res: Response;
  try {
    res = await fetch(`${base(c)}${path}`, {
      method, headers: { Authorization: auth(c), 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20_000),
    });
  } catch (e) {
    throw new BadRequestException({ code: 'PROVIDER_UNREACHABLE', message: `Could not reach Razorpay: ${(e as Error).message}` });
  }
  const json: any = await res.json().catch(() => ({}));
  if (!res.ok) throw new BadRequestException({ code: 'PROVIDER_ERROR', message: `Razorpay said: ${json?.error?.description ?? `HTTP ${res.status}`}` });
  return json;
}

export interface LinkInput {
  /** Rupees. */
  amount: number;
  description: string;
  customer: { name: string; contact?: string | null };
  /** Our own link id, echoed back by Razorpay. */
  referenceId: string;
  /** Where the customer lands after paying. */
  callbackUrl?: string;
}

export async function createPaymentLink(c: Credentials, i: LinkInput): Promise<{ id: string; shortUrl: string }> {
  const phone = i.customer.contact?.replace(/\D/g, '');
  const r = await call(c, 'POST', '/v1/payment_links', {
    amount: Math.round(i.amount * 100),
    currency: 'INR',
    accept_partial: false,
    reference_id: i.referenceId,
    description: i.description.slice(0, 2000),
    customer: { name: i.customer.name, ...(phone && phone.length >= 10 ? { contact: phone.length === 10 ? `+91${phone}` : `+${phone}` } : {}) },
    notify: { sms: false, email: false },
    reminder_enable: false,
    ...(i.callbackUrl ? { callback_url: i.callbackUrl, callback_method: 'get' } : {}),
  });
  return { id: r.id, shortUrl: r.short_url };
}

/** The link as Razorpay sees it now; used to catch up when a webhook was missed. */
export async function fetchPaymentLink(c: Credentials, id: string): Promise<{ status: string; amountPaid: number; paymentId: string | null }> {
  const r = await call(c, 'GET', `/v1/payment_links/${id}`);
  return { status: r.status, amountPaid: Number(r.amount_paid ?? 0) / 100, paymentId: r.payments?.[0]?.payment_id ?? null };
}

export async function cancelPaymentLink(c: Credentials, id: string) {
  await call(c, 'POST', `/v1/payment_links/${id}/cancel`);
}

/** Razorpay signs the exact bytes of the webhook body with HMAC-SHA256 and the webhook secret. */
export function verifyWebhook(rawBody: Buffer | string, signature: string | undefined, secret: string): boolean {
  if (!signature || !secret) return false;
  const expected = crypto.createHmac('sha256', secret).update(rawBody).digest('hex');
  const a = Buffer.from(expected);
  const b = Buffer.from(signature);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** A UPI payment request string, for a QR code the customer's UPI app can scan. */
export function upiUri(opts: { upiId: string; name: string; amount?: number; note?: string }) {
  const q = new URLSearchParams({ pa: opts.upiId, pn: opts.name, cu: 'INR' });
  if (opts.amount && opts.amount > 0) q.set('am', opts.amount.toFixed(2));
  if (opts.note) q.set('tn', opts.note);
  return `upi://pay?${q.toString().replace(/\+/g, '%20')}`;
}
