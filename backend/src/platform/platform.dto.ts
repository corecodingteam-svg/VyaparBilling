import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBoolean, IsEmail, IsIn, IsInt, IsUUID, IsObject, IsOptional, IsString, Matches, Max, MaxLength, Min, MinLength, ValidateIf } from 'class-validator';
import { STATE_CODES } from '../common/states';
import { PLANS } from '../auth/tenant-access';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);
const lower = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim().toLowerCase() : value);
const emptyToNull = ({ value }: { value: unknown }) => (value === '' ? null : value);

export class CreateTenantDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(2) @MaxLength(120)
  firmName: string;

  @ApiProperty() @IsIn(STATE_CODES)
  stateCode: string;

  @ApiProperty() @Transform(trim) @IsString() @MinLength(2) @MaxLength(120)
  ownerName: string;

  @ApiProperty() @Transform(lower) @IsEmail()
  ownerEmail: string;

  @ApiProperty({ minLength: 8, description: 'First password; the owner changes it after signing in' }) @IsString() @MinLength(8) @MaxLength(128)
  ownerPassword: string;

  @ApiProperty({ enum: Object.keys(PLANS) }) @IsIn(Object.keys(PLANS))
  plan: string;

  @ApiPropertyOptional({ description: 'Switches that differ from the plan' }) @IsOptional() @IsObject()
  features?: Record<string, boolean>;

  @ApiPropertyOptional({ description: 'Last day of the licence, YYYY-MM-DD; empty = no end' }) @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @Matches(/^\d{4}-\d{2}-\d{2}$/)
  licenceExpiresOn?: string | null;

  @ApiPropertyOptional({ description: 'How many devices may be activated (default 5)' }) @IsOptional() @IsInt() @Min(1) @Max(1000)
  maxDevices?: number;
}

export class UpdateTenantDto {
  @ApiPropertyOptional({ enum: Object.keys(PLANS), description: 'Changing the plan also resets the switches to that plan, then applies "features"' }) @IsOptional() @IsIn(Object.keys(PLANS))
  plan?: string;

  @ApiPropertyOptional() @IsOptional() @IsObject()
  features?: Record<string, boolean>;

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @Matches(/^\d{4}-\d{2}-\d{2}$/)
  licenceExpiresOn?: string | null;

  @ApiPropertyOptional({ enum: ['active', 'suspended', 'revoked'] }) @IsOptional() @IsIn(['active', 'suspended', 'revoked'])
  status?: 'active' | 'suspended' | 'revoked';

  @ApiPropertyOptional() @IsOptional() @Transform(emptyToNull) @ValidateIf((_, v) => v !== null) @IsString() @MaxLength(200)
  statusReason?: string | null;

  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(1) @Max(1000)
  maxDevices?: number;
}

export class SetUserDisabledDto {
  @ApiProperty({ description: 'true = this login can no longer sign in (in any business)' }) @IsBoolean()
  disabled: boolean;
}

export class SetOwnerDto {
  @ApiProperty({ description: 'A user already in the business; the current owner becomes an admin' }) @IsUUID()
  userId: string;
}
