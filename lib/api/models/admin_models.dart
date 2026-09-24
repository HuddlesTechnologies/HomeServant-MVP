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
