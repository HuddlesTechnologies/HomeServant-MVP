import 'api_client.dart';
import 'models/review.dart';

class ReviewsRepository {
  ReviewsRepository(this._client);

  final ApiClient _client;

  Future<List<Review>> forProperty(String propertyId) {
    return _client.call(() async {
      final response = await _client.dio.get('/reviews', queryParameters: {'propertyId': propertyId});
      return (response.data as List).cast<Map<String, dynamic>>().map(Review.fromApi).toList();
    });
  }

  Future<List<Review>> mine() {
    return _client.call(() async {
      final response = await _client.dio.get('/reviews/mine');
      return (response.data as List).cast<Map<String, dynamic>>().map(Review.fromApi).toList();
    });
  }

  Future<Review> upsert({required String propertyId, required int rating, String? comment}) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/reviews',
        data: {'propertyId': propertyId, 'rating': rating, if (comment != null && comment.isNotEmpty) 'comment': comment},
      );
      return Review.fromApi(response.data as Map<String, dynamic>);
    });
  }
}
