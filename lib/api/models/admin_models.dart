import '../../models/user_role.dart';
import 'vendor.dart';

/// Ranked low to high — matches the backend's declaration order
/// (SUPPORT < MODERATOR < SUPER_ADMIN, see AdminLevel in
/// backend/prisma/schema.prisma). [index] on the enum itself doubles as
/// the rank for UI comparisons like "can this admin do X".
enum AdminLevel {
  support,
  moderator,
  superAdmin;

  String get apiValue => switch (this) {
    AdminLevel.support => 'SUPPORT',
    AdminLevel.moderator => 'MODERATOR',
    AdminLevel.superAdmin => 'SUPER_ADMIN',
  };

  String get label => switch (this) {
    AdminLevel.support => 'Support',
    AdminLevel.moderator => 'Moderator',
    AdminLevel.superAdmin => 'Super Admin',
  };

  bool get atLeastModerator => index >= AdminLevel.moderator.index;
  bool get isSuperAdmin => this == AdminLevel.superAdmin;

  static AdminLevel fromApi(String value) => switch (value) {
    'MODERATOR' => AdminLevel.moderator,
    'SUPER_ADMIN' => AdminLevel.superAdmin,
    _ => AdminLevel.support,
  };
}

class AdminAccount {
  const AdminAccount({
    required this.id,
    required this.email,
    required this.level,
    this.fullName,
    required this.createdAt,
    this.twoFactorEnabled = false,
    this.mustChangePassword = false,
  });

  final String id;
  final String email;
  final AdminLevel level;
  final String? fullName;
  final DateTime createdAt;
  final bool twoFactorEnabled;
  final bool mustChangePassword;

  factory AdminAccount.fromApi(Map<String, dynamic> json) => AdminAccount(
    id: json['id'] as String,
    email: json['email'] as String,
    level: AdminLevel.fromApi(json['adminLevel'] as String),
    fullName: json['fullName'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    twoFactorEnabled: json['twoFactorEnabled'] as bool? ?? false,
    mustChangePassword: json['mustChangePassword'] as bool? ?? false,
  );
}

class AdminStats {
  const AdminStats({
    required this.totalUsers,
    required this.tenants,
    required this.landlords,
    required this.vendors,
    required this.pendingVendors,
    required this.properties,
    required this.bookings,
    required this.marketplaceOrders,
    required this.deactivatedAccounts,
  });

  final int totalUsers;
  final int tenants;
  final int landlords;
  final int vendors;
  final int pendingVendors;
  final int properties;
  final int bookings;
  final int marketplaceOrders;
  final int deactivatedAccounts;

  factory AdminStats.fromApi(Map<String, dynamic> json) => AdminStats(
    totalUsers: json['totalUsers'] as int,
    tenants: json['tenants'] as int,
    landlords: json['landlords'] as int,
    vendors: json['vendors'] as int,
    pendingVendors: json['pendingVendors'] as int,
    properties: json['properties'] as int,
    bookings: json['bookings'] as int,
    marketplaceOrders: json['marketplaceOrders'] as int,
    deactivatedAccounts: json['deactivatedAccounts'] as int,
  );
}

class AdminPage<T> {
  const AdminPage({required this.items, required this.total, required this.page, required this.pageSize});

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => page * pageSize < total;
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.role,
    this.fullName,
    this.phoneNumber,
    this.emailVerifiedAt,
    this.deactivatedAt,
    required this.createdAt,
  });

  final String id;
  final String email;
  final UserRole role;
  final String? fullName;
  final String? phoneNumber;
  final DateTime? emailVerifiedAt;
  final DateTime? deactivatedAt;
  final DateTime createdAt;

  bool get isDeactivated => deactivatedAt != null;

  factory AdminUser.fromApi(Map<String, dynamic> json) => AdminUser(
    id: json['id'] as String,
    email: json['email'] as String,
    role: UserRoleFromApiValue.fromApiValue(json['role'] as String),
    fullName: json['fullName'] as String?,
    phoneNumber: json['phoneNumber'] as String?,
    emailVerifiedAt: json['emailVerifiedAt'] != null ? DateTime.parse(json['emailVerifiedAt'] as String) : null,
    deactivatedAt: json['deactivatedAt'] != null ? DateTime.parse(json['deactivatedAt'] as String) : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Every field on the account (minus the password hash, which the
/// backend never returns) — GET /admin/users/:id, see
/// AdminService.findUserDetail.
class AdminUserDetail {
  const AdminUserDetail({
    required this.id,
    required this.email,
    required this.role,
    this.fullName,
    this.phoneNumber,
    this.houseAddress,
    this.dateOfBirth,
    this.profilePhotoUrl,
    this.twoFactorEnabled = false,
    this.emailVerifiedAt,
    this.deactivatedAt,
    this.bankCode,
    this.bankName,
    this.accountNumber,
    this.accountName,
    this.referralCode,
    required this.createdAt,
    this.vendorBusinessName,
    this.vendorStatus,
    this.vendorIsActive,
    this.propertiesCount = 0,
    this.bookingsCount = 0,
    this.marketplaceOrdersCount = 0,
    this.favoritesCount = 0,
    this.reviewsCount = 0,
  });

  final String id;
  final String email;
  final UserRole role;
  final String? fullName;
  final String? phoneNumber;
  final String? houseAddress;
  final DateTime? dateOfBirth;
  final String? profilePhotoUrl;
  final bool twoFactorEnabled;
  final DateTime? emailVerifiedAt;
  final DateTime? deactivatedAt;
  final String? bankCode;
  final String? bankName;
  final String? accountNumber;
  final String? accountName;
  final String? referralCode;
  final DateTime createdAt;

  final String? vendorBusinessName;
  final String? vendorStatus;
  final bool? vendorIsActive;

  final int propertiesCount;
  final int bookingsCount;
  final int marketplaceOrdersCount;
  final int favoritesCount;
  final int reviewsCount;

  bool get isDeactivated => deactivatedAt != null;

  factory AdminUserDetail.fromApi(Map<String, dynamic> json) {
    final vendorProfile = json['vendorProfile'] as Map<String, dynamic>?;
    final counts = json['_count'] as Map<String, dynamic>? ?? const {};
    return AdminUserDetail(
      id: json['id'] as String,
      email: json['email'] as String,
      role: UserRoleFromApiValue.fromApiValue(json['role'] as String),
      fullName: json['fullName'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      houseAddress: json['houseAddress'] as String?,
      dateOfBirth: json['dateOfBirth'] != null ? DateTime.parse(json['dateOfBirth'] as String) : null,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      twoFactorEnabled: json['twoFactorEnabled'] as bool? ?? false,
      emailVerifiedAt: json['emailVerifiedAt'] != null ? DateTime.parse(json['emailVerifiedAt'] as String) : null,
      deactivatedAt: json['deactivatedAt'] != null ? DateTime.parse(json['deactivatedAt'] as String) : null,
      bankCode: json['bankCode'] as String?,
      bankName: json['bankName'] as String?,
      accountNumber: json['accountNumber'] as String?,
      accountName: json['accountName'] as String?,
      referralCode: json['referralCode'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      vendorBusinessName: vendorProfile?['businessName'] as String?,
      vendorStatus: vendorProfile?['status'] as String?,
      vendorIsActive: vendorProfile?['isActive'] as bool?,
      propertiesCount: counts['properties'] as int? ?? 0,
      bookingsCount: counts['bookings'] as int? ?? 0,
      marketplaceOrdersCount: counts['marketplaceOrders'] as int? ?? 0,
      favoritesCount: counts['favorites'] as int? ?? 0,
      reviewsCount: counts['reviews'] as int? ?? 0,
    );
  }
}

class AdminVendor {
  const AdminVendor({
    required this.id,
    required this.userId,
    required this.businessName,
    required this.category,
    required this.state,
    required this.status,
    required this.isActive,
    this.rejectionReason,
    this.ownerEmail,
    this.ownerName,
    this.ownerPhone,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String businessName;
  final MarketplaceCategory category;
  final String state;
  final VendorApplicationStatus status;
  final bool isActive;
  final String? rejectionReason;
  final String? ownerEmail;
  final String? ownerName;
  final String? ownerPhone;
  final DateTime createdAt;

  factory AdminVendor.fromApi(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return AdminVendor(
      id: json['id'] as String,
      userId: json['userId'] as String,
      businessName: json['businessName'] as String,
      category: MarketplaceCategoryApi.fromApi(json['category'] as String),
      state: json['state'] as String,
      status: VendorApplicationStatus.fromApi(json['status'] as String),
      isActive: json['isActive'] as bool? ?? true,
      rejectionReason: json['rejectionReason'] as String?,
      ownerEmail: user?['email'] as String?,
      ownerName: user?['fullName'] as String?,
      ownerPhone: user?['phoneNumber'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class AdminProperty {
  const AdminProperty({
    required this.id,
    required this.title,
    required this.location,
    required this.price,
    this.landlordName,
    this.landlordEmail,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String location;
  final int price;
  final String? landlordName;
  final String? landlordEmail;
  final DateTime createdAt;

  factory AdminProperty.fromApi(Map<String, dynamic> json) {
    final landlord = json['landlord'] as Map<String, dynamic>?;
    return AdminProperty(
      id: json['id'] as String,
      title: json['title'] as String,
      location: json['location'] as String,
      price: json['price'] as int,
      landlordName: landlord?['fullName'] as String?,
      landlordEmail: landlord?['email'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class AdminProduct {
  const AdminProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.isAvailable,
    this.vendorName,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int price;
  final bool isAvailable;
  final String? vendorName;
  final DateTime createdAt;

  factory AdminProduct.fromApi(Map<String, dynamic> json) {
    final vendor = json['vendor'] as Map<String, dynamic>?;
    return AdminProduct(
      id: json['id'] as String,
      name: json['name'] as String,
      price: json['price'] as int,
      isAvailable: json['isAvailable'] as bool? ?? true,
      vendorName: vendor?['businessName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class AdminOrder {
  const AdminOrder({
    required this.id,
    required this.total,
    this.buyerName,
    this.buyerEmail,
    required this.itemCount,
    required this.createdAt,
  });

  final String id;
  final int total;
  final String? buyerName;
  final String? buyerEmail;
  final int itemCount;
  final DateTime createdAt;

  factory AdminOrder.fromApi(Map<String, dynamic> json) {
    final buyer = json['buyer'] as Map<String, dynamic>?;
    final items = (json['items'] as List).cast<Map<String, dynamic>>();
    final total = items.fold<int>(0, (sum, item) => sum + (item['unitPrice'] as int) * (item['quantity'] as int));
    return AdminOrder(
      id: json['id'] as String,
      total: total,
      buyerName: buyer?['fullName'] as String?,
      buyerEmail: buyer?['email'] as String?,
      itemCount: items.length,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

extension UserRoleFromApiValue on UserRole {
  static UserRole fromApiValue(String value) => switch (value) {
    'LANDLORD' => UserRole.landlord,
    'VENDOR' => UserRole.vendor,
    'ADMIN' => UserRole.admin,
    _ => UserRole.tenant,
  };
}

enum ActivityLogType {
  adminLogin,
  adminPasswordChanged,
  adminPasswordReset;

  static ActivityLogType fromApi(String value) => switch (value) {
    'ADMIN_LOGIN' => ActivityLogType.adminLogin,
    'ADMIN_PASSWORD_CHANGED' => ActivityLogType.adminPasswordChanged,
    'ADMIN_PASSWORD_RESET' => ActivityLogType.adminPasswordReset,
    _ => ActivityLogType.adminLogin,
  };

  String get label => switch (this) {
    ActivityLogType.adminLogin => 'Logged in',
    ActivityLogType.adminPasswordChanged => 'Changed password',
    ActivityLogType.adminPasswordReset => 'Password reset',
  };
}

class ActivityLogPersonRef {
  const ActivityLogPersonRef({required this.id, required this.email, this.fullName});

  final String id;
  final String email;
  final String? fullName;

  String get displayName => fullName?.isNotEmpty == true ? fullName! : email;

  factory ActivityLogPersonRef.fromApi(Map<String, dynamic> json) => ActivityLogPersonRef(
    id: json['id'] as String,
    email: json['email'] as String,
    fullName: json['fullName'] as String?,
  );
}

class ActivityLogEntry {
  const ActivityLogEntry({
    required this.id,
    required this.type,
    this.actor,
    this.target,
    this.ip,
    this.location,
    required this.createdAt,
  });

  final String id;
  final ActivityLogType type;
  final ActivityLogPersonRef? actor;
  final ActivityLogPersonRef? target;
  final String? ip;
  final String? location;
  final DateTime createdAt;

  factory ActivityLogEntry.fromApi(Map<String, dynamic> json) => ActivityLogEntry(
    id: json['id'] as String,
    type: ActivityLogType.fromApi(json['type'] as String),
    actor: json['actor'] != null ? ActivityLogPersonRef.fromApi(json['actor'] as Map<String, dynamic>) : null,
    target: json['target'] != null ? ActivityLogPersonRef.fromApi(json['target'] as Map<String, dynamic>) : null,
    ip: json['ip'] as String?,
    location: json['location'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

enum ReportTargetType {
  property,
  marketplaceItem;

  static ReportTargetType fromApi(String value) => value == 'PROPERTY' ? ReportTargetType.property : ReportTargetType.marketplaceItem;
  String get apiValue => this == ReportTargetType.property ? 'PROPERTY' : 'MARKETPLACE_ITEM';
}

enum ReportStatus {
  open,
  inProgress,
  resolved;

  static ReportStatus fromApi(String value) => switch (value) {
    'OPEN' => ReportStatus.open,
    'IN_PROGRESS' => ReportStatus.inProgress,
    'RESOLVED' => ReportStatus.resolved,
    _ => ReportStatus.open,
  };

  String get apiValue => switch (this) {
    ReportStatus.open => 'OPEN',
    ReportStatus.inProgress => 'IN_PROGRESS',
    ReportStatus.resolved => 'RESOLVED',
  };

  String get label => switch (this) {
    ReportStatus.open => 'Open',
    ReportStatus.inProgress => 'In Progress',
    ReportStatus.resolved => 'Resolved',
  };
}

class AdminReport {
  const AdminReport({
    required this.id,
    required this.targetType,
    this.propertyTitle,
    this.productName,
    required this.reason,
    required this.status,
    this.reporter,
    this.assignedAdmin,
    required this.createdAt,
  });

  final String id;
  final ReportTargetType targetType;
  final String? propertyTitle;
  final String? productName;
  final String reason;
  final ReportStatus status;
  final ActivityLogPersonRef? reporter;
  final ActivityLogPersonRef? assignedAdmin;
  final DateTime createdAt;

  String get targetLabel => propertyTitle ?? productName ?? 'Unknown listing';

  factory AdminReport.fromApi(Map<String, dynamic> json) {
    final property = json['property'] as Map<String, dynamic>?;
    final product = json['product'] as Map<String, dynamic>?;
    return AdminReport(
      id: json['id'] as String,
      targetType: ReportTargetType.fromApi(json['targetType'] as String),
      propertyTitle: property?['title'] as String?,
      productName: product?['name'] as String?,
      reason: json['reason'] as String,
      status: ReportStatus.fromApi(json['status'] as String),
      reporter: json['reporter'] != null ? ActivityLogPersonRef.fromApi(json['reporter'] as Map<String, dynamic>) : null,
      assignedAdmin: json['assignedAdmin'] != null ? ActivityLogPersonRef.fromApi(json['assignedAdmin'] as Map<String, dynamic>) : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
