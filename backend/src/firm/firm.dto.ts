import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import { IsDateString, IsEmail, IsIn, IsOptional, IsString, IsUUID, Matches, MaxLength, MinLength, ValidateIf, ValidateNested } from 'class-validator';
import { FirmSettingsDto } from './firm-settings';
import { GSTIN_PATTERN, STATE_CODES } from '../common/states';

/** Empty strings from forms become null so optional fields can be cleared. */
export const emptyToNull = ({ value }: { value: unknown }) =>
  typeof value === 'string' && value.trim() === '' ? null : typeof value === 'string' ? value.trim() : value;
export const upperOrNull = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? (value.trim() === '' ? null : value.trim().toUpperCase()) : value;

export class UpdateFirmDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MinLength(2) @MaxLength(120)
  name?: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(20)
  phone?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(upperOrNull) @ValidateIf((_, v) => v !== null) @Matches(GSTIN_PATTERN, { message: 'GSTIN is not valid' })
  gstin?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @IsEmail()
  email?: string | null;

  @ApiPropertyOptional() @IsOptional() @IsDateString()
  booksStartDate?: string;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(60)
  businessType?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(60)
  businessCategory?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @IsIn(STATE_CODES)
  stateCode?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @Matches(/^[1-9][0-9]{5}$/, { message: 'Pincode must be 6 digits' })
  pincode?: string | null;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @IsString() @MaxLength(500)
  address?: string | null;

  @ApiPropertyOptional({ description: 'Uploaded logo (see POST /files); null removes it' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  logoFileId?: string | null;

  @ApiPropertyOptional({ description: 'Uploaded signature image; null removes it' }) @IsOptional() @ValidateIf((_, v) => v !== null) @IsUUID()
  signatureFileId?: string | null;

  @ApiPropertyOptional({ description: 'Only the keys sent are changed' }) @IsOptional() @ValidateNested() @Type(() => FirmSettingsDto)
  settings?: FirmSettingsDto;
}
