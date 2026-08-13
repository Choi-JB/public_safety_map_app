import 'package:latlong2/latlong.dart';

import '../core/geo/geo_utils.dart';
import '../data/models/route_models.dart';
import 'guidance_progress.dart';

/// 경로 폴리선에서 [me]까지 최단 거리(m). 경로 이탈 판단용.
double distanceOffRouteM(List<LatLng> points, LatLng me) {
  if (points.length < 2) return double.infinity;
  var best = double.infinity;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final segM =
        distKm(a.latitude, a.longitude, b.latitude, b.longitude) * 1000;
    if (segM <= 0) continue;
    final t = _projectT(me, a, b);
    final proj = LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
    final d =
        distKm(me.latitude, me.longitude, proj.latitude, proj.longitude) * 1000;
    if (d < best) best = d;
  }
  return best;
}

double _projectT(LatLng p, LatLng a, LatLng b) {
  final dx = b.longitude - a.longitude;
  final dy = b.latitude - a.latitude;
  final len2 = dx * dx + dy * dy;
  if (len2 <= 0) return 0;
  final t =
      ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) /
          len2;
  return t.clamp(0.0, 1.0);
}

/// [me] 기준 앞구간을 잘라 TMAP 재호출 없이 경로 수정. 이탈 시 null.
RouteCandidate? trimRouteFromPosition(
  RouteCandidate route,
  LatLng me, {
  double maxOffRouteM = 50,
}) {
  final points = route.points;
  if (points.length < 2) return null;
  if (distanceOffRouteM(points, me) > maxOffRouteM) return null;

  final traveled = distanceTraveledAlongRoute(points, me);
  if (traveled >= route.distanceM - 5) return null;

  final newPoints = remainingPolylinePoints(points, traveled);
  if (newPoints.length < 2) return null;

  final newDistanceM = _polylineLengthM(newPoints);
  if (newDistanceM < 10) return null;

  double? newDuration;
  if (route.durationSec != null && route.distanceM > 0) {
    newDuration = route.durationSec! * (newDistanceM / route.distanceM);
  }

  final newSteps = <RouteStep>[
    for (final s in route.steps)
      if (s.alongRouteM > traveled + 8)
        RouteStep(
          point: s.point,
          description: s.description,
          turnType: s.turnType,
          alongRouteM: (s.alongRouteM - traveled).clamp(0.0, newDistanceM),
        ),
  ];

  return route.copyWithGeometry(
    points: newPoints,
    distanceM: newDistanceM,
    durationSec: newDuration,
    steps: newSteps,
  );
}

/// 지나온 traveledM 만큼 앞구간을 잘라 남은 폴리라인 반환
List<LatLng> remainingPolylinePoints(List<LatLng> points, double traveledM) {
  final out = <LatLng>[];
  var along = 0.0;

  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final segM =
        distKm(a.latitude, a.longitude, b.latitude, b.longitude) * 1000;
    if (segM <= 0) continue;

    if (along + segM < traveledM - 0.5) {
      along += segM;
      continue;
    }

    if (out.isEmpty) {
      final t = segM <= 0 ? 0.0 : ((traveledM - along) / segM).clamp(0.0, 1.0);
      final start = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
      if (isValidLatLng(start.latitude, start.longitude)) {
        out.add(start);
      }
    }

    if (out.isEmpty || out.last.latitude != b.latitude ||
        out.last.longitude != b.longitude) {
      out.add(b);
    }
    along += segM;
  }

  return out;
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
