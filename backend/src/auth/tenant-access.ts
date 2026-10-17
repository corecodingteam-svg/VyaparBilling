/**
 * What a business (tenant) is allowed to use, decided by the provider rather than by the business itself:
 * feature switches, a plan, a licence end date and suspension. Enforced on every request by JwtAuthGuard.
 */

/** Every switch there is, with what it is when the provider has not set it. */
export const FEATURE_DEFAULTS = {
  /** Only the POS counter and what serves it; everything else is refused by the server. */
  posOnly: false,
  accounting: true,
  reports: true,
  manufacturing: true,
  integrations: true,
  onlineStore: true,
  locationTracking: true,
  /** May add further companies under one login. */
  multiCompany: true,
} as const;

export type FeatureName = keyof typeof FEATURE_DEFAULTS;
export type Features = Record<FeatureName, boolean>;

export const FEATURE_LABELS: Record<FeatureName, string> = {
  posOnly: 'POS only',
  accounting: 'Accounting',
  reports: 'Reports',
  manufacturing: 'Manufacturing',
  integrations: 'Integrations',
  onlineStore: 'Online store',
  locationTracking: 'Location tracking',
  multiCompany: 'Several companies',
};

/** Starting points for a new business; the provider can still change each switch afterwards. */
export const PLANS: Record<string, { label: string; features: Partial<Features> }> = {
  full: { label: 'Full billing', features: {} },
  pos: {
    label: 'POS only',
    features: { posOnly: true, accounting: false, reports: false, manufacturing: false, integrations: false, onlineStore: false, locationTracking: false, multiCompany: false },
  },
};

/** The defaults with the provider's changes on top; unknown names are ignored. */
export function effectiveFeatures(overrides: Record<string, unknown> | null | undefined): Features {
  const out = { ...FEATURE_DEFAULTS } as Features;
  for (const k of Object.keys(FEATURE_DEFAULTS) as FeatureName[]) {
    const v = overrides?.[k];
    if (typeof v === 'boolean') out[k] = v;
  }
  return out;
}

export interface TenantInfo {
  features: Features;
  plan: string;
  licenceStatus: 'active' | 'suspended' | 'revoked';
  licenceReason: string | null;
  /** Last working day of the licence (YYYY-MM-DD), or null. */
  licenceExpiresOn: string | null;
  licenceExpired: boolean;
}

export interface RequestInfo {
  method: string;
  /** Path without the API prefix or query string, e.g. "/invoices/next-number". */
  path: string;
  query: Record<string, unknown>;
  body: unknown;
}

export interface Refusal {
  code: string;
  message: string;
}

const seg = (path: string) => path.split('/').filter(Boolean);

/** Always reachable, even when blocked: signing in, finding out who you are, and moving to another company. */
const isAccountRoute = (r: RequestInfo) => ['auth', 'licenses'].includes(seg(r.path)[0]) || (r.method === 'GET' && r.path === '/firms');

/** The parts of the API each feature owns (first path segment). */
const FEATURE_PREFIXES: Partial<Record<FeatureName, string[]>> = {
  accounting: ['ledger-accounts', 'journals', 'currencies'],
  reports: ['reports'],
  manufacturing: ['manufacturing'],
  integrations: ['integrations', 'messages', 'einvoice', 'online-payments', 'google-profile'],
  onlineStore: ['store-admin'],
  locationTracking: ['locations'],
};

/**
 * What a POS-only business may call: the counter itself (items, accounts, sale bills and their receipts), the company
 * profile and files, signing in, and managing items and users. Everything else is refused (deny by default).
 */
function posOnlyAllows(r: RequestInfo): boolean {
  const [a, b] = seg(r.path);
  const get = r.method === 'GET';
  switch (a) {
    case 'auth':
    case 'firm':
    case 'files':
    case 'items':
    case 'categories':
    case 'units':
    case 'users':
      return true;
    case 'bank-accounts':
      return get && !b;
    case 'invoices':
      if (r.method === 'POST' && !b) return (r.body as { type?: unknown } | null)?.type === 'sale';
      if (get && !b) return r.query.type === 'sale';
      return get && b !== undefined; // next-number, and one bill for its receipt
    default:
      return false;
  }
}

/** Why this request must not go ahead for this business, or null if it may. */
export function tenantRefusal(r: RequestInfo, t: TenantInfo): Refusal | null {
  const a = seg(r.path)[0];
  if (a === 'platform' || isAccountRoute(r)) return null; // /platform has its own check
  if (t.licenceStatus !== 'active') {
    const why = t.licenceReason ? `: ${t.licenceReason}` : '';
    return t.licenceStatus === 'revoked'
      ? { code: 'LICENSE_REVOKED', message: `This business's licence has been revoked${why}. Contact your provider.` }
      : { code: 'LICENSE_SUSPENDED', message: `This business's licence is suspended${why}. Contact your provider.` };
  }
  if (t.licenceExpired) {
    return { code: 'LICENSE_EXPIRED', message: `The licence for this business ended on ${t.licenceExpiresOn}. Contact your provider to renew it.` };
  }
  if (t.features.posOnly && !posOnlyAllows(r)) {
    return { code: 'POS_ONLY', message: 'This business is set up for POS only; that is not available.' };
  }
  for (const [feature, prefixes] of Object.entries(FEATURE_PREFIXES) as [FeatureName, string[]][]) {
    if (!t.features[feature] && prefixes.includes(a)) return { code: 'FEATURE_OFF', message: `${FEATURE_LABELS[feature]} is not part of this business's plan.` };
  }
  if (!t.features.multiCompany && r.method === 'POST' && r.path === '/firms') {
    return { code: 'FEATURE_OFF', message: "Adding companies is not part of this business's plan." };
  }
  return null;
}
