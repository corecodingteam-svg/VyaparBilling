import { effectiveFeatures, PLANS, tenantRefusal, TenantInfo } from '../src/auth/tenant-access';

const tenant = (over: Partial<Omit<TenantInfo, 'features'>> & { features?: Record<string, boolean> } = {}): TenantInfo => ({
  plan: 'full',
  licenceStatus: 'active',
  licenceReason: null,
  licenceExpiresOn: null,
  licenceExpired: false,
  ...over,
  features: effectiveFeatures(over.features),
});
const req = (method: string, path: string, query: Record<string, unknown> = {}, body: unknown = undefined) => ({ method, path, query, body });
const code = (r: ReturnType<typeof req>, t: TenantInfo) => tenantRefusal(r, t)?.code ?? null;

describe('POS-only business', () => {
  const pos = tenant({ features: PLANS.pos.features as Record<string, boolean> });

  it('may run the counter', () => {
    expect(code(req('GET', '/items', { type: 'all' }), pos)).toBeNull();
    expect(code(req('GET', '/bank-accounts'), pos)).toBeNull();
    expect(code(req('GET', '/invoices/next-number', { type: 'sale' }), pos)).toBeNull();
    expect(code(req('POST', '/invoices', {}, { type: 'sale' }), pos)).toBeNull();
    expect(code(req('GET', '/invoices/abc'), pos)).toBeNull();
    expect(code(req('GET', '/invoices', { type: 'sale' }), pos)).toBeNull();
    expect(code(req('GET', '/firm'), pos)).toBeNull();
    expect(code(req('GET', '/auth/me'), pos)).toBeNull();
  });

  it('is refused everything else by the server', () => {
    for (const r of [
      req('POST', '/invoices', {}, { type: 'purchase' }),
      req('GET', '/invoices', { type: 'purchase' }),
      req('GET', '/parties'),
      req('GET', '/reports/sales'),
      req('GET', '/dashboard'),
      req('POST', '/expenses'),
      req('POST', '/payments'),
      req('GET', '/backup'),
      req('POST', '/bank-accounts'),
      req('POST', '/firms'),
      req('GET', '/journals'),
      req('DELETE', '/invoices/abc'),
      req('PUT', '/invoices/abc'),
    ]) {
      expect(`${r.method} ${r.path} ${code(r, pos)}`).toMatch(/ (POS_ONLY|FEATURE_OFF)$/);
    }
  });

  it('reports why', () => {
    expect(code(req('GET', '/parties'), pos)).toBe('POS_ONLY');
  });
});

describe('other businesses', () => {
  it('a full business may do all of it', () => {
    expect(code(req('GET', '/parties'), tenant())).toBeNull();
    expect(code(req('GET', '/reports/sales'), tenant())).toBeNull();
    expect(code(req('POST', '/firms'), tenant())).toBeNull();
  });

  it('individual switches close their part of the API only', () => {
    const t = tenant({ features: { accounting: false, reports: false, multiCompany: false } });
    expect(code(req('GET', '/journals'), t)).toBe('FEATURE_OFF');
    expect(code(req('GET', '/currencies'), t)).toBe('FEATURE_OFF');
    expect(code(req('GET', '/reports/x'), t)).toBe('FEATURE_OFF');
    expect(code(req('POST', '/firms'), t)).toBe('FEATURE_OFF');
    expect(code(req('GET', '/parties'), t)).toBeNull();
  });

  it('a suspended or expired business is stopped, but can still sign in and see its companies', () => {
    const s = tenant({ licenceStatus: 'suspended', licenceReason: 'unpaid' });
    expect(code(req('GET', '/items'), s)).toBe('LICENSE_SUSPENDED');
    expect(code(req('GET', '/auth/me'), s)).toBeNull();
    expect(code(req('GET', '/firms'), s)).toBeNull();
    expect(code(req('POST', '/licenses/refresh'), s)).toBeNull();
    expect(code(req('GET', '/items'), tenant({ licenceStatus: 'revoked' }))).toBe('LICENSE_REVOKED');
    const e = tenant({ licenceExpired: true, licenceExpiresOn: '2026-09-30' });
    expect(tenantRefusal(req('POST', '/invoices', {}, { type: 'sale' }), e)?.message).toContain('2026-09-30');
  });
});

describe('features and platform admins', () => {
  it('unknown or non-boolean overrides are ignored', () => {
    const f = effectiveFeatures({ posOnly: true, bogus: true, reports: 'no' });
    expect([f.posOnly, f.reports, (f as unknown as Record<string, unknown>).bogus]).toEqual([true, true, undefined]);
  });

});
