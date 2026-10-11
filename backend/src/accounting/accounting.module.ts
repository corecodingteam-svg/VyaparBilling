import { Body, Controller, Delete, Get, HttpCode, Module, Param, ParseUUIDPipe, Post, Put, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { CurrencyDto, LedgerAccountDto, SaveJournalDto } from './accounting.dto';
import { AccountingService } from './accounting.service';

@ApiTags('accounting')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Roles(...STAFF)
@Controller()
export class AccountingController {
  constructor(private readonly accounting: AccountingService) {}

  @Get('ledger-accounts')
  ledgerAccounts(@CurrentUser() u: JwtPayload) {
    return this.accounting.ledgerAccounts(u.firmId);
  }

  @Post('ledger-accounts')
  createLedgerAccount(@CurrentUser() u: JwtPayload, @Body() dto: LedgerAccountDto) {
    return this.accounting.saveLedgerAccount(u.firmId, dto);
  }

  @Put('ledger-accounts/:id')
  updateLedgerAccount(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: LedgerAccountDto) {
    return this.accounting.saveLedgerAccount(u.firmId, dto, id);
  }

  @Delete('ledger-accounts/:id')
  @HttpCode(204)
  deleteLedgerAccount(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.accounting.deleteLedgerAccount(u.firmId, id);
  }

  @Get('journals')
  journals(@CurrentUser() u: JwtPayload, @Query('from') from?: string, @Query('to') to?: string) {
    return this.accounting.journals(u.firmId, from, to);
  }

  @Get('journals/next-number')
  nextNumber(@CurrentUser() u: JwtPayload) {
    return this.accounting.nextJournalNumber(u.firmId);
  }

  @Get('journals/:id')
  journal(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.accounting.journal(u.firmId, id);
  }

  @Post('journals')
  createJournal(@CurrentUser() u: JwtPayload, @Body() dto: SaveJournalDto) {
    return this.accounting.createJournal(u.firmId, dto);
  }

  @Put('journals/:id')
  updateJournal(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SaveJournalDto) {
    return this.accounting.updateJournal(u.firmId, id, dto);
  }

  @Delete('journals/:id')
  @HttpCode(204)
  deleteJournal(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.accounting.deleteJournal(u.firmId, id);
  }

  /** Readable by everyone: the invoice form offers them. */
  @Get('currencies')
  @Roles('owner', 'admin', 'accountant', 'salesman')
  currencies(@CurrentUser() u: JwtPayload) {
    return this.accounting.currencies(u.firmId);
  }

  @Put('currencies')
  saveCurrency(@CurrentUser() u: JwtPayload, @Body() dto: CurrencyDto) {
    return this.accounting.saveCurrency(u.firmId, dto);
  }

  @Delete('currencies/:id')
  @HttpCode(204)
  deleteCurrency(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.accounting.deleteCurrency(u.firmId, id);
  }
}

@Module({ controllers: [AccountingController], providers: [AccountingService] })
export class AccountingModule {}
