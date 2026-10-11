import { Global, Module } from '@nestjs/common';
import { FirmController } from './firm.controller';
import { FirmService } from './firm.service';

@Global()
@Module({ controllers: [FirmController], providers: [FirmService], exports: [FirmService] })
export class FirmModule {}
