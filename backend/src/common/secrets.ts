import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from 'crypto';

/**
 * Provider credentials (API tokens, passwords) are stored encrypted with AES-256-GCM. The key comes from
 * SECRETS_KEY, or from JWT_SECRET when that is not set. Changing the key makes stored credentials
 * unreadable (they have to be entered again), so it should be set once and kept.
 */
function key(env: NodeJS.ProcessEnv = process.env): Buffer {
  const material = env.SECRETS_KEY || env.JWT_SECRET;
  if (!material) throw new Error('SECRETS_KEY or JWT_SECRET must be set to store provider credentials.');
  return Buffer.from(hkdfSync('sha256', material, 'billing-secrets', 'integration-credentials', 32));
}

export function encryptSecrets(value: Record<string, string>, env?: NodeJS.ProcessEnv): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key(env), iv);
  const data = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
  return `v1.${iv.toString('base64')}.${cipher.getAuthTag().toString('base64')}.${data.toString('base64')}`;
}

/** The stored credentials, or {} when none are stored or they can no longer be decrypted. */
export function decryptSecrets(stored: string | null | undefined, env?: NodeJS.ProcessEnv): Record<string, string> {
  if (!stored) return {};
  try {
    const [version, iv, tag, data] = stored.split('.');
    if (version !== 'v1') return {};
    const decipher = createDecipheriv('aes-256-gcm', key(env), Buffer.from(iv, 'base64'));
    decipher.setAuthTag(Buffer.from(tag, 'base64'));
    return JSON.parse(Buffer.concat([decipher.update(Buffer.from(data, 'base64')), decipher.final()]).toString('utf8')) as Record<string, string>;
  } catch {
    return {};
  }
}

/** "••••1234": enough to recognise a stored secret without revealing it. */
export const mask = (secret: string | undefined): string | null => (secret ? `••••${secret.slice(-4)}` : null);
