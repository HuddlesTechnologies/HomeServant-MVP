class Review {
  const Review({
    required this.id,
    required this.propertyId,
    required this.authorId,
    required this.authorName,
    required this.rating,
    required this.createdAt,
    this.comment,
  });

  final String id;
  final String propertyId;
  final String authorId;
  final String authorName;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  factory Review.fromApi(Map<String, dynamic> json) => Review(
    id: json['id'] as String,
    propertyId: json['propertyId'] as String,
    authorId: json['authorId'] as String,
    authorName: (json['author'] as Map<String, dynamic>?)?['fullName'] as String? ?? 'Tenant',
    rating: json['rating'] as int,
    comment: json['comment'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
