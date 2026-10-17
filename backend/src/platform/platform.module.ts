import { Body, CanActivate, Controller, Delete, ExecutionContext, ForbiddenException, Get, HttpCode, Injectable, Module, Param, ParseUUIDPipe, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { CreateTenantDto, SetOwnerDto, SetUserDisabledDto, UpdateTenantDto } from './platform.dto';
import { PlatformService } from './platform.service';

/** Only the master admin (the one account in master_admin, signed in with its own token). Runs after JwtAuthGuard. */
@Injectable()
export class PlatformAdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const user = context.switchToHttp().getRequest().user as JwtPayload | undefined;
    if (!user?.master) throw new ForbiddenException({ code: 'FORBIDDEN', message: 'Only the master admin can do this.' });
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
  create(@CurrentUser() me: JwtPayload, @Body() dto: CreateTenantDto) {
    return this.platform.create(me.email, dto);
  }

  @Patch('tenants/:id')
  update(@CurrentUser() me: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateTenantDto) {
    return this.platform.update(me.email, id, dto);
  }

  @Delete('tenants/:id/devices/:deviceId')
  removeDevice(@CurrentUser() me: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Param('deviceId', ParseUUIDPipe) deviceId: string) {
    return this.platform.removeDevice(me.email, id, deviceId);
  }

  // ---- a business's users

  @Get('tenants/:id/users')
  users(@Param('id', ParseUUIDPipe) id: string) {
    return this.platform.users(id);
  }

  /** Sets a new random password and returns it once, to hand to the person. */
  @Post('tenants/:id/users/:userId/reset-password')
  @HttpCode(200)
  resetPassword(@CurrentUser() me: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Param('userId', ParseUUIDPipe) userId: string) {
    return this.platform.resetPassword(me.email, id, userId);
  }

  @Patch('tenants/:id/users/:userId')
  setDisabled(@CurrentUser() me: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Param('userId', ParseUUIDPipe) userId: string, @Body() dto: SetUserDisabledDto) {
    return this.platform.setDisabled(me.email, id, userId, dto.disabled);
  }

  @Post('tenants/:id/owner')
  @HttpCode(200)
  setOwner(@CurrentUser() me: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SetOwnerDto) {
    return this.platform.setOwner(me.email, id, dto.userId);
  }

  // ---- audit log

  @Get('audit')
  auditLog(@Query('firmId') firmId?: string, @Query('limit') limit?: string) {
    return this.platform.auditLog(firmId, Number(limit) || 200);
  }
}

@Module({ controllers: [PlatformController], providers: [PlatformService, PlatformAdminGuard] })
export class PlatformModule {}
