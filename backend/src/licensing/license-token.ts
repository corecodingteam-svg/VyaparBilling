import { createPrivateKey, createPublicKey, KeyObject, sign, verify } from 'crypto';

/**
 * A licence certificate: what a device keeps so it can tell, with no connection, whether it may run.
 *
 * Format: base64url(payload JSON) + "." + base64url(Ed25519 signature of those payload bytes).
 * The signature covers the exact bytes sent, so nothing needs to be re-serialised identically on the device.
 * Only the server holds the private key; the app embeds the public key.
 */
export interface LicensePayload {
  /** Format version of this payload. */
  v: 1;
  /** Which signing key made it, so keys can be rotated. */
  kid: string;
  license_id: string;
  /** The company (customer) the licence belongs to. */
  customer_id: string;
  /** The installation (device) it is bound to. */
  installation_id: string;
  product_id: string;
  plan: string;
  /** Only "active" certificates are ever issued. */
  status: 'active';
  issued_at: string;
  valid_from: string;
  /** First instant the licence no longer works (ISO, UTC); null = no end. */
  expires_at: string | null;
  /** The last day it works, as a date to show people (YYYY-MM-DD, India time); null = no end. */
  expires_on: string | null;
  max_devices: number;
  license_version: number;
  /** The server's clock when this was issued: the floor under the device's idea of "now". */
  server_timestamp: string;
  /** The device must reach the server again by this time (ISO), or it asks to be validated online; null = never. */
  checkin_by: string | null;
  features: Record<string, boolean>;
  /** Shown on the "License expired" screen. */
  support_contact: string | null;
}

const b64u = (b: Buffer) => b.toString('base64url');

export interface SigningKey {
  kid: string;
  privateKey: KeyObject;
  publicKey: KeyObject;
}

/** Reads LICENSE_SIGNING_PRIVATE_KEY (base64 of a PKCS#8 DER Ed25519 key); null when it is not set or is not a valid key. */
export function loadSigningKey(base64: string | undefined, kid = process.env.LICENSE_KEY_ID ?? 'k1'): SigningKey | null {
  if (!base64?.trim()) return null;
  try {
    const privateKey = createPrivateKey({ key: Buffer.from(base64.trim(), 'base64'), format: 'der', type: 'pkcs8' });
    if (privateKey.asymmetricKeyType !== 'ed25519') return null;
    return { kid, privateKey, publicKey: createPublicKey(privateKey) };
  } catch {
    return null;
  }
}

/** The 32 raw bytes of an Ed25519 public key, base64: what the app is built with (LICENSE_PUBLIC_KEY). */
export function rawPublicKey(key: KeyObject): string {
  return (key.export({ format: 'der', type: 'spki' }) as Buffer).subarray(-32).toString('base64');
}

export function signLicense(payload: LicensePayload, privateKey: KeyObject): string {
  const body = Buffer.from(JSON.stringify(payload), 'utf8');
  return `${b64u(body)}.${b64u(sign(null, body, privateKey))}`;
}

/** The payload if the signature is good, otherwise null. (The app does the same check on the device.) */
export function verifyLicense(token: string, publicKey: KeyObject): LicensePayload | null {
  const [body, sig, extra] = token.split('.');
  if (!body || !sig || extra !== undefined) return null;
  try {
    const bytes = Buffer.from(body, 'base64url');
    if (!verify(null, bytes, publicKey, Buffer.from(sig, 'base64url'))) return null;
    return JSON.parse(bytes.toString('utf8')) as LicensePayload;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------- dates

const IST = '+05:30';

/** The licence end date picked as the last working day (YYYY-MM-DD, India) becomes the first instant it no longer works. */
export function expiresAtFor(lastDay: string): Date {
  const d = new Date(`${lastDay}T00:00:00${IST}`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d;
}

/** The last working day, as shown to people (India time). */
export function lastDayOf(expiresAt: Date | null): string | null {
  if (!expiresAt) return null;
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(expiresAt.getTime() - 1));
}
