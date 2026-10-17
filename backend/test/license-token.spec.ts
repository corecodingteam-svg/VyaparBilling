import { generateKeyPairSync } from 'crypto';
import { expiresAtFor, lastDayOf, LicensePayload, loadSigningKey, rawPublicKey, signLicense, verifyLicense } from '../src/licensing/license-token';

const pair = () => generateKeyPairSync('ed25519');
const payload = (over: Partial<LicensePayload> = {}): LicensePayload => ({
  v: 1, kid: 'k1', license_id: 'L1', customer_id: 'C1', installation_id: 'inst-0123456789abcdef', product_id: 'billing', plan: 'full', status: 'active',
  issued_at: '2026-10-01T00:00:00.000Z', valid_from: '2026-10-01T00:00:00.000Z', expires_at: '2026-10-20T18:30:00.000Z', expires_on: '2026-10-20',
  max_devices: 5, license_version: 1, server_timestamp: '2026-10-01T00:00:00.000Z', checkin_by: null, features: { posOnly: false }, support_contact: null, ...over,
});

describe('licence certificate', () => {
  it('verifies with the public key and returns the payload', () => {
    const { privateKey, publicKey } = pair();
    const token = signLicense(payload(), privateKey);
    expect(verifyLicense(token, publicKey)).toEqual(payload());
  });

  it('rejects a changed payload (e.g. a longer expiry), a wrong key and junk', () => {
    const { privateKey, publicKey } = pair();
    const token = signLicense(payload(), privateKey);
    const [, sig] = token.split('.');
    const forged = Buffer.from(JSON.stringify(payload({ expires_at: '2099-01-01T00:00:00.000Z' }))).toString('base64url');
    expect(verifyLicense(`${forged}.${sig}`, publicKey)).toBeNull();
    expect(verifyLicense(token, pair().publicKey)).toBeNull();
    expect(verifyLicense('nonsense', publicKey)).toBeNull();
    expect(verifyLicense(`${token}.x`, publicKey)).toBeNull();
  });

  it('loads a signing key from base64 PKCS#8 and exposes the 32-byte public key', () => {
    const { privateKey } = pair();
    const b64 = (privateKey.export({ format: 'der', type: 'pkcs8' }) as Buffer).toString('base64');
    const key = loadSigningKey(b64, 'k9')!;
    expect(key.kid).toBe('k9');
    expect(Buffer.from(rawPublicKey(key.publicKey), 'base64')).toHaveLength(32);
    expect(loadSigningKey('', 'k')).toBeNull();
    expect(loadSigningKey('not a key', 'k')).toBeNull();
    const rsa = generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey.export({ format: 'der', type: 'pkcs8' }) as Buffer;
    expect(loadSigningKey(rsa.toString('base64'), 'k')).toBeNull();
  });
});

describe('licence end date', () => {
  it('a licence "until 20 Oct" stops working at the start of 21 Oct, India time', () => {
    const end = expiresAtFor('2026-10-20');
    expect(end.toISOString()).toBe('2026-10-20T18:30:00.000Z');
    expect(lastDayOf(end)).toBe('2026-10-20');
    expect(lastDayOf(null)).toBeNull();
    expect(lastDayOf(expiresAtFor('2026-12-31'))).toBe('2026-12-31');
  });
});
