import {
  BadRequestException, Controller, Delete, Get, HttpCode, Inject, Injectable, Logger, Module, NotFoundException, OnModuleDestroy, OnModuleInit, Param,
  ParseUUIDPipe, Post, Query, Res, UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import { promises as fs } from 'fs';
import { sql } from 'kysely';
import * as path from 'path';
import { promisify } from 'util';
import { gunzip, gzip } from 'zlib';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { ADMINS, Roles } from '../auth/roles';
import { today } from '../common/numbers';
import { Db, KYSELY } from '../database/database.module';
import { FirmService } from '../firm/firm.service';
import { exportFirm } from '../utilities/backup';
import { consentUrl, driveConfig, exchangeCode, signState, uploadToDrive, verifyState } from './drive';

const zip = promisify(gzip);
const unzip = promisify(gunzip);
const HOUR = 60 * 60 * 1000;

@Injectable()
export class BackupsService implements OnModuleInit, OnModuleDestroy {
  private readonly log = new Logger('Backups');
  private timer?: NodeJS.Timeout;

  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly firms: FirmService,
  ) {}

  /** Backups live on the server's disk, one folder per company. In Docker this is a mounted volume. */
  private get dir() {
    return process.env.BACKUP_DIR ?? path.join(process.cwd(), 'backups');
  }

  private file(firmId: string, name: string) {
    return path.join(this.dir, firmId, name);
  }

  onModuleInit() {
    // Checked every half hour; a company gets a new backup once its last automatic one is old enough.
    if (process.env.NODE_ENV === 'test') return;
    this.timer = setInterval(() => void this.runDue(), HOUR / 2);
    this.timer.unref();
    setTimeout(() => void this.runDue(), 20_000).unref();
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  /** Makes the automatic backups that are due. One company failing does not stop the others. */
  async runDue(now = Date.now()) {
    const due = await sql<{ id: string; every: string; last: Date | null }>`
      select f.id, f.settings->>'autoBackup' as every,
             (select max(b.created_at) from backups b where b.firm_id = f.id and b.kind = 'auto') as last
        from firms f where f.settings->>'autoBackup' in ('daily', 'weekly')`.execute(this.db);
    let made = 0;
    for (const f of due.rows) {
      const age = f.last ? now - new Date(f.last).getTime() : Infinity;
      // An hour of slack so a daily backup does not drift later each day.
      if (age < (f.every === 'weekly' ? 7 * 24 : 24) * HOUR - HOUR) continue;
      try {
        await this.create(f.id, 'auto');
        made++;
      } catch (e) {
        this.log.error(`Automatic backup failed for company ${f.id}: ${(e as Error).message}`);
      }
    }
    return made;
  }

  async list(firmId: string) {
    const rows = await this.db.selectFrom('backups').selectAll().where('firm_id', '=', firmId).orderBy('created_at', 'desc').execute();
    return rows.map((b) => ({
      id: b.id, fileName: b.file_name, size: b.size, kind: b.kind, createdAt: b.created_at, onDrive: b.drive_file_id !== null, driveError: b.drive_error,
    }));
  }

  /** Writes a compressed backup to disk, copies it to Google Drive when connected, and trims old automatic ones. */
  async create(firmId: string, kind: 'auto' | 'manual') {
    const firm = await this.db.selectFrom('firms').select(['name', 'drive_refresh_token']).where('id', '=', firmId).executeTakeFirstOrThrow();
    const data = await zip(Buffer.from(JSON.stringify(await exportFirm(this.db, firmId))));
    const safe = firm.name.replace(/[^A-Za-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'company';
    const fileName = `${safe}-${today()}-${Date.now().toString(36)}.json.gz`;
    await fs.mkdir(path.join(this.dir, firmId), { recursive: true });
    await fs.writeFile(this.file(firmId, fileName), data);

    let driveFileId: string | null = null;
    let driveError: string | null = null;
    const config = driveConfig();
    if (config && firm.drive_refresh_token) {
      try {
        driveFileId = await uploadToDrive(config, firm.drive_refresh_token, fileName, data);
      } catch (e) {
        // The backup itself is safe on the server; the list shows that the copy to Drive failed.
        driveError = (e as Error).message.slice(0, 300);
        this.log.warn(`Drive upload failed for company ${firmId}: ${driveError}`);
      }
    }
    await this.db.insertInto('backups').values({ firm_id: firmId, file_name: fileName, size: data.length, kind, drive_file_id: driveFileId, drive_error: driveError }).execute();

    const keep = (await this.firms.settings(firmId)).autoBackupKeep;
    const old = await this.db.selectFrom('backups').select(['id']).where('firm_id', '=', firmId).where('kind', '=', 'auto').orderBy('created_at', 'desc').offset(keep).execute();
    for (const b of old) await this.remove(firmId, b.id);
    return this.list(firmId);
  }

  private async find(firmId: string, id: string) {
    const b = await this.db.selectFrom('backups').selectAll().where('id', '=', id).where('firm_id', '=', firmId).executeTakeFirst();
    if (!b) throw new NotFoundException({ code: 'BACKUP_NOT_FOUND', message: 'Backup not found.' });
    return b;
  }

  /** The backup's contents, ready to save as a file or to restore. */
  async read(firmId: string, id: string) {
    const b = await this.find(firmId, id);
    try {
      const backup = JSON.parse((await unzip(await fs.readFile(this.file(firmId, b.file_name)))).toString()) as Record<string, unknown>;
      return { fileName: b.file_name.replace(/\.gz$/, ''), backup };
    } catch {
      throw new NotFoundException({ code: 'BACKUP_FILE_MISSING', message: 'The backup file is no longer on the server.' });
    }
  }

  async remove(firmId: string, id: string) {
    const b = await this.find(firmId, id);
    await fs.rm(this.file(firmId, b.file_name), { force: true });
    await this.db.deleteFrom('backups').where('id', '=', id).execute();
  }

  // ---------------------------------------------------------------- Google Drive

  async driveStatus(firmId: string) {
    const firm = await this.db.selectFrom('firms').select(['drive_refresh_token', 'drive_email']).where('id', '=', firmId).executeTakeFirstOrThrow();
    return { configured: driveConfig() !== null, connected: firm.drive_refresh_token !== null, email: firm.drive_email };
  }

  private get secret() {
    return process.env.JWT_SECRET ?? '';
  }

  /** The Google page where the user allows the app to put files in their Drive. */
  driveAuthUrl(firmId: string) {
    const config = driveConfig();
    if (!config) {
      throw new BadRequestException({
        code: 'DRIVE_NOT_CONFIGURED',
        message: 'Google Drive is not set up on this server yet. Ask whoever runs it to add the Google client ID and secret.',
      });
    }
    return { url: consentUrl(config, signState(firmId, this.secret)) };
  }

  /** Google redirects here after consent. Returns where to send the browser next. */
  async driveCallback(code: string | undefined, state: string | undefined, error: string | undefined) {
    const app = (process.env.APP_URL ?? '').replace(/\/$/, '');
    const back = (result: string) => `${app}/#/backup?drive=${result}`;
    const config = driveConfig();
    const firmId = state ? verifyState(state, this.secret) : null;
    if (!config || !firmId || !code || error) return back('failed');
    try {
      const { refreshToken, email } = await exchangeCode(config, code);
      await this.db.updateTable('firms').set({ drive_refresh_token: refreshToken, drive_email: email }).where('id', '=', firmId).execute();
      return back('connected');
    } catch (e) {
      this.log.warn(`Drive connection failed: ${(e as Error).message}`);
      return back('failed');
    }
  }

  async driveDisconnect(firmId: string) {
    await this.db.updateTable('firms').set({ drive_refresh_token: null, drive_email: null }).where('id', '=', firmId).execute();
  }
}

@ApiTags('backups')
@Controller('backups')
export class BackupsController {
  constructor(private readonly backups: BackupsService) {}

  @Get()
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...ADMINS)
  list(@CurrentUser() u: JwtPayload) {
    return this.backups.list(u.firmId);
  }

  @Post()
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...ADMINS)
  create(@CurrentUser() u: JwtPayload) {
    return this.backups.create(u.firmId, 'manual');
  }

  @Get('drive/status')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...ADMINS)
  driveStatus(@CurrentUser() u: JwtPayload) {
    return this.backups.driveStatus(u.firmId);
  }

  @Get('drive/auth-url')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...ADMINS)
  driveAuthUrl(@CurrentUser() u: JwtPayload) {
    return this.backups.driveAuthUrl(u.firmId);
  }

  /** Opened by Google in the user's browser, so it carries no login; the signed `state` says which company it is for. */
  @Get('drive/callback')
  async driveCallback(@Res() res: Response, @Query('code') code?: string, @Query('state') state?: string, @Query('error') error?: string) {
    res.redirect(await this.backups.driveCallback(code, state, error));
  }

  @Delete('drive')
  @HttpCode(204)
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...ADMINS)
  driveDisconnect(@CurrentUser() u: JwtPayload) {
    return this.backups.driveDisconnect(u.firmId);
  }

  @Get(':id')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...ADMINS)
  read(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.backups.read(u.firmId, id);
  }

  @Delete(':id')
  @HttpCode(204)
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...ADMINS)
  remove(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.backups.remove(u.firmId, id);
  }
}

@Module({ controllers: [BackupsController], providers: [BackupsService], exports: [BackupsService] })
export class BackupsModule {}
