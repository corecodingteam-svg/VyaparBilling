import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Put, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt.strategy';
import { Roles, STAFF } from '../auth/roles';
import { ExpenseCategoryDto, ExpenseItemDefDto, SaveExpenseDto } from './expense.dto';
import { ExpensesService } from './expenses.service';

@ApiTags('expenses')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Roles(...STAFF)
@Controller()
export class ExpensesController {
  constructor(private readonly expenses: ExpensesService) {}

  @Get('expense-categories')
  categories(@CurrentUser() u: JwtPayload) {
    return this.expenses.categories(u.firmId);
  }

  @Post('expense-categories')
  createCategory(@CurrentUser() u: JwtPayload, @Body() dto: ExpenseCategoryDto) {
    return this.expenses.createCategory(u.firmId, dto);
  }

  @Patch('expense-categories/:id')
  renameCategory(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ExpenseCategoryDto) {
    return this.expenses.renameCategory(u.firmId, id, dto);
  }

  @Delete('expense-categories/:id')
  @HttpCode(204)
  deleteCategory(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.expenses.deleteCategory(u.firmId, id);
  }

  @Get('expense-items')
  itemDefs(@CurrentUser() u: JwtPayload) {
    return this.expenses.itemDefs(u.firmId);
  }

  @Post('expense-items')
  createItemDef(@CurrentUser() u: JwtPayload, @Body() dto: ExpenseItemDefDto) {
    return this.expenses.saveItemDef(u.firmId, dto);
  }

  @Put('expense-items/:id')
  updateItemDef(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ExpenseItemDefDto) {
    return this.expenses.saveItemDef(u.firmId, dto, id);
  }

  @Delete('expense-items/:id')
  @HttpCode(204)
  deleteItemDef(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.expenses.deleteItemDef(u.firmId, id);
  }

  @Get('expenses')
  list(@CurrentUser() u: JwtPayload, @Query('categoryId') categoryId?: string, @Query('from') from?: string, @Query('to') to?: string) {
    return this.expenses.list(u.firmId, { categoryId, from, to });
  }

  @Get('expenses/:id')
  get(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.expenses.get(u.firmId, id);
  }

  @Post('expenses')
  create(@CurrentUser() u: JwtPayload, @Body() dto: SaveExpenseDto) {
    return this.expenses.create(u.firmId, dto);
  }

  @Put('expenses/:id')
  update(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SaveExpenseDto) {
    return this.expenses.update(u.firmId, id, dto);
  }

  @Delete('expenses/:id')
  @HttpCode(204)
  remove(@CurrentUser() u: JwtPayload, @Param('id', ParseUUIDPipe) id: string) {
    return this.expenses.remove(u.firmId, id);
  }
}
