import { Module } from '@nestjs/common';
import { PartiesModule } from '../parties/parties.module';
import { ReportsController } from './reports.controller';
import { ReportsService } from './reports.service';

@Module({ imports: [PartiesModule], controllers: [ReportsController], providers: [ReportsService] })
export class ReportsModule {}
