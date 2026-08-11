import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/env.dart';
import '../../core/geo/geo_utils.dart';
import '../../core/network/api_exception.dart';
import '../models/route_models.dart';

/// TMAP 보행자 경로 (SK open API). BE 프록시 없음 · 앱 직접 호출.
/// 직행 + (선택) 경유 후보로 대안 경로를 만든다.
class DirectionRepository {
  DirectionRepository({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _pedestrianUrl =
      'https://apis.openapi.sk.com/tmap/routes/pedestrian';

  /// 직행 후보: 추천(0) · 최단거리(10)
  static const _directOptions = ['0', '10'];

  static String labelForSearchOption(String opt) => switch (opt) {
        '0' => '추천',
        '10' => '최단거리',
        _ => '경로',
      };

  Future<List<RouteCandidate>> fetch({
    required LatLng origin,
    required LatLng destination,
    required NavMode mode,
    List<LatLng> viaPoints = const [],
  }) async {
    if (!isValidLatLng(origin.latitude, origin.longitude) ||
        !isValidLatLng(destination.latitude, destination.longitude)) {
      throw ApiException('출발/도착 좌표가 올바르지 않습니다.');
    }

    final key = Env.tmapAppKey.trim();
    if (key.isEmpty) {
      throw ApiException('TMAP_APP_KEY 가 없습니다.');
    }

    final merged = <RouteCandidate>[];
    Object? lastError;
    int? lastStatus;

    Future<void> addFrom(Future<List<RouteCandidate>> Function() call) async {
      try {
        final list = await call();
        for (final c in list) {
          if (!isDuplicate(merged, c)) merged.add(c);
        }
      } on DioException catch (e) {
        lastStatus = e.response?.statusCode;
        final data = e.response?.data;
        if (data is Map) {
          lastError = data['error'] ?? data['message'] ?? data['msg'];
        } else {
          lastError = e.message;
        }
      } catch (e) {
        lastError = e;
      }
    }

    for (final opt in _directOptions) {
      await addFrom(
        () => _fetchPedestrian(
          origin: origin,
          destination: destination,
          appKey: key,
          searchOption: opt,
          idSuffix: 'direct_$opt',
          displayLabel: labelForSearchOption(opt),
        ),
      );
    }

    for (var i = 0; i < viaPoints.length; i++) {
      final via = viaPoints[i];
      if (!isValidLatLng(via.latitude, via.longitude)) continue;
      await addFrom(
        () => _fetchPedestrian(
          origin: origin,
          destination: destination,
          appKey: key,
          searchOption: '0',
          waypoints: [via],
          idSuffix: 'via_$i',
          displayLabel: '대안 ${i + 1}',
        ),
      );
    }

    if (merged.isEmpty) {
      throw ApiException(
        lastError?.toString() ??
            '길찾기 요청 실패${lastStatus != null ? ' ($lastStatus)' : ''}',
        statusCode: lastStatus,
      );
    }
    return merged;
  }

  Future<List<RouteCandidate>> _fetchPedestrian({
    required LatLng origin,
    required LatLng destination,
    required String appKey,
    required String searchOption,
    required String idSuffix,
    required String displayLabel,
    List<LatLng> waypoints = const [],
  }) async {
    final body = <String, dynamic>{
      'startX': origin.longitude.toString(),
      'startY': origin.latitude.toString(),
      'endX': destination.longitude.toString(),
      'endY': destination.latitude.toString(),
      'startName': Uri.encodeComponent('출발'),
      'endName': Uri.encodeComponent('도착'),
      'reqCoordType': 'WGS84GEO',
      'resCoordType': 'WGS84GEO',
      'searchOption': searchOption,
      'sort': 'index',
    };
    if (waypoints.isNotEmpty) {
      body['passList'] = waypoints
          .map((w) => '${w.longitude},${w.latitude}')
          .join('_');
    }

    final res = await _dio.post<Map<String, dynamic>>(
      _pedestrianUrl,
      queryParameters: {'version': '1'},
      data: body,
      options: Options(
        headers: {
          'appKey': appKey,
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    final parsed = _parseTmapPedestrian(res.data, idSuffix, displayLabel);
    return parsed == null ? const [] : [parsed];
  }

  RouteCandidate? _parseTmapPedestrian(
    Map<String, dynamic>? data,
    String idSuffix,
    String displayLabel,
  ) {
    if (data == null) return null;
    final features = data['features'];
    if (features is! List || features.isEmpty) return null;

    double distanceM = 0;
    double? durationSec;
    final points = <LatLng>[];
    final rawSteps = <({LatLng point, String description, int? turnType})>[];

    for (final raw in features) {
      if (raw is! Map) continue;
      final feature = Map<String, dynamic>.from(raw);
      final geometry = feature['geometry'];
      final properties = feature['properties'];
      Map<String, dynamic>? props;
      if (properties is Map) {
        props = Map<String, dynamic>.from(properties);
        final td = (props['totalDistance'] as num?)?.toDouble();
        final tt = (props['totalTime'] as num?)?.toDouble();
        if (td != null && td > distanceM) distanceM = td;
        if (tt != null) durationSec ??= tt;
      }

      if (geometry is! Map) continue;
      final type = geometry['type']?.toString();
      final coords = geometry['coordinates'];

      if (type == 'Point' && coords is List && coords.length >= 2) {
        final lng = (coords[0] as num?)?.toDouble();
        final lat = (coords[1] as num?)?.toDouble();
        if (lat == null || lng == null || !isValidLatLng(lat, lng)) continue;
        final desc = (props?['description'] as String?)?.trim() ?? '';
        if (desc.isEmpty) continue;
        final turn = (props?['turnType'] as num?)?.toInt();
        rawSteps.add((
          point: LatLng(lat, lng),
          description: desc,
          turnType: turn,
        ));
        continue;
      }

      if (type != 'LineString' || coords is! List) continue;

      for (final c in coords) {
        if (c is! List || c.length < 2) continue;
        final lng = (c[0] as num?)?.toDouble();
        final lat = (c[1] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        if (!isValidLatLng(lat, lng)) continue;
        if (points.isNotEmpty &&
            points.last.latitude == lat &&
            points.last.longitude == lng) {
          continue;
        }
        points.add(LatLng(lat, lng));
      }
    }

    if (points.length < 2) return null;
    if (distanceM <= 0) {
      distanceM = _polylineLengthM(points);
    }

    final steps = <RouteStep>[
      for (final s in rawSteps)
        RouteStep(
          point: s.point,
          description: s.description,
          turnType: s.turnType,
          alongRouteM: _alongNearest(points, s.point),
        ),
    ]..sort((a, b) => a.alongRouteM.compareTo(b.alongRouteM));

    return RouteCandidate(
      id: 'tmap_$idSuffix',
      points: points,
      distanceM: distanceM,
      durationSec: durationSec,
      displayLabel: displayLabel,
      steps: steps,
    );
  }

  double _alongNearest(List<LatLng> poly, LatLng p) {
    if (poly.length < 2) return 0;
    var bestDist = double.infinity;
    var bestAlong = 0.0;
    var along = 0.0;
    for (var i = 1; i < poly.length; i++) {
      final a = poly[i - 1];
      final b = poly[i];
      final segM =
          distKm(a.latitude, a.longitude, b.latitude, b.longitude) * 1000;
      if (segM <= 0) continue;
      final dx = b.longitude - a.longitude;
      final dy = b.latitude - a.latitude;
      final len2 = dx * dx + dy * dy;
      final t = len2 <= 0
          ? 0.0
          : (((p.longitude - a.longitude) * dx +
                      (p.latitude - a.latitude) * dy) /
                  len2)
              .clamp(0.0, 1.0);
      final proj = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
      final d =
          distKm(p.latitude, p.longitude, proj.latitude, proj.longitude) * 1000;
      if (d < bestDist) {
        bestDist = d;
        bestAlong = along + segM * t;
      }
      along += segM;
    }
    return bestAlong;
  }

  static bool isDuplicate(List<RouteCandidate> existing, RouteCandidate next) {
    for (final e in existing) {
      if ((e.distanceM - next.distanceM).abs() < 25 &&
          e.durationSec != null &&
          next.durationSec != null &&
          (e.durationSec! - next.durationSec!).abs() < 20) {
        return true;
      }
      if (e.points.length >= 2 &&
          next.points.length >= 2 &&
          (e.distanceM - next.distanceM).abs() < 40) {
        final eMid = e.points[e.points.length ~/ 2];
        final nMid = next.points[next.points.length ~/ 2];
        final midM = distKm(
              eMid.latitude,
              eMid.longitude,
              nMid.latitude,
              nMid.longitude,
            ) *
            1000;
        if (midM < 60) return true;
      }
    }
    return false;
  }

  double _polylineLengthM(List<LatLng> pts) {
    var m = 0.0;
    for (var i = 1; i < pts.length; i++) {
      m += distKm(
            pts[i - 1].latitude,
            pts[i - 1].longitude,
            pts[i].latitude,
            pts[i].longitude,
          ) *
          1000;
    }
    return m;
  }
}
