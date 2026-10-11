import { Body, Controller, Get, HttpCode, Module, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { ADMINS, Roles, STAFF } from '../auth/roles';
import { CloseBooksDto, NewYearDto, RestoreDto } from './utilities.dto';
import { UtilitiesService } from './utilities.service';

@ApiTags('utilities')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class UtilitiesController {
  constructor(private readonly utilities: UtilitiesService) {}

  @Get('utilities/setup')
  setup(@CurrentUser() u: JwtPayload) {
    return this.utilities.setup(u.firmId);
  }

  @Get('utilities/verify')
  @Roles(...STAFF)
  verify(@CurrentUser() u: JwtPayload) {
    return this.utilities.verify(u.firmId);
  }

  @Post('utilities/verify/fix')
  @HttpCode(200)
  @Roles(...STAFF)
  fix(@CurrentUser() u: JwtPayload) {
    return this.utilities.fix(u.firmId);
  }

  @Post('utilities/close-books')
  @HttpCode(200)
  @Roles(...ADMINS)
  closeBooks(@CurrentUser() u: JwtPayload, @Body() dto: CloseBooksDto) {
    return this.utilities.closeBooks(u.firmId, dto.date);
  }

  @Post('utilities/new-year')
  @Roles(...ADMINS)
  newYear(@CurrentUser() u: JwtPayload, @Body() dto: NewYearDto) {
    return this.utilities.startNewYear(u, dto);
  }

  @Get('backup')
  @Roles(...ADMINS)
  backup(@CurrentUser() u: JwtPayload) {
    return this.utilities.backup(u.firmId);
  }

  /** Any login may restore: the backup becomes a new company of their own. */
  @Post('firms/restore')
  restore(@CurrentUser() u: JwtPayload, @Body() dto: RestoreDto) {
    return this.utilities.restore(u, dto.backup, dto.name);
  }
}

@Module({ controllers: [UtilitiesController], providers: [UtilitiesService] })
export class UtilitiesModule {}
