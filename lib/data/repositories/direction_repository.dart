import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/env.dart';
import '../../core/geo/geo_utils.dart';
import '../../core/network/api_exception.dart';
import '../models/route_models.dart';
import '../../services/tmap_route_cache.dart';

/// TMAP 보행자 경로 (SK open API). BE 프록시 없음 · 앱 직접 호출.
/// 직행 + (선택) 경유 후보로 대안 경로를 만든다.
class DirectionRepository {
  DirectionRepository({Dio? dio, TmapRouteCache? cache})
      : _dio = dio ?? Dio(),
        _cache = cache ?? TmapRouteCache.instance;

  final Dio _dio;
  final TmapRouteCache _cache;

  static const _pedestrianUrl =
      'https://apis.openapi.sk.com/tmap/routes/pedestrian';

  /// 직행 후보: 최단거리(10) 먼저 · 실패 시 추천·경유 요청 생략 · 성공 시 추천(0)
  static const _directOptions = ['10', '0'];

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
    String? lastError;
    int? lastStatus;

    Future<void> addPedestrian({
      required String searchOption,
      required String idSuffix,
      required String displayLabel,
      List<LatLng> waypoints = const [],
    }) async {
      final cacheKey = _cache.makeKey(
        startLat: origin.latitude,
        startLng: origin.longitude,
        endLat: destination.latitude,
        endLng: destination.longitude,
        searchOption: searchOption,
        waypointKeys: [
          for (final w in waypoints)
            TmapRouteCache.waypointKey(w.latitude, w.longitude),
        ],
      );

      final hit = _cache.lookup(cacheKey);
      if (hit != null) {
        if (hit.error != null) {
          lastError = hit.error;
          return;
        }
        final route = hit.route;
        if (route != null && !isDuplicate(merged, route)) {
          merged.add(route);
        }
        return;
      }

      try {
        final list = await _fetchPedestrian(
          origin: origin,
          destination: destination,
          appKey: key,
          searchOption: searchOption,
          idSuffix: idSuffix,
          displayLabel: displayLabel,
          waypoints: waypoints,
        );
        if (list.isEmpty) {
          lastError ??= '경로를 찾지 못했습니다.';
          _cache.putFailure(
            cacheKey,
            lastError ?? '경로를 찾지 못했습니다.',
            negative: false,
          );
          return;
        }
        for (final c in list) {
          if (!isDuplicate(merged, c)) merged.add(c);
          _cache.putSuccess(cacheKey, c);
        }
      } on DioException catch (e) {
        lastStatus = e.response?.statusCode;
        lastError = _tmapUserMessage(e.response?.data);
        _cache.putFailure(
          cacheKey,
          lastError!,
          negative: _isFatalTmapCode(e.response?.data),
        );
      } catch (_) {
        lastError = '경로를 찾지 못했습니다.';
      }
    }

    for (var i = 0; i < _directOptions.length; i++) {
      final opt = _directOptions[i];
      await addPedestrian(
        searchOption: opt,
        idSuffix: 'direct_$opt',
        displayLabel: labelForSearchOption(opt),
      );
      // 최단거리(10) 실패 시 추천·경유 TMAP 호출 생략 (일일 한도 절약)
      if (i == 0 && merged.isEmpty) {
        throw ApiException(
          lastError ?? '경로를 찾지 못했습니다.',
          statusCode: lastStatus,
        );
      }
    }

    for (var i = 0; i < viaPoints.length; i++) {
      final via = viaPoints[i];
      if (!isValidLatLng(via.latitude, via.longitude)) continue;
      await addPedestrian(
        searchOption: '0',
        idSuffix: 'via_$i',
        displayLabel: '대안 ${i + 1}',
        waypoints: [via],
      );
    }
    if (merged.isEmpty) {
      throw ApiException(
        lastError ?? '경로를 찾지 못했습니다.',
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
  String _tmapUserMessage(dynamic data) {
    if (data is! Map) return '경로를 찾지 못했습니다.';

    final nested = data['error'];
    final source = nested is Map ? nested : data;
    final code = source['code']?.toString();

    switch (code) {
      case '3102':
      case '3002':
        return '보행 길찾기를 지원하지 않는 구간입니다.';
      case '1009':
        return '출발/도착 위치를 다시 선택해 주세요.';
      default:
        return '경로를 찾지 못했습니다.';
    }
  }

  bool _isFatalTmapCode(dynamic data) {
    if (data is! Map) return false;
    final nested = data['error'];
    final source = nested is Map ? nested : data;
    final code = source['code']?.toString();
    return code == '3102' || code == '3002' || code == '1009';
  }
}
