import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { Db, KYSELY } from '../database/database.module';
import type { MemberRole } from '../database/schema';
import { lastDayOf } from '../licensing/license-token';
import { effectiveFeatures, TenantInfo } from './tenant-access';

export interface JwtPayload {
  sub: string; // user id
  firmId: string; // the company this token works in
  email: string;
  role: MemberRole;
  /** What the provider allows this company; read fresh on every request. */
  tenant?: TenantInfo;
  /** The master admin (the provider): belongs to no business, may only use /platform. firmId is then ''. */
  master?: boolean;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    config: ConfigService,
    @Inject(KYSELY) private readonly db: Db,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.getOrThrow<string>('JWT_SECRET'),
    });
  }

  /** The role is read fresh on every request, so removing someone from a company takes effect at once. */
  async validate(payload: Omit<JwtPayload, 'role'>): Promise<JwtPayload> {
    if (payload.master) {
      const admin = await this.db.selectFrom('master_admin').select(['id', 'email']).where('id', '=', payload.sub).executeTakeFirst();
      if (!admin) throw new UnauthorizedException({ code: 'NO_ACCESS', message: 'This master admin account no longer exists.' });
      return { sub: admin.id, firmId: '', email: admin.email, role: 'owner', master: true };
    }
    const member = await this.db
      .selectFrom('firm_members as m')
      .innerJoin('firms as f', 'f.id', 'm.firm_id')
      .leftJoin('licenses as l', 'l.firm_id', 'm.firm_id')
      .innerJoin('users as u', 'u.id', 'm.user_id')
      .select(['u.disabled_at', 'm.role', 'f.features', 'f.plan', 'l.status', 'l.status_reason', 'l.expires_at'])
      .where('m.user_id', '=', payload.sub)
      .where('m.firm_id', '=', payload.firmId)
      .executeTakeFirst();
    if (!member) throw new UnauthorizedException({ code: 'NO_ACCESS', message: 'You no longer have access to this company.' });
    if (member.disabled_at) throw new UnauthorizedException({ code: 'ACCOUNT_DISABLED', message: 'This login has been disabled. Contact your provider.' });
    const tenant: TenantInfo = {
      features: effectiveFeatures(member.features),
      plan: member.plan,
      licenceStatus: member.status ?? 'active',
      licenceReason: member.status_reason,
      licenceExpiresOn: lastDayOf(member.expires_at),
      licenceExpired: member.expires_at !== null && member.expires_at.getTime() <= Date.now(),
    };
    return { sub: payload.sub, firmId: payload.firmId, email: payload.email, role: member.role, tenant };
  }
}
