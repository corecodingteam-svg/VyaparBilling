import { Body, Controller, Delete, Get, Module, Param, ParseUUIDPipe, Post, Put, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsIn, IsInt, IsOptional, IsString, Matches, Max, MaxLength, Min, MinLength, ValidateIf } from 'class-validator';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { FirmService } from '../firm/firm.service';
import { EinvoiceService } from './einvoice.service';

class TransportDto {
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsIn(['road', 'rail', 'air', 'ship']) mode?: 'road' | 'rail' | 'air' | 'ship' | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @Matches(/^(\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d])?$/, { message: 'Transporter ID is a 15-character GSTIN' }) transporterId?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsString() @MaxLength(120) transporterName?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsString() @MaxLength(15) docNo?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null && v !== '') @Matches(/^\d{4}-\d{2}-\d{2}$/) docDate?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null && v !== '') @Matches(/^[A-Za-z0-9 -]{4,15}$/, { message: 'Vehicle number looks like MH12AB1234' }) vehicleNo?: string | null;
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsInt() @Min(0) @Max(4000) distanceKm?: number | null;
}

class RecordDto {
  @IsString() @MinLength(8) @MaxLength(100) irn: string;
  @IsOptional() @IsString() @MaxLength(30) ackNo?: string;
  @IsOptional() @IsString() @MaxLength(30) ackDate?: string;
  @IsOptional() @IsString() @MaxLength(5000) signedQr?: string;
}

class RecordEwayDto {
  @IsString() @Matches(/^\d{12}$/, { message: 'An e-way bill number has 12 digits' }) no: string;
  @IsOptional() @IsString() @MaxLength(30) date?: string;
  @IsOptional() @IsString() @MaxLength(30) validUpto?: string;
}

class CancelDto {
  @IsIn(['1', '2', '3', '4']) reason: '1' | '2' | '3' | '4';
  @IsString() @MinLength(1) @MaxLength(100) remark: string;
  /** Also cancel it on the portal (needs the portal set up); otherwise only mark it here. */
  @IsOptional() onPortal?: boolean;
}

@ApiTags('e-invoice')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Roles(...STAFF)
@Controller('einvoice')
export class EinvoiceController {
  constructor(
    private readonly e: EinvoiceService,
    private readonly firm: FirmService,
  ) {}

  @Get(':id')
  async status(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.e.status(u.firmId, id, await this.firm.scope(u));
  }

  @Get(':id/einvoice-json')
  async einvoiceJson(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.e.einvoiceJson(u.firmId, id, await this.firm.scope(u));
  }

  @Get(':id/eway-json')
  async ewayJson(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.e.ewayJson(u.firmId, id, await this.firm.scope(u));
  }

  @Put(':id/transport')
  async transport(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: TransportDto) {
    return this.e.saveTransport(u.firmId, id, dto, await this.firm.scope(u));
  }

  @Post(':id/generate')
  async generate(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.e.generate(u.firmId, id, await this.firm.scope(u));
  }

  @Post(':id/record')
  async record(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RecordDto) {
    return this.e.record(u.firmId, id, dto, await this.firm.scope(u));
  }

  @Post(':id/cancel')
  async cancel(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CancelDto) {
    return this.e.cancel(u.firmId, id, dto.reason, dto.remark, !!dto.onPortal, await this.firm.scope(u));
  }

  @Post(':id/eway/generate')
  async generateEway(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.e.generateEway(u.firmId, id, await this.firm.scope(u));
  }

  @Post(':id/eway/record')
  async recordEway(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RecordEwayDto) {
    return this.e.recordEway(u.firmId, id, dto, await this.firm.scope(u));
  }

  @Delete(':id/eway')
  async clearEway(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.e.clearEway(u.firmId, id, await this.firm.scope(u));
  }
}

@Module({ controllers: [EinvoiceController], providers: [EinvoiceService], exports: [EinvoiceService] })
export class EinvoiceModule {}
