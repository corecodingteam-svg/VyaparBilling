import { CallHandler, ConflictException, ExecutionContext, Inject, Injectable, NestInterceptor } from '@nestjs/common';
import type { Request } from 'express';
import { Observable, from, of } from 'rxjs';
import { Db, KYSELY } from '../database/database.module';

/**
 * A save sent with an Idempotency-Key header is applied once. The phone app keeps saves made without a connection and
 * sends them again later, possibly more than once if the reply was lost; the second arrival gets the first answer back
 * instead of creating a second invoice. Keys are kept for a week.
 */
@Injectable()
export class IdempotencyInterceptor implements NestInterceptor {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req = context.switchToHttp().getRequest<Request & { user?: { firmId?: string } }>();
    const key = req.headers['idempotency-key'];
    const firmId = req.user?.firmId;
    if (typeof key !== 'string' || !/^[A-Za-z0-9_-]{16,80}$/.test(key) || !firmId || !['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) return next.handle();
    return from(this.run(firmId, key, req, next));
  }

  private async run(firmId: string, key: string, req: Request, next: CallHandler): Promise<unknown> {
    // The row is the lock: whoever inserts it runs the request, everyone else waits for or reuses its answer.
    const claimed = await this.db
      .insertInto('idempotency_keys')
      .values({ firm_id: firmId, key, method: req.method, path: req.path, status: 0, response: null })
      .onConflict((oc) => oc.columns(['firm_id', 'key']).doNothing())
      .returning('key')
      .executeTakeFirst();
    if (!claimed) {
      const seen = await this.db.selectFrom('idempotency_keys').selectAll().where('firm_id', '=', firmId).where('key', '=', key).executeTakeFirst();
      if (seen && seen.status === 0) throw new ConflictException({ code: 'IN_PROGRESS', message: 'This save is still being processed. Try again in a moment.' });
      return seen?.response ?? null;
    }
    try {
      const body = await new Promise<unknown>((resolve, reject) => next.handle().subscribe({ next: resolve, error: reject, complete: () => resolve(undefined) }));
      await this.db.updateTable('idempotency_keys').set({ status: 200, response: JSON.stringify(body ?? null) }).where('firm_id', '=', firmId).where('key', '=', key).execute();
      if (Math.random() < 0.02) await this.db.deleteFrom('idempotency_keys').where('created_at', '<', new Date(Date.now() - 7 * 86400_000)).execute();
      return body;
    } catch (e) {
      // A failed save leaves nothing behind, so the same key may be tried again once the cause is fixed.
      await this.db.deleteFrom('idempotency_keys').where('firm_id', '=', firmId).where('key', '=', key).execute();
      throw e;
    }
  }
}

void of;
