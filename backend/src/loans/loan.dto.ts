import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsDateString, IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength, ValidateIf } from 'class-validator';
import { emptyToNull } from '../firm/firm.dto';

const money = { maxDecimalPlaces: 2 };
const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class CreateLoanDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(1) @MaxLength(80)
  name: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(80)
  lender?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(40)
  accountNumber?: string | null;

  @ApiPropertyOptional({ description: 'Loan amount outstanding on balanceDate' }) @IsOptional() @IsNumber(money) @Min(0) @Max(1e11)
  openingBalance?: number;

  @ApiPropertyOptional() @IsOptional() @IsDateString()
  balanceDate?: string;

  @ApiPropertyOptional({ description: 'Bank account the loan was received into; null = cash' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  bankAccountId?: string | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(money) @Min(0) @Max(100)
  interestRate?: number | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsInt() @Min(1) @Max(600)
  termMonths?: number | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(300)
  description?: string | null;
}

export class UpdateLoanDto extends PartialType(CreateLoanDto) {}

export class CreateLoanTransactionDto {
  @ApiProperty({ enum: ['payment', 'increase', 'charge'] }) @IsIn(['payment', 'increase', 'charge'])
  kind: 'payment' | 'increase' | 'charge';

  @ApiProperty({ description: 'Principal repaid / extra amount borrowed / charge added to the loan' }) @IsNumber(money) @Min(0) @Max(1e11)
  principal: number;

  @ApiPropertyOptional({ description: 'Payments only' }) @IsOptional() @IsNumber(money) @Min(0) @Max(1e11)
  interest?: number;

  @ApiProperty() @IsDateString()
  date: string;

  @ApiPropertyOptional({ description: 'Paid from / received into this bank account; null = cash' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  bankAccountId?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(300)
  description?: string | null;
}
