import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo/geo_utils.dart';
import '../core/network/api_exception.dart';
import '../data/models/models.dart';
import '../data/models/route_models.dart';
import '../data/repositories/direction_repository.dart';
import '../data/repositories/map_repository.dart';
import '../services/guidance_progress.dart';
import '../services/route_scorer.dart';
import '../services/via_candidate_picker.dart';

class NavProvider extends ChangeNotifier {
  NavProvider(this._directions, this._mapRepo);

  final DirectionRepository _directions;
  final MapRepository _mapRepo;

  bool active = false;
  LatLng? origin;
  LatLng? destination;
  /// 보행 전용 (TMAP pedestrian)
  NavMode mode = NavMode.walk;
  RouteOption option = RouteOption.shortest;

  /// 길찾기 시트 높이(px). FAB 상승용. 비활성 시 0.
  double sheetHeight = 0;
  static const double _sheetHeightEstimate = 360;
  static const double _guideSheetEstimate = 76;

  /// TMAP·경유 원본 후보 (채점용)
  List<RouteCandidate> candidates = const [];
  /// 고정 4카드: 추천 · 최단거리 · CCTV 많은 곳 · 제보 최소화
  List<RouteCandidate> choiceCards = const [];
  RouteCandidate? selected;
  RouteCandidate? shortest;
  RouteCompareMeta? compare;
  String? message;
  bool loading = false;
  String? error;

  /// 턴바이턴 안내 중
  bool guiding = false;
  double remainingDistanceM = 0;
  double? remainingDurationSec;
  RouteStep? currentStep;
  double distanceToStepM = 0;
  bool arrived = false;

  void toggleActive({LatLng? myPos}) {
    active = !active;
    if (active) {
      if (myPos != null) origin = myPos;
      if (sheetHeight <= 0) sheetHeight = _sheetHeightEstimate;
    } else {
      sheetHeight = 0;
      destination = null;
      clearRoute();
    }
    notifyListeners();
  }

  void setSheetHeight(double h) {
    if (!active) return;
    if (h <= 0 || (h - sheetHeight).abs() < 1) return;
    sheetHeight = h;
    notifyListeners();
  }

  void setOrigin(LatLng? v) {
    origin = v;
    notifyListeners();
  }

  void setDestination(LatLng v) {
    destination = v;
    notifyListeners();
  }

  Future<void> setMode(NavMode m) async {
    if (m != NavMode.walk) return;
    if (mode == m) return;
    mode = NavMode.walk;
    if (!mode.options.contains(option)) {
      option = RouteOption.shortest;
    }
    notifyListeners();
    if (origin != null && destination != null) {
      await plan();
    }
  }

  /// 목록에서 경로 카드 선택
  void selectCandidate(RouteCandidate c) {
    selected = c;
    if (shortest != null) {
      compare = vsShortest(c, shortest!);
    }
    notifyListeners();
  }

  /// 카드에서 안내 시작
  void startGuidance(RouteCandidate c, {LatLng? myPos}) {
    selected = c;
    if (shortest != null) {
      compare = vsShortest(c, shortest!);
    }
    guiding = true;
    arrived = false;
    sheetHeight = _guideSheetEstimate;
    if (myPos != null) {
      updateGuideProgress(myPos);
    } else {
      remainingDistanceM = c.distanceM;
      remainingDurationSec = c.durationSec;
      currentStep = c.steps.isNotEmpty ? c.steps.first : null;
      distanceToStepM = currentStep?.alongRouteM ?? c.distanceM;
    }
    notifyListeners();
  }

  /// 안내 종료 = 길찾기 완전 종료 (경로 선택 시트·경로 선 제거)
  void stopGuidance() {
    _resetGuidanceFields();
    active = false;
    sheetHeight = 0;
    destination = null;
    candidates = const [];
    choiceCards = const [];
    selected = null;
    shortest = null;
    compare = null;
    message = null;
    error = null;
    notifyListeners();
  }

  void _resetGuidanceFields() {
    guiding = false;
    arrived = false;
    currentStep = null;
    distanceToStepM = 0;
    remainingDistanceM = 0;
    remainingDurationSec = null;
  }

  /// 새 목적지/재탐색: 안내는 끄고 길찾기(경로 선택) 모드는 유지
  void cancelGuidanceForReplan() {
    _resetGuidanceFields();
    selected = null;
    choiceCards = const [];
    candidates = const [];
    compare = null;
    message = null;
    error = null;
    if (active) {
      sheetHeight = _sheetHeightEstimate;
    }
    notifyListeners();
  }

  void updateGuideProgress(LatLng me) {
    if (!guiding) return;
    final route = selected;
    if (route == null || route.points.length < 2) return;

    final traveled = distanceTraveledAlongRoute(route.points, me);
    final remain = (route.distanceM - traveled).clamp(0.0, route.distanceM);
    remainingDistanceM = remain;

    if (route.durationSec != null && route.distanceM > 0) {
      remainingDurationSec = route.durationSec! * (remain / route.distanceM);
    }

    if (remain <= 25) {
      arrived = true;
      currentStep = null;
      distanceToStepM = 0;
      notifyListeners();
      return;
    }

    arrived = false;
    final step = nextGuideStep(steps: route.steps, traveledM: traveled);
    currentStep = step;
    if (step != null) {
      distanceToStepM = (step.alongRouteM - traveled).clamp(0.0, route.distanceM);
    } else {
      distanceToStepM = remain;
    }
    notifyListeners();
  }

  void clearRoute() {
    candidates = const [];
    choiceCards = const [];
    selected = null;
    shortest = null;
    compare = null;
    message = null;
    error = null;
    guiding = false;
    arrived = false;
    currentStep = null;
    distanceToStepM = 0;
    remainingDistanceM = 0;
    remainingDurationSec = null;
    notifyListeners();
  }

  Future<void> plan() async {
    final o = origin;
    final d = destination;
    if (o == null || d == null) return;
    if (!isValidLatLng(o.latitude, o.longitude) ||
        !isValidLatLng(d.latitude, d.longitude)) {
      cancelGuidanceForReplan();
      error = '좌표가 올바르지 않습니다.';
      notifyListeners();
      return;
    }

    // 안내 중 재탐색 시 기존 안내·경로선 즉시 제거
    cancelGuidanceForReplan();
    loading = true;
    error = null;
    message = null;
    notifyListeners();

    try {
      List<InfrastructureItem> cctvsForVia = const [];
      try {
        final q = ViaCandidatePicker.queryCircle(o, d);
        cctvsForVia = await _mapRepo.fetchInfrastructures(
          lat: q.center.latitude,
          lng: q.center.longitude,
          radiusM: q.radiusM,
          type: 'CCTV',
        );
      } catch (_) {}

      final vias = ViaCandidatePicker.pick(
        origin: o,
        destination: d,
        cctvs: cctvsForVia,
      );

      final raw = await _directions.fetch(
        origin: o,
        destination: d,
        mode: NavMode.walk,
        viaPoints: vias,
      );
      if (raw.isEmpty) {
        error = '경로를 찾지 못했습니다.';
        candidates = const [];
        choiceCards = const [];
        selected = null;
        return;
      }
      candidates = raw;
      await _buildChoices();
    } on ApiException catch (e) {
      error = e.message;
      candidates = const [];
      choiceCards = const [];
      selected = null;
    } catch (e) {
      error = e.toString();
      candidates = const [];
      choiceCards = const [];
      selected = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _buildChoices() async {
    if (candidates.isEmpty) return;

    final ctx = await _loadScoreContext(candidates);
    final annotated = annotateRoutes(
      candidates: candidates,
      cctvs: ctx.cctvs,
      reports: ctx.reports,
    );
    candidates = annotated;

    final built = buildChoiceCards(annotated);
    choiceCards = built.cards;
    shortest = built.shortest;
    message = built.message;
    selected = built.cards.first;
    compare = vsShortest(selected!, shortest!);
    notifyListeners();
  }

  Future<
      ({
        List<InfrastructureItem> cctvs,
        List<ReportItem> reports,
      })> _loadScoreContext(List<RouteCandidate> routes) async {
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final r in routes) {
      for (final p in r.points) {
        minLat = mathMin(minLat, p.latitude);
        maxLat = mathMax(maxLat, p.latitude);
        minLng = mathMin(minLng, p.longitude);
        maxLng = mathMax(maxLng, p.longitude);
      }
    }
    const pad = 0.01;
    minLat -= pad;
    maxLat += pad;
    minLng -= pad;
    maxLng += pad;

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final radiusM = (distKm(minLat, minLng, maxLat, maxLng) * 1000 / 2)
        .clamp(500, 8000)
        .round();

    List<InfrastructureItem> cctvs = const [];
    List<ReportItem> reports = const [];

    try {
      cctvs = await _mapRepo.fetchInfrastructures(
        lat: center.latitude,
        lng: center.longitude,
        radiusM: radiusM,
        type: 'CCTV',
      );
    } catch (_) {}

    try {
      reports = await _mapRepo.fetchReports(
        swLat: minLat,
        swLng: minLng,
        neLat: maxLat,
        neLng: maxLng,
      );
    } catch (_) {}

    return (cctvs: cctvs, reports: reports);
  }
}

double mathMin(double a, double b) => a < b ? a : b;
double mathMax(double a, double b) => a > b ? a : b;
