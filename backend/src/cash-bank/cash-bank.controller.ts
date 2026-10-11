import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Put, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { ChequeDepositDto, CreateAdjustmentDto, CreateBankAccountDto, UpdateBankAccountDto } from './cash-bank.dto';
import { CashBankService } from './cash-bank.service';

@ApiTags('cash-bank')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Roles(...STAFF)
@Controller()
export class CashBankController {
  constructor(private readonly service: CashBankService) {}

  @Get('bank-accounts')
  @Roles('owner', 'admin', 'accountant', 'salesman')
  accounts(@CurrentUser() u: JwtPayload) {
    return this.service.listAccounts(u.firmId);
  }

  @Post('bank-accounts')
  createAccount(@CurrentUser() u: JwtPayload, @Body() dto: CreateBankAccountDto) {
    return this.service.createAccount(u.firmId, dto);
  }

  @Get('bank-accounts/:id/transactions')
  accountTransactions(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.service.accountTransactions(u.firmId, id);
  }

  @Patch('bank-accounts/:id')
  updateAccount(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateBankAccountDto) {
    return this.service.updateAccount(u.firmId, id, dto);
  }

  @Delete('bank-accounts/:id')
  @HttpCode(204)
  deleteAccount(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.service.deleteAccount(u.firmId, id);
  }

  @Get('cash-in-hand')
  cash(@CurrentUser() u: JwtPayload) {
    return this.service.cash(u.firmId);
  }

  @Post('fund-adjustments')
  createAdjustment(@CurrentUser() u: JwtPayload, @Body() dto: CreateAdjustmentDto) {
    return this.service.createAdjustment(u.firmId, dto);
  }

  @Get('fund-adjustments/:id')
  getAdjustment(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.service.getAdjustment(u.firmId, id);
  }

  @Put('fund-adjustments/:id')
  updateAdjustment(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CreateAdjustmentDto) {
    return this.service.updateAdjustment(u.firmId, id, dto);
  }

  @Delete('fund-adjustments/:id')
  @HttpCode(204)
  deleteAdjustment(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.service.deleteAdjustment(u.firmId, id);
  }

  @Get('cheques')
  cheques(@CurrentUser() u: JwtPayload) {
    return this.service.cheques(u.firmId);
  }

  @Post('cheques/:source/:id/deposit')
  @HttpCode(204)
  depositCheque(
    @CurrentUser() u: JwtPayload,
    @Param('source') source: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ChequeDepositDto,
  ) {
    return this.service.setChequeAccount(u.firmId, source, id, dto.bankAccountId);
  }

  @Post('cheques/:source/:id/reopen')
  @HttpCode(204)
  reopenCheque(@CurrentUser() u: JwtPayload, @Param('source') source: string, @Param('id', ParseUUIDPipe) id: string) {
    return this.service.setChequeAccount(u.firmId, source, id, null);
  }
}
