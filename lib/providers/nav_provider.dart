import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo/geo_utils.dart';
import '../core/network/api_exception.dart';
import '../core/network/user_error.dart';
import '../data/models/models.dart';
import '../data/models/route_models.dart';
import '../data/repositories/direction_repository.dart';
import '../data/repositories/map_repository.dart';
import '../services/guidance_progress.dart';
import '../services/route_scorer.dart';
import '../services/route_trim.dart';
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

  /// 안내 중 지도에 그릴 남은 경로 (원본 selected.points는 유지)
  List<LatLng>? guideDisplayPoints;

  /// 목적지 주변 도착 (경로 잔여 / 직선, m). 자동 종료 없음 → 알림에서 안내 종료.
  static const double _arriveNearM = 10;

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

  /// 경로 이탈 시 TMAP 재탐색, 경로 위면 trim만 (TMAP 0회).
  static const double _editRouteMaxOffRouteM = 25;
  static const Duration _autoReplanCooldown = Duration(seconds: 25);
  DateTime? _lastAutoReplanAt;
  bool _autoReplanQueued = false;

  /// 경로 수정: 안내는 끄고 도착지 유지 → 현재 위치 기준으로 경로 조정 또는 재탐색
  Future<void> editRoute({LatLng? from}) async {
    if (from != null) origin = from;
    if (origin == null || destination == null) {
      cancelGuidanceForReplan();
      error = '출발/도착이 없습니다. 길찾기를 다시 해 주세요.';
      notifyListeners();
      return;
    }

    final me = from ?? origin!;
    final savedSelected = selected;
    final savedLabel = savedSelected?.displayLabel;
    final savedCandidates = List<RouteCandidate>.from(candidates);

    if (savedSelected != null &&
        savedCandidates.isNotEmpty &&
        trimRouteFromPosition(
              savedSelected,
              me,
              maxOffRouteM: _editRouteMaxOffRouteM,
            ) !=
            null) {
      final trimmed = <RouteCandidate>[];
      for (final c in savedCandidates) {
        final t = trimRouteFromPosition(
          c,
          me,
          maxOffRouteM: _editRouteMaxOffRouteM,
        );
        if (t != null) trimmed.add(t);
      }
      if (trimmed.isNotEmpty) {
        await _applyTrimmedRoutes(
          trimmed,
          priorLabel: savedLabel,
          notice: '현재 위치 기준으로 경로를 조정했습니다.',
        );
        return;
      }
    }

    await plan();
  }

  Future<void> _applyTrimmedRoutes(
    List<RouteCandidate> trimmed, {
    String? priorLabel,
    String? notice,
  }) async {
    cancelGuidanceForReplan();
    loading = true;
    error = null;
    message = notice;
    notifyListeners();

    try {
      candidates = trimmed;
      await _buildChoices();
      if (priorLabel != null) {
        final match = choiceCards
            .where((c) => c.displayLabel == priorLabel)
            .firstOrNull;
        if (match != null) {
          selected = match;
          if (shortest != null) {
            compare = vsShortest(match, shortest!);
          }
        }
      }
    } catch (e) {
      error = userFacingError(e, fallback: '경로를 찾지 못했습니다.');
      candidates = const [];
      choiceCards = const [];
      selected = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _resetGuidanceFields() {
    guiding = false;
    arrived = false;
    currentStep = null;
    distanceToStepM = 0;
    remainingDistanceM = 0;
    remainingDurationSec = null;
    guideDisplayPoints = null;
    _lastAutoReplanAt = null;
    _autoReplanQueued = false;
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

  void _maybeAutoReplan(LatLng me) {
    if (!guiding || loading || _autoReplanQueued) return;
    if (destination == null) return;
    final last = _lastAutoReplanAt;
    if (last != null &&
        DateTime.now().difference(last) < _autoReplanCooldown) {
      return;
    }
    _autoReplanQueued = true;
    _lastAutoReplanAt = DateTime.now();
    message = '경로를 벗어났습니다. 다시 찾는 중…';
    notifyListeners();
    Future(() async {
      try {
        await editRoute(from: me);
      } finally {
        _autoReplanQueued = false;
      }
    });
  }

  void updateGuideProgress(LatLng me) {
    if (!guiding) return;
    final route = selected;
    if (route == null || route.points.length < 2) return;

    final traveled = distanceTraveledAlongRoute(route.points, me);

    final remainPts = remainingPolylinePoints(route.points, traveled);
    guideDisplayPoints = remainPts.length >= 2 ? remainPts : null;

    final remain = (route.distanceM - traveled).clamp(0.0, route.distanceM);
    remainingDistanceM = remain;

    if (route.durationSec != null && route.distanceM > 0) {
      remainingDurationSec = route.durationSec! * (remain / route.distanceM);
    }

    final dest = destination;
    var near = remain <= _arriveNearM;
    if (!near && dest != null) {
      final straightM =
          distKm(me.latitude, me.longitude, dest.latitude, dest.longitude) *
              1000;
      near = straightM <= _arriveNearM;
    }

    if (near) {
      arrived = true;
      currentStep = null;
      distanceToStepM = 0;
      guideDisplayPoints = null;
      notifyListeners();
      return;
    }

    final off = distanceOffRouteM(route.points, me);
    if (off > _editRouteMaxOffRouteM) {
      _maybeAutoReplan(me);
    }

    arrived = false;
    final step = nextGuideStep(steps: route.steps, traveledM: traveled);
    currentStep = step;
    if (step != null) {
      distanceToStepM =
          (step.alongRouteM - traveled).clamp(0.0, route.distanceM);
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
    guideDisplayPoints = null;
    _lastAutoReplanAt = null;
    _autoReplanQueued = false;
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
      error = userFacingError(e, fallback: '경로를 찾지 못했습니다.');
      candidates = const [];
      choiceCards = const [];
      selected = null;
    } catch (e) {
      error = userFacingError(e, fallback: '경로를 찾지 못했습니다.');
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
