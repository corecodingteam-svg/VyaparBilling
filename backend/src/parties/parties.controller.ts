import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { FirmService } from '../firm/firm.service';
import { CreatePartyDto, ImportPartiesDto, PartyGroupDto, UpdatePartyDto } from './party.dto';
import { PartiesService } from './parties.service';

@ApiTags('parties')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class PartiesController {
  constructor(
    private readonly parties: PartiesService,
    private readonly firm: FirmService,
  ) {}

  @Get('party-groups')
  groups(@CurrentUser() u: JwtPayload) {
    return this.parties.groups(u.firmId);
  }

  @Post('party-groups')
  @Roles(...STAFF)
  createGroup(@CurrentUser() u: JwtPayload, @Body() dto: PartyGroupDto) {
    return this.parties.saveGroup(u.firmId, dto.name);
  }

  @Patch('party-groups/:id')
  @Roles(...STAFF)
  renameGroup(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: PartyGroupDto) {
    return this.parties.saveGroup(u.firmId, dto.name, id);
  }

  @Delete('party-groups/:id')
  @Roles(...STAFF)
  @HttpCode(204)
  deleteGroup(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.parties.deleteGroup(u.firmId, id);
  }

  @Get('parties')
  async list(@CurrentUser() u: JwtPayload, @Query('search') search?: string, @Query('groupId') groupId?: string) {
    return this.parties.list(u.firmId, search, await this.firm.scope(u), groupId);
  }

  @Get('parties/:id')
  async get(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.parties.get(u.firmId, id, await this.firm.scope(u));
  }

  @Get('parties/:id/transactions')
  async transactions(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.parties.transactions(u.firmId, id, await this.firm.scope(u));
  }

  @Post('parties')
  create(@CurrentUser() u: JwtPayload, @Body() dto: CreatePartyDto) {
    return this.parties.create(u.firmId, dto, { userId: u.sub, isSalesman: u.role === 'salesman' });
  }

  @Post('parties/import')
  @Roles(...STAFF)
  @HttpCode(200)
  import(@CurrentUser() u: JwtPayload, @Body() dto: ImportPartiesDto) {
    return this.parties.import(u.firmId, dto.parties);
  }

  @Patch('parties/:id')
  async update(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdatePartyDto) {
    return this.parties.update(u.firmId, id, dto, await this.firm.scope(u));
  }

  @Delete('parties/:id')
  @Roles(...STAFF)
  @HttpCode(204)
  remove(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.parties.remove(u.firmId, id);
  }
}
