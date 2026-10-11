import {
  BadRequestException, Body, Controller, Delete, ForbiddenException, Get, HttpCode, Param, ParseUUIDPipe, Post, Put, Query, UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { INVOICE_TYPE_NAMES, InvoiceType } from '../common/invoice-types';
import { FirmService } from '../firm/firm.service';
import { SaveInvoiceDto } from './invoice.dto';
import { InvoicesService } from './invoices.service';

const parseType = (t?: string) => {
  if (!INVOICE_TYPE_NAMES.includes(t as InvoiceType)) {
    throw new BadRequestException({ code: 'BAD_TYPE', message: `type must be one of: ${INVOICE_TYPE_NAMES.join(', ')}` });
  }
  return t as InvoiceType;
};

/** Documents on the buying side, which salesmen cannot see or create. */
const PURCHASE_SIDE: InvoiceType[] = ['purchase', 'purchase_order', 'debit_note'];

const assertAllowed = (user: JwtPayload, type: InvoiceType) => {
  if (user.role === 'salesman' && PURCHASE_SIDE.includes(type)) {
    throw new ForbiddenException({ code: 'FORBIDDEN', message: 'Your role does not have access to purchases.' });
  }
  return type;
};

@ApiTags('invoices')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('invoices')
export class InvoicesController {
  constructor(
    private readonly invoices: InvoicesService,
    private readonly firm: FirmService,
  ) {}

  @Get()
  async list(
    @CurrentUser() u: JwtPayload,
    @Query('type') type?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('partyId') partyId?: string,
    @Query('unpaid') unpaid?: string,
  ) {
    return this.invoices.list(u.firmId, assertAllowed(u, parseType(type)), { from, to, partyId, unpaidOnly: unpaid === 'true' }, await this.firm.scope(u));
  }

  @Get('next-number')
  nextNumber(@CurrentUser() u: JwtPayload, @Query('type') type?: string) {
    return this.invoices.nextNumber(u.firmId, assertAllowed(u, parseType(type)));
  }

  @Get(':id')
  async get(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    const invoice = await this.invoices.get(u.firmId, id, await this.firm.scope(u));
    assertAllowed(u, invoice.type);
    return invoice;
  }

  @Post()
  create(@CurrentUser() u: JwtPayload, @Body() dto: SaveInvoiceDto) {
    return this.invoices.create(u.firmId, { ...dto, type: assertAllowed(u, dto.type) }, u.sub);
  }

  @Put(':id')
  async update(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SaveInvoiceDto) {
    return this.invoices.update(u.firmId, id, { ...dto, type: assertAllowed(u, dto.type) }, await this.firm.scope(u));
  }

  @Delete(':id')
  @HttpCode(204)
  async remove(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    const scope = await this.firm.scope(u);
    assertAllowed(u, (await this.invoices.get(u.firmId, id, scope)).type);
    return this.invoices.remove(u.firmId, id, scope);
  }
}
