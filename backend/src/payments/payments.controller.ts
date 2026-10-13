import { BadRequestException, Body, ForbiddenException, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Put, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { SavePaymentDto } from './payment.dto';
import { FirmService } from '../firm/firm.service';
import { MessagingService } from '../messaging/messaging.service';
import { PaymentsService } from './payments.service';

const parseType = (t?: string) => {
  if (t !== 'in' && t !== 'out') throw new BadRequestException({ code: 'BAD_TYPE', message: 'type must be in or out' });
  return t;
};

/** Salesmen record money received from customers only. */
const assertAllowed = (user: JwtPayload, type: 'in' | 'out') => {
  if (user.role === 'salesman' && type === 'out') {
    throw new ForbiddenException({ code: 'FORBIDDEN', message: 'Your role does not have access to payments made.' });
  }
  return type;
};

@ApiTags('payments')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('payments')
export class PaymentsController {
  constructor(
    private readonly payments: PaymentsService,
    private readonly firm: FirmService,
    private readonly messaging: MessagingService,
  ) {}

  @Get()
  async list(@CurrentUser() u: JwtPayload, @Query('type') type?: string, @Query('from') from?: string, @Query('to') to?: string) {
    return this.payments.list(u.firmId, assertAllowed(u, parseType(type)), from, to, await this.firm.scope(u));
  }

  @Get('next-number')
  nextNumber(@CurrentUser() u: JwtPayload, @Query('type') type?: string) {
    return this.payments.nextNumber(u.firmId, assertAllowed(u, parseType(type)));
  }

  @Get(':id')
  async get(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.payments.get(u.firmId, id, await this.firm.scope(u));
  }

  @Post()
  async create(@CurrentUser() u: JwtPayload, @Body() dto: SavePaymentDto) {
    const created = await this.payments.create(u.firmId, { ...dto, type: assertAllowed(u, dto.type) }, u.sub);
    void this.messaging.autoSend(u.firmId, u.sub, 'payment', created.id);
    return created;
  }

  @Put(':id')
  async update(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SavePaymentDto) {
    return this.payments.update(u.firmId, id, { ...dto, type: assertAllowed(u, dto.type) }, await this.firm.scope(u));
  }

  @Delete(':id')
  @HttpCode(204)
  async remove(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.payments.remove(u.firmId, id, await this.firm.scope(u));
  }
}
