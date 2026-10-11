import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsDateString, IsObject, IsOptional, IsString, MaxLength, MinLength, ValidateIf } from 'class-validator';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class CloseBooksDto {
  @ApiProperty({ description: 'Lock everything dated on or before this day; null re-opens the books', nullable: true })
  @ValidateIf((_, v) => v !== null) @IsDateString()
  date: string | null;
}

export class NewYearDto {
  @ApiProperty({ description: 'Name of the new company, e.g. "My Shop 2027-28"' }) @Transform(trim) @IsString() @MinLength(2) @MaxLength(120)
  name: string;

  @ApiProperty({ description: 'First day of the new books' }) @IsDateString()
  startDate: string;
}

export class RestoreDto {
  @ApiProperty({ description: 'The file produced by GET /backup' }) @IsObject()
  backup: Record<string, unknown>;

  @ApiPropertyOptional({ description: 'Name for the restored company (defaults to the name in the backup)' })
  @IsOptional() @Transform(trim) @IsString() @MinLength(2) @MaxLength(120)
  name?: string;
}
