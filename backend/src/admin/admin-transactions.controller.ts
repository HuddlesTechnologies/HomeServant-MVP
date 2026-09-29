import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminLevelGuard } from '../common/guards/admin-level.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MustChangePasswordGuard } from '../common/guards/must-change-password.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AdminTransactionsService, TransactionStatusFilter } from './admin-transactions.service';

/// The console's Transactions page. Deliberately no `@MinAdminLevel`:
/// support admins, moderators and super admins can all look up a payment
/// (it's read-only; money actions stay on Payouts & Refunds, moderator+).
@Controller('admin/transactions')
@UseGuards(JwtAuthGuard, RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
@Roles(UserRole.ADMIN)
export class AdminTransactionsController {
  constructor(private readonly transactions: AdminTransactionsService) {}

  @Get()
  list(
    @Query('page') page?: string,
    @Query('pageSize') pageSize?: string,
    @Query('search') search?: string,
    @Query('status') status?: string,
  ) {
    const filter = status === 'credited' || status === 'held' || status === 'refunded' ? (status as TransactionStatusFilter) : undefined;
    return this.transactions.findTransactions(page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined, search, filter);
  }
}
