import { Body, Controller, Delete, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { AdminLevel, UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { MinAdminLevel } from '../common/decorators/min-admin-level.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminLevelGuard } from '../common/guards/admin-level.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { AdminService } from './admin.service';
import { CreateAdminDto } from './dto/create-admin.dto';
import { QueryUsersDto } from './dto/query-users.dto';
import { QueryVendorsDto } from './dto/query-vendors.dto';
import { RejectVendorDto } from './dto/reject-vendor.dto';
import { SetAdminLevelDto } from './dto/set-admin-level.dto';

/// Every route here requires an authenticated ADMIN account at minimum
/// (SUPPORT tier or above); routes that need more than that carry their
/// own `@MinAdminLevel(...)`. See AdminLevel's doc comment in
/// schema.prisma for the SUPPORT < MODERATOR < SUPER_ADMIN ranking.
@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard, AdminLevelGuard)
@Roles(UserRole.ADMIN)
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  /// Confirms `request.user` is really an admin (and which tier) — used
  /// by the client right after login to decide whether to route into the
  /// admin console and which actions to show, rather than trusting a
  /// client-side guess.
  @Get('me')
  me(@CurrentUser() user: AuthenticatedUser) {
    return { id: user.sub, email: user.email, role: user.role, adminLevel: user.adminLevel };
  }

  @Get('stats')
  stats() {
    return this.admin.stats();
  }

  // --- Admin management (SUPER_ADMIN only) --------------------------------

  @Get('admins')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  findAdmins() {
    return this.admin.findAdmins();
  }

  @Post('admins')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  createAdmin(@Body() dto: CreateAdminDto) {
    return this.admin.createAdmin(dto);
  }

  @Patch('admins/:id/level')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  setAdminLevel(@CurrentUser() actingAdmin: AuthenticatedUser, @Param('id') id: string, @Body() dto: SetAdminLevelDto) {
    return this.admin.setAdminLevel(actingAdmin.sub, id, dto.level);
  }

  @Delete('admins/:id')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  async removeAdmin(@CurrentUser() actingAdmin: AuthenticatedUser, @Param('id') id: string): Promise<void> {
    await this.admin.removeAdmin(actingAdmin.sub, id);
  }

  // --- Users -----------------------------------------------------------

  @Get('users')
  findUsers(@Query() query: QueryUsersDto) {
    return this.admin.findUsers(query);
  }

  @Patch('users/:id/deactivate')
  async deactivateUser(@Param('id') id: string): Promise<void> {
    await this.admin.deactivateUser(id);
  }

  @Delete('users/:id')
  @MinAdminLevel(AdminLevel.MODERATOR)
  async deleteUser(@Param('id') id: string): Promise<void> {
    await this.admin.deleteUser(id);
  }

  // --- Vendors ---------------------------------------------------------

  @Get('vendors')
  findVendors(@Query() query: QueryVendorsDto) {
    return this.admin.findVendors(query);
  }

  @Patch('vendors/:id/approve')
  @MinAdminLevel(AdminLevel.MODERATOR)
  approveVendor(@Param('id') id: string) {
    return this.admin.approveVendor(id);
  }

  @Patch('vendors/:id/reject')
  @MinAdminLevel(AdminLevel.MODERATOR)
  rejectVendor(@Param('id') id: string, @Body() dto: RejectVendorDto) {
    return this.admin.rejectVendor(id, dto);
  }

  @Patch('vendors/:id/suspend')
  @MinAdminLevel(AdminLevel.MODERATOR)
  suspendVendor(@Param('id') id: string) {
    return this.admin.suspendVendor(id);
  }

  @Patch('vendors/:id/unsuspend')
  @MinAdminLevel(AdminLevel.MODERATOR)
  unsuspendVendor(@Param('id') id: string) {
    return this.admin.unsuspendVendor(id);
  }

  // --- Properties --------------------------------------------------------

  @Get('properties')
  findProperties(@Query('page') page?: string, @Query('pageSize') pageSize?: string, @Query('search') search?: string) {
    return this.admin.findProperties(page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined, search);
  }

  @Delete('properties/:id')
  @MinAdminLevel(AdminLevel.MODERATOR)
  async removeProperty(@Param('id') id: string): Promise<void> {
    await this.admin.removeProperty(id);
  }

  // --- Marketplace ---------------------------------------------------------

  @Get('marketplace/products')
  findProducts(@Query('page') page?: string, @Query('pageSize') pageSize?: string, @Query('search') search?: string) {
    return this.admin.findProducts(page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined, search);
  }

  @Delete('marketplace/products/:id')
  @MinAdminLevel(AdminLevel.MODERATOR)
  async removeProduct(@Param('id') id: string): Promise<void> {
    await this.admin.removeProduct(id);
  }

  @Get('marketplace/orders')
  findOrders(@Query('page') page?: string, @Query('pageSize') pageSize?: string) {
    return this.admin.findOrders(page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined);
  }
}
