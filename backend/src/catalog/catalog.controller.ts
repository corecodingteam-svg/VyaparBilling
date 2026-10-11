import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { CategoryDto, UnitDto } from './catalog.dto';
import { CatalogService } from './catalog.service';

@ApiTags('catalog')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class CatalogController {
  constructor(private readonly catalog: CatalogService) {}

  @Get('categories')
  categories(@CurrentUser() u: JwtPayload) {
    return this.catalog.categories(u.firmId);
  }

  @Post('categories')
  @Roles(...STAFF)
  createCategory(@CurrentUser() u: JwtPayload, @Body() dto: CategoryDto) {
    return this.catalog.createCategory(u.firmId, dto);
  }

  @Patch('categories/:id')
  @Roles(...STAFF)
  renameCategory(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CategoryDto) {
    return this.catalog.renameCategory(u.firmId, id, dto);
  }

  @Delete('categories/:id')
  @Roles(...STAFF)
  @HttpCode(204)
  deleteCategory(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.catalog.deleteCategory(u.firmId, id);
  }

  @Get('units')
  units(@CurrentUser() u: JwtPayload) {
    return this.catalog.units(u.firmId);
  }

  @Post('units')
  @Roles(...STAFF)
  createUnit(@CurrentUser() u: JwtPayload, @Body() dto: UnitDto) {
    return this.catalog.createUnit(u.firmId, dto);
  }

  @Delete('units/:id')
  @Roles(...STAFF)
  @HttpCode(204)
  deleteUnit(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.catalog.deleteUnit(u.firmId, id);
  }
}
