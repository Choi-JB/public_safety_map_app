import '../../core/network/api_client.dart';
import '../models/models.dart';

class MyPageRepository {
  MyPageRepository(this._api);
  final ApiClient _api;

  Future<MyPageSummary> fetchSummary() async {
    final data = await _api.get<Map<String, dynamic>>('/mypage');
    return MyPageSummary.fromJson(data);
  }

  Future<List<MyReport>> fetchReports({int page = 1, int limit = 10}) async {
    final data = await _api.get<dynamic>(
      '/mypage/report',
      query: {'page': page, 'limit': limit},
    );
    final list = _listFrom(data, 'reports');
    return list.map(MyReport.fromJson).toList();
  }

  Future<List<MyFeedback>> fetchFeedbacks({int page = 1, int limit = 10}) async {
    final data = await _api.get<dynamic>(
      '/mypage/feedback',
      query: {'page': page, 'limit': limit},
    );
    final list = _listFrom(data, 'feedbacks');
    return list.map(MyFeedback.fromJson).toList();
  }

  List<Map<String, dynamic>> _listFrom(dynamic data, String key) {
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is Map && data[key] is List) {
      return (data[key] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const [];
  }
}
