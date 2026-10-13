import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseEnumPipe, Put, UseGuards, Global } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsObject } from 'class-validator';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { ADMINS, Roles } from '../auth/roles';
import type { Provider } from '../database/schema';
import { PROVIDER_NAMES } from './providers';
import { IntegrationsService } from './integrations.service';

class SaveIntegrationDto {
  @IsObject()
  values: Record<string, string>;
}

enum ProviderEnum {
  whatsapp = 'whatsapp', sms = 'sms', einvoice = 'einvoice', razorpay = 'razorpay', google_profile = 'google_profile',
}
void PROVIDER_NAMES;

@ApiTags('integrations')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Roles(...ADMINS)
@Controller('integrations')
export class IntegrationsController {
  constructor(private readonly integrations: IntegrationsService) {}

  @Get()
  status(@CurrentUser() u: JwtPayload) {
    return this.integrations.status(u.firmId);
  }

  @Put(':provider')
  async save(@CurrentUser() u: JwtPayload, @Param('provider', new ParseEnumPipe(ProviderEnum)) provider: Provider, @Body() dto: SaveIntegrationDto) {
    await this.integrations.save(u.firmId, provider, dto.values);
    return this.integrations.status(u.firmId);
  }

  @Delete(':provider')
  @HttpCode(204)
  remove(@CurrentUser() u: JwtPayload, @Param('provider', new ParseEnumPipe(ProviderEnum)) provider: Provider) {
    return this.integrations.remove(u.firmId, provider);
  }
}

@Global()
@Module({ controllers: [IntegrationsController], providers: [IntegrationsService], exports: [IntegrationsService] })
export class IntegrationsModule {}
