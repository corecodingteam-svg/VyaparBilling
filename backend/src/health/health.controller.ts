import { Controller, Get, Inject } from '@nestjs/common';
import { sql } from 'kysely';
import { Db, KYSELY } from '../database/database.module';

@Controller()
export class HealthController {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  @Get('health')
  health() {
    return { status: 'ok' };
  }

  @Get('ready')
  async ready() {
    await sql`select 1`.execute(this.db);
    return { status: 'ready' };
  }
}
