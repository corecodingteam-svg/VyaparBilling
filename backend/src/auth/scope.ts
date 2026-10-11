import { JwtPayload } from './jwt.strategy';

/** Whose data a request may see: everything, or only one salesman's own. */
export interface Scope {
  /** Set for a salesman limited to their own parties and documents. */
  ownerUserId?: string;
}

/**
 * A salesman is limited to the parties assigned to them and the documents they entered, unless the
 * business has switched that off. Everyone else sees everything.
 */
export const scopeOf = (user: JwtPayload, settings: { salesmanOwnDataOnly: boolean }): Scope =>
  user.role === 'salesman' && settings.salesmanOwnDataOnly ? { ownerUserId: user.sub } : {};
