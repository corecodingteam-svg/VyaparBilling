import { ApiProperty } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsEmail, IsIn, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';
import { STATE_CODES } from '../../common/states';

const normalizeEmail = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim().toLowerCase() : value;
const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class LoginDto {
  @ApiProperty({ example: 'owner@example.com' })
  @Transform(normalizeEmail)
  @IsEmail()
  email: string;

  @ApiProperty()
  @IsString()
  @MinLength(1)
  password: string;
}

export class ChangePasswordDto {
  @ApiProperty() @IsString() @MinLength(1)
  currentPassword: string;

  @ApiProperty({ minLength: 8 }) @IsString() @MinLength(8) @MaxLength(128)
  newPassword: string;
}

export class CreateFirmDto {
  @ApiProperty({ example: 'Sharma Traders' }) @Transform(trim) @IsString() @MinLength(2) @MaxLength(120)
  firmName: string;

  @ApiProperty({ example: '07', description: 'GST state code of the business' }) @IsIn(STATE_CODES)
  stateCode: string;
}

export class SwitchFirmDto {
  @ApiProperty() @IsUUID()
  firmId: string;
}

export class RegisterDto extends CreateFirmDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(2) @MaxLength(120)
  fullName: string;

  @ApiProperty() @Transform(normalizeEmail) @IsEmail()
  email: string;

  @ApiProperty({ minLength: 8 }) @IsString() @MinLength(8) @MaxLength(128)
  password: string;
}

export const ASSIGNABLE_ROLES = ['admin', 'accountant', 'salesman'] as const;

/** Adds a person to the current company. A new login is created unless the email already has one. */
export class AddMemberDto {
  @ApiProperty() @Transform(trim) @IsString() @MinLength(2) @MaxLength(120)
  fullName: string;

  @ApiProperty() @Transform(normalizeEmail) @IsEmail()
  email: string;

  @ApiProperty({ minLength: 8, description: 'Used only when a new login is created' }) @IsString() @MinLength(8) @MaxLength(128)
  password: string;

  @ApiProperty({ enum: ASSIGNABLE_ROLES }) @IsIn(ASSIGNABLE_ROLES)
  role: (typeof ASSIGNABLE_ROLES)[number];
}

export class UpdateMemberDto {
  @ApiProperty({ enum: ASSIGNABLE_ROLES }) @IsIn(ASSIGNABLE_ROLES)
  role: (typeof ASSIGNABLE_ROLES)[number];
}

export class DeleteFirmDto {
  @ApiProperty({ description: 'The company name, typed to confirm' }) @IsString() @MinLength(1) @MaxLength(120)
  name: string;
}
