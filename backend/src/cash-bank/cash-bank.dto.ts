import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsDateString, IsIn, IsNumber, IsOptional, IsPositive, IsString, IsUUID, Max, MaxLength, MinLength, ValidateIf } from 'class-validator';
import { emptyToNull, upperOrNull } from '../firm/firm.dto';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class CreateBankAccountDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(1) @MaxLength(80)
  name: string;

  @ApiPropertyOptional() @IsOptional() @IsNumber({ maxDecimalPlaces: 2 })
  openingBalance?: number;

  @ApiPropertyOptional() @IsOptional() @IsDateString()
  openingDate?: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(34)
  accountNumber?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(upperOrNull) @IsString() @MaxLength(11)
  ifsc?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(80)
  bankName?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(80)
  holderName?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(80)
  upiId?: string | null;
}

export class UpdateBankAccountDto extends PartialType(CreateBankAccountDto) {}

export const ADJUSTMENT_KINDS = ['cash_add', 'cash_reduce', 'bank_add', 'bank_reduce', 'bank_to_cash', 'cash_to_bank', 'bank_to_bank'] as const;

export class CreateAdjustmentDto {
  @ApiProperty({ enum: ADJUSTMENT_KINDS }) @IsIn(ADJUSTMENT_KINDS)
  kind: (typeof ADJUSTMENT_KINDS)[number];

  @ApiPropertyOptional({ description: 'Required for every bank_* / *_bank kind' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  bankAccountId?: string | null;

  @ApiPropertyOptional({ description: 'bank_to_bank destination' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  toBankAccountId?: string | null;

  @ApiProperty() @IsNumber({ maxDecimalPlaces: 2 }) @IsPositive() @Max(1e11)
  amount: number;

  @ApiProperty() @IsDateString()
  date: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(300)
  description?: string | null;
}

export class ChequeDepositDto {
  @ApiProperty() @IsUUID()
  bankAccountId: string;
}
