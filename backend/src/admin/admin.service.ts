import { randomBytes } from 'crypto';
import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { AdminLevel, ActivityLogType, NotificationType, OtpPurpose, Prisma } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { ActivityLogService } from '../activity-log/activity-log.service';
import { AuthService } from '../auth/auth.service';
import { ChatGateway } from '../chat/chat.gateway';
import { ChatService } from '../chat/chat.service';
import { PresenceService } from '../chat/presence.service';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { OtpService } from '../otp/otp.service';
import { PrismaService } from '../prisma/prisma.service';
import { ConfirmAdminDto } from './dto/confirm-admin.dto';
import { ConfirmAdminResetDto } from './dto/confirm-admin-reset.dto';
import { CreateAdminDto } from './dto/create-admin.dto';
import { QueryUsersDto } from './dto/query-users.dto';
import { QueryVendorsDto } from './dto/query-vendors.dto';
import { RejectVendorDto } from './dto/reject-vendor.dto';
import { RequestAdminDto } from './dto/request-admin.dto';
import { UpdateUserDto } from './dto/update-user.dto';

/// Mirrors AdminLevelGuard's RANK map — declaration order in the Prisma
/// schema is the rank (SUPPORT < MODERATOR < SUPER_ADMIN). Used here (not
/// just server-authorized by `@MinAdminLevel`) because
/// requestAdminPasswordReset needs to compare the *acting* admin against
/// the *target*, not just check a fixed minimum.
const RANK: Record<AdminLevel, number> = {
  SUPPORT: 0,
  MODERATOR: 1,
  SUPER_ADMIN: 2,
};

const adminSelect = {
  id: true,
  email: true,
  fullName: true,
  role: true,
  adminLevel: true,
  twoFactorEnabled: true,
  mustChangePassword: true,
  createdAt: true,
} as const;

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auth: AuthService,
    private readonly mail: MailService,
    private readonly notifications: NotificationsService,
    private readonly otp: OtpService,
    private readonly activityLog: ActivityLogService,
    private readonly presence: PresenceService,
    private readonly chat: ChatService,
    private readonly chatGateway: ChatGateway,
  ) {}

  // --- Bootstrap / admin accounts ---------------------------------------

  /// The only way the very first admin account is ever created — after
  /// this, [requestAdminOtp]/[confirmAdminOtp] (a SUPER_ADMIN acting from
  /// the console) is the only other way one can exist; signup/Google auth
  /// both explicitly refuse role: ADMIN. Always SUPER_ADMIN — someone has
  /// to be able to manage the rest.
  async bootstrapFirstAdmin(dto: CreateAdminDto) {
    const existingAdmin = await this.prisma.user.findFirst({ where: { role: 'ADMIN' } });
    if (existingAdmin) {
      throw new ForbiddenException('An admin account already exists — sign in and create additional admins from the console');
    }
    return this.createAdminAccount(dto, AdminLevel.SUPER_ADMIN);
  }

  private async createAdminAccount(dto: CreateAdminDto, level: AdminLevel) {
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw new ConflictException('An account with this email already exists');
    const passwordHash = await bcrypt.hash(dto.password, 10);
    return this.prisma.user.create({
      data: {
        email: dto.email,
        passwordHash,
        role: 'ADMIN',
        adminLevel: level,
        fullName: dto.fullName,
        emailVerifiedAt: new Date(),
      },
      select: adminSelect,
    });
  }

  /// Step 1 of adding an admin from the console: generates a one-time
  /// temporary password and an OTP, emails both to [dto.email] in a
  /// single message, and stashes [dto.fullName]/[dto.level]/the temp
  /// password's hash in PendingAdmin until [confirmAdminOtp] is called
  /// with that code — no User row exists for this email yet, so re-
  /// requesting before confirming just overwrites the pending invite.
  async requestAdminOtp(dto: RequestAdminDto): Promise<{ message: string }> {
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw new ConflictException('An account with this email already exists');

    const tempPassword = randomBytes(9).toString('base64url'); // 12 chars
    const tempPasswordHash = await bcrypt.hash(tempPassword, 10);
    const code = await this.otp.generate(dto.email, OtpPurpose.ADMIN_CREATE);

    await this.prisma.pendingAdmin.upsert({
      where: { email: dto.email },
      create: { email: dto.email, fullName: dto.fullName, level: dto.level, tempPasswordHash },
      update: { fullName: dto.fullName, level: dto.level, tempPasswordHash },
    });

    await this.mail.send(
      dto.email,
      'Your HomeServant admin invite',
      `<p>You've been invited to the HomeServant admin console as <strong>${dto.level}</strong>.</p>` +
        `<p>Confirmation code (give this to whoever is setting up your account):</p>` +
        `<p style="font-size:28px;font-weight:700;letter-spacing:4px;">${code}</p>` +
        `<p>Your one-time temporary password (sign in with this, then set your own — it only works until you do):</p>` +
        `<p style="font-size:20px;font-weight:700;">${tempPassword}</p>` +
        `<p>The code expires in 10 minutes.</p>`,
      `You've been invited to the HomeServant admin console as ${dto.level}.\n\n` +
        `Confirmation code: ${code}\n` +
        `Temporary password: ${tempPassword}\n\n` +
        `Sign in with the temporary password, then set your own — it only works until you do. The code expires in 10 minutes.`,
    );

    // Keeps the Admins nav badge (AdminShell._pendingAdminInvitesCount)
    // live across every other admin's already-open console.
    this.chatGateway.broadcastToAdmins('admin:badges-changed', {});
    return { message: `Code sent to ${dto.email}` };
  }

  /// Step 2: the code from that same email, entered back in the console,
  /// actually creates the admin account with the temp password from step
  /// 1 — see requestAdminOtp's doc comment for why both live there.
  async confirmAdminOtp(dto: ConfirmAdminDto) {
    await this.otp.verify(dto.email, OtpPurpose.ADMIN_CREATE, dto.code);
    const pending = await this.prisma.pendingAdmin.findUnique({ where: { email: dto.email } });
    if (!pending) throw new BadRequestException('No pending invite for this email — request a new code');

    const admin = await this.prisma.user.create({
      data: {
        email: pending.email,
        passwordHash: pending.tempPasswordHash,
        role: 'ADMIN',
        adminLevel: pending.level,
        fullName: pending.fullName,
        emailVerifiedAt: new Date(),
        mustChangePassword: true,
      },
      select: adminSelect,
    });
    await this.prisma.pendingAdmin.delete({ where: { email: dto.email } });
    this.chatGateway.broadcastToAdmins('admin:badges-changed', {});
    return admin;
  }

  /// SUPER_ADMIN toggling 2FA on another admin's behalf — distinct from
  /// that admin turning their own on/off via `PATCH /users/me` (Settings),
  /// which needs no special permission since it's just their own account.
  async setAdminTwoFactor(targetId: string, enabled: boolean) {
    await this.requireAdmin(targetId);
    return this.prisma.user.update({ where: { id: targetId }, data: { twoFactorEnabled: enabled }, select: adminSelect });
  }

  /// A locked-out admin has no self-service reset (AuthService.forgotPassword
  /// explicitly refuses ADMIN accounts) — only a SUPER_ADMIN/MODERATOR can
  /// get them back in, and only after re-verifying *their own* identity
  /// first: this sends a step-up OTP to the acting admin's own email
  /// (never the target's), so resetting someone else's password can't be
  /// done from an unlocked/unattended console session. [confirmAdminPasswordReset]
  /// is the second half, gated on that code.
  ///
  /// [actingAdminLevel] must outrank (or match, for SUPER_ADMIN) the
  /// target — otherwise a MODERATOR could force-reset a SUPER_ADMIN's
  /// password (and sign every one of their sessions out) at will, which
  /// is a denial-of-service against a higher-privileged account even
  /// though the MODERATOR never actually learns the new password (that's
  /// emailed only to the target).
  async requestAdminPasswordReset(
    actingAdminEmail: string,
    actingAdminId: string,
    actingAdminLevel: AdminLevel,
    targetId: string,
  ): Promise<{ message: string }> {
    const target = await this.requireAdmin(targetId);
    if (RANK[actingAdminLevel] < RANK[target.adminLevel!]) {
      throw new ForbiddenException("Can't reset the password of an admin ranked above you");
    }
    await this.otp.issue(actingAdminEmail, OtpPurpose.ADMIN_RESET_CONFIRM, actingAdminId);
    return { message: `Confirmation code sent to ${actingAdminEmail}` };
  }

  async confirmAdminPasswordReset(
    actingAdminEmail: string,
    actingAdminId: string,
    actingAdminLevel: AdminLevel,
    targetId: string,
    dto: ConfirmAdminResetDto,
    ip?: string,
  ): Promise<{ message: string }> {
    await this.otp.verify(actingAdminEmail, OtpPurpose.ADMIN_RESET_CONFIRM, dto.code);
    const target = await this.requireAdmin(targetId);
    // Re-checked here too (not just in the request step) in case the
    // target's level changed in between.
    if (RANK[actingAdminLevel] < RANK[target.adminLevel!]) {
      throw new ForbiddenException("Can't reset the password of an admin ranked above you");
    }

    const tempPassword = randomBytes(9).toString('base64url');
    const passwordHash = await bcrypt.hash(tempPassword, 10);
    await this.prisma.user.update({ where: { id: targetId }, data: { passwordHash, mustChangePassword: true } });
    // Matches AuthService.changePassword/resetPassword — a credential
    // reset should sign every session for this account out, not just
    // hand out a new password alongside still-valid old ones.
    await this.prisma.refreshToken.updateMany({ where: { userId: targetId, revokedAt: null }, data: { revokedAt: new Date() } });
    await this.activityLog.log(ActivityLogType.ADMIN_PASSWORD_RESET, { actorId: actingAdminId, targetId, ip });

    await this.mail.send(
      target.email,
      'Your HomeServant admin password was reset',
      `<p>A super admin or moderator reset your admin password.</p>` +
        `<p>Your new one-time temporary password (sign in with this, then set your own — it only works until you do):</p>` +
        `<p style="font-size:20px;font-weight:700;">${tempPassword}</p>`,
      `A super admin or moderator reset your admin password.\n\nTemporary password: ${tempPassword}\n\nSign in with this, then set your own — it only works until you do.`,
    );

    return { message: `Password reset — a new temporary password was emailed to ${target.email}` };
  }

  findAdmins() {
    return this.prisma.user.findMany({ where: { role: 'ADMIN' }, select: adminSelect, orderBy: { createdAt: 'asc' } });
  }

  /// [actingAdminId] is only used to block a SUPER_ADMIN demoting
  /// themself out of being the last one — anyone else moving anyone else
  /// between tiers is otherwise unrestricted (a SUPER_ADMIN can even
  /// promote another admin to SUPER_ADMIN, or demote one that isn't the
  /// last).
  async setAdminLevel(actingAdminId: string, targetId: string, level: AdminLevel) {
    const target = await this.requireAdmin(targetId);
    if (target.adminLevel === AdminLevel.SUPER_ADMIN && level !== AdminLevel.SUPER_ADMIN) {
      await this.assertNotLastSuperAdmin(targetId);
    }
    return this.prisma.user.update({ where: { id: targetId }, data: { adminLevel: level }, select: adminSelect });
  }

  async removeAdmin(actingAdminId: string, targetId: string): Promise<void> {
    if (actingAdminId === targetId) {
      throw new ForbiddenException("Can't remove your own admin account from the console");
    }
    const target = await this.requireAdmin(targetId);
    if (target.adminLevel === AdminLevel.SUPER_ADMIN) {
      await this.assertNotLastSuperAdmin(targetId);
    }
    await this.auth.deleteAccount(targetId);
  }

  private async requireAdmin(id: string) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user || user.role !== 'ADMIN') throw new NotFoundException('Admin not found');
    return user;
  }

  /// Guards both [setAdminLevel] (demoting) and [removeAdmin] (deleting)
  /// against ever leaving the platform with zero SUPER_ADMINs able to
  /// manage the rest of the console.
  private async assertNotLastSuperAdmin(excludingId: string): Promise<void> {
    const remaining = await this.prisma.user.count({
      where: { role: 'ADMIN', adminLevel: AdminLevel.SUPER_ADMIN, id: { not: excludingId } },
    });
    if (remaining === 0) {
      throw new ForbiddenException("Can't demote/remove the last super admin — promote another admin first");
    }
  }

  // --- Activity log --------------------------------------------------------

  findActivityLog(page?: number, pageSize?: number, type?: ActivityLogType) {
    return this.activityLog.findAll(page, pageSize, type);
  }

  /// SUPER_ADMIN only (see AdminController) — every other admin can only
  /// view the log, never wipe it. Clearing a single [type] leaves no trace
  /// (it's a routine housekeeping action, and logging it would just be
  /// noise in that same type's history). Clearing the *whole* log — every
  /// type, [type] omitted — is different: the log would otherwise go from
  /// "full history" to "totally empty" with nothing showing who did that,
  /// which is exactly the kind of admin action this log exists to catch.
  /// So that case writes one ADMIN_ACTIVITY_LOG_CLEARED row right after the
  /// wipe, naming the acting super admin.
  async clearActivityLog(actingAdminId: string, type?: ActivityLogType): Promise<void> {
    await this.activityLog.clear(type);
    if (!type) {
      await this.activityLog.log(ActivityLogType.ADMIN_ACTIVITY_LOG_CLEARED, { actorId: actingAdminId });
    }
  }

  // --- Chat log ------------------------------------------------------------

  /// SUPER_ADMIN only (see AdminController) — delegates straight to
  /// ChatService, which already owns every Thread/Message/ThreadTransferLog
  /// query; this stays a one-line pass-through the same way
  /// [findActivityLog] delegates to ActivityLogService.
  findChatLog() {
    return this.chat.findChatLog();
  }

  // --- Platform stats ----------------------------------------------------

  async stats() {
    const [
      totalUsers,
      tenants,
      landlords,
      vendors,
      pendingVendors,
      activeVendors,
      properties,
      bookings,
      marketplaceOrders,
      deactivatedAccounts,
    ] = await Promise.all([
      this.prisma.user.count(),
      this.prisma.user.count({ where: { role: 'TENANT' } }),
      this.prisma.user.count({ where: { role: 'LANDLORD' } }),
      // A vendor keeps their original User.role (typically TENANT) — a
      // VendorProfile row, not User.role, is what makes someone a vendor.
      // See AdminService.findUsers' role=VENDOR handling below for the
      // same distinction.
      this.prisma.vendorProfile.count(),
      this.prisma.vendorProfile.count({ where: { status: 'PENDING' } }),
      // A shop is actually visible/trading only when all three hold — see
      // VendorProfile.isActive's doc comment in schema.prisma.
      this.prisma.vendorProfile.count({ where: { isActive: true, suspendedAt: null, status: 'APPROVED' } }),
      this.prisma.property.count(),
      this.prisma.booking.count(),
      this.prisma.marketplaceOrder.count(),
      this.prisma.user.count({ where: { deactivatedAt: { not: null } } }),
    ]);
    return {
      totalUsers,
      tenants,
      landlords,
      vendors,
      pendingVendors,
      activeVendors,
      properties,
      bookings,
      marketplaceOrders,
      deactivatedAccounts,
    };
  }

  pendingVendorsCount(): Promise<number> {
    return this.prisma.vendorProfile.count({ where: { status: 'PENDING' } });
  }

  // --- Activity feed -------------------------------------------------------

  /// "What's happening on the platform right now" for the dashboard —
  /// distinct from [findActivityLog], which only ever records admin
  /// console actions (login/password events) and nothing a regular user
  /// does. Rather than adding a new write path at every place a signup/
  /// listing/application/order/report is created, this just reads the
  /// most recent rows each of those tables already has (they all have
  /// their own `createdAt`) and merges them by time — real business
  /// activity, no schema change or extra instrumentation needed.
  async activityFeed(limit = 20) {
    const perTypeTake = Math.min(Math.max(limit, 1), 20);
    const [signups, properties, vendorApplications, orders, reports] = await Promise.all([
      this.prisma.user.findMany({
        where: { role: { not: 'ADMIN' } },
        select: { id: true, email: true, fullName: true, role: true, createdAt: true },
        orderBy: { createdAt: 'desc' },
        take: perTypeTake,
      }),
      this.prisma.property.findMany({
        select: { id: true, title: true, createdAt: true, landlord: { select: { id: true, email: true, fullName: true } } },
        orderBy: { createdAt: 'desc' },
        take: perTypeTake,
      }),
      this.prisma.vendorProfile.findMany({
        select: {
          id: true,
          businessName: true,
          status: true,
          createdAt: true,
          user: { select: { id: true, email: true, fullName: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: perTypeTake,
      }),
      this.prisma.marketplaceOrder.findMany({
        select: {
          id: true,
          createdAt: true,
          buyer: { select: { id: true, email: true, fullName: true } },
          _count: { select: { items: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: perTypeTake,
      }),
      this.prisma.report.findMany({
        select: {
          id: true,
          reason: true,
          targetType: true,
          createdAt: true,
          reporter: { select: { id: true, email: true, fullName: true } },
        },
        orderBy: { createdAt: 'desc' },
        take: perTypeTake,
      }),
    ]);

    type FeedItem = {
      type: 'USER_SIGNUP' | 'PROPERTY_LISTED' | 'VENDOR_APPLICATION' | 'MARKETPLACE_ORDER' | 'REPORT_FILED';
      createdAt: Date;
      actor: { id: string; email: string; fullName: string | null } | null;
      /// The id of the thing tapping this row should open — a user id for
      /// a signup (AdminUserDetailScreen), property id for a listing
      /// (AdminPropertyDetailScreen), vendor-profile id for an application
      /// (AdminVendorDetailScreen), order id (AdminOrderDetailScreen), or
      /// report id (AdminReportDetailScreen). See admin_dashboard_tab.dart.
      entityId: string;
      role?: string;
      propertyTitle?: string;
      businessName?: string;
      vendorStatus?: string;
      itemCount?: number;
      reportReason?: string;
      reportTargetType?: string;
    };

    const items: FeedItem[] = [
      ...signups.map((u) => ({ type: 'USER_SIGNUP' as const, createdAt: u.createdAt, actor: u, entityId: u.id, role: u.role })),
      ...properties.map((p) => ({
        type: 'PROPERTY_LISTED' as const,
        createdAt: p.createdAt,
        actor: p.landlord,
        entityId: p.id,
        propertyTitle: p.title,
      })),
      ...vendorApplications.map((v) => ({
        type: 'VENDOR_APPLICATION' as const,
        createdAt: v.createdAt,
        actor: v.user,
        entityId: v.id,
        businessName: v.businessName,
        vendorStatus: v.status,
      })),
      ...orders.map((o) => ({
        type: 'MARKETPLACE_ORDER' as const,
        createdAt: o.createdAt,
        actor: o.buyer,
        entityId: o.id,
        itemCount: o._count.items,
      })),
      ...reports.map((r) => ({
        type: 'REPORT_FILED' as const,
        createdAt: r.createdAt,
        actor: r.reporter,
        entityId: r.id,
        reportReason: r.reason,
        reportTargetType: r.targetType,
      })),
    ];

    return items.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime()).slice(0, limit);
  }

  // --- Users ---------------------------------------------------------------

  async findUsers(query: QueryUsersDto) {
    const where: Prisma.UserWhereInput = {
      // A vendor keeps their original role (TENANT, in practice) — nothing
      // ever sets User.role = 'VENDOR', so that value never actually
      // matches by itself. "Vendor" here means "has a VendorProfile".
      ...(query.role === 'VENDOR' ? { vendorProfile: { isNot: null } } : { role: query.role }),
      ...(query.deactivatedOnly ? { deactivatedAt: { not: null } } : {}),
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
          profilePhotoUrl: true,
          emailVerifiedAt: true,
          deactivatedAt: true,
          createdAt: true,
          // Lets the console badge a non-vendor role (typically TENANT)
          // that's *also* running a shop — see the role=='VENDOR' filter
          // above for why VendorProfile, not User.role, is the source of
          // truth for "is this person a vendor".
          vendorProfile: { select: { id: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.user.count({ where }),
    ]);
    return { items, total, page, pageSize };
  }

  /// Every field on the account (minus [passwordHash]) plus enough of its
  /// relations to be useful at a glance: the existing `_count` summary is
  /// kept as-is, and alongside it the real lists an admin actually wants
  /// to page through without leaving this screen — a landlord's listings,
  /// a tenant's rental history, a buyer's marketplace order history (with
  /// each item's vendor). Viewable by any admin tier; only mutating a user
  /// is tier-gated.
  async findUserDetail(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      include: {
        vendorProfile: { select: { id: true, businessName: true, status: true, isActive: true } },
        _count: { select: { properties: true, bookings: true, marketplaceOrders: true, favorites: true, reviews: true } },
        properties: {
          select: { id: true, listingNumber: true, title: true, price: true, priceUnit: true, isOccupied: true, createdAt: true },
          orderBy: { createdAt: 'desc' },
        },
        bookings: {
          select: {
            id: true,
            propertyId: true,
            status: true,
            requestedDate: true,
            createdAt: true,
            property: { select: { title: true, price: true, priceUnit: true } },
          },
          orderBy: { createdAt: 'desc' },
        },
        marketplaceOrders: {
          select: {
            id: true,
            createdAt: true,
            items: {
              select: {
                id: true,
                productName: true,
                unitPrice: true,
                quantity: true,
                status: true,
                vendorId: true,
                vendor: { select: { businessName: true } },
              },
            },
          },
          orderBy: { createdAt: 'desc' },
        },
      },
    });
    if (!user) throw new NotFoundException('User not found');
    const { passwordHash, properties, bookings, marketplaceOrders, ...rest } = user;
    return {
      ...rest,
      isOnline: this.presence.isOnline(user.id),
      properties: user.role === 'LANDLORD' ? properties : [],
      bookings: bookings.map((b) => ({
        id: b.id,
        propertyId: b.propertyId,
        propertyTitle: b.property.title,
        price: b.property.price,
        priceUnit: b.property.priceUnit,
        status: b.status,
        requestedDate: b.requestedDate,
        createdAt: b.createdAt,
      })),
      marketplaceOrders: marketplaceOrders.map((o) => ({
        id: o.id,
        createdAt: o.createdAt,
        items: o.items.map((i) => ({
          id: i.id,
          productName: i.productName,
          unitPrice: i.unitPrice,
          quantity: i.quantity,
          status: i.status,
          vendorId: i.vendorId,
          vendorBusinessName: i.vendor.businessName,
        })),
      })),
    };
  }

  /// Support's one new capability: edit a user's basic profile fields.
  /// Deliberately not gated behind `@MinAdminLevel` (see AdminController) —
  /// every tier can view a user's detail already, and per the ruling this
  /// is a new *editing* power for the lowest tier, not a loosening of the
  /// existing delete/moderate gates. Logged like every other admin action
  /// for auditability, same as ADMIN_PASSWORD_RESET.
  async updateUser(id: string, dto: UpdateUserDto, actingAdminId: string) {
    await this.requireUser(id);
    if (dto.name === undefined && dto.phone === undefined && dto.houseAddress === undefined) {
      throw new BadRequestException('Provide at least one of name, phone, or houseAddress');
    }
    const updated = await this.prisma.user.update({
      where: { id },
      data: {
        ...(dto.name !== undefined ? { fullName: dto.name } : {}),
        ...(dto.phone !== undefined ? { phoneNumber: dto.phone } : {}),
        ...(dto.houseAddress !== undefined ? { houseAddress: dto.houseAddress } : {}),
      },
      select: { id: true, email: true, fullName: true, phoneNumber: true, houseAddress: true, role: true },
    });
    await this.activityLog.log(ActivityLogType.ADMIN_USER_EDITED, { actorId: actingAdminId, targetId: id });
    return updated;
  }

  /// Admin-triggered — unlike AuthService.deactivate (self-service), this
  /// doesn't need the account's own session and skips straight to the
  /// same effect: listings hidden, every session signed out, "your
  /// account has been deactivated" email sent. Logged with [reason] for
  /// auditability, same as [updateUser].
  async deactivateUser(id: string, reason: string, actorId: string): Promise<void> {
    await this.requireUser(id);
    await this.auth.deactivate(id, reason);
    await this.activityLog.log(ActivityLogType.ADMIN_USER_DEACTIVATED, { actorId, targetId: id, reason });
  }

  /// Logged *before* the delete, not after — [auth.deleteAccount] is a
  /// real hard delete (see its own doc comment), and the log row's
  /// targetId FK needs the user to still exist at insert time.
  async deleteUser(id: string, reason: string, actorId: string): Promise<void> {
    await this.requireUser(id);
    await this.activityLog.log(ActivityLogType.ADMIN_USER_DELETED, { actorId, targetId: id, reason });
    await this.auth.deleteAccount(id, reason);
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
    // Idempotent: a double-tap or a retry on a slow response previously
    // re-sent the approval notification + email every time this was
    // called, even for a vendor already approved.
    if (vendor.status === 'APPROVED') return vendor;
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
    // Keeps the Vendors nav badge (AdminShell._pendingVendorsCount) live
    // across every other admin's already-open console.
    this.chatGateway.broadcastToAdmins('admin:badges-changed', {});
    return updated;
  }

  async rejectVendor(id: string, dto: RejectVendorDto) {
    const vendor = await this.requireVendor(id);
    if (vendor.status === 'REJECTED' && vendor.rejectionReason === (dto.reason ?? null)) return vendor;
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
    this.chatGateway.broadcastToAdmins('admin:badges-changed', {});
    return updated;
  }

  /// Vendor profile plus the products they list and every order item
  /// they've received (joined to the parent order's buyer/createdAt) —
  /// the vendor-side equivalent of [findUserDetail]. Any admin tier can
  /// view; only [suspendVendor]/[unsuspendVendor]/[approveVendor]/
  /// [rejectVendor] stay Moderator+.
  async findVendorDetail(id: string) {
    const vendor = await this.prisma.vendorProfile.findUnique({
      where: { id },
      include: {
        user: { select: { email: true } },
        products: {
          select: { id: true, listingNumber: true, name: true, price: true, stock: true, isAvailable: true, category: true },
          orderBy: { createdAt: 'desc' },
        },
        orderItems: {
          select: {
            id: true,
            productName: true,
            unitPrice: true,
            quantity: true,
            status: true,
            order: { select: { id: true, createdAt: true, buyer: { select: { fullName: true, email: true } } } },
          },
        },
      },
    });
    if (!vendor) throw new NotFoundException('Vendor not found');
    const orders = [...vendor.orderItems].sort((a, b) => b.order.createdAt.getTime() - a.order.createdAt.getTime());
    return {
      id: vendor.id,
      businessName: vendor.businessName,
      category: vendor.category,
      state: vendor.state,
      ownerEmail: vendor.user.email,
      status: vendor.status,
      isActive: vendor.isActive,
      suspendedAt: vendor.suspendedAt,
      rejectionReason: vendor.rejectionReason,
      rcNumber: vendor.rcNumber,
      bankCode: vendor.bankCode,
      bankName: vendor.bankName,
      accountNumber: vendor.accountNumber,
      accountName: vendor.accountName,
      products: vendor.products,
      orders: orders.map((i) => ({
        id: i.id,
        orderId: i.order.id,
        productName: i.productName,
        unitPrice: i.unitPrice,
        quantity: i.quantity,
        status: i.status,
        buyerName: i.order.buyer.fullName ?? i.order.buyer.email,
        createdAt: i.order.createdAt,
      })),
    };
  }

  async suspendVendor(id: string, reason: string) {
    const vendor = await this.requireVendor(id);
    if (vendor.suspendedAt !== null) return vendor;
    const updated = await this.prisma.vendorProfile.update({ where: { id }, data: { suspendedAt: new Date() } });
    await this.notifications.create(
      vendor.userId,
      NotificationType.VENDOR_SUSPENDED,
      'Your shop has been suspended',
      `${vendor.businessName} has been suspended by an admin. Reason: ${reason}`,
    );
    await this.mail.send(
      vendor.user.email,
      `Your shop "${vendor.businessName}" has been suspended`,
      `<p>Your shop <strong>${vendor.businessName}</strong> has been suspended from the HomeServant Marketplace by an admin.</p><p>Reason: ${reason}</p>`,
      `Your shop "${vendor.businessName}" has been suspended from the HomeServant Marketplace by an admin.\n\nReason: ${reason}`,
    );
    return updated;
  }

  async unsuspendVendor(id: string, reason: string) {
    const vendor = await this.requireVendor(id);
    if (vendor.suspendedAt === null) return vendor;
    const updated = await this.prisma.vendorProfile.update({ where: { id }, data: { suspendedAt: null } });
    await this.notifications.create(
      vendor.userId,
      NotificationType.VENDOR_UNSUSPENDED,
      'Your shop has been reinstated',
      `${vendor.businessName} has been reinstated by an admin. ${reason}`,
    );
    await this.mail.send(
      vendor.user.email,
      `Your shop "${vendor.businessName}" has been reinstated`,
      `<p>Your shop <strong>${vendor.businessName}</strong> has been reinstated on the HomeServant Marketplace by an admin.</p><p>Note: ${reason}</p>`,
      `Your shop "${vendor.businessName}" has been reinstated on the HomeServant Marketplace by an admin.\n\nNote: ${reason}`,
    );
    return updated;
  }

  private async requireVendor(id: string) {
    const vendor = await this.prisma.vendorProfile.findUnique({ where: { id }, include: { user: { select: { email: true } } } });
    if (!vendor) throw new NotFoundException('Vendor not found');
    return vendor;
  }

  // --- Properties --------------------------------------------------------

  async findProperties(page = 1, pageSize = 20, search?: string) {
    // A purely numeric search also matches the listing number exactly, so
    // an admin can jump straight to a listing by the number shown to them
    // everywhere it appears, not just by title/location text.
    const searchAsNumber = search && /^\d+$/.test(search) ? Number(search) : undefined;
    const where: Prisma.PropertyWhereInput = search
      ? {
          OR: [
            { title: { contains: search, mode: 'insensitive' } },
            { location: { contains: search, mode: 'insensitive' } },
            ...(searchAsNumber !== undefined ? [{ listingNumber: searchAsNumber }] : []),
          ],
        }
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

  /// Full listing — everything `findProperties` already fetches via
  /// `include` but discards when shaping the list-row response, plus
  /// relation counts the list doesn't need.
  async findPropertyDetail(id: string) {
    const property = await this.prisma.property.findUnique({
      where: { id },
      include: {
        landlord: { select: { id: true, fullName: true, email: true, phoneNumber: true } },
        _count: { select: { bookings: true, favorites: true, reviews: true } },
      },
    });
    if (!property) throw new NotFoundException('Property not found');
    return property;
  }

  /// A landlord can't re-list their own occupied property (a tenant's
  /// active lease depends on it staying that way — see
  /// PropertiesService's own delete guard for the same reasoning) — this
  /// is the moderator/super-admin override for when it's genuinely needed
  /// sooner than the lease-lifecycle cron would otherwise flip it back.
  /// Only clears the occupied flag; it does not touch the underlying
  /// Booking/Payment/TenancyAgreement rows.
  async relistProperty(id: string): Promise<void> {
    const property = await this.prisma.property.findUnique({ where: { id }, include: { landlord: { select: { email: true } } } });
    if (!property) throw new NotFoundException('Property not found');
    await this.prisma.property.update({ where: { id }, data: { isOccupied: false } });
    await this.mail.send(
      property.landlord.email,
      `"${property.title}" is listed again`,
      `<p>An admin has re-listed <strong>${property.title}</strong> — it's visible to renters again.</p>`,
      `An admin has re-listed "${property.title}" — it's visible to renters again.`,
    );
  }

  async removeProperty(id: string, reason: string): Promise<void> {
    const property = await this.prisma.property.findUnique({
      where: { id },
      include: { landlord: { select: { email: true } } },
    });
    if (!property) throw new NotFoundException('Property not found');
    await this.prisma.property.delete({ where: { id } });
    await this.mail.send(
      property.landlord.email,
      `Your listing "${property.title}" was removed`,
      `<p>Your listing <strong>${property.title}</strong> has been removed from HomeServant by an admin.</p><p>Reason: ${reason}</p>`,
      `Your listing "${property.title}" has been removed from HomeServant by an admin.\n\nReason: ${reason}`,
    );
  }

  // --- Marketplace ---------------------------------------------------------

  async findProducts(page = 1, pageSize = 20, search?: string) {
    // Same "search also matches the listing number exactly" treatment as
    // findProperties, above.
    const searchAsNumber = search && /^\d+$/.test(search) ? Number(search) : undefined;
    const where: Prisma.ProductWhereInput = search
      ? {
          OR: [
            { name: { contains: search, mode: 'insensitive' } },
            ...(searchAsNumber !== undefined ? [{ listingNumber: searchAsNumber }] : []),
          ],
        }
      : {};
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

  async removeProduct(id: string, reason: string): Promise<void> {
    const product = await this.prisma.product.findUnique({
      where: { id },
      include: { vendor: { select: { user: { select: { email: true } } } } },
    });
    if (!product) throw new NotFoundException('Product not found');
    await this.prisma.product.update({ where: { id }, data: { isAvailable: false } });
    await this.mail.send(
      product.vendor.user.email,
      `Your listing "${product.name}" was removed`,
      `<p>Your listing <strong>${product.name}</strong> has been removed from the HomeServant Marketplace by an admin.</p><p>Reason: ${reason}</p>`,
      `Your listing "${product.name}" has been removed from the HomeServant Marketplace by an admin.\n\nReason: ${reason}`,
    );
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

  /// Full order detail — reached by tapping an order row (Marketplace tab
  /// or the dashboard's activity feed). Unlike [findOrders]' trimmed list
  /// shape, this pulls in every field a support/dispute conversation would
  /// need: full item fulfillment/shipment state, the buyer's delivery
  /// details, and each item's vendor so an admin can jump straight to the
  /// vendor's shop from here.
  async findOrderDetail(id: string) {
    const order = await this.prisma.marketplaceOrder.findUnique({
      where: { id },
      include: {
        buyer: { select: { id: true, fullName: true, email: true } },
        items: {
          select: {
            id: true,
            productId: true,
            productName: true,
            quantity: true,
            unitPrice: true,
            fulfillment: true,
            status: true,
            trackingNumber: true,
            shippedAt: true,
            vendor: { select: { id: true, businessName: true } },
          },
        },
      },
    });
    if (!order) throw new NotFoundException('Order not found');
    return order;
  }

  // --- Messages / admin-invite badge counts ---------------------------------

  /// Backs the Messages nav badge: the acting admin's own unread messages
  /// (mirrors ChatService.findForUser's unreadCount query) plus every open
  /// "Contact Support" thread awaiting any admin's reply — the same two
  /// concepts the request behind this named ("unread message" and
  /// "unattended activity").
  async messagesAttentionCount(adminId: string): Promise<number> {
    const [unreadOwnMessages, openSupportThreads] = await Promise.all([
      this.prisma.message.count({
        where: { thread: { participants: { some: { userId: adminId } } }, senderId: { not: adminId }, readAt: null },
      }),
      this.prisma.thread.count({ where: { isSupport: true, status: 'OPEN' } }),
    ]);
    return unreadOwnMessages + openSupportThreads;
  }

  /// Backs the Admins nav badge — invites sent (via [requestAdminOtp]) but
  /// never confirmed, i.e. genuinely "unattended".
  pendingAdminInvitesCount(): Promise<number> {
    return this.prisma.pendingAdmin.count();
  }
}
