import '../../core/network/api_client.dart';
import '../models/models.dart';

class FeedbackRepository {
  FeedbackRepository(this._api);
  final ApiClient _api;

  /// GET /feedbacks/tags
  Future<List<FeedbackTag>> fetchTags() async {
    final data = await _api.get<dynamic>('/feedbacks/tags');
    if (data is! List) return const [];
    return data
        .map((e) => FeedbackTag.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// POST /grids/:id/feedbacks
  Future<void> createFeedback({
    required int gridId,
    required String safetyFeeling,
    String? comment,
    List<int>? tagIds,
    String? imgUrl,
  }) async {
    await _api.post<dynamic>(
      '/grids/$gridId/feedbacks',
      body: {
        'safety_feeling': safetyFeeling,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
        if (tagIds != null && tagIds.isNotEmpty) 'tag_ids': tagIds,
        if (imgUrl != null && imgUrl.isNotEmpty) 'img_url': imgUrl,
      },
    );
  }

  /// PATCH /feedbacks/:id — 본인 수정
  Future<void> updateFeedback(
    int id, {
    String? safetyFeeling,
    String? comment,
    String? imgUrl,
    bool clearImage = false,
    List<int>? tagIds,
  }) async {
    await _api.patch<dynamic>(
      '/feedbacks/$id',
      body: {
        if (safetyFeeling != null) 'safety_feeling': safetyFeeling,
        if (comment != null) 'comment': comment,
        if (clearImage) 'img_url': null,
        if (!clearImage && imgUrl != null) 'img_url': imgUrl,
        if (tagIds != null) 'tag_ids': tagIds,
      },
    );
  }

  Future<void> deleteFeedback(int id) async {
    await _api.delete<dynamic>('/feedbacks/$id');
  }

  /// 제보와 동일: POST /uploads/image/report (얼굴 모자이크)
  Future<String> uploadFeedbackImage(String filePath) async {
    final data = await _api.uploadImage('/uploads/image/report', filePath);
    return data['img_url'] as String? ?? data['image_path'] as String? ?? '';
  }
}
