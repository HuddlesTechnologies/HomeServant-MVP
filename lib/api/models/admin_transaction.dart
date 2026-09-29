/// One successful rent payment on the admin console's Transactions page —
/// see backend AdminTransactionsService.toTransaction.
enum TransactionStatus { credited, held, refunded }

class TransactionPerson {
  const TransactionPerson({required this.id, required this.name, required this.email, this.phoneNumber, this.profilePhotoUrl});

  final String id;
  final String name;
  final String email;
  final String? phoneNumber;
  final String? profilePhotoUrl;

  factory TransactionPerson.fromApi(Map<String, dynamic> json) => TransactionPerson(
    id: json['id'] as String,
    name: json['name'] as String? ?? json['email'] as String? ?? '',
    email: json['email'] as String? ?? '',
    phoneNumber: json['phoneNumber'] as String?,
    profilePhotoUrl: json['profilePhotoUrl'] as String?,
  );
}

class TransactionProperty {
  const TransactionProperty({
    required this.id,
    required this.listingNumber,
    required this.title,
    required this.location,
    required this.state,
    required this.category,
    required this.price,
    required this.priceUnit,
    required this.bedrooms,
    required this.bathrooms,
    this.imageUrl,
    this.galleryUrls = const [],
  });

  final String id;
  final int listingNumber;
  final String title;
  final String location;
  final String state;
  final String category;
  final int price;
  final String priceUnit;
  final int bedrooms;
  final int bathrooms;
  final String? imageUrl;
  final List<String> galleryUrls;

  /// Cover photo first, then the rest of the gallery, without repeats.
  List<String> get photos => [if (imageUrl != null) imageUrl!, ...galleryUrls.where((url) => url != imageUrl)];

  factory TransactionProperty.fromApi(Map<String, dynamic> json) => TransactionProperty(
    id: json['id'] as String,
    listingNumber: json['listingNumber'] as int? ?? 0,
    title: json['title'] as String? ?? 'Property',
    location: json['location'] as String? ?? '',
    state: json['state'] as String? ?? '',
    category: json['category'] as String? ?? '',
    price: json['price'] as int? ?? 0,
    priceUnit: json['priceUnit'] as String? ?? '',
    bedrooms: json['bedrooms'] as int? ?? 0,
    bathrooms: json['bathrooms'] as int? ?? 0,
    imageUrl: json['imageUrl'] as String?,
    galleryUrls: (json['galleryUrls'] as List?)?.cast<String>() ?? const [],
  );
}

class AdminTransaction {
  const AdminTransaction({
    required this.id,
    required this.status,
    required this.amountKobo,
    required this.platformFeeKobo,
    required this.landlordShareKobo,
    required this.reference,
    required this.paidAt,
    required this.tenant,
    required this.landlord,
    this.payoutReference,
    this.creditedAt,
    this.refundedAt,
    this.refundReason,
    this.heldForVerification = false,
    this.landlordBankName,
    this.landlordAccountName,
    this.landlordAccountLast4,
    this.paymentPlan,
    this.nights,
    this.leaseStartDate,
    this.leaseEndDate,
    this.property,
  });

  final String id;
  final TransactionStatus status;
  final int amountKobo;
  final int platformFeeKobo;
  final int landlordShareKobo;

  /// The Paystack reference of the tenant's charge.
  final String reference;

  /// The Paystack transfer reference of the payout to the landlord.
  final String? payoutReference;
  final DateTime paidAt;

  /// When the landlord's share was sent to their bank account.
  final DateTime? creditedAt;
  final DateTime? refundedAt;
  final String? refundReason;

  /// Held because the landlord isn't verified yet.
  final bool heldForVerification;
  final TransactionPerson tenant;
  final TransactionPerson landlord;
  final String? landlordBankName;
  final String? landlordAccountName;
  final String? landlordAccountLast4;

  /// FULL or MONTHLY.
  final String? paymentPlan;
  final int? nights;
  final DateTime? leaseStartDate;
  final DateTime? leaseEndDate;

  /// Null only if the booking behind this payment no longer exists.
  final TransactionProperty? property;

  String get statusLabel => switch (status) {
    TransactionStatus.credited => 'Credited to landlord',
    TransactionStatus.refunded => 'Refunded to tenant',
    TransactionStatus.held => heldForVerification ? 'Held: landlord not verified' : 'Held in escrow',
  };

  factory AdminTransaction.fromApi(Map<String, dynamic> json) {
    DateTime? date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    final landlord = json['landlord'] as Map<String, dynamic>;
    final booking = json['booking'] as Map<String, dynamic>?;
    final property = json['property'] as Map<String, dynamic>?;
    return AdminTransaction(
      id: json['id'] as String,
      status: switch (json['status']) {
        'RELEASED' => TransactionStatus.credited,
        'REFUNDED' => TransactionStatus.refunded,
        _ => TransactionStatus.held,
      },
      amountKobo: json['amountKobo'] as int? ?? 0,
      platformFeeKobo: json['platformFeeKobo'] as int? ?? 0,
      landlordShareKobo: json['landlordShareKobo'] as int? ?? 0,
      reference: json['reference'] as String? ?? '',
      payoutReference: json['payoutReference'] as String?,
      paidAt: date(json['paidAt']) ?? DateTime.now(),
      creditedAt: date(json['creditedAt']),
      refundedAt: date(json['refundedAt']),
      refundReason: json['refundReason'] as String?,
      heldForVerification: json['heldForVerification'] as bool? ?? false,
      tenant: TransactionPerson.fromApi(json['tenant'] as Map<String, dynamic>),
      landlord: TransactionPerson.fromApi(landlord),
      landlordBankName: landlord['bankName'] as String?,
      landlordAccountName: landlord['accountName'] as String?,
      landlordAccountLast4: landlord['accountLast4'] as String?,
      paymentPlan: booking?['paymentPlan'] as String?,
      nights: booking?['nights'] as int?,
      leaseStartDate: date(booking?['leaseStartDate']),
      leaseEndDate: date(booking?['leaseEndDate']),
      property: property == null ? null : TransactionProperty.fromApi(property),
    );
  }
}
