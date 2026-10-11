import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { Db, KYSELY } from '../database/database.module';
import type { MemberRole } from '../database/schema';

export interface JwtPayload {
  sub: string; // user id
  firmId: string; // the company this token works in
  email: string;
  role: MemberRole;
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
    const member = await this.db
      .selectFrom('firm_members')
      .select('role')
      .where('user_id', '=', payload.sub)
      .where('firm_id', '=', payload.firmId)
      .executeTakeFirst();
    if (!member) throw new UnauthorizedException({ code: 'NO_ACCESS', message: 'You no longer have access to this company.' });
    return { sub: payload.sub, firmId: payload.firmId, email: payload.email, role: member.role };
  }
}
