import '../../core/network/api_client.dart';
import '../models/models.dart';

class MapRepository {
  MapRepository(this._api);
  final ApiClient _api;

  Future<List<GridItem>> fetchGrids({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
  }) async {
    final data = await _api.get<dynamic>(
      '/grids',
      query: {
        'sw_lat': swLat,
        'sw_lng': swLng,
        'ne_lat': neLat,
        'ne_lng': neLng,
      },
    );
    return _asList(data).map((e) => GridItem.fromJson(e)).toList();
  }

  Future<GridDetail> fetchGridDetail(int gridId) async {
    final data = await _api.get<Map<String, dynamic>>('/grids/$gridId/detail');
    return GridDetail.fromJson(data);
  }

  /// GET /grids/:id/infrastructures — 격자 내 인프라 (웹 인포카드 타입별 집계용)
  Future<List<InfrastructureItem>> fetchGridInfrastructures(int gridId) async {
    final data = await _api.get<dynamic>('/grids/$gridId/infrastructures');
    return _asList(data).map((e) => InfrastructureItem.fromJson(e)).toList();
  }

  Future<List<ReportItem>> fetchReports({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
  }) async {
    final data = await _api.get<dynamic>(
      '/reports',
      query: {
        'sw_lat': swLat,
        'sw_lng': swLng,
        'ne_lat': neLat,
        'ne_lng': neLng,
      },
    );
    return _asList(data).map((e) => ReportItem.fromJson(e)).toList();
  }

  Future<List<CityEventItem>> fetchCityEvents({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
  }) async {
    final data = await _api.get<dynamic>(
      '/city-events',
      query: {
        'sw_lat': swLat,
        'sw_lng': swLng,
        'ne_lat': neLat,
        'ne_lng': neLng,
      },
    );
    return _asList(data).map((e) => CityEventItem.fromJson(e)).toList();
  }

  Future<List<InfrastructureItem>> fetchInfrastructures({
    required double lat,
    required double lng,
    required int radiusM,
    String? type,
  }) async {
    final data = await _api.get<dynamic>(
      '/infrastructures',
      query: {
        'lat': lat,
        'lng': lng,
        'radius_m': radiusM,
        if (type != null) 'type': type,
      },
    );
    return _asList(data).map((e) => InfrastructureItem.fromJson(e)).toList();
  }

  Future<List<AccidentZoneItem>> fetchAccidentZones({
    required String siDo,
    required String guGun,
    String? type,
  }) async {
    final data = await _api.get<Map<String, dynamic>>(
      '/accident-zones',
      query: {
        'siDo': siDo,
        'guGun': guGun,
        if (type != null) 'type': type,
      },
    );
    final items = data['items'] as List? ?? [];
    return items
        .map((e) => AccidentZoneItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }
}
