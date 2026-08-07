import '../../core/network/api_client.dart';

class ReportRepository {
  ReportRepository(this._api);
  final ApiClient _api;

  Future<void> createReport({
    required String type,
    required double lat,
    required double lng,
    required String description,
    String? imgUrl,
  }) async {
    await _api.post<dynamic>(
      '/reports',
      body: {
        'type': type,
        'lat': lat,
        'lng': lng,
        'description': description,
        if (imgUrl != null) 'img_url': imgUrl,
      },
    );
  }

  /// PATCH /reports/:id — description, img_url 만 (본인)
  Future<void> updateReport(
    int id, {
    String? description,
    String? imgUrl,
    bool clearImage = false,
  }) async {
    await _api.patch<dynamic>(
      '/reports/$id',
      body: {
        if (description != null) 'description': description,
        if (clearImage) 'img_url': null,
        if (!clearImage && imgUrl != null) 'img_url': imgUrl,
      },
    );
  }

  Future<void> deleteReport(int id) async {
    await _api.delete<dynamic>('/reports/$id');
  }

  Future<String> uploadReportImage(String filePath) async {
    final data = await _api.uploadImage('/uploads/image/report', filePath);
    return data['img_url'] as String? ?? data['image_path'] as String? ?? '';
  }
}