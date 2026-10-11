import { Body, Controller, Delete, Get, HttpCode, Inject, Injectable, Module, NotFoundException, BadRequestException, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiTags } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsBase64, IsIn, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { assertOwnFile } from '../common/own-file';
import { Db, KYSELY } from '../database/database.module';

/** Largest single upload. Files live in the database, so they are kept small. */
export const MAX_FILE_BYTES = 5 * 1024 * 1024;
const MIME_TYPES = ['image/png', 'image/jpeg', 'image/webp', 'application/pdf'] as const;
const OWNER_TYPES = ['invoice', 'expense', 'payment'] as const;
type OwnerType = (typeof OWNER_TYPES)[number];
const OWNER_TABLE = { invoice: 'invoices', expense: 'expenses', payment: 'payments' } as const;

export class UploadFileDto {
  @ApiProperty() @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value)) @IsString() @MinLength(1) @MaxLength(200)
  name: string;

  @ApiProperty({ enum: MIME_TYPES }) @IsIn(MIME_TYPES, { message: 'Only PNG, JPEG, WebP images and PDF files can be uploaded' })
  mimeType: (typeof MIME_TYPES)[number];

  @ApiProperty({ description: 'File contents, base64-encoded' }) @IsBase64()
  dataBase64: string;
}

export class AttachDto {
  @ApiProperty({ enum: OWNER_TYPES }) @IsIn(OWNER_TYPES)
  ownerType: OwnerType;

  @ApiProperty() @IsUUID()
  ownerId: string;

  @ApiProperty() @IsUUID()
  fileId: string;
}

@Injectable()
export class FilesService {
  constructor(@Inject(KYSELY) private readonly db: Db) {}

  async upload(firmId: string, dto: UploadFileDto) {
    const data = Buffer.from(dto.dataBase64, 'base64');
    if (!data.length) throw new BadRequestException({ code: 'EMPTY_FILE', message: 'The file is empty.' });
    if (data.length > MAX_FILE_BYTES) throw new BadRequestException({ code: 'FILE_TOO_LARGE', message: 'Files can be at most 5 MB.' });
    const row = await this.db
      .insertInto('files')
      .values({ firm_id: firmId, name: dto.name, mime_type: dto.mimeType, size: data.length, data })
      .returning(['id', 'name', 'mime_type', 'size'])
      .executeTakeFirstOrThrow();
    return { id: row.id, name: row.name, mimeType: row.mime_type, size: row.size };
  }

  async get(firmId: string, id: string) {
    const f = await this.db.selectFrom('files').selectAll().where('id', '=', id).where('firm_id', '=', firmId).executeTakeFirst();
    if (!f) throw new NotFoundException({ code: 'FILE_NOT_FOUND', message: 'File not found.' });
    return { id: f.id, name: f.name, mimeType: f.mime_type, size: f.size, dataBase64: f.data.toString('base64') };
  }

  private async assertOwner(firmId: string, ownerType: OwnerType, ownerId: string) {
    const owner = await this.db.selectFrom(OWNER_TABLE[ownerType]).select('id').where('id', '=', ownerId).where('firm_id', '=', firmId).executeTakeFirst();
    if (!owner) throw new NotFoundException({ code: 'OWNER_NOT_FOUND', message: 'The transaction no longer exists.' });
  }

  async attachments(firmId: string, ownerType: string, ownerId: string) {
    if (!OWNER_TYPES.includes(ownerType as OwnerType)) throw new BadRequestException({ code: 'BAD_OWNER', message: 'Unknown transaction type.' });
    const rows = await this.db
      .selectFrom('attachments as a')
      .innerJoin('files as f', 'f.id', 'a.file_id')
      .select(['a.id', 'a.file_id', 'f.name', 'f.mime_type', 'f.size'])
      .where('a.firm_id', '=', firmId)
      .where('a.owner_type', '=', ownerType as OwnerType)
      .where('a.owner_id', '=', ownerId)
      .orderBy('a.created_at')
      .execute();
    return rows.map((r) => ({ id: r.id, fileId: r.file_id, name: r.name, mimeType: r.mime_type, size: r.size }));
  }

  async attach(firmId: string, dto: AttachDto) {
    await this.assertOwner(firmId, dto.ownerType, dto.ownerId);
    await assertOwnFile(this.db, firmId, dto.fileId);
    await this.db.insertInto('attachments').values({ firm_id: firmId, owner_type: dto.ownerType, owner_id: dto.ownerId, file_id: dto.fileId }).execute();
    return this.attachments(firmId, dto.ownerType, dto.ownerId);
  }

  /** Removes the attachment and the file behind it. */
  async detach(firmId: string, id: string) {
    const a = await this.db.selectFrom('attachments').select(['id', 'file_id']).where('id', '=', id).where('firm_id', '=', firmId).executeTakeFirst();
    if (!a) throw new NotFoundException({ code: 'ATTACHMENT_NOT_FOUND', message: 'Attachment not found.' });
    await this.db.deleteFrom('files').where('id', '=', a.file_id).execute(); // cascades to the attachment
  }
}

@ApiTags('files')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class FilesController {
  constructor(private readonly files: FilesService) {}

  @Post('files')
  upload(@CurrentUser() u: JwtPayload, @Body() dto: UploadFileDto) {
    return this.files.upload(u.firmId, dto);
  }

  @Get('files/:id')
  get(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.files.get(u.firmId, id);
  }

  @Get('attachments')
  attachments(@CurrentUser() u: JwtPayload, @Query('ownerType') ownerType: string, @Query('ownerId', ParseUUIDPipe) ownerId: string) {
    return this.files.attachments(u.firmId, ownerType, ownerId);
  }

  @Post('attachments')
  attach(@CurrentUser() u: JwtPayload, @Body() dto: AttachDto) {
    return this.files.attach(u.firmId, dto);
  }

  @Delete('attachments/:id')
  @HttpCode(204)
  detach(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.files.detach(u.firmId, id);
  }
}

@Module({ controllers: [FilesController], providers: [FilesService] })
export class FilesModule {}
