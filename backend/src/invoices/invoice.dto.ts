import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsDateString, IsIn, IsInt, IsNumber, IsOptional, IsPositive, IsString,
  IsUUID, Matches, Max, MaxLength, Min, MinLength, ValidateIf, ValidateNested,
} from 'class-validator';
import { INVOICE_TYPE_NAMES, InvoiceType } from '../common/invoice-types';
import { PAYMENT_MODES } from '../common/party-balance';
import { STATE_CODES } from '../common/states';
import { emptyToNull } from '../firm/firm.dto';
import { GST_RATES } from '../items/item.dto';

const money = { maxDecimalPlaces: 2 };

export class InvoiceLineDto {
  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  itemId?: string | null;

  @ApiProperty() @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value)) @IsString() @MinLength(1) @MaxLength(150)
  name: string;

  @ApiProperty() @IsNumber({ maxDecimalPlaces: 3 }) @IsPositive() @Max(1e9)
  quantity: number;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(20)
  unit?: string | null;

  @ApiProperty() @IsNumber(money) @Min(0) @Max(1e11)
  price: number;

  @ApiPropertyOptional({ description: 'Takes precedence over discountAmount' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(money) @Min(0) @Max(100)
  discountPct?: number | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(money) @Min(0)
  discountAmount?: number | null;

  @ApiPropertyOptional({ description: 'GST %; null/omitted = no tax', enum: GST_RATES }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsIn(GST_RATES)
  gstRate?: number | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @Matches(/^[0-9]{4,8}$/, { message: 'HSN/SAC must be 4 to 8 digits' })
  hsnCode?: string | null;

  @ApiPropertyOptional({ description: 'Compensation cess %' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(money) @Min(0) @Max(300)
  cessRate?: number | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(40)
  batchNo?: string | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsDateString()
  mfgDate?: string | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsDateString()
  expiryDate?: string | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(money) @Min(0) @Max(1e11)
  mrp?: number | null;

  @ApiPropertyOptional({ description: 'Serial numbers / IMEIs, comma-separated, one per unit' }) @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(4000)
  serialNos?: string | null;
}

/** Freight, packing and the like, added to the bill after tax. */
export class ChargeDto {
  @ApiProperty() @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value)) @IsString() @MinLength(1) @MaxLength(30)
  name: string;

  @ApiProperty() @IsNumber(money) @Min(0) @Max(1e11)
  amount: number;
}

/** One part of what was paid at billing time (a bill can be split, e.g. part cash and part UPI). */
export class PaymentPartDto {
  @ApiProperty({ enum: PAYMENT_MODES }) @IsIn(PAYMENT_MODES)
  mode: (typeof PAYMENT_MODES)[number];

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  bankAccountId?: string | null;

  @ApiProperty() @IsNumber(money) @Min(0) @Max(1e11)
  amount: number;
}

export class SaveInvoiceDto {
  @ApiProperty({ enum: INVOICE_TYPE_NAMES }) @IsIn(INVOICE_TYPE_NAMES)
  type: InvoiceType;

  @ApiPropertyOptional({ description: 'Quotation-like document this one is created from; it is then marked converted' })
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  fromDocumentId?: string | null;

  @ApiProperty({ description: 'Required for every type we number ourselves; optional supplier bill number for purchases' })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value)) @IsString() @MaxLength(30)
  number: string;

  @ApiProperty() @IsDateString()
  invoiceDate: string;

  @ApiProperty({ description: 'Cash sale: fully paid, party optional' }) @IsBoolean()
  isCash: boolean;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  partyId?: string | null;

  @ApiPropertyOptional({ description: 'Walk-in customer name when no party is selected' }) @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(120)
  partyName?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(20)
  phone?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(500)
  billingAddress?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @IsIn(STATE_CODES)
  stateOfSupply?: string | null;

  @ApiProperty({ type: [InvoiceLineDto] }) @IsArray() @ArrayMinSize(1, { message: 'Add at least one item' }) @ArrayMaxSize(500) @ValidateNested({ each: true }) @Type(() => InvoiceLineDto)
  lines: InvoiceLineDto[];

  @ApiProperty() @IsBoolean()
  roundOff: boolean;

  @ApiPropertyOptional({ description: 'Unit prices already include GST' }) @IsOptional() @IsBoolean()
  pricesIncludeTax?: boolean;

  @ApiPropertyOptional({ type: [PaymentPartDto], description: 'Split payment; replaces received/paymentMode/bankAccountId when given' })
  @IsOptional() @IsArray() @ArrayMaxSize(10) @ValidateNested({ each: true }) @Type(() => PaymentPartDto)
  payments?: PaymentPartDto[];

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(500)
  shippingAddress?: string | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsDateString()
  dueDate?: string | null;

  @ApiPropertyOptional({ description: 'Store the stock moves through; null = main store' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  godownId?: string | null;

  @ApiPropertyOptional({ description: 'Bill-level discount %, taken off before tax; wins over discountAmount' })
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 4 }) @Min(0) @Max(100)
  discountPct?: number | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(money) @Min(0)
  discountAmount?: number | null;

  @ApiPropertyOptional({ type: [ChargeDto] }) @IsOptional() @IsArray() @ArrayMaxSize(6) @ValidateNested({ each: true }) @Type(() => ChargeDto)
  charges?: ChargeDto[];

  @ApiPropertyOptional({ description: 'TCS %, collected on top of the bill' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 3 }) @Min(0) @Max(30)
  tcsRate?: number | null;

  @ApiPropertyOptional({ description: 'TDS %, held back by the payer on the taxable value' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 3 }) @Min(0) @Max(30)
  tdsRate?: number | null;

  @ApiPropertyOptional({ description: 'Loyalty points the customer redeems against this sale' }) @IsOptional() @IsInt() @Min(0) @Max(1e9)
  loyaltyRedeem?: number;

  @ApiPropertyOptional({ description: 'Currency the document is made out in: prices and amounts sent are in it, and are booked at exchangeRate' })
  @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @Matches(/^[A-Z]{3}$/, { message: 'Currency code must be 3 letters' })
  currencyCode?: string | null;

  @ApiPropertyOptional({ description: 'Base-currency value of one unit of currencyCode' })
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 6 }) @IsPositive()
  exchangeRate?: number | null;

  @ApiPropertyOptional() @IsOptional() @IsNumber(money) @Min(0)
  received?: number;

  @ApiPropertyOptional({ enum: PAYMENT_MODES }) @IsOptional() @IsIn(PAYMENT_MODES)
  paymentMode?: (typeof PAYMENT_MODES)[number];

  @ApiPropertyOptional({ description: 'Bank account the money moved through (bank/UPI/card, or a deposited cheque)' })
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  bankAccountId?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(1000)
  description?: string | null;
}
