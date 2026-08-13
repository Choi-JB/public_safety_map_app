import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/config/env.dart';
import '../core/geo/geo_utils.dart';
import '../core/geo/region_code.dart';
import '../core/network/api_exception.dart';
import '../core/network/user_error.dart';
import '../data/models/models.dart';
import '../data/repositories/map_repository.dart';
import '../services/nearby_report_alert.dart';

const kInfraTypes = ['CCTV', '경찰서', '소방서', '편의점'];
const kSafetyGrades = ['안전', '보통', '불안'];

/// 웹 ACCIDENT_ZONE_TYPES
const kAccidentZoneTypes = [
  'pedestrian',
  'bicycle',
  'motorcycle',
  'schoolzone',
];

const kAccidentZoneLabel = {
  'pedestrian': '보행자',
  'bicycle': '자전거',
  'motorcycle': '이륜차',
  'schoolzone': '어린이보호구역',
};

class MapProvider extends ChangeNotifier {
  MapProvider(this._mapRepo, {NearbyReportAlert? nearbyAlert})
      : _nearbyAlert = nearbyAlert;

  final MapRepository _mapRepo;
  NearbyReportAlert? _nearbyAlert;

  void bindNearbyAlert(NearbyReportAlert alert) {
    _nearbyAlert = alert;
  }

  LatLng center = defaultMapCenter();
  double zoom = 17;

  bool gridsVisible = true;
  bool infraVisible = false;
  bool accidentZonesVisible = false;
  bool loading = false;
  String? error;

  /// 격자 등급 필터 (웹 MapControls)
  final Set<String> visibleGrades = {...kSafetyGrades};

  /// 인프라 타입 필터
  final Set<String> visibleInfraTypes = {...kInfraTypes};

  /// 사고다발 타입 필터 (웹 visibleAccidentTypes)
  final Set<String> visibleAccidentTypes = {...kAccidentZoneTypes};

  List<GridItem> grids = [];
  List<ReportItem> reports = [];
  List<CityEventItem> events = [];
  List<InfrastructureItem> infrastructures = [];
  List<AccidentZoneItem> accidentZones = [];
  GridDetail? selectedGridDetail;
  List<InfrastructureItem> selectedGridInfras = [];

  /// 캐시용 마지막 행정 키 (siDo|guGun)
  String? _lastAccidentRegionKey;
  Timer? _accidentDebounce;
  int _accidentReqId = 0;

  List<GridItem> get displayGrids {
    if (!gridsVisible) return const [];
    return grids.where((g) {
      if (!isValidLatLng(g.lat, g.lng)) return false;
      final grade = g.safetyGrade ?? '보통';
      return visibleGrades.contains(grade);
    }).toList();
  }

  List<InfrastructureItem> get displayInfras {
    if (!infraVisible) return const [];
    return infrastructures
        .where(
          (i) =>
              isValidLatLng(i.lat, i.lng) &&
              visibleInfraTypes.contains(i.type ?? ''),
        )
        .toList();
  }

  /// 지도에 그릴 다발 (타입 필터 반영)
  List<AccidentZoneItem> get displayAccidentZones {
    if (!accidentZonesVisible) return const [];
    return accidentZones
        .where((z) => visibleAccidentTypes.contains(z.type))
        .toList();
  }

  void setCenter(LatLng c) {
    if (!isValidLatLng(c.latitude, c.longitude)) return;
    center = c;
    notifyListeners();
  }

  void setZoom(double z) {
    zoom = safeZoom(z, fallback: zoom.isFinite ? zoom : 14);
  }

  void toggleGrids() {
    gridsVisible = !gridsVisible;
    notifyListeners();
  }

  void setGridsVisible(bool v) {
    gridsVisible = v;
    notifyListeners();
  }

  void toggleGradeFilter(String grade) {
    if (visibleGrades.contains(grade)) {
      if (visibleGrades.length == 1) return;
      visibleGrades.remove(grade);
    } else {
      visibleGrades.add(grade);
    }
    notifyListeners();
  }

  void toggleInfra() {
    infraVisible = !infraVisible;
    if (infraVisible) {
      refreshInfra();
    } else {
      infrastructures = [];
      notifyListeners();
    }
  }

  void setInfraVisible(bool v) {
    infraVisible = v;
    if (v) {
      refreshInfra();
    } else {
      infrastructures = [];
      notifyListeners();
    }
  }

  void toggleInfraType(String type) {
    if (visibleInfraTypes.contains(type)) {
      if (visibleInfraTypes.length == 1) return;
      visibleInfraTypes.remove(type);
    } else {
      visibleInfraTypes.add(type);
    }
    notifyListeners();
  }

  void toggleAccidentZones() {
    accidentZonesVisible = !accidentZonesVisible;
    unawaited(
      _nearbyAlert?.setAccidentAlertsEnabled(accidentZonesVisible) ??
          Future.value(),
    );
    if (accidentZonesVisible) {
      scheduleAccidentZonesRefresh(force: true);
      final c = center;
      if (isValidLatLng(c.latitude, c.longitude)) {
        unawaited(_nearbyAlert?.checkNear(c, force: true) ?? Future.value());
      }
      notifyListeners();
    } else {
      _cancelAccidentDebounce();
      _lastAccidentRegionKey = null;
      accidentZones = [];
      notifyListeners();
    }
  }

  void toggleAccidentType(String type) {
    if (visibleAccidentTypes.contains(type)) {
      if (visibleAccidentTypes.length == 1) return;
      visibleAccidentTypes.remove(type);
    } else {
      visibleAccidentTypes.add(type);
    }
    notifyListeners();
  }

  /// 웹: 중심 2초 디바운스 후 구 변경 시만 API
  void scheduleAccidentZonesRefresh({bool force = false}) {
    if (!accidentZonesVisible) return;
    _cancelAccidentDebounce();
    _accidentDebounce = Timer(
      Duration(milliseconds: Env.accidentRegionDebounceMs),
      () => unawaited(refreshAccidentZones(forceRegion: force)),
    );
  }

  void _cancelAccidentDebounce() {
    _accidentDebounce?.cancel();
    _accidentDebounce = null;
  }

  Future<void> refreshFromViewport({
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required LatLng newCenter,
  }) async {
    if (!isValidLatLng(newCenter.latitude, newCenter.longitude)) return;
    if (!_isValidBounds(swLat, swLng, neLat, neLng)) return;

    center = newCenter;
    loading = true;
    error = null;
    notifyListeners();

    try {
      final futures = <Future>[
        _mapRepo.fetchGrids(
          swLat: swLat,
          swLng: swLng,
          neLat: neLat,
          neLng: neLng,
        ),
        _mapRepo.fetchReports(
          swLat: swLat,
          swLng: swLng,
          neLat: neLat,
          neLng: neLng,
        ),
        _mapRepo.fetchCityEvents(
          swLat: swLat,
          swLng: swLng,
          neLat: neLat,
          neLng: neLng,
        ),
      ];
      final results = await Future.wait(futures);
      grids = (results[0] as List<GridItem>)
          .where((g) => isValidLatLng(g.lat, g.lng))
          .toList();
      reports = (results[1] as List<ReportItem>)
          .where((r) => isValidLatLng(r.lat, r.lng))
          .toList();
      events = (results[2] as List<CityEventItem>)
          .where((e) => isValidLatLng(e.lat, e.lng))
          .toList();

      if (infraVisible) await refreshInfra(silent: true);
      if (accidentZonesVisible) scheduleAccidentZonesRefresh();
    } on ApiException catch (e) {
      error = userFacingError(e);
    } catch (e) {
      error = userFacingError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshInfra({bool silent = false}) async {
    if (!isValidLatLng(center.latitude, center.longitude)) return;
    try {
      final list = await _mapRepo.fetchInfrastructures(
        lat: center.latitude,
        lng: center.longitude,
        radiusM: _radiusForZoom(safeZoom(zoom)),
      );
      infrastructures =
          list.where((i) => isValidLatLng(i.lat, i.lng)).toList();
    } on ApiException catch (e) {
      if (!silent) error = userFacingError(e);
    } catch (e) {
      if (!silent) error = userFacingError(e);
    }
    if (!silent) notifyListeners();
  }

  /// 웹 사고다발: 중심 reverse-geo → siDo/guGun → GET /accident-zones
  Future<void> refreshAccidentZones({
    bool silent = false,
    bool forceRegion = false,
  }) async {
    if (!accidentZonesVisible) return;
    if (!isValidLatLng(center.latitude, center.longitude)) return;

    final z = safeZoom(zoom);
    // 너무 멀리 줌아웃 시 숨김 (앱 minZoom=13 이면 실질 미적용 가능)
    if (z < Env.accidentHideMaxZoom) {
      accidentZones = [];
      _lastAccidentRegionKey = null;
      if (!silent) notifyListeners();
      return;
    }

    final req = ++_accidentReqId;
    final lat = center.latitude;
    final lng = center.longitude;

    try {
      final region = await coordToSiDoGuGun(lat: lat, lng: lng);
      if (req != _accidentReqId) return;
      if (region == null) {
        if (!silent) error = '위치의 행정구역을 확인할 수 없습니다';
        accidentZones = [];
        if (!silent) notifyListeners();
        return;
      }

      final regionKey = '${region.siDo}|${region.guGun}';
      if (!forceRegion && _lastAccidentRegionKey == regionKey) {
        // 같은 구 → 타입/거리만 재필터하면 됨 (이미 갖고 있음)
        _refilterAccidentZones(lat, lng);
        if (!silent) notifyListeners();
        return;
      }

      final list = await _mapRepo.fetchAccidentZones(
        siDo: region.siDo,
        guGun: region.guGun,
      );
      if (req != _accidentReqId) return;

      final radiusKm = Env.accidentZoneRadiusKm;
      final sanitized = <AccidentZoneItem>[];
      for (final z0 in list) {
        final z = _sanitizeAccidentZone(z0);
        if (z == null) continue;
        // 중심 반경 이내 (앱 기본 4km)
        if (z.lat == null || z.lng == null) continue;
        if (distKm(lat, lng, z.lat!, z.lng!) > radiusKm) continue;
        sanitized.add(z);
      }

      accidentZones = sanitized;
      _lastAccidentRegionKey = regionKey;
    } on ApiException catch (e) {
      if (!silent) error = userFacingError(e);
    } catch (e) {
      if (!silent) error = userFacingError(e);
    }
    if (!silent) notifyListeners();
  }

  void _refilterAccidentZones(double lat, double lng) {
    final radiusKm = Env.accidentZoneRadiusKm;
    accidentZones = accidentZones.where((z) {
      if (z.lat == null || z.lng == null) return false;
      return distKm(lat, lng, z.lat!, z.lng!) <= radiusKm;
    }).toList();
  }

  Future<void> selectGrid(int gridId) async {
    try {
      final detail = await _mapRepo.fetchGridDetail(gridId);
      List<InfrastructureItem> infras = const [];
      try {
        infras = await _mapRepo.fetchGridInfrastructures(gridId);
      } catch (_) {
        // 인프라는 선택
      }
      selectedGridDetail = detail;
      selectedGridInfras =
          infras.where((i) => isValidLatLng(i.lat, i.lng)).toList();
      notifyListeners();
    } on ApiException catch (e) {
      error = userFacingError(e);
      notifyListeners();
    }
  }

  void clearSelectedGrid() {
    selectedGridDetail = null;
    selectedGridInfras = [];
    notifyListeners();
  }

  /// Nominatim (앱 전용, BE 변경 없음) — 웹 카카오 검색에 대응
  Future<LatLng?> searchPlace(String query) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'User-Agent': 'public_safety_map_app/1.0'},
        ),
      );
      final res = await dio.get<List<dynamic>>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': q,
          'format': 'json',
          'limit': 1,
          'countrycodes': 'kr',
        },
      );
      final list = res.data;
      if (list == null || list.isEmpty) return null;
      final first = list.first as Map;
      final lat = double.tryParse('${first['lat']}');
      final lon = double.tryParse('${first['lon']}');
      return tryLatLng(lat, lon);
    } catch (e) {
      error = userFacingError(e, fallback: '검색에 실패했습니다.');
      notifyListeners();
      return null;
    }
  }

  Map<String, int> infraStatsForSelectedGrid() {
    final counts = {for (final t in kInfraTypes) t: 0};
    for (final i in selectedGridInfras) {
      final t = i.type;
      if (t != null && counts.containsKey(t)) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  bool _isValidBounds(
    double swLat,
    double swLng,
    double neLat,
    double neLng,
  ) {
    if (![swLat, swLng, neLat, neLng].every((v) => v.isFinite)) return false;
    if (!isValidLatLng(swLat, swLng) || !isValidLatLng(neLat, neLng)) {
      return false;
    }
    if (swLat >= neLat || swLng >= neLng) return false;
    return true;
  }

  AccidentZoneItem? _sanitizeAccidentZone(AccidentZoneItem z) {
    final path =
        z.path.where((p) => isValidLatLng(p.lat, p.lng)).toList();
    if (path.length < 3) return null;
    final latLngOk = isValidLatLng(z.lat, z.lng);
    return AccidentZoneItem(
      id: z.id,
      type: z.type,
      name: z.name,
      path: path,
      yearCd: z.yearCd,
      lat: latLngOk ? z.lat : null,
      lng: latLngOk ? z.lng : null,
      occrrncCnt: z.occrrncCnt,
      casltCnt: z.casltCnt,
      dthDnvCnt: z.dthDnvCnt,
    );
  }

  /// 마이페이지 「위치로 이동」 등 → 기존 지도로 복귀할 때 적용할 포커스
  MapFocusTarget? _pendingFocus;

  /// 마이페이지 위치 이동 중 (GPS follow / 스피너 가드)
  bool mapFocusing = false;
  Timer? _mapFocusingTimeout;
  static const _mapFocusingMaxDuration = Duration(seconds: 5);

  /// 지도 이동 후 마이페이지 재진입 시 상세 시트 복원
  int? _pendingReopenReportId;
  int? _pendingReopenFeedbackId;

  MapFocusTarget? get pendingFocus => _pendingFocus;

  void requestMapFocus(MapFocusTarget target) {
    _pendingFocus = target;
    mapFocusing = true;
    _mapFocusingTimeout?.cancel();
    _mapFocusingTimeout = Timer(_mapFocusingMaxDuration, clearMapFocusing);
    notifyListeners();
  }

  MapFocusTarget? takePendingFocus() {
    final t = _pendingFocus;
    _pendingFocus = null;
    return t;
  }

  void clearMapFocusing() {
    _mapFocusingTimeout?.cancel();
    _mapFocusingTimeout = null;
    if (!mapFocusing) return;
    mapFocusing = false;
    notifyListeners();
  }

  void setPendingMypageReopen({int? reportId, int? feedbackId}) {
    _pendingReopenReportId = reportId;
    _pendingReopenFeedbackId = feedbackId;
  }

  ({int? reportId, int? feedbackId})? takePendingMypageReopen() {
    final reportId = _pendingReopenReportId;
    final feedbackId = _pendingReopenFeedbackId;
    if (reportId == null && feedbackId == null) return null;
    _pendingReopenReportId = null;
    _pendingReopenFeedbackId = null;
    return (reportId: reportId, feedbackId: feedbackId);
  }

  int _radiusForZoom(double z) {
    final safe = safeZoom(z);
    if (safe >= 17) return 280;
    if (safe >= 16) return 400;
    if (safe >= 15) return 600;
    if (safe >= 14) return 900;
    if (safe >= 13) return 1400;
    return 2000;
  }

  @override
  void dispose() {
    _mapFocusingTimeout?.cancel();
    _cancelAccidentDebounce();
    super.dispose();
  }
}
