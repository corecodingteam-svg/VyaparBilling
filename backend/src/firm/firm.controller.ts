import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { UpdateFirmDto } from './firm.dto';
import { FirmService } from './firm.service';

@ApiTags('firm')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('firm')
export class FirmController {
  constructor(private readonly firm: FirmService) {}

  @Get()
  get(@CurrentUser() user: JwtPayload) {
    return this.firm.get(user.firmId);
  }

  @Patch()
  @Roles(...STAFF)
  update(@CurrentUser() user: JwtPayload, @Body() dto: UpdateFirmDto) {
    return this.firm.update(user.firmId, dto);
  }
}
