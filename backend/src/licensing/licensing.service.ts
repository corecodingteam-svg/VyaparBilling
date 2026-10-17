import { ConflictException, ForbiddenException, Inject, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { effectiveFeatures } from '../auth/tenant-access';
import { Db, KYSELY } from '../database/database.module';
import { DeviceDto } from './licensing.dto';
import { lastDayOf, LicensePayload, loadSigningKey, signLicense, SigningKey } from './license-token';

const DAY = 86_400_000;

@Injectable()
export class LicensingService {
  private key: SigningKey | null | undefined;

  constructor(@Inject(KYSELY) private readonly db: Db) {}

  /** Loaded on first use so a server without a key still runs (everything but licensing). */
  private signingKey(): SigningKey {
    if (this.key === undefined) this.key = loadSigningKey(process.env.LICENSE_SIGNING_PRIVATE_KEY);
    if (!this.key) {
      throw new ServiceUnavailableException({ code: 'LICENSING_NOT_CONFIGURED', message: 'Licensing is not set up on this server (no signing key).' });
    }
    return this.key;
  }

  /**
   * Registers this installation on the company's licence (once; the same installation again is fine) and returns a
   * signed certificate. Refused when the licence is suspended or revoked, or when every device slot is taken.
   * A licence past its end date still gets a certificate: the device then shows exactly when it ended.
   */
  async activate(firmId: string, dto: DeviceDto) {
    const key = this.signingKey();
    return this.db.transaction().execute(async (trx) => {
      const license = await trx.selectFrom('licenses').selectAll().where('firm_id', '=', firmId).forUpdate().executeTakeFirst();
      if (!license) throw new NotFoundException({ code: 'NO_LICENSE', message: 'This business has no licence.' });
      this.mustBeActive(license);
      const existing = await trx.selectFrom('license_devices').select('id').where('license_id', '=', license.id).where('installation_id', '=', dto.installationId).executeTakeFirst();
      if (existing) {
        await trx.updateTable('license_devices').set({ last_seen_at: new Date(), device_name: dto.deviceName ?? null, platform: dto.platform ?? null }).where('id', '=', existing.id).execute();
      } else {
        const used = Number((await trx.selectFrom('license_devices').select((eb) => eb.fn.countAll().as('n')).where('license_id', '=', license.id).executeTakeFirstOrThrow()).n);
        if (used >= license.max_devices) {
          throw new ConflictException({ code: 'DEVICE_LIMIT', message: `This licence allows ${license.max_devices} ${license.max_devices === 1 ? 'device' : 'devices'} and all are in use. Remove one from the Businesses page, or ask your provider for more.` });
        }
        await trx.insertInto('license_devices').values({ license_id: license.id, installation_id: dto.installationId, device_name: dto.deviceName ?? null, platform: dto.platform ?? null }).execute();
      }
      return this.certificate(trx, license, firmId, dto.installationId, key);
    });
  }

  /** A fresh certificate for an installation that is already registered (also the daily check-in). */
  async refresh(firmId: string, installationId: string) {
    const key = this.signingKey();
    const license = await this.db.selectFrom('licenses').selectAll().where('firm_id', '=', firmId).executeTakeFirst();
    if (!license) throw new NotFoundException({ code: 'NO_LICENSE', message: 'This business has no licence.' });
    this.mustBeActive(license);
    const device = await this.db.selectFrom('license_devices').select('id').where('license_id', '=', license.id).where('installation_id', '=', installationId).executeTakeFirst();
    if (!device) throw new NotFoundException({ code: 'NOT_ACTIVATED', message: 'This device is not activated on the licence.' });
    await this.db.updateTable('license_devices').set({ last_seen_at: new Date() }).where('id', '=', device.id).execute();
    return this.certificate(this.db, license, firmId, installationId, key);
  }

  /** Frees this installation's slot. */
  async deactivate(firmId: string, installationId: string) {
    const license = await this.db.selectFrom('licenses').select('id').where('firm_id', '=', firmId).executeTakeFirst();
    if (license) await this.db.deleteFrom('license_devices').where('license_id', '=', license.id).where('installation_id', '=', installationId).execute();
  }

  private mustBeActive(license: { status: string; status_reason: string | null }) {
    if (license.status === 'active') return;
    const why = license.status_reason ? `: ${license.status_reason}` : '';
    throw new ForbiddenException(
      license.status === 'revoked'
        ? { code: 'LICENSE_REVOKED', message: `This licence has been revoked${why}.` }
        : { code: 'LICENSE_SUSPENDED', message: `This licence is suspended${why}.` },
    );
  }

  private async certificate(
    db: Pick<Db, 'selectFrom'>,
    license: { id: string; firm_id: string; product_id: string; valid_from: Date; expires_at: Date | null; max_devices: number; version: number },
    firmId: string,
    installationId: string,
    key: SigningKey,
  ) {
    const firm = await db.selectFrom('firms').select(['plan', 'features']).where('id', '=', firmId).executeTakeFirstOrThrow();
    const now = new Date();
    const checkinDays = Number(process.env.LICENSE_CHECKIN_DAYS ?? 30);
    const payload: LicensePayload = {
      v: 1,
      kid: key.kid,
      license_id: license.id,
      customer_id: firmId,
      installation_id: installationId,
      product_id: license.product_id,
      plan: firm.plan,
      status: 'active',
      issued_at: now.toISOString(),
      valid_from: new Date(license.valid_from).toISOString(),
      expires_at: license.expires_at ? license.expires_at.toISOString() : null,
      expires_on: lastDayOf(license.expires_at),
      max_devices: license.max_devices,
      license_version: license.version,
      server_timestamp: now.toISOString(),
      checkin_by: checkinDays > 0 ? new Date(now.getTime() + checkinDays * DAY).toISOString() : null,
      features: effectiveFeatures(firm.features),
      support_contact: process.env.LICENSE_SUPPORT_CONTACT || null,
    };
    return { certificate: signLicense(payload, key.privateKey), serverTime: now.toISOString() };
  }
}
