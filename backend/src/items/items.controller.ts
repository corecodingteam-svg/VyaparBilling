import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { AdjustStockDto, BulkUpdateItemsDto, CreateItemDto, ImportItemsDto, UpdateItemDto } from './item.dto';
import { ItemsService } from './items.service';

@ApiTags('items')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('items')
export class ItemsController {
  constructor(private readonly items: ItemsService) {}

  @Get()
  list(
    @CurrentUser() u: JwtPayload,
    @Query('type') type?: string,
    @Query('search') search?: string,
    @Query('categoryId') categoryId?: string,
  ) {
    return this.items.list(u.firmId, { type, search, categoryId });
  }

  @Post('import')
  @Roles(...STAFF)
  @HttpCode(200)
  import(@CurrentUser() u: JwtPayload, @Body() dto: ImportItemsDto) {
    return this.items.import(u.firmId, dto.items);
  }

  @Patch('bulk')
  @Roles(...STAFF)
  bulkUpdate(@CurrentUser() u: JwtPayload, @Body() dto: BulkUpdateItemsDto) {
    return this.items.bulkUpdate(u.firmId, dto.items);
  }

  @Get(':id')
  get(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.items.get(u.firmId, id);
  }

  @Get(':id/batches')
  batches(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Query('godownId') godownId?: string) {
    // "main" asks for the main store; no value means every store together.
    return this.items.batches(u.firmId, id, godownId === undefined ? undefined : godownId === 'main' ? null : godownId);
  }

  @Get(':id/serials')
  serials(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.items.serials(u.firmId, id);
  }

  @Get(':id/godowns')
  stockByGodown(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.items.stockByGodown(u.firmId, id);
  }

  @Get(':id/movements')
  movements(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.items.movements(u.firmId, id);
  }

  @Post()
  @Roles(...STAFF)
  create(@CurrentUser() u: JwtPayload, @Body() dto: CreateItemDto) {
    return this.items.create(u.firmId, dto);
  }

  @Patch(':id')
  @Roles(...STAFF)
  update(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateItemDto) {
    return this.items.update(u.firmId, id, dto);
  }

  @Post(':id/adjust')
  @Roles(...STAFF)
  @HttpCode(200)
  adjust(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: AdjustStockDto) {
    return this.items.adjust(u.firmId, id, dto);
  }

  @Delete(':id')
  @Roles(...STAFF)
  @HttpCode(204)
  remove(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.items.remove(u.firmId, id);
  }
}
