import { Body, Controller, Get, Global, Module, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsNumber, Min, IsArray, IsIn, IsOptional, IsString, IsUUID, Matches, MaxLength, MinLength, ArrayMaxSize } from 'class-validator';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { ADMINS, Roles, STAFF } from '../auth/roles';
import { FirmService } from '../firm/firm.service';
import { MessagingService } from './messaging.service';

const CHANNELS = ['whatsapp', 'sms'];

class SendDto {
  @IsIn(CHANNELS) channel: 'whatsapp' | 'sms';
  /** Use this number instead of the customer's saved one. */
  @IsOptional() @IsString() @Matches(/^[+\d\s()-]{7,20}$/) phone?: string;
}

class ReminderDto {
  @IsIn(CHANNELS) channel: 'whatsapp' | 'sms';
  @IsUUID() partyId: string;
  @IsNumber() @Min(0) amount: number;
  @IsOptional() @IsString() @Matches(/^[+\d\s()-]{7,20}$/) phone?: string;
}

class MarketingDto {
  @IsIn(CHANNELS) channel: 'whatsapp' | 'sms';
  @IsString() @MinLength(1) @MaxLength(500) text: string;
  @IsOptional() @IsArray() @ArrayMaxSize(500) @IsUUID('all', { each: true }) partyIds?: string[];
  @IsOptional() @IsUUID() groupId?: string;
}

class TestDto {
  @IsIn(CHANNELS) channel: 'whatsapp' | 'sms';
  @IsString() @Matches(/^[+\d\s()-]{7,20}$/) to: string;
}

@ApiTags('messages')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('messages')
export class MessagingController {
  constructor(
    private readonly messages: MessagingService,
    private readonly firm: FirmService,
  ) {}

  @Get()
  @Roles(...STAFF)
  history(@CurrentUser() u: JwtPayload) {
    return this.messages.history(u.firmId);
  }

  @Post('invoices/:id')
  async invoice(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SendDto) {
    await this.messages.sendInvoice(u.firmId, u.sub, id, dto.channel, await this.firm.scope(u), dto.phone);
    return { ok: true };
  }

  @Post('payments/:id')
  async payment(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SendDto) {
    await this.messages.sendPayment(u.firmId, u.sub, id, dto.channel, await this.firm.scope(u), dto.phone);
    return { ok: true };
  }

  @Post('reminders')
  @Roles(...STAFF)
  async reminder(@CurrentUser() u: JwtPayload, @Body() dto: ReminderDto) {
    await this.messages.sendReminder(u.firmId, u.sub, dto.partyId, dto.amount, dto.channel, dto.phone);
    return { ok: true };
  }

  @Post('marketing')
  @Roles(...ADMINS)
  marketing(@CurrentUser() u: JwtPayload, @Body() dto: MarketingDto) {
    return this.messages.marketing(u.firmId, u.sub, dto.channel, dto.text, { partyIds: dto.partyIds, groupId: dto.groupId });
  }

  @Post('test')
  @Roles(...ADMINS)
  test(@CurrentUser() u: JwtPayload, @Body() dto: TestDto) {
    return this.messages.test(u.firmId, u.sub, dto.channel, dto.to);
  }
}

@Global()
@Module({ controllers: [MessagingController], providers: [MessagingService], exports: [MessagingService] })
export class MessagingModule {}
