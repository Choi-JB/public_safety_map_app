import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/geo/geo_utils.dart';
import '../data/models/models.dart';
import '../data/models/route_models.dart';

const double detourDurationFactor = 1.30;
const double detourLengthFactor = 1.25;
const double sampleStepMeters = 40.0;
const double scoreBufferMeters = 200.0;
const double _epsKm = 0.001;

/// maxCctv 길이 패널티 (클수록 최단 선호)
const double cctvLengthPenaltyBeta = 0.05;

class RouteScoreResult {
  const RouteScoreResult({
    required this.selected,
    required this.shortest,
    required this.usedFallback,
    this.message,
    this.compare,
  });

  final RouteCandidate selected;
  final RouteCandidate shortest;
  final bool usedFallback;
  final String? message;
  final RouteCompareMeta? compare;
}

RouteCandidate pickShortest(List<RouteCandidate> all) {
  if (all.isEmpty) {
    throw StateError('candidates empty');
  }
  return all.reduce((a, b) {
    final ad = a.durationSec;
    final bd = b.durationSec;
    if (ad != null && bd != null) {
      if (ad != bd) return ad < bd ? a : b;
    } else if (ad != null) {
      return a;
    } else if (bd != null) {
      return b;
    }
    return a.distanceM <= b.distanceM ? a : b;
  });
}

List<RouteCandidate> filterDetour(
  List<RouteCandidate> all,
  RouteCandidate shortest,
) {
  final d0 = shortest.durationSec;
  if (d0 != null && d0 > 0) {
    final limit = d0 * detourDurationFactor;
    return all
        .where((r) => (r.durationSec ?? double.infinity) <= limit)
        .toList();
  }
  final limit = shortest.distanceM * detourLengthFactor;
  return all.where((r) => r.distanceM <= limit).toList();
}

RouteCompareMeta vsShortest(RouteCandidate selected, RouteCandidate shortest) {
  final sDur = selected.durationSec ?? 0;
  final oDur = shortest.durationSec ?? 0;
  final extraMin =
      ((sDur - oDur) / 60.0).clamp(-9999.0, 9999.0).toDouble();
  final extraKm =
      ((selected.distanceM - shortest.distanceM) / 1000.0);
  return RouteCompareMeta(extraMinutes: extraMin, extraKm: extraKm);
}

/// 모든 후보에 CCTV·제보 점수 부여
List<RouteCandidate> annotateRoutes({
  required List<RouteCandidate> candidates,
  required List<InfrastructureItem> cctvs,
  required List<ReportItem> reports,
  List<AccidentZoneItem> accidents = const [],
}) {
  return candidates
      .map(
        (c) => _scoreOne(
          c,
          cctvs: cctvs,
          reports: reports,
          accidents: accidents,
        ),
      )
      .toList();
}

/// 고정 4카드: 추천 · 최단거리 · CCTV 많은 곳 · 제보 최소화
/// [annotated] 는 [annotateRoutes] 결과여야 함.
({List<RouteCandidate> cards, RouteCandidate shortest, String? message})
    buildChoiceCards(List<RouteCandidate> annotated) {
  if (annotated.isEmpty) {
    throw StateError('candidates empty');
  }

  final shortest = pickShortest(annotated);
  final recommend = annotated.firstWhere(
    (c) => c.id.contains('direct_0'),
    orElse: () => annotated.firstWhere(
      (c) => c.displayLabel == '추천',
      orElse: () => shortest,
    ),
  );

  var pool = filterDetour(annotated, shortest);
  String? message;
  if (pool.isEmpty) {
    pool = [shortest];
    message = '우회 한도 내 대안이 없어 최단 기준으로 표시합니다.';
  } else if (annotated.length == 1) {
    message = '대안 경로가 부족해 동일 경로일 수 있습니다.';
  }

  final cctvBest = pool.reduce((a, b) {
    final sa = _cctvScore(a, shortest);
    final sb = _cctvScore(b, shortest);
    if (sa != sb) return sa > sb ? a : b;
    return _preferShorter(a, b);
  });

  final reportBest = pool.reduce((a, b) {
    final ap = a.reportPerKm ?? double.infinity;
    final bp = b.reportPerKm ?? double.infinity;
    if (ap != bp) return ap < bp ? a : b;
    return _preferShorter(a, b);
  });

  final cards = [
    recommend.asChoiceCard(choiceId: 'choice_recommend', label: '추천'),
    shortest.asChoiceCard(choiceId: 'choice_shortest', label: '최단거리'),
    cctvBest.asChoiceCard(choiceId: 'choice_max_cctv', label: 'CCTV 많은 곳'),
    reportBest.asChoiceCard(
      choiceId: 'choice_min_reports',
      label: '제보 최소화',
    ),
  ];

  return (cards: cards, shortest: shortest, message: message);
}

RouteScoreResult selectBestRoute({
  required List<RouteCandidate> candidates,
  required RouteOption option,
  required List<InfrastructureItem> cctvs,
  required List<ReportItem> reports,
  required List<AccidentZoneItem> accidents,
}) {
  final annotated = annotateRoutes(
    candidates: candidates,
    cctvs: cctvs,
    reports: reports,
    accidents: accidents,
  );
  final shortest = pickShortest(annotated);

  if (option == RouteOption.shortest) {
    return RouteScoreResult(
      selected: shortest,
      shortest: shortest,
      usedFallback: false,
      compare: vsShortest(shortest, shortest),
    );
  }

  final built = buildChoiceCards(annotated);
  final selected = switch (option) {
    RouteOption.maxCctv => built.cards.firstWhere(
        (c) => c.id == 'choice_max_cctv',
        orElse: () => built.shortest.asChoiceCard(
              choiceId: 'choice_max_cctv',
              label: 'CCTV 많은 곳',
            ),
      ),
    RouteOption.minReports => built.cards.firstWhere(
        (c) => c.id == 'choice_min_reports',
        orElse: () => built.shortest.asChoiceCard(
              choiceId: 'choice_min_reports',
              label: '제보 최소화',
            ),
      ),
    RouteOption.avoidAccident || RouteOption.shortest => built.shortest,
  };

  return RouteScoreResult(
    selected: selected,
    shortest: built.shortest,
    usedFallback: built.message != null,
    message: built.message,
    compare: vsShortest(selected, built.shortest),
  );
}

/// 밀도 - β × (소요/최단소요)
double _cctvScore(RouteCandidate r, RouteCandidate shortest) {
  final dens = r.cctvPerKm ?? 0;
  final d0 = shortest.durationSec ?? shortest.distanceM;
  final d = r.durationSec ?? r.distanceM;
  if (d0 <= 0) return dens;
  return dens - cctvLengthPenaltyBeta * (d / d0);
}

RouteCandidate _preferShorter(RouteCandidate a, RouteCandidate b) {
  final ad = a.durationSec;
  final bd = b.durationSec;
  if (ad != null && bd != null && ad != bd) return ad < bd ? a : b;
  return a.distanceM <= b.distanceM ? a : b;
}

RouteCandidate _scoreOne(
  RouteCandidate c, {
  required List<InfrastructureItem> cctvs,
  required List<ReportItem> reports,
  required List<AccidentZoneItem> accidents,
}) {
  final samples = samplePolyline(c.points, sampleStepMeters);
  final bufKm = scoreBufferMeters / 1000.0;

  var cctvCount = 0;
  for (final i in cctvs) {
    if (!isValidLatLng(i.lat, i.lng)) continue;
    if (_nearAny(samples, i.lat!, i.lng!, bufKm)) cctvCount++;
  }

  var reportCount = 0;
  for (final r in reports) {
    if (!isValidLatLng(r.lat, r.lng)) continue;
    if (_nearAny(samples, r.lat!, r.lng!, bufKm)) reportCount++;
  }

  var accidentHits = 0;
  for (final z in accidents) {
    for (final p in z.path) {
      if (!isValidLatLng(p.lat, p.lng)) continue;
      if (_nearAny(samples, p.lat, p.lng, bufKm)) {
        accidentHits++;
        break;
      }
    }
  }

  final km = math.max(c.lengthKm, _epsKm);
  return c.copyWithScores(
    cctvCount: cctvCount,
    reportCount: reportCount,
    accidentCost: accidentHits.toDouble(),
    cctvPerKm: cctvCount / km,
    reportPerKm: reportCount / km,
  );
}

bool _nearAny(List<LatLng> samples, double lat, double lng, double bufKm) {
  for (final s in samples) {
    if (distKm(s.latitude, s.longitude, lat, lng) <= bufKm) return true;
  }
  return false;
}

List<LatLng> samplePolyline(List<LatLng> points, double stepM) {
  if (points.length < 2) return List.of(points);
  final out = <LatLng>[points.first];
  var acc = 0.0;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final segM = distKm(a.latitude, a.longitude, b.latitude, b.longitude) * 1000;
    if (segM <= 0) continue;
    var d = stepM - acc;
    while (d <= segM) {
      final t = d / segM;
      out.add(
        LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ),
      );
      d += stepM;
    }
    acc = segM - (d - stepM);
  }
  if (out.last != points.last) out.add(points.last);
  return out;
}