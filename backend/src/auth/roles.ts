import { SetMetadata } from '@nestjs/common';
import type { MemberRole } from '../database/schema';

export const ROLES_KEY = 'roles';

/** Restricts a controller or handler to these roles (checked by JwtAuthGuard). No decorator = any member. */
export const Roles = (...roles: MemberRole[]) => SetMetadata(ROLES_KEY, roles);

/** Everyone except salesmen: full access to the books. */
export const STAFF: MemberRole[] = ['owner', 'admin', 'accountant'];

/** Can manage users and company-level settings. */
export const ADMINS: MemberRole[] = ['owner', 'admin'];
