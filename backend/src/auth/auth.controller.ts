import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { CurrentUser } from './current-user.decorator';
import { AddMemberDto, ChangePasswordDto, CreateFirmDto, DeleteFirmDto, LoginDto, RegisterDto, SwitchFirmDto, UpdateMemberDto } from './dto/auth.dto';
import { JwtAuthGuard } from './jwt-auth.guard';
import { JwtPayload } from './jwt.strategy';
import { ADMINS, Roles, STAFF } from './roles';

@ApiTags('auth')
@Controller()
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('auth/register')
  register(@Body() dto: RegisterDto) {
    return this.auth.register(dto);
  }

  @Post('auth/login')
  @HttpCode(200)
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto);
  }

  @Post('auth/change-password')
  @HttpCode(204)
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  changePassword(@CurrentUser() user: JwtPayload, @Body() dto: ChangePasswordDto) {
    return this.auth.changePassword(user.sub, dto, user.master);
  }

  @Get('auth/me')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  me(@CurrentUser() user: JwtPayload) {
    return user.master ? this.auth.masterMe(user.sub) : this.auth.me(user.sub, user.firmId);
  }

  /** Returns a new token that works in the chosen company. */
  @Post('auth/switch-firm')
  @HttpCode(200)
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  switchFirm(@CurrentUser() user: JwtPayload, @Body() dto: SwitchFirmDto) {
    return this.auth.switchFirm(user, dto.firmId);
  }

  @Get('firms')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  firms(@CurrentUser() user: JwtPayload) {
    return this.auth.firms(user);
  }

  @Post('firms')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  createFirm(@CurrentUser() user: JwtPayload, @Body() dto: CreateFirmDto) {
    return this.auth.createFirm(user, dto);
  }

  @Delete('firms/:id')
  @HttpCode(204)
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  deleteFirm(@CurrentUser() user: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: DeleteFirmDto) {
    return this.auth.deleteFirm(user, id, dto.name);
  }

  @Get('users')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...STAFF)
  members(@CurrentUser() user: JwtPayload) {
    return this.auth.members(user.firmId);
  }

  @Post('users')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...ADMINS)
  addMember(@CurrentUser() user: JwtPayload, @Body() dto: AddMemberDto) {
    return this.auth.addMember(user.firmId, dto);
  }

  @Patch('users/:id')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...ADMINS)
  updateMember(@CurrentUser() user: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateMemberDto) {
    return this.auth.updateMember(user.firmId, id, dto);
  }

  @Delete('users/:id')
  @HttpCode(204)
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Roles(...ADMINS)
  removeMember(@CurrentUser() user: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.auth.removeMember(user, id);
  }
}
