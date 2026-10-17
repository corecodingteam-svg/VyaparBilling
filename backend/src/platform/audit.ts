import { Db } from '../database/database.module';

/** One line in the master admin's audit log. The password of a reset is never recorded. */
export interface AuditEntry {
  action: string;
  firmId?: string | null;
  firmName?: string | null;
  /** Who or what it was about, e.g. a user's email or a device. */
  target?: string | null;
  details?: Record<string, unknown>;
}

export async function audit(db: Pick<Db, 'insertInto'>, actorEmail: string, e: AuditEntry): Promise<void> {
  await db
    .insertInto('platform_audit')
    .values({
      actor_email: actorEmail,
      action: e.action,
      firm_id: e.firmId ?? null,
      firm_name: e.firmName ?? null,
      target: e.target ?? null,
      details: JSON.stringify(e.details ?? {}),
    })
    .execute();
}
