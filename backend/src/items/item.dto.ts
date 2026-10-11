import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, ValidateNested,
  IsBoolean, IsDateString, IsIn, IsInt, IsNumber, IsOptional, IsPositive, IsString, IsUUID, Matches, Max, MaxLength, Min,
  MinLength, ValidateIf,
} from 'class-validator';
import { emptyToNull } from '../firm/firm.dto';

export const GST_RATES = [0, 0.1, 0.25, 1.5, 3, 5, 6, 12, 18, 28, 40];

const money = { maxDecimalPlaces: 2 };
const qty = { maxDecimalPlaces: 3 };

export class CreateItemDto {
  @ApiPropertyOptional({ enum: ['product', 'service'] }) @IsOptional() @IsIn(['product', 'service'])
  type?: 'product' | 'service';

  @ApiProperty() @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value)) @IsString() @MinLength(1) @MaxLength(150)
  name: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @Matches(/^[0-9]{4,8}$/, { message: 'HSN/SAC must be 4 to 8 digits' })
  hsnCode?: string | null;

  @ApiPropertyOptional({ description: 'Unit short name, e.g. PCS' }) @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(20)
  unit?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @IsUUID()
  categoryId?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(40)
  itemCode?: string | null;

  @ApiPropertyOptional() @IsOptional() @IsNumber(money) @Min(0)
  salePrice?: number;

  @ApiPropertyOptional() @IsOptional() @IsBoolean()
  salePriceIncludesTax?: boolean;

  @ApiPropertyOptional() @IsOptional() @IsNumber(money) @Min(0)
  saleDiscount?: number;

  @ApiPropertyOptional({ enum: ['percent', 'amount'] }) @IsOptional() @IsIn(['percent', 'amount'])
  saleDiscountType?: 'percent' | 'amount';

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(money) @Min(0)
  wholesalePrice?: number | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(qty) @IsPositive()
  wholesaleMinQty?: number | null;

  @ApiPropertyOptional() @IsOptional() @IsNumber(money) @Min(0)
  purchasePrice?: number;

  @ApiPropertyOptional() @IsOptional() @IsBoolean()
  purchasePriceIncludesTax?: boolean;

  @ApiPropertyOptional({ description: 'null = none', enum: GST_RATES }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsIn(GST_RATES)
  gstRate?: number | null;

  @ApiPropertyOptional() @IsOptional() @IsNumber(qty) @Min(0)
  openingQty?: number;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(money) @Min(0)
  openingPrice?: number | null;

  @ApiPropertyOptional() @IsOptional() @IsDateString()
  openingDate?: string;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(qty) @Min(0)
  minStock?: number | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(80)
  location?: string | null;

  @ApiPropertyOptional({ description: 'Compensation cess %' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(money) @Min(0) @Max(300)
  cessRate?: number | null;

  @ApiPropertyOptional({ description: 'Maximum retail price' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(money) @Min(0)
  mrp?: number | null;

  @ApiPropertyOptional({ description: 'Uploaded image (see POST /files)' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  imageFileId?: string | null;

  @ApiPropertyOptional({ description: 'Services: remind the customer this many days after each sale' })
  @IsOptional() @ValidateIf((_, v) => v !== null) @IsInt() @Min(1) @Max(3650)
  serviceReminderDays?: number | null;
}

export class UpdateItemDto extends PartialType(CreateItemDto) {}

/** One row of an item import: an item plus its category by name (created when missing). */
export class ImportItemDto extends CreateItemDto {
  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(60)
  categoryName?: string | null;
}

export class ImportItemsDto {
  @ApiProperty({ type: [ImportItemDto] }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(2000) @ValidateNested({ each: true }) @Type(() => ImportItemDto)
  items: ImportItemDto[];
}

/** Price/tax/stock-alert changes for one existing item. */
export class BulkItemChangeDto {
  @ApiProperty() @IsUUID()
  id: string;

  @ApiPropertyOptional() @IsOptional() @IsNumber(money) @Min(0)
  salePrice?: number;

  @ApiPropertyOptional() @IsOptional() @IsNumber(money) @Min(0)
  purchasePrice?: number;

  @ApiPropertyOptional({ enum: GST_RATES }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsIn(GST_RATES)
  gstRate?: number | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(qty) @Min(0)
  minStock?: number | null;
}

export class BulkUpdateItemsDto {
  @ApiProperty({ type: [BulkItemChangeDto] }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(2000) @ValidateNested({ each: true }) @Type(() => BulkItemChangeDto)
  items: BulkItemChangeDto[];
}

export class AdjustStockDto {
  @ApiProperty({ enum: ['add', 'reduce'] }) @IsIn(['add', 'reduce'])
  type: 'add' | 'reduce';

  @ApiProperty() @IsNumber(qty) @IsPositive() @Max(1e9)
  quantity: number;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber(money) @Min(0)
  pricePerUnit?: number | null;

  @ApiProperty() @IsDateString()
  date: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(300)
  notes?: string | null;

  @ApiPropertyOptional({ description: 'Store to adjust; null = main store' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  godownId?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(40)
  batchNo?: string | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsDateString()
  expiryDate?: string | null;
}
