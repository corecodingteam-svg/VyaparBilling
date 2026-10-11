import { Body, Controller, ForbiddenException, Get, HttpCode, Inject, Injectable, Module, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { IsIn, IsNumber, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { sql } from 'kysely';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { ADMINS, Roles } from '../auth/roles';
import { today } from '../common/numbers';
import { Db, KYSELY } from '../database/database.module';
import { FirmService } from '../firm/firm.service';

export class LocationDto {
  @ApiProperty() @IsNumber() @Min(-90) @Max(90)
  latitude: number;

  @ApiProperty() @IsNumber() @Min(-180) @Max(180)
  longitude: number;

  @ApiPropertyOptional({ description: 'Metres' }) @IsOptional() @IsNumber() @Min(0)
  accuracy?: number;

  @ApiPropertyOptional({ enum: ['ping', 'sale', 'payment'] }) @IsOptional() @IsIn(['ping', 'sale', 'payment'])
  context?: 'ping' | 'sale' | 'payment';

  @ApiPropertyOptional({ description: 'The sale or payment just saved' }) @IsOptional() @IsUUID()
  refId?: string;
}

@Injectable()
export class LocationsService {
  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly firms: FirmService,
  ) {}

  /** Stores where the user is. Ignored (not an error) while tracking is switched off, so the app need not check first. */
  async record(user: JwtPayload, dto: LocationDto) {
    if (!(await this.firms.settings(user.firmId)).locationTrackingEnabled) return { recorded: false };
    await this.db
      .insertInto('user_locations')
      .values({
        firm_id: user.firmId, user_id: user.sub, latitude: dto.latitude, longitude: dto.longitude, accuracy: dto.accuracy ?? null,
        context: dto.context ?? 'ping', ref_id: dto.refId ?? null,
      })
      .execute();
    return { recorded: true };
  }

  /** Every member's most recent position, with how many check-ins, sales and payments they logged today. */
  async latest(firmId: string) {
    const rows = await sql<{
      user_id: string; full_name: string; role: string; latitude: number | null; longitude: number | null; accuracy: number | null;
      recorded_at: Date | null; context: string | null; points_today: string; sales_today: string; payments_today: string;
    }>`
      select m.user_id, u.full_name, m.role, l.latitude, l.longitude, l.accuracy, l.recorded_at, l.context,
             (select count(*) from user_locations x where x.firm_id = m.firm_id and x.user_id = m.user_id
                 and (x.recorded_at at time zone 'Asia/Kolkata')::date = ${today()}::date) as points_today,
             (select count(*) from user_locations x where x.firm_id = m.firm_id and x.user_id = m.user_id and x.context = 'sale'
                 and (x.recorded_at at time zone 'Asia/Kolkata')::date = ${today()}::date) as sales_today,
             (select count(*) from user_locations x where x.firm_id = m.firm_id and x.user_id = m.user_id and x.context = 'payment'
                 and (x.recorded_at at time zone 'Asia/Kolkata')::date = ${today()}::date) as payments_today
        from firm_members m
        join users u on u.id = m.user_id
        left join lateral (select * from user_locations x where x.firm_id = m.firm_id and x.user_id = m.user_id order by x.recorded_at desc limit 1) l on true
       where m.firm_id = ${firmId}
       order by l.recorded_at desc nulls last, lower(u.full_name)`.execute(this.db);
    return rows.rows.map((r) => ({
      userId: r.user_id, fullName: r.full_name, role: r.role, latitude: r.latitude, longitude: r.longitude, accuracy: r.accuracy,
      recordedAt: r.recorded_at, context: r.context, pointsToday: Number(r.points_today), salesToday: Number(r.sales_today),
      paymentsToday: Number(r.payments_today),
    }));
  }

  /** One user's positions on one day, oldest first, with the document number where a sale or payment was saved there. */
  async trail(firmId: string, userId: string, date: string) {
    const rows = await sql<{
      latitude: number; longitude: number; accuracy: number | null; recorded_at: Date; context: string; ref_id: string | null; ref: string | null;
    }>`
      select l.latitude, l.longitude, l.accuracy, l.recorded_at, l.context, l.ref_id,
             case l.context when 'sale' then (select i.number || ' · ' || i.party_name from invoices i where i.id = l.ref_id)
                            when 'payment' then (select p.number || ' · ' || pa.name from payments p join parties pa on pa.id = p.party_id where p.id = l.ref_id)
             end as ref
        from user_locations l
       where l.firm_id = ${firmId} and l.user_id = ${userId} and (l.recorded_at at time zone 'Asia/Kolkata')::date = ${date}::date
       order by l.recorded_at`.execute(this.db);
    return rows.rows.map((r) => ({
      latitude: r.latitude, longitude: r.longitude, accuracy: r.accuracy, recordedAt: r.recorded_at, context: r.context, refId: r.ref_id, ref: r.ref,
    }));
  }
}

@ApiTags('locations')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('locations')
export class LocationsController {
  constructor(private readonly locations: LocationsService) {}

  @Post()
  @HttpCode(200)
  record(@CurrentUser() u: JwtPayload, @Body() dto: LocationDto) {
    return this.locations.record(u, dto);
  }

  @Get('latest')
  @Roles(...ADMINS)
  latest(@CurrentUser() u: JwtPayload) {
    return this.locations.latest(u.firmId);
  }

  /** A user's trail for a day. Admins can see anyone's; everyone can see their own. */
  @Get('trail')
  trail(@CurrentUser() u: JwtPayload, @Query('userId') userId?: string, @Query('date') date?: string) {
    const target = userId ?? u.sub;
    if (target !== u.sub && !ADMINS.includes(u.role)) throw new ForbiddenException({ code: 'FORBIDDEN', message: 'Your role does not have access to this.' });
    return this.locations.trail(u.firmId, target, date ?? today());
  }
}

@Module({ controllers: [LocationsController], providers: [LocationsService] })
export class LocationsModule {}
