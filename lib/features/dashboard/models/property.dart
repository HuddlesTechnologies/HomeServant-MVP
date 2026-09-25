import '../../../core/thousands_separator.dart';

class Property {
  const Property({
    required this.id,
    required this.title,
    required this.location,
    required this.state,
    required this.rating,
    required this.image,
    required this.category,
    required this.price,
    required this.priceUnit,
    required this.bedrooms,
    required this.bathrooms,
    required this.description,
    required this.landlordName,
    this.galleryImages = const [],
    this.videoPath,
    this.landlordId,
    this.reviewCount = 0,
    this.isOccupied = false,
    this.rentDurationMonths,
    this.messagingEnabled = true,
    this.unitAddress,
    this.roomNumber,
    this.shortletUnavailable = false,
    this.shortletUnavailableUntil,
  });

  /// Builds a [Property] from a `GET /properties` / `GET /properties/:id`
  /// response (see backend/src/properties/properties.service.ts) — the
  /// landlord's name comes from the included `landlord` relation, and
  /// rating/reviewCount from the aggregated review summary that endpoint
  /// merges in.
  factory Property.fromApi(Map<String, dynamic> json) {
    final category = json['category'] as String;
    return Property(
      id: json['id'] as String,
      title: json['title'] as String,
      location: json['location'] as String,
      state: json['state'] as String,
      rating: (json['avgRating'] as num?)?.toDouble() ?? 0,
      reviewCount: json['reviewCount'] as int? ?? 0,
      image: (json['imageUrl'] as String?) ?? 'assets/images/homepage.jpg',
      category: _categoryFromApi(category),
      price: json['price'] as int,
      priceUnit: (json['priceUnit'] as String) == 'NIGHT' ? 'night' : 'year',
      bedrooms: json['bedrooms'] as int,
      bathrooms: json['bathrooms'] as int,
      description: json['description'] as String,
      landlordName: (json['landlord'] as Map<String, dynamic>?)?['fullName'] as String? ?? 'Landlord',
      landlordId: (json['landlord'] as Map<String, dynamic>?)?['id'] as String? ?? json['landlordId'] as String?,
      galleryImages: ((json['galleryUrls'] as List?)?.cast<String>()) ?? const [],
      isOccupied: json['isOccupied'] as bool? ?? false,
      rentDurationMonths: json['rentDurationMonths'] as int?,
      messagingEnabled: json['messagingEnabled'] as bool? ?? true,
      unitAddress: json['unitAddress'] as String?,
      roomNumber: json['roomNumber'] as String?,
      // Field names for shortlet-availability are a best guess against the
      // backend contract described in the build plan (which flagged these
      // names as unconfirmed) — verify against the real Property response
      // once the backend agent's work lands, and adjust here if different.
      // Real backend field names (properties.service.ts): isCurrentlyUnavailable /
      // availableAgainAt. The others are kept as a defensive fallback only.
      shortletUnavailable: (json['isCurrentlyUnavailable'] as bool?) ??
          (json['shortletUnavailable'] as bool?) ??
          (json['isShortletUnavailable'] as bool?) ??
          false,
      shortletUnavailableUntil: _parseDate(json['availableAgainAt']) ??
          _parseDate(json['shortletUnavailableUntil']) ??
          _parseDate(json['unavailableUntil']),
    );
  }

  static DateTime? _parseDate(dynamic value) => value is String ? DateTime.tryParse(value) : null;

  /// Body for `POST /properties` (see CreatePropertyDto) — omits
  /// server-assigned fields (id, landlordId, rating). `rentDurationMonths`
  /// is required for every non-Shortlet category; `unitAddress`/`roomNumber`
  /// are required only for Shortlet.
  Map<String, dynamic> toCreateJson() => {
    'title': title,
    'location': location,
    'state': state,
    'category': categoryApiValue(category),
    'price': price,
    'priceUnit': priceUnit == 'night' ? 'NIGHT' : 'YEAR',
    'bedrooms': bedrooms,
    'bathrooms': bathrooms,
    'description': description,
    if (!image.startsWith('assets/')) 'imageUrl': image,
    if (galleryImages.isNotEmpty) 'galleryUrls': galleryImages,
    'messagingEnabled': messagingEnabled,
    if (category == 'Shortlet') ...{
      if (unitAddress != null) 'unitAddress': unitAddress,
      if (roomNumber != null) 'roomNumber': roomNumber,
    } else ...{
      if (rentDurationMonths != null) 'rentDurationMonths': rentDurationMonths,
    },
  };

  /// Body for `PATCH /properties/:id` — same shape as [toCreateJson] since
  /// there's no narrower UpdatePropertyDto documented; the backend is
  /// expected to accept a partial version of the same fields.
  Map<String, dynamic> toUpdateJson() => toCreateJson();

  Property copyWith({
    String? title,
    String? location,
    String? state,
    String? category,
    int? price,
    String? priceUnit,
    int? bedrooms,
    int? bathrooms,
    String? description,
    String? image,
    List<String>? galleryImages,
    String? videoPath,
    int? rentDurationMonths,
    bool? messagingEnabled,
    String? unitAddress,
    String? roomNumber,
  }) => Property(
    id: id,
    title: title ?? this.title,
    location: location ?? this.location,
    state: state ?? this.state,
    rating: rating,
    image: image ?? this.image,
    galleryImages: galleryImages ?? this.galleryImages,
    category: category ?? this.category,
    price: price ?? this.price,
    priceUnit: priceUnit ?? this.priceUnit,
    bedrooms: bedrooms ?? this.bedrooms,
    bathrooms: bathrooms ?? this.bathrooms,
    description: description ?? this.description,
    landlordName: landlordName,
    videoPath: videoPath ?? this.videoPath,
    landlordId: landlordId,
    reviewCount: reviewCount,
    isOccupied: isOccupied,
    rentDurationMonths: rentDurationMonths ?? this.rentDurationMonths,
    messagingEnabled: messagingEnabled ?? this.messagingEnabled,
    unitAddress: unitAddress ?? this.unitAddress,
    roomNumber: roomNumber ?? this.roomNumber,
    shortletUnavailable: shortletUnavailable,
    shortletUnavailableUntil: shortletUnavailableUntil,
  );

  static String _categoryFromApi(String value) => switch (value) {
    'HOUSE' => 'House',
    'SHORTLET' => 'Shortlet',
    'SELF_CON' => 'Self-Con',
    'APARTMENT' => 'Apartment',
    _ => value,
  };

  static String categoryApiValue(String value) => switch (value) {
    'House' => 'HOUSE',
    'Shortlet' => 'SHORTLET',
    'Self-Con' => 'SELF_CON',
    'Apartment' => 'APARTMENT',
    _ => value.toUpperCase(),
  };

  /// Stable key used to track this listing in the wishlist — titles alone
  /// aren't guaranteed unique once real listings replace the mock data.
  final String id;

  final String title;
  final String location;

  /// Nigerian state this listing is in — kept separate from [location] (the
  /// display string, e.g. "Agege, Lagos") so the filter sheet's state
  /// dropdown can match on it directly.
  final String state;

  final double rating;

  /// Local asset path for the card and the hero image on the detail screen.
  final String image;

  /// One of the dashboard's category tabs — House, Shortlet, Self-Con,
  /// Apartment — used to filter the feed.
  final String category;

  final int price;

  /// 'year' or 'night' — shortlets are priced per night, everything else
  /// per year.
  final String priceUnit;

  final int bedrooms;
  final int bathrooms;
  final String description;

  /// Name shown as the other party when a tenant taps "Message Landlord" on
  /// the detail screen.
  final String landlordName;

  /// Extra interior shots shown in the detail screen's preview strip.
  final List<String> galleryImages;

  /// A landlord-uploaded walkthrough clip, shown in the detail screen's
  /// "Property Tour" section when set. A local file path on mobile/desktop,
  /// a blob URL on web — same convention as every other upload in the app
  /// (see `imageProviderForPath`). None of the seed listings have one; it's
  /// only ever set by [LandlordAddPropertyScreen].
  final String? videoPath;

  /// The owning landlord's user id — absent on the bundled seed listings,
  /// present on anything loaded from the API. Used to filter "my
  /// properties" for the signed-in landlord.
  final String? landlordId;

  final int reviewCount;
  final bool isOccupied;

  /// Lease length in months (6-24), required at listing time for every
  /// category except Shortlet — drives the tenant's `leaseEndDate` once a
  /// booking reaches MOVED_IN.
  final int? rentDurationMonths;

  /// Per-property replacement for the old device-local
  /// `AppState.landlordMessagesEnabled` toggle — when false, a tenant can't
  /// message this landlord or book an inspection through chat, only pay
  /// rent directly.
  final bool messagingEnabled;

  /// Shortlet-only: the specific unit's address and room/unit number,
  /// required at listing time when [category] is Shortlet.
  final String? unitAddress;
  final String? roomNumber;

  /// Derived server-side from an active booking's `leaseEndDate` — true
  /// while this Shortlet is currently booked out. Field name is a best
  /// guess against the backend contract; see the doc comment on
  /// [Property.fromApi].
  final bool shortletUnavailable;

  /// Countdown target shown to the tenant while [shortletUnavailable] is
  /// true — null if not currently unavailable.
  final DateTime? shortletUnavailableUntil;

  String get priceLabel => '₦${formatNaira(price)}/$priceUnit';
}

/// Formats a whole naira amount with thousands separators, e.g. `2,500,000`.
String formatNaira(int amount) => formatWithThousandsSeparator(amount);

/// The 36 Nigerian states plus the FCT, for the dashboard's state filter.
/// All of today's mock listings are in Lagos — picking any other state is
/// expected to show no results, same as it would for a real, sparser market.
const nigerianStates = [
  'Abia',
  'Adamawa',
  'Akwa Ibom',
  'Anambra',
  'Bauchi',
  'Bayelsa',
  'Benue',
  'Borno',
  'Cross River',
  'Delta',
  'Ebonyi',
  'Edo',
  'Ekiti',
  'Enugu',
  'FCT (Abuja)',
  'Gombe',
  'Imo',
  'Jigawa',
  'Kaduna',
  'Kano',
  'Katsina',
  'Kebbi',
  'Kogi',
  'Kwara',
  'Lagos',
  'Nasarawa',
  'Niger',
  'Ogun',
  'Ondo',
  'Osun',
  'Oyo',
  'Plateau',
  'Rivers',
  'Sokoto',
  'Taraba',
  'Yobe',
  'Zamfara',
];

