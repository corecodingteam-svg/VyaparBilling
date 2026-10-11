import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { REPORT_CATALOG, ReportsService } from './reports.service';

@ApiTags('reports')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Roles(...STAFF)
@Controller('reports')
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  /** The reports on offer and which filters each one takes. */
  @Get()
  catalog() {
    return REPORT_CATALOG;
  }

  @Get(':id')
  run(
    @CurrentUser() u: JwtPayload,
    @Param('id') id: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('partyId') partyId?: string,
    @Query('bankAccountId') bankAccountId?: string,
    @Query('itemId') itemId?: string,
  ) {
    return this.reports.run(u.firmId, id, { from, to, partyId, bankAccountId, itemId });
  }
}
