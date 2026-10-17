import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsOptional, IsString, Matches, MaxLength } from 'class-validator';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class DeviceDto {
  @ApiProperty({ description: 'Random id the app makes once per installation' })
  @IsString() @Matches(/^[A-Za-z0-9-]{16,64}$/)
  installationId: string;

  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(80)
  deviceName?: string;

  @ApiPropertyOptional() @IsOptional() @Transform(trim) @IsString() @MaxLength(30)
  platform?: string;
}

export class DeactivateDto {
  @ApiProperty() @IsString() @Matches(/^[A-Za-z0-9-]{16,64}$/)
  installationId: string;
}
