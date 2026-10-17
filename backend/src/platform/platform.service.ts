import { BadRequestException, ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { sql } from 'kysely';
import { expiresAtFor, lastDayOf } from '../licensing/license-token';
import { createFirm } from '../auth/auth.service';
import { effectiveFeatures, FEATURE_DEFAULTS, FEATURE_LABELS, PLANS } from '../auth/tenant-access';
import { Db, KYSELY } from '../database/database.module';
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
  async create(dto: CreateTenantDto) {
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
      return firmId;
    });
    return this.get(id);
  }

  async get(id: string) {
    const row = (await this.list()).find((t) => t.id === id);
    if (!row) throw new NotFoundException({ code: 'NOT_FOUND', message: 'That business was not found.' });
    return row;
  }

  async update(id: string, dto: UpdateTenantDto) {
    const current = await this.db.selectFrom('firms').select(['features']).where('id', '=', id).executeTakeFirst();
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
    });
    return this.get(id);
  }

  /** Frees a device slot, e.g. for a lost phone. */
  async removeDevice(firmId: string, deviceId: string) {
    const license = await this.db.selectFrom('licenses').select('id').where('firm_id', '=', firmId).executeTakeFirst();
    if (!license) throw new NotFoundException({ code: 'NOT_FOUND', message: 'That business was not found.' });
    await this.db.deleteFrom('license_devices').where('license_id', '=', license.id).where('id', '=', deviceId).execute();
    return this.get(firmId);
  }
}
