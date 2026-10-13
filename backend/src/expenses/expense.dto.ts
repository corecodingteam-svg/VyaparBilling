import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsDateString, IsIn, IsNumber, IsOptional, IsPositive, IsString, IsUUID,
  Matches, Max, MaxLength, Min, MinLength, ValidateIf, ValidateNested,
} from 'class-validator';
import { PAYMENT_MODES } from '../common/party-balance';
import { GSTIN_PATTERN, STATE_CODES } from '../common/states';
import { emptyToNull } from '../firm/firm.dto';
import { PaymentPartDto } from '../invoices/invoice.dto';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class ExpenseCategoryDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(1) @MaxLength(60)
  name: string;
}

export class ExpenseLineDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(1) @MaxLength(150)
  name: string;

  @ApiProperty() @IsNumber({ maxDecimalPlaces: 3 }) @IsPositive() @Max(1e9)
  quantity: number;

  @ApiProperty() @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(1e11)
  price: number;

  @ApiPropertyOptional({ description: 'GST % paid on this line (input tax)' }) @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(100)
  gstRate?: number;
}

/** A reusable expense item ("Petrol", "Tea") offered while entering expenses. */
export class ExpenseItemDefDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(1) @MaxLength(150)
  name: string;

  @ApiPropertyOptional() @IsOptional() @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(1e11)
  price?: number;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @Matches(/^[0-9]{4,8}$/, { message: 'HSN/SAC must be 4 to 8 digits' })
  hsnCode?: string | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0) @Max(100)
  gstRate?: number | null;
}

export class SaveExpenseDto {
  @ApiProperty() @IsUUID()
  categoryId: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(30)
  number?: string | null;

  @ApiProperty() @IsDateString()
  expenseDate: string;

  @ApiProperty({ type: [ExpenseLineDto] }) @IsArray() @ArrayMinSize(1, { message: 'Add at least one item' }) @ArrayMaxSize(200) @ValidateNested({ each: true }) @Type(() => ExpenseLineDto)
  lines: ExpenseLineDto[];

  @ApiProperty() @IsBoolean()
  roundOff: boolean;

  @ApiPropertyOptional({ description: 'Line prices already include GST' }) @IsOptional() @IsBoolean()
  pricesIncludeTax?: boolean;

  @ApiPropertyOptional({ type: [PaymentPartDto], description: 'Paid in several modes; the parts must add up to the total. Replaces paymentMode/bankAccountId.' })
  @IsOptional() @IsArray() @ArrayMaxSize(10) @ValidateNested({ each: true }) @Type(() => PaymentPartDto)
  payments?: PaymentPartDto[];

  @ApiPropertyOptional({ enum: PAYMENT_MODES }) @IsOptional() @IsIn(PAYMENT_MODES)
  paymentMode?: (typeof PAYMENT_MODES)[number];

  @ApiPropertyOptional({ description: 'Bank account the money moved through (bank/UPI/card, or a deposited cheque)' })
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  bankAccountId?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(1000)
  description?: string | null;

  @ApiPropertyOptional({ description: 'State the supplier billed from; when it is not the company’s state the GST is IGST' })
  @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @IsIn(STATE_CODES)
  supplierState?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @Matches(GSTIN_PATTERN, { message: 'GSTIN is not valid' })
  supplierGstin?: string | null;
}
