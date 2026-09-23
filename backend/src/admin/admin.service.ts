import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { NotificationType, Prisma } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { AuthService } from '../auth/auth.service';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { CreateAdminDto } from './dto/create-admin.dto';
import { QueryUsersDto } from './dto/query-users.dto';
import { QueryVendorsDto } from './dto/query-vendors.dto';
import { RejectVendorDto } from './dto/reject-vendor.dto';

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auth: AuthService,
    private readonly mail: MailService,
    private readonly notifications: NotificationsService,
  ) {}

  // --- Bootstrap / admin accounts ---------------------------------------

  /// The only way an admin account is ever created — either this (once,
  /// when no admin exists yet, gated by ADMIN_BOOTSTRAP_SECRET at the
  /// controller) or [createAdmin] (by an existing admin, from the
  /// console). Signup/Google auth both explicitly refuse role: ADMIN.
  async bootstrapFirstAdmin(dto: CreateAdminDto) {
    const existingAdmin = await this.prisma.user.findFirst({ where: { role: 'ADMIN' } });
    if (existingAdmin) {
      throw new ForbiddenException('An admin account already exists — sign in and create additional admins from the console');
    }
    return this.createAdminAccount(dto);
  }

  async createAdmin(dto: CreateAdminDto) {
    return this.createAdminAccount(dto);
  }

  private async createAdminAccount(dto: CreateAdminDto) {
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw new ConflictException('An account with this email already exists');
    const passwordHash = await bcrypt.hash(dto.password, 10);
    return this.prisma.user.create({
      data: {
        email: dto.email,
        passwordHash,
        role: 'ADMIN',
        fullName: dto.fullName,
        emailVerifiedAt: new Date(),
      },
      select: { id: true, email: true, fullName: true, role: true, createdAt: true },
    });
  }

  // --- Platform stats ----------------------------------------------------

  async stats() {
    const [
      totalUsers,
      tenants,
      landlords,
      vendors,
      pendingVendors,
      properties,
      bookings,
      marketplaceOrders,
      deactivatedAccounts,
    ] = await Promise.all([
      this.prisma.user.count(),
      this.prisma.user.count({ where: { role: 'TENANT' } }),
      this.prisma.user.count({ where: { role: 'LANDLORD' } }),
      this.prisma.user.count({ where: { role: 'VENDOR' } }),
      this.prisma.vendorProfile.count({ where: { status: 'PENDING' } }),
      this.prisma.property.count(),
      this.prisma.booking.count(),
      this.prisma.marketplaceOrder.count(),
      this.prisma.user.count({ where: { deactivatedAt: { not: null } } }),
    ]);
    return { totalUsers, tenants, landlords, vendors, pendingVendors, properties, bookings, marketplaceOrders, deactivatedAccounts };
  }

  // --- Users ---------------------------------------------------------------

  async findUsers(query: QueryUsersDto) {
    const where: Prisma.UserWhereInput = {
      role: query.role,
      ...(query.search
        ? {
            OR: [
              { email: { contains: query.search, mode: 'insensitive' } },
              { fullName: { contains: query.search, mode: 'insensitive' } },
            ],
          }
        : {}),
    };
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const [items, total] = await Promise.all([
      this.prisma.user.findMany({
        where,
        select: {
          id: true,
          email: true,
          fullName: true,
          role: true,
          phoneNumber: true,
          emailVerifiedAt: true,
          deactivatedAt: true,
          createdAt: true,
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.user.count({ where }),
    ]);
    return { items, total, page, pageSize };
  }

  /// Admin-triggered — unlike AuthService.deactivate (self-service), this
  /// doesn't need the account's own session and skips straight to the
  /// same effect: listings hidden, every session signed out, "your
  /// account has been deactivated" email sent.
  async deactivateUser(id: string): Promise<void> {
    await this.requireUser(id);
    await this.auth.deactivate(id);
  }

  async deleteUser(id: string): Promise<void> {
    await this.requireUser(id);
    await this.auth.deleteAccount(id);
  }

  private async requireUser(id: string) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) throw new NotFoundException('User not found');
    if (user.role === 'ADMIN') throw new ForbiddenException("Can't moderate another admin account from here");
    return user;
  }

  // --- Vendors ---------------------------------------------------------

  async findVendors(query: QueryVendorsDto) {
    const where: Prisma.VendorProfileWhereInput = {
      status: query.status,
      ...(query.search ? { businessName: { contains: query.search, mode: 'insensitive' } } : {}),
    };
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const [items, total] = await Promise.all([
      this.prisma.vendorProfile.findMany({
        where,
        include: { user: { select: { id: true, email: true, fullName: true, phoneNumber: true } } },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.vendorProfile.count({ where }),
    ]);
    return { items, total, page, pageSize };
  }

  async approveVendor(id: string) {
    const vendor = await this.requireVendor(id);
    const updated = await this.prisma.vendorProfile.update({
      where: { id },
      data: { status: 'APPROVED', rejectionReason: null },
    });
    await this.notifications.create(
      vendor.userId,
      NotificationType.VENDOR_APPROVED,
      'Your shop is approved!',
      `Great news — ${vendor.businessName} has been approved. Your products are now visible in the Marketplace.`,
    );
    await this.mail.send(
      vendor.user.email,
      'Your HomeServant shop has been approved',
      `<p>Great news — <strong>${vendor.businessName}</strong> has been approved.</p><p>Your products are now visible to shoppers in the Marketplace.</p>`,
      `Great news — ${vendor.businessName} has been approved. Your products are now visible to shoppers in the Marketplace.`,
    );
    return updated;
  }

  async rejectVendor(id: string, dto: RejectVendorDto) {
    const vendor = await this.requireVendor(id);
    const updated = await this.prisma.vendorProfile.update({
      where: { id },
      data: { status: 'REJECTED', rejectionReason: dto.reason ?? null },
    });
    await this.notifications.create(
      vendor.userId,
      NotificationType.VENDOR_REJECTED,
      'Your vendor application',
      `Your application for ${vendor.businessName} wasn't approved${dto.reason ? `: ${dto.reason}` : '.'} You can update your shop details for another review.`,
    );
    await this.mail.send(
      vendor.user.email,
      'Your HomeServant vendor application',
      `<p>Thanks for applying to sell on HomeServant. After review, <strong>${vendor.businessName}</strong> hasn't been approved${
        dto.reason ? `: ${dto.reason}` : '.'
      }</p><p>You can update your shop details and this will be reviewed again.</p>`,
      `Thanks for applying to sell on HomeServant. After review, ${vendor.businessName} hasn't been approved${
        dto.reason ? `: ${dto.reason}` : '.'
      }\n\nYou can update your shop details and this will be reviewed again.`,
    );
    return updated;
  }

  async suspendVendor(id: string) {
    await this.requireVendor(id);
    return this.prisma.vendorProfile.update({ where: { id }, data: { isActive: false } });
  }

  async unsuspendVendor(id: string) {
    await this.requireVendor(id);
    return this.prisma.vendorProfile.update({ where: { id }, data: { isActive: true } });
  }

  private async requireVendor(id: string) {
    const vendor = await this.prisma.vendorProfile.findUnique({ where: { id }, include: { user: { select: { email: true } } } });
    if (!vendor) throw new NotFoundException('Vendor not found');
    return vendor;
  }

  // --- Properties --------------------------------------------------------

  async findProperties(page = 1, pageSize = 20, search?: string) {
    const where: Prisma.PropertyWhereInput = search
      ? { OR: [{ title: { contains: search, mode: 'insensitive' } }, { location: { contains: search, mode: 'insensitive' } }] }
      : {};
    const [items, total] = await Promise.all([
      this.prisma.property.findMany({
        where,
        include: { landlord: { select: { id: true, fullName: true, email: true } } },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.property.count({ where }),
    ]);
    return { items, total, page, pageSize };
  }

  async removeProperty(id: string): Promise<void> {
    const property = await this.prisma.property.findUnique({ where: { id } });
    if (!property) throw new NotFoundException('Property not found');
    await this.prisma.property.delete({ where: { id } });
  }

  // --- Marketplace ---------------------------------------------------------

  async findProducts(page = 1, pageSize = 20, search?: string) {
    const where: Prisma.ProductWhereInput = search ? { name: { contains: search, mode: 'insensitive' } } : {};
    const [items, total] = await Promise.all([
      this.prisma.product.findMany({
        where,
        include: { vendor: { select: { id: true, businessName: true } } },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.product.count({ where }),
    ]);
    return { items, total, page, pageSize };
  }

  async removeProduct(id: string): Promise<void> {
    const product = await this.prisma.product.findUnique({ where: { id } });
    if (!product) throw new NotFoundException('Product not found');
    await this.prisma.product.update({ where: { id }, data: { isAvailable: false } });
  }

  async findOrders(page = 1, pageSize = 20) {
    const [items, total] = await Promise.all([
      this.prisma.marketplaceOrder.findMany({
        include: {
          buyer: { select: { id: true, fullName: true, email: true } },
          items: { select: { id: true, productName: true, quantity: true, unitPrice: true, status: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.marketplaceOrder.count(),
    ]);
    return { items, total, page, pageSize };
  }
}
