import { Body, Controller, HttpCode, Module, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { DeactivateDto, DeviceDto } from './licensing.dto';
import { LicensingService } from './licensing.service';

/** What a device calls to get, renew and give back its signed licence certificate. Checking the certificate needs no call. */
@ApiTags('licenses')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('licenses')
export class LicensingController {
  constructor(private readonly licensing: LicensingService) {}

  @Post('activate')
  @HttpCode(200)
  activate(@CurrentUser() user: JwtPayload, @Body() dto: DeviceDto) {
    return this.licensing.activate(user.firmId, dto);
  }

  @Post('refresh')
  @HttpCode(200)
  refresh(@CurrentUser() user: JwtPayload, @Body() dto: DeactivateDto) {
    return this.licensing.refresh(user.firmId, dto.installationId);
  }

  @Post('deactivate')
  @HttpCode(204)
  deactivate(@CurrentUser() user: JwtPayload, @Body() dto: DeactivateDto) {
    return this.licensing.deactivate(user.firmId, dto.installationId);
  }
}

@Module({ controllers: [LicensingController], providers: [LicensingService] })
export class LicensingModule {}
