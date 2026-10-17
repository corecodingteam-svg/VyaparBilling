import { Body, CanActivate, Delete, Controller, ExecutionContext, ForbiddenException, Get, Injectable, Module, Param, ParseUUIDPipe, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { isPlatformAdmin } from '../auth/platform-admin';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreateTenantDto, UpdateTenantDto } from './platform.dto';
import { PlatformService } from './platform.service';

/** Provider staff only: their email is listed in PLATFORM_ADMIN_EMAILS. Runs after JwtAuthGuard. */
@Injectable()
export class PlatformAdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const user = context.switchToHttp().getRequest().user as { email?: string } | undefined;
    if (!user?.email || !isPlatformAdmin(user.email)) {
      throw new ForbiddenException({ code: 'FORBIDDEN', message: 'Only the provider can do this.' });
    }
    return true;
  }
}

@ApiTags('platform')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, PlatformAdminGuard)
@Controller('platform')
export class PlatformController {
  constructor(private readonly platform: PlatformService) {}

  @Get('catalog')
  catalog() {
    return this.platform.catalog();
  }

  @Get('tenants')
  list(@Query('q') q?: string) {
    return this.platform.list(q);
  }

  @Post('tenants')
  create(@Body() dto: CreateTenantDto) {
    return this.platform.create(dto);
  }

  @Delete('tenants/:id/devices/:deviceId')
  removeDevice(@Param('id', ParseUUIDPipe) id: string, @Param('deviceId', ParseUUIDPipe) deviceId: string) {
    return this.platform.removeDevice(id, deviceId);
  }

  @Patch('tenants/:id')
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateTenantDto) {
    return this.platform.update(id, dto);
  }
}

@Module({ controllers: [PlatformController], providers: [PlatformService, PlatformAdminGuard] })
export class PlatformModule {}
