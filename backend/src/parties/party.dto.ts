import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsDateString, IsEmail, IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID, Matches, Max,
  MaxLength, Min, MinLength, ValidateIf, ValidateNested,
} from 'class-validator';
import { GSTIN_PATTERN, STATE_CODES } from '../common/states';
import { emptyToNull, upperOrNull } from '../firm/firm.dto';

export class AdditionalFieldDto {
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(40)
  name: string;

  @ApiProperty() @IsString() @MaxLength(200)
  value: string;
}

export class CreatePartyDto {
  @ApiProperty() @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value)) @IsString() @MinLength(1) @MaxLength(120)
  name: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @Matches(/^[0-9+\- ]{6,20}$/, { message: 'Phone number is not valid' })
  phone?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(upperOrNull) @ValidateIf((_, v) => v !== null) @Matches(GSTIN_PATTERN, { message: 'GSTIN is not valid' })
  gstin?: string | null;

  @ApiPropertyOptional({ enum: ['unregistered', 'regular', 'composition'] }) @IsOptional() @IsIn(['unregistered', 'regular', 'composition'])
  gstType?: 'unregistered' | 'regular' | 'composition';

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @IsIn(STATE_CODES)
  stateCode?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @IsEmail()
  email?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(500)
  billingAddress?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(500)
  shippingAddress?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(100)
  city?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @Matches(/^[1-9][0-9]{5}$/, { message: 'Pincode must be 6 digits' })
  pincode?: string | null;

  @ApiPropertyOptional({ description: 'Positive = to receive, negative = to pay' }) @IsOptional() @IsNumber({ maxDecimalPlaces: 2 })
  openingBalance?: number;

  @ApiPropertyOptional() @IsOptional() @IsDateString()
  openingBalanceDate?: string;

  @ApiPropertyOptional({ description: 'null = no limit' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsNumber({ maxDecimalPlaces: 2 }) @Min(0)
  creditLimit?: number | null;

  @ApiPropertyOptional() @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  groupId?: string | null;

  @ApiPropertyOptional({ description: 'The salesman this party belongs to' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  assignedUserId?: string | null;

  @ApiPropertyOptional({ description: 'A foreign party is billed and pays in this currency' })
  @IsOptional() @Transform(upperOrNull) @ValidateIf((_, v) => v !== null) @Matches(/^[A-Z]{3}$/, { message: 'Currency code must be 3 letters' })
  currencyCode?: string | null;

  @ApiPropertyOptional({ description: 'Loyalty points the party starts with' }) @IsOptional() @IsInt() @Min(0) @Max(1e9)
  loyaltyOpening?: number;

  @ApiPropertyOptional({ type: [AdditionalFieldDto] }) @IsOptional() @IsArray() @ArrayMaxSize(4) @ValidateNested({ each: true }) @Type(() => AdditionalFieldDto)
  additionalFields?: AdditionalFieldDto[];
}

export class UpdatePartyDto extends PartialType(CreatePartyDto) {}

export class PartyGroupDto {
  @ApiProperty() @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value)) @IsString() @MinLength(1) @MaxLength(60)
  name: string;
}

export class ImportPartiesDto {
  @ApiProperty({ type: [CreatePartyDto] }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(2000) @ValidateNested({ each: true }) @Type(() => CreatePartyDto)
  parties: CreatePartyDto[];
}
