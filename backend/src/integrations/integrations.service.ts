import { BadRequestException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { decryptSecrets, encryptSecrets, mask } from '../common/secrets';
import { Db, KYSELY } from '../database/database.module';
import type { Provider } from '../database/schema';
import { PROVIDERS, specOf } from './providers';

export interface Credentials {
  /** Plain settings. */
  config: Record<string, string>;
  /** Decrypted secrets. */
  secrets: Record<string, string>;
}

@Injectable()
export class IntegrationsService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  /** The stored settings and decrypted secrets of a provider, or null when it is not set up. */
  async credentials(firmId: string, provider: Provider): Promise<Credentials | null> {
    const row = await this.db.selectFrom('integrations').selectAll().where('firm_id', '=', firmId).where('provider', '=', provider).executeTakeFirst();
    if (!row) return null;
    return { config: row.config as Record<string, string>, secrets: decryptSecrets(row.secrets) };
  }

  /**
   * Every provider with whether it is set up and its non-secret settings. Secrets are only ever shown
   * as their last four characters, so the screen can tell they are stored.
   */
  async status(firmId: string) {
    const rows = await this.db.selectFrom('integrations').selectAll().where('firm_id', '=', firmId).execute();
    return PROVIDERS.map((spec) => {
      const row = rows.find((r) => r.provider === spec.provider);
      const secrets = decryptSecrets(row?.secrets);
      const config = (row?.config ?? {}) as Record<string, string>;
      const missing = spec.fields.filter((f) => f.required && !(f.secret ? secrets[f.key] : config[f.key]));
      return {
        provider: spec.provider,
        title: spec.title,
        help: spec.help,
        connected: !!row && missing.length === 0 && (spec.provider !== 'google_profile' || !!secrets.refreshToken),
        fields: spec.fields.map((f) => ({
          key: f.key,
          label: f.label,
          secret: !!f.secret,
          required: !!f.required,
          help: f.help ?? null,
          options: f.options ?? null,
          value: f.secret ? null : (config[f.key] ?? ''),
          stored: f.secret ? mask(secrets[f.key]) : null,
        })),
        // Google Business Profile keeps the account it was connected as and the chosen listing in its settings.
        info: spec.provider === 'google_profile' ? { email: config.email ?? null, location: config.locationName ?? null } : null,
      };
    });
  }

  /** Saves the sent fields; a secret left empty keeps the stored one. */
  async save(firmId: string, provider: Provider, values: Record<string, string>) {
    const spec = specOf(provider);
    const current = (await this.credentials(firmId, provider)) ?? { config: {}, secrets: {} };
    const config = { ...current.config };
    const secrets = { ...current.secrets };
    for (const f of spec.fields) {
      const v = values[f.key]?.trim();
      if (v === undefined) continue;
      if (f.options && v && !f.options.includes(v)) {
        throw new BadRequestException({ code: 'BAD_VALUE', message: `${f.label} must be one of: ${f.options.join(', ')}.` });
      }
      if (f.secret) {
        if (v) secrets[f.key] = v;
      } else if (v) {
        config[f.key] = v;
      } else {
        delete config[f.key];
      }
    }
    const missing = spec.fields.filter((f) => f.required && !(f.secret ? secrets[f.key] : config[f.key]));
    if (missing.length) throw new BadRequestException({ code: 'MISSING_FIELDS', message: `Fill in: ${missing.map((f) => f.label).join(', ')}.` });
    await this.write(firmId, provider, config, secrets);
  }

  /** Writes settings and secrets as they are (providers that learn values themselves, like Google's tokens, use this). */
  async write(firmId: string, provider: Provider, config: Record<string, string>, secrets: Record<string, string>) {
    const values = { config: JSON.stringify(config), secrets: Object.keys(secrets).length ? encryptSecrets(secrets) : null, updated_at: new Date() };
    await this.db
      .insertInto('integrations')
      .values({ firm_id: firmId, provider, ...values })
      .onConflict((oc) => oc.columns(['firm_id', 'provider']).doUpdateSet(values))
      .execute();
  }

  async remove(firmId: string, provider: Provider) {
    const res = await this.db.deleteFrom('integrations').where('firm_id', '=', firmId).where('provider', '=', provider).executeTakeFirst();
    if (!res.numDeletedRows) throw new NotFoundException({ code: 'NOT_CONNECTED', message: 'This is not set up.' });
  }
}
