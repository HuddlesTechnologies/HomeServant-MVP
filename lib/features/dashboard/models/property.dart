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
    );
  }

  /// Body for `POST /properties` (see CreatePropertyDto) — omits
  /// server-assigned fields (id, landlordId, rating).
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
  };

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

