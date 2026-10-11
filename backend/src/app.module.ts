import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AccountingModule } from './accounting/accounting.module';
import { AuthModule } from './auth/auth.module';
import { BackupsModule } from './backups/backups.module';
import { CashBankModule } from './cash-bank/cash-bank.module';
import { CatalogModule } from './catalog/catalog.module';
import { DashboardModule } from './dashboard/dashboard.module';
import { DatabaseModule } from './database/database.module';
import { ExpensesModule } from './expenses/expenses.module';
import { FilesModule } from './files/files.module';
import { FirmModule } from './firm/firm.module';
import { GodownsModule } from './godowns/godowns.module';
import { HealthController } from './health/health.controller';
import { InvoicesModule } from './invoices/invoices.module';
import { ItemsModule } from './items/items.module';
import { LoansModule } from './loans/loans.module';
import { LocationsModule } from './locations/locations.module';
import { PartiesModule } from './parties/parties.module';
import { PaymentsModule } from './payments/payments.module';
import { RemindersModule } from './reminders/reminders.module';
import { ReportsModule } from './reports/reports.module';
import { SearchModule } from './search/search.module';
import { UtilitiesModule } from './utilities/utilities.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    DatabaseModule,
    AuthModule,
    FirmModule,
    PartiesModule,
    ItemsModule,
    CatalogModule,
    DashboardModule,
    InvoicesModule,
    PaymentsModule,
    ExpensesModule,
    CashBankModule,
    LoansModule,
    ReportsModule,
    FilesModule,
    AccountingModule,
    RemindersModule,
    SearchModule,
    UtilitiesModule,
    GodownsModule,
    LocationsModule,
    BackupsModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
