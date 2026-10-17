import { ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import type { MemberRole } from '../database/schema';
import { JwtPayload } from './jwt.strategy';
import { ROLES_KEY } from './roles';
import { tenantRefusal } from './tenant-access';

/** Requires a valid token and, where @Roles(...) is set, one of those roles in the current company. */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private readonly reflector: Reflector) {
    super();
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (!(await super.canActivate(context))) return false;
    // What the provider allows this business (POS only, features, licence, suspension).
    const req = context.switchToHttp().getRequest();
    const path = String(req.path ?? '').replace(/^\/api\/v1/, '') || '/';
    if ((req.user as JwtPayload).master) {
      // The master admin account has no business: it may only manage businesses, and its own sign-in.
      if (path.startsWith('/platform') || path === '/auth/me' || path === '/auth/change-password') return true;
      throw new ForbiddenException({ code: 'MASTER_ONLY', message: 'The master admin account only manages businesses.' });
    }
    const tenant = (req.user as JwtPayload).tenant;
    if (tenant) {
      const refusal = tenantRefusal({ method: req.method, path: path, query: req.query ?? {}, body: req.body }, tenant);
      if (refusal) throw new ForbiddenException(refusal);
    }
    const allowed = this.reflector.getAllAndOverride<MemberRole[] | undefined>(ROLES_KEY, [context.getHandler(), context.getClass()]);
    if (!allowed) return true;
    const user = context.switchToHttp().getRequest().user as JwtPayload;
    if (!allowed.includes(user.role)) {
      throw new ForbiddenException({ code: 'FORBIDDEN', message: 'Your role does not have access to this.' });
    }
    return true;
  }
}
