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

  /// Unwraps the `{items, total, page, pageSize}` shape every paginated
  /// admin list endpoint returns — was duplicated at each call site in
  /// AdminRepository (stats/findUsers/findVendors/etc).
  factory AdminPage.fromApi(Map<String, dynamic> json, T Function(Map<String, dynamic>) itemParser) => AdminPage<T>(
    items: (json['items'] as List).cast<Map<String, dynamic>>().map(itemParser).toList(),
    total: json['total'] as int,
    page: json['page'] as int,
    pageSize: json['pageSize'] as int,
  );
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
    this.properties = const [],
    this.bookings = const [],
    this.marketplaceOrders = const [],
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

  /// The landlord's own listings — empty for non-landlords. See
  /// AdminService.findUserDetail.
  final List<AdminUserProperty> properties;

  /// Rental history as a tenant (bookings made against other landlords'
  /// properties) — empty for non-tenants.
  final List<AdminUserBooking> bookings;

  /// Purchase history as a marketplace buyer — empty for users who've
  /// never ordered.
  final List<AdminUserOrder> marketplaceOrders;

  bool get isDeactivated => deactivatedAt != null;

  factory AdminUserDetail.fromApi(Map<String, dynamic> json) {
    final vendorProfile = json['vendorProfile'] as Map<String, dynamic>?;
    final counts = json['_count'] as Map<String, dynamic>? ?? const {};
    final properties = (json['properties'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AdminUserProperty.fromApi)
        .toList();
    final bookings = (json['bookings'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AdminUserBooking.fromApi)
        .toList();
    final marketplaceOrders = (json['marketplaceOrders'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AdminUserOrder.fromApi)
        .toList();
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
      propertiesCount: counts['properties'] as int? ?? properties.length,
      bookingsCount: counts['bookings'] as int? ?? bookings.length,
      marketplaceOrdersCount: counts['marketplaceOrders'] as int? ?? marketplaceOrders.length,
      favoritesCount: counts['favorites'] as int? ?? 0,
      reviewsCount: counts['reviews'] as int? ?? 0,
      properties: properties,
      bookings: bookings,
      marketplaceOrders: marketplaceOrders,
    );
  }
}

/// One of a landlord's own listings — GET /admin/users/:id's `properties`.
class AdminUserProperty {
  const AdminUserProperty({
    required this.id,
    required this.title,
    required this.price,
    required this.priceUnit,
    required this.isOccupied,
    required this.createdAt,
  });

  final String id;
  final String title;
  final int price;
  final String priceUnit;
  final bool isOccupied;
  final DateTime createdAt;

  factory AdminUserProperty.fromApi(Map<String, dynamic> json) => AdminUserProperty(
    id: json['id'] as String,
    title: json['title'] as String,
    price: json['price'] as int,
    priceUnit: json['priceUnit'] as String,
    isOccupied: json['isOccupied'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// One entry in a tenant's rental history — GET /admin/users/:id's
/// `bookings`. No per-booking payment ledger exists in the schema, so
/// price/priceUnit reflect the property's listed rent, not an amount paid.
class AdminUserBooking {
  const AdminUserBooking({
    required this.id,
    required this.propertyId,
    required this.propertyTitle,
    required this.price,
    required this.priceUnit,
    required this.status,
    this.requestedDate,
    required this.createdAt,
  });

  final String id;
  final String propertyId;
  final String propertyTitle;
  final int price;
  final String priceUnit;
  final String status;
  final DateTime? requestedDate;
  final DateTime createdAt;

  factory AdminUserBooking.fromApi(Map<String, dynamic> json) => AdminUserBooking(
    id: json['id'] as String,
    propertyId: json['propertyId'] as String,
    propertyTitle: json['propertyTitle'] as String,
    price: json['price'] as int,
    priceUnit: json['priceUnit'] as String,
    status: json['status'] as String,
    requestedDate: json['requestedDate'] != null ? DateTime.parse(json['requestedDate'] as String) : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// One line item within a marketplace purchase — nested inside
/// [AdminUserOrder.items].
class AdminUserOrderItem {
  const AdminUserOrderItem({
    required this.id,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.status,
    required this.vendorId,
    this.vendorBusinessName,
  });

  final String id;
  final String productName;
  final int unitPrice;
  final int quantity;
  final String status;
  final String vendorId;
  final String? vendorBusinessName;

  factory AdminUserOrderItem.fromApi(Map<String, dynamic> json) => AdminUserOrderItem(
    id: json['id'] as String,
    productName: json['productName'] as String,
    unitPrice: json['unitPrice'] as int,
    quantity: json['quantity'] as int,
    status: json['status'] as String,
    vendorId: json['vendorId'] as String,
    vendorBusinessName: json['vendorBusinessName'] as String?,
  );
}

/// One marketplace order placed by this user as buyer — GET
/// /admin/users/:id's `marketplaceOrders`.
class AdminUserOrder {
  const AdminUserOrder({required this.id, required this.createdAt, required this.items});

  final String id;
  final DateTime createdAt;
  final List<AdminUserOrderItem> items;

  factory AdminUserOrder.fromApi(Map<String, dynamic> json) => AdminUserOrder(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    items: (json['items'] as List? ?? const []).cast<Map<String, dynamic>>().map(AdminUserOrderItem.fromApi).toList(),
  );
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
    this.suspendedAt,
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

  /// Set by an admin (suspendVendor/unsuspendVendor) — distinct from
  /// [isActive], which is the vendor's own "Deactivate Shop" toggle. Use
  /// this, not [isActive], to drive the admin Suspend/Unsuspend UI.
  final DateTime? suspendedAt;
  final String? rejectionReason;
  final String? ownerEmail;
  final String? ownerName;
  final String? ownerPhone;
  final DateTime createdAt;

  bool get isSuspended => suspendedAt != null;

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
      suspendedAt: json['suspendedAt'] != null ? DateTime.parse(json['suspendedAt'] as String) : null,
      rejectionReason: json['rejectionReason'] as String?,
      ownerEmail: user?['email'] as String?,
      ownerName: user?['fullName'] as String?,
      ownerPhone: user?['phoneNumber'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// One of a vendor's own catalog products — nested inside
/// [AdminVendorDetail.products]. GET /admin/vendors/:id.
class AdminVendorProduct {
  const AdminVendorProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    required this.isAvailable,
    required this.category,
  });

  final String id;
  final String name;
  final int price;
  final int stock;
  final bool isAvailable;
  final MarketplaceCategory category;

  factory AdminVendorProduct.fromApi(Map<String, dynamic> json) => AdminVendorProduct(
    id: json['id'] as String,
    name: json['name'] as String,
    price: json['price'] as int,
    stock: json['stock'] as int,
    isAvailable: json['isAvailable'] as bool? ?? true,
    category: MarketplaceCategoryApi.fromApi(json['category'] as String),
  );
}

/// One order-item this vendor received — nested inside
/// [AdminVendorDetail.orders]. GET /admin/vendors/:id.
class AdminVendorOrder {
  const AdminVendorOrder({
    required this.id,
    required this.orderId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.status,
    this.buyerName,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String productName;
  final int unitPrice;
  final int quantity;
  final String status;
  final String? buyerName;
  final DateTime createdAt;

  factory AdminVendorOrder.fromApi(Map<String, dynamic> json) => AdminVendorOrder(
    id: json['id'] as String,
    orderId: json['orderId'] as String,
    productName: json['productName'] as String,
    unitPrice: json['unitPrice'] as int,
    quantity: json['quantity'] as int,
    status: json['status'] as String,
    buyerName: json['buyerName'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Full vendor profile + catalog + received orders — GET
/// /admin/vendors/:id, see AdminService.findVendorDetail (backend).
class AdminVendorDetail {
  const AdminVendorDetail({
    required this.id,
    required this.businessName,
    required this.category,
    required this.state,
    this.ownerEmail,
    required this.status,
    required this.isActive,
    this.suspendedAt,
    this.rejectionReason,
    this.bankCode,
    this.bankName,
    this.accountNumber,
    this.accountName,
    this.products = const [],
    this.orders = const [],
  });

  final String id;
  final String businessName;
  final MarketplaceCategory category;
  final String state;
  final String? ownerEmail;
  final VendorApplicationStatus status;
  final bool isActive;

  /// Set by an admin (suspendVendor/unsuspendVendor) — distinct from
  /// [isActive], which is the vendor's own "Deactivate Shop" toggle. Use
  /// this, not [isActive], to drive the admin Suspend/Unsuspend UI.
  final DateTime? suspendedAt;
  final String? rejectionReason;

  /// The vendor's payout account, same shape as [VendorProfile]'s own
  /// fields — not yet returned by `GET /admin/vendors/:id` as of this
  /// writing (see AdminService.findVendorDetail), so these stay null
  /// until that endpoint is extended to include them.
  final String? bankCode;
  final String? bankName;
  final String? accountNumber;
  final String? accountName;

  final List<AdminVendorProduct> products;
  final List<AdminVendorOrder> orders;

  bool get isSuspended => suspendedAt != null;

  factory AdminVendorDetail.fromApi(Map<String, dynamic> json) => AdminVendorDetail(
    id: json['id'] as String,
    businessName: json['businessName'] as String,
    category: MarketplaceCategoryApi.fromApi(json['category'] as String),
    state: json['state'] as String,
    ownerEmail: json['ownerEmail'] as String?,
    status: VendorApplicationStatus.fromApi(json['status'] as String),
    isActive: json['isActive'] as bool? ?? true,
    suspendedAt: json['suspendedAt'] != null ? DateTime.parse(json['suspendedAt'] as String) : null,
    rejectionReason: json['rejectionReason'] as String?,
    bankCode: json['bankCode'] as String?,
    bankName: json['bankName'] as String?,
    accountNumber: json['accountNumber'] as String?,
    accountName: json['accountName'] as String?,
    products: (json['products'] as List? ?? const []).cast<Map<String, dynamic>>().map(AdminVendorProduct.fromApi).toList(),
    orders: (json['orders'] as List? ?? const []).cast<Map<String, dynamic>>().map(AdminVendorOrder.fromApi).toList(),
  );
}

class AdminProperty {
  const AdminProperty({
    required this.id,
    required this.title,
    required this.location,
    required this.price,
    this.landlordName,
    this.landlordEmail,
    this.isOccupied = false,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String location;
  final int price;
  final String? landlordName;
  final String? landlordEmail;

  /// True while a landlord-side "can't re-list an occupied property" rule
  /// is in effect — a moderator/super admin can override it (see
  /// [AdminRepository.relistProperty]).
  final bool isOccupied;
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
      isOccupied: json['isOccupied'] as bool? ?? false,
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
