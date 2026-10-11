import { Global, Inject, Module, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Kysely, PostgresDialect } from 'kysely';
import { Pool, types } from 'pg';
import { Database } from './schema';

export const KYSELY = 'KYSELY_CONNECTION';

// Return DATE columns as 'YYYY-MM-DD' strings instead of JS Dates (avoids timezone shifts).
types.setTypeParser(1082, (v) => v);

@Global()
@Module({
  providers: [
    {
      provide: KYSELY,
      inject: [ConfigService],
      useFactory: (config: ConfigService) =>
        new Kysely<Database>({
          dialect: new PostgresDialect({
            pool: new Pool({ connectionString: config.get<string>('DATABASE_URL'), max: 10 }),
          }),
        }),
    },
  ],
  exports: [KYSELY],
})
export class DatabaseModule implements OnModuleDestroy {
  constructor(@Inject(KYSELY) private readonly db: Kysely<Database>) {}

  async onModuleDestroy() {
    await this.db.destroy();
  }
}

export type Db = Kysely<Database>;
