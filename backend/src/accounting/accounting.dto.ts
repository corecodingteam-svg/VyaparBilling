import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsDateString, IsIn, IsNumber, IsOptional, IsPositive, IsString, IsUUID, Matches, Max, MaxLength, Min,
  MinLength, ValidateIf, ValidateNested,
} from 'class-validator';
import { emptyToNull } from '../firm/firm.dto';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);
export const LEDGER_TYPES = ['asset', 'liability', 'income', 'expense', 'equity'] as const;

export class LedgerAccountDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(1) @MaxLength(80)
  name: string;

  @ApiProperty({ enum: LEDGER_TYPES }) @IsIn(LEDGER_TYPES)
  type: (typeof LEDGER_TYPES)[number];
}

export class JournalLineDto {
  @ApiPropertyOptional({ description: 'One of your own ledger accounts…' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  ledgerAccountId?: string | null;

  @ApiPropertyOptional({ enum: ['cash', 'bank'], description: '…or cash / a bank account' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsIn(['cash', 'bank'])
  moneyAccount?: 'cash' | 'bank' | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  bankAccountId?: string | null;

  @ApiPropertyOptional() @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(1e11)
  debit?: number;

  @ApiPropertyOptional() @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(1e11)
  credit?: number;
}

export class SaveJournalDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(1) @MaxLength(30)
  number: string;

  @ApiProperty() @IsDateString()
  date: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(500)
  description?: string | null;

  @ApiProperty({ type: [JournalLineDto] }) @IsArray() @ArrayMinSize(2, { message: 'A journal entry needs at least two lines' }) @ArrayMaxSize(50)
  @ValidateNested({ each: true }) @Type(() => JournalLineDto)
  lines: JournalLineDto[];
}

export class CurrencyDto {
  @ApiProperty({ example: 'USD' }) @Transform(({ value }) => (typeof value === 'string' ? value.trim().toUpperCase() : value)) @Matches(/^[A-Z]{3}$/, { message: 'Currency code must be 3 letters, e.g. USD' })
  code: string;

  @ApiProperty({ example: '$' }) @Transform(trim) @IsString() @MinLength(1) @MaxLength(6)
  symbol: string;

  @ApiProperty({ description: 'Value of 1 unit in your own currency' }) @IsNumber({ maxDecimalPlaces: 6 }) @IsPositive() @Max(1e7)
  rate: number;
}
