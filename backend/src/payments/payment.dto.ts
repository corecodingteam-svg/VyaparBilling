import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize, IsArray, IsDateString, IsIn, IsNumber, IsOptional, IsPositive, IsString, IsUUID, Matches, Max, MaxLength, MinLength, ValidateIf,
  ValidateNested,
} from 'class-validator';
import { PAYMENT_MODES } from '../common/party-balance';
import { emptyToNull } from '../firm/firm.dto';
import { PaymentPartDto } from '../invoices/invoice.dto';

/** Part of a payment set against one specific invoice. */
export class AllocationDto {
  @ApiProperty() @IsUUID()
  invoiceId: string;

  @ApiProperty() @IsNumber({ maxDecimalPlaces: 2 }) @IsPositive()
  amount: number;
}

export class SavePaymentDto {
  @ApiProperty({ enum: ['in', 'out'] }) @IsIn(['in', 'out'])
  type: 'in' | 'out';

  @ApiProperty() @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value)) @IsString() @MinLength(1) @MaxLength(30)
  number: string;

  @ApiProperty() @IsUUID()
  partyId: string;

  @ApiProperty() @IsDateString()
  paymentDate: string;

  @ApiProperty({ description: 'In currencyCode when one is given, otherwise in the base currency' }) @IsNumber({ maxDecimalPlaces: 2 }) @IsPositive() @Max(1e11)
  amount: number;

  @ApiPropertyOptional({ description: 'A foreign-currency payment: amount, parts and allocations are in this currency' })
  @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @Matches(/^[A-Z]{3}$/, { message: 'Currency code must be 3 letters' })
  currencyCode?: string | null;

  @ApiPropertyOptional({ description: 'Base-currency value of one unit of currencyCode on the payment date' })
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 6 }) @IsPositive()
  exchangeRate?: number | null;

  @ApiPropertyOptional({ type: [PaymentPartDto], description: 'Paid in several modes; the parts must add up to amount. Replaces paymentMode/bankAccountId.' })
  @IsOptional() @IsArray() @ArrayMaxSize(10) @ValidateNested({ each: true }) @Type(() => PaymentPartDto)
  parts?: PaymentPartDto[];

  @ApiPropertyOptional({ enum: PAYMENT_MODES }) @IsOptional() @IsIn(PAYMENT_MODES)
  paymentMode?: (typeof PAYMENT_MODES)[number];

  @ApiPropertyOptional({ description: 'Bank account the money moved through (bank/UPI/card, or a deposited cheque)' })
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  bankAccountId?: string | null;

  @ApiPropertyOptional({ type: [AllocationDto], description: 'Invoices this payment settles; omit to leave existing links unchanged' })
  @IsOptional() @IsArray() @ArrayMaxSize(200) @ValidateNested({ each: true }) @Type(() => AllocationDto)
  allocations?: AllocationDto[];

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(1000)
  description?: string | null;
}
