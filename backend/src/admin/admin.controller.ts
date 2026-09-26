import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { ActivityLogType, AdminLevel, UserRole } from '@prisma/client';
import { AllowMustChangePassword } from '../common/decorators/allow-must-change-password.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { MinAdminLevel } from '../common/decorators/min-admin-level.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminLevelGuard } from '../common/guards/admin-level.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MustChangePasswordGuard } from '../common/guards/must-change-password.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { AdminService } from './admin.service';
import { ConfirmAdminDto } from './dto/confirm-admin.dto';
import { ConfirmAdminResetDto } from './dto/confirm-admin-reset.dto';
import { DelistReasonDto } from './dto/delist-reason.dto';
import { QueryUsersDto } from './dto/query-users.dto';
import { QueryVendorsDto } from './dto/query-vendors.dto';
import { RejectVendorDto } from './dto/reject-vendor.dto';
import { RequestAdminDto } from './dto/request-admin.dto';
import { SetAdminLevelDto } from './dto/set-admin-level.dto';
import { SetAdminTwoFactorDto } from './dto/set-admin-two-factor.dto';
import { UpdateUserDto } from './dto/update-user.dto';

/// Every route here requires an authenticated ADMIN account at minimum
/// (SUPPORT tier or above); routes that need more than that carry their
/// own `@MinAdminLevel(...)`. See AdminLevel's doc comment in
/// schema.prisma for the SUPPORT < MODERATOR < SUPER_ADMIN ranking.
@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
@Roles(UserRole.ADMIN)
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  /// Confirms `request.user` is really an admin (and which tier) — used
  /// by the client right after login to decide whether to route into the
  /// admin console and which actions to show, rather than trusting a
  /// client-side guess. Exempted from MustChangePasswordGuard since the
  /// console needs this to render at all, even before that gate clears.
  @Get('me')
  @AllowMustChangePassword()
  me(@CurrentUser() user: AuthenticatedUser) {
    return { id: user.sub, email: user.email, role: user.role, adminLevel: user.adminLevel };
  }

  @Get('stats')
  stats() {
    return this.admin.stats();
  }

  @Get('activity-feed')
  activityFeed(@Query('limit') limit?: string) {
    return this.admin.activityFeed(limit ? Number(limit) : undefined);
  }

  // --- Admin management (SUPER_ADMIN only) --------------------------------

  @Get('admins')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  findAdmins() {
    return this.admin.findAdmins();
  }

  /// Backs the Admins nav badge — visible to MODERATOR+ same as the tab
  /// itself, not SUPER_ADMIN-only like [findAdmins] (this is just a count,
  /// nothing sensitive).
  @Get('admins/pending-count')
  @MinAdminLevel(AdminLevel.MODERATOR)
  async pendingAdminInvitesCount() {
    return { count: await this.admin.pendingAdminInvitesCount() };
  }

  @Post('admins/request')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  requestAdmin(@Body() dto: RequestAdminDto) {
    return this.admin.requestAdminOtp(dto);
  }

  @Post('admins/confirm')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  confirmAdmin(@Body() dto: ConfirmAdminDto) {
    return this.admin.confirmAdminOtp(dto);
  }

  @Patch('admins/:id/level')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  setAdminLevel(@CurrentUser() actingAdmin: AuthenticatedUser, @Param('id') id: string, @Body() dto: SetAdminLevelDto) {
    return this.admin.setAdminLevel(actingAdmin.sub, id, dto.level);
  }

  @Patch('admins/:id/two-factor')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  setAdminTwoFactor(@Param('id') id: string, @Body() dto: SetAdminTwoFactorDto) {
    return this.admin.setAdminTwoFactor(id, dto.enabled);
  }

  /// SUPPORT can't reach either of these — a locked-out admin needs a
  /// SUPER_ADMIN or MODERATOR to vouch for the reset.
  @Post('admins/:id/reset-password/request')
  @MinAdminLevel(AdminLevel.MODERATOR)
  requestAdminPasswordReset(@CurrentUser() actingAdmin: AuthenticatedUser, @Param('id') id: string) {
    return this.admin.requestAdminPasswordReset(actingAdmin.email, actingAdmin.sub, actingAdmin.adminLevel!, id);
  }

  @Post('admins/:id/reset-password/confirm')
  @MinAdminLevel(AdminLevel.MODERATOR)
  confirmAdminPasswordReset(
    @CurrentUser() actingAdmin: AuthenticatedUser,
    @Param('id') id: string,
    @Body() dto: ConfirmAdminResetDto,
    @Req() req: Request,
  ) {
    return this.admin.confirmAdminPasswordReset(actingAdmin.email, actingAdmin.sub, actingAdmin.adminLevel!, id, dto, req.ip);
  }

  @Delete('admins/:id')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  async removeAdmin(@CurrentUser() actingAdmin: AuthenticatedUser, @Param('id') id: string): Promise<void> {
    await this.admin.removeAdmin(actingAdmin.sub, id);
  }

  // --- Activity log ------------------------------------------------------

  @Get('activity-log')
  findActivityLog(@Query('page') page?: string, @Query('pageSize') pageSize?: string, @Query('type') type?: ActivityLogType) {
    return this.admin.findActivityLog(page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined, type);
  }

  /// `?type=ADMIN_LOGIN` (etc.) clears just that type, silently; omitted
  /// clears the whole log and records who did it — see
  /// AdminService.clearActivityLog.
  @Delete('activity-log')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  @HttpCode(HttpStatus.NO_CONTENT)
  async clearActivityLog(@CurrentUser() actingAdmin: AuthenticatedUser, @Query('type') type?: ActivityLogType): Promise<void> {
    await this.admin.clearActivityLog(actingAdmin.sub, type);
  }

  // --- Chat log ----------------------------------------------------------

  /// Every support thread from the last 30 days — badges, current handler,
  /// and the full transfer chain (who it was handed between, and how many
  /// times) — unlike the Support Queue/Inbox, this is read-only history
  /// across *every* admin's conversations, so it's restricted to
  /// SUPER_ADMIN. See ChatService.findChatLog.
  @Get('chat-log')
  @MinAdminLevel(AdminLevel.SUPER_ADMIN)
  findChatLog() {
    return this.admin.findChatLog();
  }

  // --- Users -----------------------------------------------------------

  @Get('users')
  findUsers(@Query() query: QueryUsersDto) {
    return this.admin.findUsers(query);
  }

  @Get('users/:id')
  findUserDetail(@Param('id') id: string) {
    return this.admin.findUserDetail(id);
  }

  /// Support's one new capability — edit a user's basic profile fields.
  /// Deliberately no `@MinAdminLevel` here: every admin tier (including
  /// SUPPORT) can call this. Does NOT loosen delete/moderate, which stay
  /// Moderator+ below.
  @Patch('users/:id')
  updateUser(@CurrentUser() actingAdmin: AuthenticatedUser, @Param('id') id: string, @Body() dto: UpdateUserDto) {
    return this.admin.updateUser(id, dto, actingAdmin.sub);
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

  /// Registered ahead of `vendors/:id` — Nest matches routes in
  /// registration order, so `:id` would otherwise swallow this literal path.
  @Get('vendors/pending-count')
  async pendingVendorsCount() {
    return { count: await this.admin.pendingVendorsCount() };
  }

  @Get('vendors/:id')
  findVendorDetail(@Param('id') id: string) {
    return this.admin.findVendorDetail(id);
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
  suspendVendor(@Param('id') id: string, @Body() dto: DelistReasonDto) {
    return this.admin.suspendVendor(id, dto.reason);
  }

  @Patch('vendors/:id/unsuspend')
  @MinAdminLevel(AdminLevel.MODERATOR)
  unsuspendVendor(@Param('id') id: string, @Body() dto: DelistReasonDto) {
    return this.admin.unsuspendVendor(id, dto.reason);
  }

  // --- Properties --------------------------------------------------------

  @Get('properties')
  findProperties(@Query('page') page?: string, @Query('pageSize') pageSize?: string, @Query('search') search?: string) {
    return this.admin.findProperties(page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined, search);
  }

  @Get('properties/:id')
  findPropertyDetail(@Param('id') id: string) {
    return this.admin.findPropertyDetail(id);
  }

  @Patch('properties/:id/relist')
  @MinAdminLevel(AdminLevel.MODERATOR)
  async relistProperty(@Param('id') id: string): Promise<void> {
    await this.admin.relistProperty(id);
  }

  @Delete('properties/:id')
  @MinAdminLevel(AdminLevel.MODERATOR)
  async removeProperty(@Param('id') id: string, @Body() dto: DelistReasonDto): Promise<void> {
    await this.admin.removeProperty(id, dto.reason);
  }

  // --- Marketplace ---------------------------------------------------------

  @Get('marketplace/products')
  findProducts(@Query('page') page?: string, @Query('pageSize') pageSize?: string, @Query('search') search?: string) {
    return this.admin.findProducts(page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined, search);
  }

  @Delete('marketplace/products/:id')
  @MinAdminLevel(AdminLevel.MODERATOR)
  async removeProduct(@Param('id') id: string, @Body() dto: DelistReasonDto): Promise<void> {
    await this.admin.removeProduct(id, dto.reason);
  }

  @Get('marketplace/orders')
  findOrders(@Query('page') page?: string, @Query('pageSize') pageSize?: string) {
    return this.admin.findOrders(page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined);
  }

  @Get('marketplace/orders/:id')
  findOrderDetail(@Param('id') id: string) {
    return this.admin.findOrderDetail(id);
  }

  // --- Messages badge ------------------------------------------------------

  /// Backs the Messages nav badge — see AdminService.messagesAttentionCount.
  @Get('messages/attention-count')
  async messagesAttentionCount(@CurrentUser() actingAdmin: AuthenticatedUser) {
    return { count: await this.admin.messagesAttentionCount(actingAdmin.sub) };
  }
}
