import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Put, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { CreateLoanDto, CreateLoanTransactionDto, UpdateLoanDto } from './loan.dto';
import { LoansService } from './loans.service';

@ApiTags('loans')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Roles(...STAFF)
@Controller()
export class LoansController {
  constructor(private readonly loans: LoansService) {}

  @Get('loan-accounts')
  list(@CurrentUser() u: JwtPayload) {
    return this.loans.list(u.firmId);
  }

  @Post('loan-accounts')
  create(@CurrentUser() u: JwtPayload, @Body() dto: CreateLoanDto) {
    return this.loans.create(u.firmId, dto);
  }

  @Patch('loan-accounts/:id')
  update(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateLoanDto) {
    return this.loans.update(u.firmId, id, dto);
  }

  @Delete('loan-accounts/:id')
  @HttpCode(204)
  remove(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.loans.remove(u.firmId, id);
  }

  @Get('loan-accounts/:id/transactions')
  transactions(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.loans.transactions(u.firmId, id);
  }

  @Post('loan-accounts/:id/transactions')
  addTransaction(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CreateLoanTransactionDto) {
    return this.loans.addTransaction(u.firmId, id, dto);
  }

  @Put('loan-transactions/:id')
  updateTransaction(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CreateLoanTransactionDto) {
    return this.loans.updateTransaction(u.firmId, id, dto);
  }

  @Delete('loan-transactions/:id')
  @HttpCode(204)
  removeTransaction(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.loans.removeTransaction(u.firmId, id);
  }
}
