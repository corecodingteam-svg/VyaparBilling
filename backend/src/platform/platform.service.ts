import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { randomInt } from 'crypto';
import { sql } from 'kysely';
import { expiresAtFor, lastDayOf } from '../licensing/license-token';
import { createFirm } from '../auth/auth.service';
import { effectiveFeatures, FEATURE_DEFAULTS, FEATURE_LABELS, PLANS } from '../auth/tenant-access';
import { Db, KYSELY } from '../database/database.module';
import { audit } from './audit';
import { CreateTenantDto, UpdateTenantDto } from './platform.dto';

/** Only the switches that exist, and only true/false values. */
function cleanFeatures(input: Record<string, boolean> | undefined): Record<string, boolean> {
  const out: Record<string, boolean> = {};
  for (const [k, v] of Object.entries(input ?? {})) {
    if (!(k in FEATURE_DEFAULTS)) throw new BadRequestException({ code: 'UNKNOWN_FEATURE', message: `"${k}" is not a feature.` });
    if (typeof v !== 'boolean') throw new BadRequestException({ code: 'BAD_FEATURE', message: `"${k}" must be on or off.` });
    out[k] = v;
  }
  return out;
}

/** What the businesses on this server are allowed to use. Reached only by provider staff (PlatformAdminGuard). */
@Injectable()
export class PlatformService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  catalog() {
    return {
      plans: Object.entries(PLANS).map(([id, p]) => ({ id, label: p.label, features: effectiveFeatures(p.features) })),
      features: Object.entries(FEATURE_LABELS).map(([id, label]) => ({ id, label, default: FEATURE_DEFAULTS[id as keyof typeof FEATURE_DEFAULTS] })),
    };
  }

  async list(q?: string) {
    let query = this.db
      .selectFrom('firms as f')
      .leftJoin('licenses as l', 'l.firm_id', 'f.id')
      .select([
        'f.id', 'f.name', 'f.plan', 'f.features', 'f.created_at',
        'l.id as license_id', 'l.status', 'l.status_reason', 'l.expires_at', 'l.max_devices', 'l.version', 'l.valid_from',
        sql<number>`(select count(*)::int from firm_members m where m.firm_id = f.id)`.as('members'),
        sql<string | null>`(select u.email from firm_members m join users u on u.id = m.user_id where m.firm_id = f.id and m.role = 'owner' order by m.created_at limit 1)`.as('owner_email'),
        sql<number>`(select count(*)::int from invoices i where i.firm_id = f.id and i.type = 'sale' and i.deleted_at is null and i.invoice_date >= current_date - 30)`.as('sales_30d'),
      ])
      .orderBy('f.created_at', 'desc');
    if (q?.trim()) {
      const like = `%${q.trim().toLowerCase()}%`;
      query = query.where((eb) => eb.or([eb(sql`lower(f.name)`, 'like', like), eb(sql`lower((select u.email from firm_members m join users u on u.id = m.user_id where m.firm_id = f.id and m.role = 'owner' limit 1))`, 'like', like)]));
    }
    const rows = await query.execute();
    const devices = rows.length
      ? await this.db.selectFrom('license_devices').selectAll().where('license_id', 'in', rows.map((r) => r.license_id).filter((x): x is string => !!x)).orderBy('activated_at').execute()
      : [];
    return rows.map((r) => ({
      id: r.id,
      name: r.name,
      plan: r.plan,
      features: effectiveFeatures(r.features),
      createdAt: r.created_at,
      members: r.members,
      ownerEmail: r.owner_email,
      sales30d: r.sales_30d,
      license: {
        id: r.license_id,
        status: r.status ?? 'active',
        statusReason: r.status_reason,
        validFrom: r.valid_from,
        expiresOn: lastDayOf(r.expires_at),
        expired: r.expires_at !== null && r.expires_at.getTime() <= Date.now(),
        maxDevices: r.max_devices ?? 5,
        version: r.version ?? 1,
        devices: devices
          .filter((d) => d.license_id === r.license_id)
          .map((d) => ({ id: d.id, installationId: d.installation_id, name: d.device_name, platform: d.platform, activatedAt: d.activated_at, lastSeenAt: d.last_seen_at })),
      },
    }));
  }

  /** Signs up a new business: the company, its owner's login, and the plan it is on. */
  async create(actor: string, dto: CreateTenantDto) {
    const extra = cleanFeatures(dto.features);
    const taken = await this.db.selectFrom('users').select('id').where('email', '=', dto.ownerEmail).executeTakeFirst();
    if (taken) throw new ConflictException({ code: 'EMAIL_TAKEN', message: 'An account with this email already exists.' });
    const hash = await bcrypt.hash(dto.ownerPassword, 10);
    const id = await this.db.transaction().execute(async (trx) => {
      const firmId = await createFirm(trx, { name: dto.firmName, state_code: dto.stateCode, email: dto.ownerEmail });
      await trx.updateTable('firms').set({ plan: dto.plan, features: JSON.stringify({ ...PLANS[dto.plan].features, ...extra }) }).where('id', '=', firmId).execute();
      // The company's licence row was made by the database; set its end date and device limit.
      await trx
        .updateTable('licenses')
        .set({ expires_at: dto.licenceExpiresOn ? expiresAtFor(dto.licenceExpiresOn) : null, max_devices: dto.maxDevices ?? 5 })
        .where('firm_id', '=', firmId)
        .execute();
      const user = await trx
        .insertInto('users')
        .values({ firm_id: firmId, email: dto.ownerEmail, password_hash: hash, full_name: dto.ownerName })
        .returning('id')
        .executeTakeFirstOrThrow();
      await trx.insertInto('firm_members').values({ firm_id: firmId, user_id: user.id, role: 'owner' }).execute();
      await audit(trx, actor, {
        action: 'tenant.created',
        firmId,
        firmName: dto.firmName,
        target: dto.ownerEmail,
        details: { plan: dto.plan, features: extra, licenceExpiresOn: dto.licenceExpiresOn ?? null, maxDevices: dto.maxDevices ?? 5 },
      });
      return firmId;
    });
    return this.get(id);
  }

  async get(id: string) {
    const row = (await this.list()).find((t) => t.id === id);
    if (!row) throw new NotFoundException({ code: 'NOT_FOUND', message: 'That business was not found.' });
    return row;
  }

  async update(actor: string, id: string, dto: UpdateTenantDto) {
    const current = await this.db.selectFrom('firms').select(['features', 'name']).where('id', '=', id).executeTakeFirst();
    if (!current) throw new NotFoundException({ code: 'NOT_FOUND', message: 'That business was not found.' });
    const firmSet: Record<string, unknown> = {};
    if (dto.plan !== undefined || dto.features !== undefined) {
      // A new plan starts from its own switches; individual switches then override.
      const base = dto.plan !== undefined ? { ...PLANS[dto.plan].features } : { ...current.features };
      firmSet.features = JSON.stringify({ ...base, ...cleanFeatures(dto.features) });
    }
    if (dto.plan !== undefined) firmSet.plan = dto.plan;
    const licenseSet: Record<string, unknown> = {};
    if (dto.licenceExpiresOn !== undefined) licenseSet.expires_at = dto.licenceExpiresOn ? expiresAtFor(dto.licenceExpiresOn) : null;
    if (dto.maxDevices !== undefined) licenseSet.max_devices = dto.maxDevices;
    if (dto.status !== undefined) {
      licenseSet.status = dto.status;
      licenseSet.status_reason = dto.status === 'active' ? null : (dto.statusReason ?? null);
    }
    await this.db.transaction().execute(async (trx) => {
      if (Object.keys(firmSet).length) await trx.updateTable('firms').set({ ...firmSet, updated_at: new Date() } as never).where('id', '=', id).execute();
      // Anything that is in a certificate raises the licence version, so devices know theirs is out of date.
      if (Object.keys(licenseSet).length || Object.keys(firmSet).length) {
        await trx.updateTable('licenses').set({ ...licenseSet, version: sql`version + 1`, updated_at: new Date() } as never).where('firm_id', '=', id).execute();
      }
      // Suspend / revoke / reinstate get their own entry so they are easy to find; any other change is "updated".
      const action = dto.status === 'active' ? 'license.reinstated' : dto.status ? `license.${dto.status}` : 'tenant.updated';
      await audit(trx, actor, { action, firmId: id, firmName: current.name, details: { ...dto } });
    });
    return this.get(id);
  }

  /** Frees a device slot, e.g. for a lost phone. */
  async removeDevice(actor: string, firmId: string, deviceId: string) {
    const firm = await this.firm(firmId);
    const license = await this.db.selectFrom('licenses').select('id').where('firm_id', '=', firmId).executeTakeFirst();
    if (!license) throw new NotFoundException({ code: 'NOT_FOUND', message: 'That business was not found.' });
    const removed = await this.db.deleteFrom('license_devices').where('license_id', '=', license.id).where('id', '=', deviceId).returning(['installation_id', 'device_name']).executeTakeFirst();
    if (removed) {
      await audit(this.db, actor, { action: 'device.removed', firmId, firmName: firm.name, target: `${removed.device_name ?? 'device'} ${removed.installation_id.slice(0, 8)}` });
    }
    return this.get(firmId);
  }

  private async firm(id: string) {
    const firm = await this.db.selectFrom('firms').select(['id', 'name']).where('id', '=', id).executeTakeFirst();
    if (!firm) throw new NotFoundException({ code: 'NOT_FOUND', message: 'That business was not found.' });
    return firm;
  }

  /** A user of [firmId], or 404: the master admin acts on a business's users only through that business. */
  private async member(firmId: string, userId: string) {
    const m = await this.db
      .selectFrom('firm_members as m')
      .innerJoin('users as u', 'u.id', 'm.user_id')
      .select(['u.id', 'u.email', 'u.full_name', 'u.disabled_at', 'm.role'])
      .where('m.firm_id', '=', firmId)
      .where('m.user_id', '=', userId)
      .executeTakeFirst();
    if (!m) throw new NotFoundException({ code: 'NOT_FOUND', message: 'That user is not in this business.' });
    return m;
  }

  // ---------------------------------------------------------------- a business's users

  async users(firmId: string) {
    await this.firm(firmId);
    const rows = await this.db
      .selectFrom('firm_members as m')
      .innerJoin('users as u', 'u.id', 'm.user_id')
      .select(['u.id', 'u.email', 'u.full_name', 'u.disabled_at', 'u.created_at', 'm.role'])
      .where('m.firm_id', '=', firmId)
      .orderBy('m.created_at')
      .execute();
    return rows.map((r) => ({ id: r.id, email: r.email, fullName: r.full_name, role: r.role, disabled: r.disabled_at !== null, createdAt: r.created_at }));
  }

  /** A new random password for a user (e.g. an owner who forgot theirs). Returned once; only the fact is logged. */
  async resetPassword(actor: string, firmId: string, userId: string) {
    const firm = await this.firm(firmId);
    const m = await this.member(firmId, userId);
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    const password = Array.from({ length: 12 }, () => alphabet[randomInt(alphabet.length)]).join('');
    await this.db.updateTable('users').set({ password_hash: await bcrypt.hash(password, 10) }).where('id', '=', userId).execute();
    await audit(this.db, actor, { action: 'user.password_reset', firmId, firmName: firm.name, target: m.email });
    return { email: m.email, password };
  }

  /** Disables or re-enables a login. A login can be in several businesses; disabling it stops it everywhere. */
  async setDisabled(actor: string, firmId: string, userId: string, disabled: boolean) {
    const firm = await this.firm(firmId);
    const m = await this.member(firmId, userId);
    await this.db.updateTable('users').set({ disabled_at: disabled ? new Date() : null }).where('id', '=', userId).execute();
    await audit(this.db, actor, { action: disabled ? 'user.disabled' : 'user.enabled', firmId, firmName: firm.name, target: m.email });
    return this.users(firmId);
  }

  /** Makes [userId] the business's owner; whoever was owner becomes an admin. */
  async setOwner(actor: string, firmId: string, userId: string) {
    const firm = await this.firm(firmId);
    const m = await this.member(firmId, userId);
    await this.db.transaction().execute(async (trx) => {
      const before = await trx
        .selectFrom('firm_members as m')
        .innerJoin('users as u', 'u.id', 'm.user_id')
        .select('u.email')
        .where('m.firm_id', '=', firmId)
        .where('m.role', '=', 'owner')
        .execute();
      await trx.updateTable('firm_members').set({ role: 'admin' }).where('firm_id', '=', firmId).where('role', '=', 'owner').where('user_id', '<>', userId).execute();
      await trx.updateTable('firm_members').set({ role: 'owner' }).where('firm_id', '=', firmId).where('user_id', '=', userId).execute();
      await audit(trx, actor, { action: 'tenant.owner_changed', firmId, firmName: firm.name, target: m.email, details: { previousOwners: before.map((b) => b.email) } });
    });
    return this.users(firmId);
  }

  // ---------------------------------------------------------------- audit log

  async auditLog(firmId: string | undefined, limit: number) {
    let q = this.db.selectFrom('platform_audit').selectAll().orderBy('at', 'desc').orderBy('id', 'desc').limit(Math.min(Math.max(limit, 1), 1000));
    if (firmId && /^[0-9a-f-]{36}$/i.test(firmId)) q = q.where('firm_id', '=', firmId);
    return (await q.execute()).map((r) => ({
      id: String(r.id),
      at: r.at,
      actor: r.actor_email,
      action: r.action,
      firmId: r.firm_id,
      firmName: r.firm_name,
      target: r.target,
      details: r.details,
    }));
  }
}
