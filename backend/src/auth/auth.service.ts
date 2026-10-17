import {
  BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException, UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { promises as fs } from 'fs';
import { sql, Transaction } from 'kysely';
import * as path from 'path';
import { DEFAULT_EXPENSE_CATEGORIES, DEFAULT_UNITS } from '../common/default-units';
import { Db, KYSELY } from '../database/database.module';
import { Database } from '../database/schema';
import { AddMemberDto, ChangePasswordDto, CreateFirmDto, LoginDto, RegisterDto, UpdateMemberDto } from './dto/auth.dto';
import { JwtPayload } from './jwt.strategy';
import { effectiveFeatures } from './tenant-access';
import { audit } from '../platform/audit';
import { lastDayOf } from '../licensing/license-token';

// Compared against when the email is unknown, so response time doesn't reveal which emails exist.
const DUMMY_HASH = bcrypt.hashSync('not-a-real-password', 10);

/** A new company with the starter units and expense categories every company gets. */
export async function createFirm(trx: Transaction<Database>, values: { name: string; state_code: string | null; email?: string | null }) {
  const firm = await trx.insertInto('firms').values(values).returning('id').executeTakeFirstOrThrow();
  await trx.insertInto('units').values(DEFAULT_UNITS.map(([name, short_name]) => ({ firm_id: firm.id, name, short_name }))).execute();
  await trx.insertInto('expense_categories').values(DEFAULT_EXPENSE_CATEGORIES.map((name) => ({ firm_id: firm.id, name }))).execute();
  return firm.id;
}

@Injectable()
export class AuthService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly jwt: JwtService,
  ) {}

  async register(dto: RegisterDto) {
    // Once the owner has an account, a public server can close sign-up (ALLOW_SIGNUP=false). The first account is always allowed.
    if (process.env.ALLOW_SIGNUP === 'false') {
      const any = await this.db.selectFrom('users').select('id').limit(1).executeTakeFirst();
      if (any) throw new ForbiddenException({ code: 'SIGNUP_CLOSED', message: 'Sign-up is closed on this server. Ask the owner to add you as a user.' });
    }
    const existing = await this.db.selectFrom('users').select('id').where('email', '=', dto.email).executeTakeFirst();
    if (existing) throw new ConflictException({ code: 'EMAIL_TAKEN', message: 'An account with this email already exists.' });

    const passwordHash = await bcrypt.hash(dto.password, 10);
    const user = await this.db.transaction().execute(async (trx) => {
      const firmId = await createFirm(trx, { name: dto.firmName, state_code: dto.stateCode, email: dto.email });
      const created = await trx
        .insertInto('users')
        .values({ firm_id: firmId, email: dto.email, password_hash: passwordHash, full_name: dto.fullName })
        .returning(['id', 'firm_id', 'email'])
        .executeTakeFirstOrThrow();
      await trx.insertInto('firm_members').values({ firm_id: firmId, user_id: created.id, role: 'owner' }).execute();
      return created;
    });
    return this.issue(user.id, user.firm_id);
  }

  async login(dto: LoginDto) {
    const user = await this.db
      .selectFrom('users')
      .select(['id', 'firm_id', 'password_hash', 'disabled_at'])
      .where('email', '=', dto.email)
      .executeTakeFirst();
    const ok = await bcrypt.compare(dto.password, user?.password_hash ?? DUMMY_HASH);
    if (!user || !ok) {
      throw new UnauthorizedException({ code: 'INVALID_CREDENTIALS', message: 'Incorrect email or password.' });
    }
    if (user.disabled_at) throw new UnauthorizedException({ code: 'ACCOUNT_DISABLED', message: 'This login has been disabled. Contact your provider.' });
    // Open the company they last used, or any company they still belong to.
    const memberships = await this.db.selectFrom('firm_members').select('firm_id').where('user_id', '=', user.id).orderBy('created_at').execute();
    const firmId = memberships.find((m) => m.firm_id === user.firm_id)?.firm_id ?? memberships[0]?.firm_id;
    if (!firmId) throw new UnauthorizedException({ code: 'NO_ACCESS', message: 'This login no longer has access to any company.' });
    return this.issue(user.id, firmId);
  }

  /** The master admin's own sign-in (its own page and endpoint; the business sign-in never accepts it). */
  async masterLogin(dto: LoginDto) {
    const master = await this.db.selectFrom('master_admin').select(['id', 'email', 'password_hash']).where('email', '=', dto.email).executeTakeFirst();
    const ok = await bcrypt.compare(dto.password, master?.password_hash ?? DUMMY_HASH);
    if (!master || !ok) throw new UnauthorizedException({ code: 'INVALID_CREDENTIALS', message: 'Incorrect email or password.' });
    await audit(this.db, master.email, { action: 'master.login' });
    return this.issueMaster(master.id);
  }

  async changePassword(userId: string, dto: ChangePasswordDto, master = false) {
    if (master) {
      const admin = await this.db.selectFrom('master_admin').select(['password_hash', 'email']).where('id', '=', userId).executeTakeFirst();
      if (!admin || !(await bcrypt.compare(dto.currentPassword, admin.password_hash))) {
        throw new UnauthorizedException({ code: 'WRONG_PASSWORD', message: 'Current password is incorrect.' });
      }
      await this.db.updateTable('master_admin').set({ password_hash: await bcrypt.hash(dto.newPassword, 10), updated_at: new Date() }).where('id', '=', userId).execute();
      await audit(this.db, admin.email, { action: 'master.password_changed' });
      return;
    }
    const user = await this.db.selectFrom('users').select('password_hash').where('id', '=', userId).executeTakeFirst();
    if (!user || !(await bcrypt.compare(dto.currentPassword, user.password_hash))) {
      throw new UnauthorizedException({ code: 'WRONG_PASSWORD', message: 'Current password is incorrect.' });
    }
    await this.db.updateTable('users').set({ password_hash: await bcrypt.hash(dto.newPassword, 10) }).where('id', '=', userId).execute();
  }

  async me(userId: string, firmId: string) {
    const row = await this.db
      .selectFrom('firm_members as m')
      .innerJoin('users as u', 'u.id', 'm.user_id')
      .innerJoin('firms as f', 'f.id', 'm.firm_id')
      .leftJoin('licenses as l', 'l.firm_id', 'f.id')
      .select(['u.id', 'u.email', 'u.full_name', 'm.role', 'f.id as firm_id', 'f.name as firm_name', 'f.state_code', 'f.gstin', 'f.features', 'f.plan', 'l.status as license_status', 'l.expires_at'])
      .where('m.user_id', '=', userId)
      .where('m.firm_id', '=', firmId)
      .executeTakeFirst();
    if (!row) throw new NotFoundException();
    return {
      id: row.id,
      email: row.email,
      fullName: row.full_name,
      role: row.role,
      firm: { id: row.firm_id, name: row.firm_name, stateCode: row.state_code, gstin: row.gstin },
      // What the provider allows this business; the server enforces it on every request.
      features: effectiveFeatures(row.features),
      plan: row.plan,
      licenceExpiresOn: lastDayOf(row.expires_at),
      licenceStatus: row.license_status ?? 'active',
      platformAdmin: false,
    };
  }

  /** Who the master admin is: no business, only the master pages. */
  async masterMe(id: string) {
    const admin = await this.db.selectFrom('master_admin').select(['id', 'email', 'full_name']).where('id', '=', id).executeTakeFirst();
    if (!admin) throw new NotFoundException();
    return { id: admin.id, email: admin.email, fullName: admin.full_name, role: 'master', firm: null, features: {}, plan: '', platformAdmin: true, master: true };
  }

  async issueMaster(id: string) {
    const user = await this.masterMe(id);
    const payload = { sub: id, firmId: '', email: user.email, master: true };
    return { accessToken: await this.jwt.signAsync(payload), user };
  }

  /** A token for [userId] working in [firmId]; that company is remembered as their current one. */
  async issue(userId: string, firmId: string) {
    const user = await this.me(userId, firmId);
    await this.db.updateTable('users').set({ firm_id: firmId }).where('id', '=', userId).execute();
    const payload: Omit<JwtPayload, 'role'> = { sub: userId, firmId, email: user.email };
    return { accessToken: await this.jwt.signAsync(payload), user };
  }

  // ---------------------------------------------------------------- companies

  async firms(user: JwtPayload) {
    const rows = await this.db
      .selectFrom('firm_members as m')
      .innerJoin('firms as f', 'f.id', 'm.firm_id')
      .select(['f.id', 'f.name', 'm.role'])
      .where('m.user_id', '=', user.sub)
      .orderBy('m.created_at')
      .execute();
    return rows.map((r) => ({ id: r.id, name: r.name, role: r.role, current: r.id === user.firmId }));
  }

  /** Creates another company owned by this login. Call switchFirm to start working in it. */
  async createFirm(user: JwtPayload, dto: CreateFirmDto) {
    const firmId = await this.db.transaction().execute(async (trx) => {
      const id = await createFirm(trx, { name: dto.firmName, state_code: dto.stateCode, email: user.email });
      await trx.insertInto('firm_members').values({ firm_id: id, user_id: user.sub, role: 'owner' }).execute();
      return id;
    });
    return { id: firmId, name: dto.firmName, role: 'owner' as const, current: false };
  }

  /**
   * Deletes a company and everything in it, for good. Only its owner can, only while working in another
   * company, and only by typing its name. People whose only company it was lose their login with it.
   */
  async deleteFirm(user: JwtPayload, firmId: string, name: string) {
    if (firmId === user.firmId) {
      throw new BadRequestException({ code: 'CURRENT_FIRM', message: 'Switch to another company first; the one you are working in cannot be deleted.' });
    }
    const firm = await this.db
      .selectFrom('firm_members as m').innerJoin('firms as f', 'f.id', 'm.firm_id').select(['f.name', 'm.role'])
      .where('m.user_id', '=', user.sub).where('m.firm_id', '=', firmId).executeTakeFirst();
    if (!firm || firm.role !== 'owner') throw new ForbiddenException({ code: 'NOT_OWNER', message: 'Only the owner of a company can delete it.' });
    if (firm.name.trim().toLowerCase() !== name.trim().toLowerCase()) {
      throw new BadRequestException({ code: 'NAME_MISMATCH', message: 'Type the company name exactly to confirm.' });
    }
    await this.db.transaction().execute(async (trx) => {
      // A login belongs to a "home" company; move it to another company the person is in before this one goes.
      await sql`update users u set firm_id = (select m.firm_id from firm_members m where m.user_id = u.id and m.firm_id <> ${firmId} order by m.created_at limit 1)
                 where u.firm_id = ${firmId}
                   and exists (select 1 from firm_members m where m.user_id = u.id and m.firm_id <> ${firmId})`.execute(trx);
      await trx.deleteFrom('firms').where('id', '=', firmId).execute();
    });
    await fs.rm(path.join(process.env.BACKUP_DIR ?? path.join(process.cwd(), 'backups'), firmId), { recursive: true, force: true });
  }

  async switchFirm(user: JwtPayload, firmId: string) {
    const member = await this.db.selectFrom('firm_members').select('role').where('user_id', '=', user.sub).where('firm_id', '=', firmId).executeTakeFirst();
    if (!member) throw new ForbiddenException({ code: 'NO_ACCESS', message: 'You do not have access to that company.' });
    return this.issue(user.sub, firmId);
  }

  // ---------------------------------------------------------------- people in the current company

  async members(firmId: string) {
    const rows = await this.db
      .selectFrom('firm_members as m')
      .innerJoin('users as u', 'u.id', 'm.user_id')
      .select(['u.id', 'u.full_name', 'u.email', 'm.role'])
      .where('m.firm_id', '=', firmId)
      .orderBy('m.created_at')
      .execute();
    return rows.map((r) => ({ id: r.id, fullName: r.full_name, email: r.email, role: r.role }));
  }

  async addMember(firmId: string, dto: AddMemberDto) {
    let user = await this.db.selectFrom('users').select('id').where('email', '=', dto.email).executeTakeFirst();
    if (user) {
      const already = await this.db.selectFrom('firm_members').select('role').where('firm_id', '=', firmId).where('user_id', '=', user.id).executeTakeFirst();
      if (already) throw new ConflictException({ code: 'ALREADY_MEMBER', message: 'This person already has access to this company.' });
    } else {
      // Their login lands in this company; the password given here is theirs to change.
      user = await this.db
        .insertInto('users')
        .values({ firm_id: firmId, email: dto.email, password_hash: await bcrypt.hash(dto.password, 10), full_name: dto.fullName })
        .returning('id')
        .executeTakeFirstOrThrow();
    }
    await this.db.insertInto('firm_members').values({ firm_id: firmId, user_id: user.id, role: dto.role }).execute();
    return (await this.members(firmId)).find((m) => m.id === user!.id);
  }

  async updateMember(firmId: string, userId: string, dto: UpdateMemberDto) {
    await this.assertNotOwner(firmId, userId);
    await this.db.updateTable('firm_members').set({ role: dto.role }).where('firm_id', '=', firmId).where('user_id', '=', userId).execute();
    return (await this.members(firmId)).find((m) => m.id === userId);
  }

  async removeMember(actor: JwtPayload, userId: string) {
    if (userId === actor.sub) throw new BadRequestException({ code: 'CANNOT_REMOVE_SELF', message: 'You cannot remove yourself.' });
    await this.assertNotOwner(actor.firmId, userId);
    await this.db.deleteFrom('firm_members').where('firm_id', '=', actor.firmId).where('user_id', '=', userId).execute();
  }

  private async assertNotOwner(firmId: string, userId: string) {
    const member = await this.db.selectFrom('firm_members').select('role').where('firm_id', '=', firmId).where('user_id', '=', userId).executeTakeFirst();
    if (!member) throw new NotFoundException({ code: 'MEMBER_NOT_FOUND', message: 'This person is not in this company.' });
    if (member.role === 'owner') throw new ForbiddenException({ code: 'OWNER_PROTECTED', message: "The owner's access cannot be changed." });
  }
}
