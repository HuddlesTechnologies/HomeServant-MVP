import { Body, Controller, Delete, Get, Headers, NotFoundException, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { AdminService } from './admin.service';
import { CreateAdminDto } from './dto/create-admin.dto';
import { QueryUsersDto } from './dto/query-users.dto';
import { QueryVendorsDto } from './dto/query-vendors.dto';
import { RejectVendorDto } from './dto/reject-vendor.dto';

@Controller('admin')
export class AdminController {
  constructor(
    private readonly admin: AdminService,
    private readonly config: ConfigService,
  ) {}

  /// The only unauthenticated route in this controller — creates the
  /// very first admin account, gated by a long random secret set as the
  /// ADMIN_BOOTSTRAP_SECRET env var (never committed, shared out of band
  /// with whoever is standing the platform up). Refuses once any admin
  /// already exists — see AdminService.bootstrapFirstAdmin.
  @Post('bootstrap')
  bootstrap(@Headers('x-admin-bootstrap-secret') secret: string | undefined, @Body() dto: CreateAdminDto) {
    if (!secret || secret !== this.config.getOrThrow<string>('ADMIN_BOOTSTRAP_SECRET')) {
      // Same response whether the secret is missing or wrong — no
      // "close, but no" hint.
      throw new NotFoundException();
    }
    return this.admin.bootstrapFirstAdmin(dto);
  }

  @Post('admins')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  createAdmin(@Body() dto: CreateAdminDto) {
    return this.admin.createAdmin(dto);
  }

  @Get('stats')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  stats() {
    return this.admin.stats();
  }

  @Get('users')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  findUsers(@Query() query: QueryUsersDto) {
    return this.admin.findUsers(query);
  }

  @Patch('users/:id/deactivate')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  async deactivateUser(@Param('id') id: string): Promise<void> {
    await this.admin.deactivateUser(id);
  }

  @Delete('users/:id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  async deleteUser(@Param('id') id: string): Promise<void> {
    await this.admin.deleteUser(id);
  }

  @Get('vendors')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  findVendors(@Query() query: QueryVendorsDto) {
    return this.admin.findVendors(query);
  }

  @Patch('vendors/:id/approve')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  approveVendor(@Param('id') id: string) {
    return this.admin.approveVendor(id);
  }

  @Patch('vendors/:id/reject')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  rejectVendor(@Param('id') id: string, @Body() dto: RejectVendorDto) {
    return this.admin.rejectVendor(id, dto);
  }

  @Patch('vendors/:id/suspend')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  suspendVendor(@Param('id') id: string) {
    return this.admin.suspendVendor(id);
  }

  @Patch('vendors/:id/unsuspend')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  unsuspendVendor(@Param('id') id: string) {
    return this.admin.unsuspendVendor(id);
  }

  @Get('properties')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  findProperties(@Query('page') page?: string, @Query('pageSize') pageSize?: string, @Query('search') search?: string) {
    return this.admin.findProperties(page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined, search);
  }

  @Delete('properties/:id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  async removeProperty(@Param('id') id: string): Promise<void> {
    await this.admin.removeProperty(id);
  }

  @Get('marketplace/products')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  findProducts(@Query('page') page?: string, @Query('pageSize') pageSize?: string, @Query('search') search?: string) {
    return this.admin.findProducts(page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined, search);
  }

  @Delete('marketplace/products/:id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  async removeProduct(@Param('id') id: string): Promise<void> {
    await this.admin.removeProduct(id);
  }

  @Get('marketplace/orders')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  findOrders(@Query('page') page?: string, @Query('pageSize') pageSize?: string) {
    return this.admin.findOrders(page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined);
  }

  /// Confirms `request.user` is really an admin — used by the client
  /// right after login to decide whether to route into the admin
  /// console (role is already in the JWT, but this is a real
  /// authorization check rather than trusting the client's own claim).
  @Get('me')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.ADMIN)
  me(@CurrentUser() user: AuthenticatedUser) {
    return { id: user.sub, email: user.email, role: user.role };
  }
}
