import { ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import type { MemberRole } from '../database/schema';
import { JwtPayload } from './jwt.strategy';
import { ROLES_KEY } from './roles';

/** Requires a valid token and, where @Roles(...) is set, one of those roles in the current company. */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private readonly reflector: Reflector) {
    super();
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (!(await super.canActivate(context))) return false;
    const allowed = this.reflector.getAllAndOverride<MemberRole[] | undefined>(ROLES_KEY, [context.getHandler(), context.getClass()]);
    if (!allowed) return true;
    const user = context.switchToHttp().getRequest().user as JwtPayload;
    if (!allowed.includes(user.role)) {
      throw new ForbiddenException({ code: 'FORBIDDEN', message: 'Your role does not have access to this.' });
    }
    return true;
  }
}
